// SPDX-License-Identifier: EPL-2.0
//! AST → WAT compiler for WasmGC backend
//!
//! This module compiles analyzed Clojure forms (from src/eval/analyzer/) into
//! WebAssembly Text (WAT) format using WasmGC native types.
//!
//! Key responsibilities:
//! - Transform analyzer AST nodes into WAT instructions
//! - Manage local variable allocation and scoping
//! - Emit type definitions, function bodies, and module structure
//! - Handle control flow (if/loop/recur) mapping to WAT blocks
//! - Generate calls to runtime support functions (defined in runtime.zig)
//!
//! Design decisions (see Phase 4 proposal § 編譯管線):
//! - One-pass compilation: AST → WAT directly (no intermediate IR)
//! - Stack-based evaluation model (WAT's natural execution model)
//! - Static type inference for optimization opportunities
//! - Function-level compilation unit (each defn → one WAT func)

const std = @import("std");
const value_types = @import("value_types");
const Allocator = std.mem.Allocator;

/// Compilation context for a single module
pub const CompileContext = struct {
    allocator: Allocator,
    /// WAT output buffer
    wat_output: std.array_list.Managed(u8),
    /// Current function being compiled
    current_func: ?*FunctionContext,
    /// Global symbol table (for def'd vars)
    globals: std.StringHashMap(GlobalBinding),
    /// Function table for defn'd functions
    functions: std.array_list.Managed(FunctionDef),

    pub fn init(allocator: Allocator) CompileContext {
        return .{
            .allocator = allocator,
            .wat_output = std.array_list.Managed(u8).init(allocator),
            .current_func = null,
            .globals = std.StringHashMap(GlobalBinding).init(allocator),
            .functions = std.array_list.Managed(FunctionDef).init(allocator),
        };
    }

    pub fn deinit(self: *CompileContext) void {
        self.wat_output.deinit();
        self.globals.deinit();
        self.functions.deinit();
    }
};

/// Function compilation context
pub const FunctionContext = struct {
    allocator: Allocator,
    /// Function name (for defn)
    name: []const u8,
    /// Arity (parameter count)
    arity: u32,
    /// Local variable bindings (params + lets)
    locals: std.StringHashMap(LocalBinding),
    /// Next available local index
    next_local_index: u32,
    /// Loop context stack (for recur target resolution)
    loop_stack: std.ArrayList(LoopContext),
    /// Captured variables from outer scope (for closures)
    captures: std.StringHashMap(CapturedVar),
    /// Parent context (for closure nesting)
    parent: ?*FunctionContext,

    pub fn init(allocator: Allocator, name: []const u8, arity: u32, parent: ?*FunctionContext) !FunctionContext {
        return .{
            .allocator = allocator,
            .name = name,
            .arity = arity,
            .locals = std.StringHashMap(LocalBinding).init(allocator),
            .next_local_index = arity, // params occupy first N locals
            .loop_stack = .{ .items = &.{}, .capacity = 0 },
            .captures = std.StringHashMap(CapturedVar).init(allocator),
            .parent = parent,
        };
    }

    pub fn deinit(self: *FunctionContext) void {
        self.locals.deinit();
        self.captures.deinit();
    }

    /// Look up a variable (params, locals, captures, or parent scope)
    pub fn lookupVar(self: *FunctionContext, name: []const u8) ?VarLocation {
        // Check local bindings first
        if (self.locals.get(name)) |local| {
            return .{ .local = local };
        }

        // Check captures
        if (self.captures.get(name)) |cap| {
            return .{ .capture = cap };
        }

        // Recurse to parent (for nested closures)
        if (self.parent) |parent| {
            if (parent.lookupVar(name)) |loc| {
                // Variables from parent need to be captured
                return loc;
            }
        }

        return null;
    }

    /// Allocate a new local variable
    pub fn allocLocal(self: *FunctionContext, name: []const u8, wat_type: []const u8) !u32 {
        const index = self.next_local_index;
        self.next_local_index += 1;
        try self.locals.put(name, .{ .index = index, .wat_type = wat_type });
        return index;
    }
};

/// Global variable binding
pub const GlobalBinding = struct {
    index: u32,
    wat_type: []const u8,
};

/// Local variable binding (param or let)
pub const LocalBinding = struct {
    index: u32,
    wat_type: []const u8,
};

/// Loop context for recur target resolution
pub const LoopContext = struct {
    label: []const u8,
    arity: u32,
};

/// Captured variable for closures
pub const CapturedVar = struct {
    /// Index in closure's capture array
    capture_index: u32,
    /// Original name
    name: []const u8,
    /// Type
    wat_type: []const u8,
};

/// Variable location (local, capture, or global)
pub const VarLocation = union(enum) {
    local: LocalBinding,
    capture: CapturedVar,
    global: GlobalBinding,
};

/// Function definition
pub const FunctionDef = struct {
    name: []const u8,
    arity: u32,
    params: [][]const u8,
    body: []const u8,
    captures: []CapturedVar,
};

/// AST node types (mirrors src/eval/analyzer/ output)
pub const ASTNode = union(enum) {
    literal: Literal,
    var_ref: VarRef,
    fn_call: FnCall,
    if_expr: IfExpr,
    let_expr: LetExpr,
    do_expr: DoExpr,
    def: Def,
    defn: Defn,
    fn_expr: FnExpr,
    loop_expr: LoopExpr,
    recur: Recur,
};

pub const Literal = struct {
    value: Value,
};

pub const Value = union(enum) {
    nil,
    boolean: bool,
    long: i64,
    double: f64,
    string: []const u8,
};

pub const VarRef = struct {
    name: []const u8,
};

pub const FnCall = struct {
    func: *ASTNode,
    args: []ASTNode,
};

pub const IfExpr = struct {
    test_expr: *ASTNode,
    then_expr: *ASTNode,
    else_expr: ?*ASTNode,
};

pub const LetExpr = struct {
    bindings: []Binding,
    body: []ASTNode,
};

pub const Binding = struct {
    name: []const u8,
    init: *ASTNode,
};

pub const DoExpr = struct {
    exprs: []ASTNode,
};

pub const Def = struct {
    name: []const u8,
    init: *ASTNode,
};

pub const Defn = struct {
    name: []const u8,
    params: [][]const u8,
    body: []ASTNode,
};

pub const FnExpr = struct {
    params: [][]const u8,
    body: []ASTNode,
};

pub const LoopExpr = struct {
    bindings: []Binding,
    body: []ASTNode,
};

pub const Recur = struct {
    args: []ASTNode,
};

/// Compile a module (top-level forms)
pub fn compileModule(allocator: Allocator, forms: []ASTNode) ![]const u8 {
    var ctx = CompileContext.init(allocator);
    defer ctx.deinit();

    // Emit WAT module header
    try ctx.wat_output.appendSlice("(module\n");

    // Emit type definitions using dynamic generator
    try ctx.wat_output.appendSlice("  ;; Type definitions\n");
    var type_gen = value_types.WatTypeGen.init(allocator);
    const type_defs = try type_gen.emitAllTypes();
    defer allocator.free(type_defs);

    // Indent type definitions
    var lines = std.mem.splitScalar(u8, type_defs, '\n');
    while (lines.next()) |line| {
        if (line.len > 0) {
            try ctx.wat_output.appendSlice("  ");
            try ctx.wat_output.appendSlice(line);
        }
        try ctx.wat_output.appendSlice("\n");
    }
    try ctx.wat_output.appendSlice("\n");

    // Compile each top-level form
    for (forms) |form| {
        try compileTopLevelForm(&ctx, form);
    }

    // Emit all collected functions (from fn* expressions)
    for (ctx.functions.items) |func| {
        try ctx.wat_output.appendSlice("  (func $");
        try ctx.wat_output.appendSlice(func.name);

        // Parameters
        for (func.params) |param| {
            try ctx.wat_output.appendSlice(" (param $");
            try ctx.wat_output.appendSlice(param);
            try ctx.wat_output.appendSlice(" (ref $Value))");
        }

        // Return type
        try ctx.wat_output.appendSlice(" (result (ref $Value))\n");

        // Body (already contains indentation from compileFn)
        try ctx.wat_output.appendSlice(func.body);

        try ctx.wat_output.appendSlice("  )\n");
    }

    // Close module
    try ctx.wat_output.appendSlice(")\n");

    return ctx.wat_output.toOwnedSlice();
}

/// Compile a top-level form (def/defn)
fn compileTopLevelForm(ctx: *CompileContext, form: ASTNode) !void {
    switch (form) {
        .def => |d| try compileDef(ctx, d),
        .defn => |fn_def| try compileDefn(ctx, fn_def),
        else => return error.InvalidTopLevelForm,
    }
}

/// Compile a def (global variable definition)
fn compileDef(ctx: *CompileContext, def: Def) !void {
    const global_index = @as(u32, @intCast(ctx.globals.count()));

    try ctx.wat_output.appendSlice("  (global $");
    try ctx.wat_output.appendSlice(def.name);
    try ctx.wat_output.appendSlice(" (mut (ref $Value))\n    ");

    // Compile initializer expression
    try compileExpr(ctx, def.init.*);

    try ctx.wat_output.appendSlice(")\n");

    // Record in symbol table
    try ctx.globals.put(def.name, .{
        .index = global_index,
        .wat_type = "(ref $Value)",
    });
}

/// Compile a defn (function definition)
fn compileDefn(ctx: *CompileContext, fn_def: Defn) !void {
    try ctx.wat_output.appendSlice("  (func $");
    try ctx.wat_output.appendSlice(fn_def.name);

    // Emit parameters
    for (fn_def.params, 0..) |param, i| {
        _ = i;
        try ctx.wat_output.appendSlice(" (param $");
        try ctx.wat_output.appendSlice(param);
        try ctx.wat_output.appendSlice(" (ref $Value))");
    }

    // Return type
    try ctx.wat_output.appendSlice(" (result (ref $Value))\n");

    // Create function context
    var func_ctx = try FunctionContext.init(ctx.allocator, fn_def.name, @intCast(fn_def.params.len), null);
    defer func_ctx.deinit();
    ctx.current_func = &func_ctx;

    // Register params in local bindings
    for (fn_def.params, 0..) |param, i| {
        try func_ctx.locals.put(param, .{
            .index = @intCast(i),
            .wat_type = "(ref $Value)",
        });
    }

    // Compile body
    for (fn_def.body, 0..) |expr, i| {
        try ctx.wat_output.appendSlice("    ");
        try compileExpr(ctx, expr);
        // Drop all but last expression result
        if (i < fn_def.body.len - 1) {
            try ctx.wat_output.appendSlice("\n    drop");
        }
        try ctx.wat_output.appendSlice("\n");
    }

    try ctx.wat_output.appendSlice("  )\n");
    ctx.current_func = null;
}

/// Compile an expression
pub fn compileExpr(ctx: *CompileContext, node: ASTNode) error{ OutOfMemory, InvalidExpression, UndefinedVariable, LetOutsideFunction, NotImplementedYet, LoopOutsideFunction, RecurOutsideFunction, RecurWithoutLoop, NoSpaceLeft, InvalidTopLevelForm }!void {
    switch (node) {
        .literal => |lit| try compileLiteral(ctx, lit),
        .var_ref => |v| try compileVarRef(ctx, v),
        .fn_call => |call| try compileFnCall(ctx, call),
        .if_expr => |if_expr| try compileIf(ctx, if_expr),
        .let_expr => |let_expr| try compileLet(ctx, let_expr),
        .do_expr => |do_expr| try compileDo(ctx, do_expr),
        .fn_expr => |fn_expr| try compileFn(ctx, fn_expr),
        .loop_expr => |loop_expr| try compileLoop(ctx, loop_expr),
        .recur => |recur| try compileRecur(ctx, recur),
        else => return error.InvalidExpression,
    }
}

/// Compile a literal value
fn compileLiteral(ctx: *CompileContext, lit: Literal) !void {
    switch (lit.value) {
        .nil => {
            try ctx.wat_output.appendSlice("(struct.new $Value\n");
            try ctx.wat_output.appendSlice("      (i32.const ");
            try ctx.wat_output.appendSlice(value_types.TypeTag.nil.toWAT());
            try ctx.wat_output.appendSlice(")\n");
            try ctx.wat_output.appendSlice("      (ref.null $ValueData))");
        },
        .boolean => |b| {
            try ctx.wat_output.appendSlice("(struct.new $Value\n");
            try ctx.wat_output.appendSlice("      (i32.const ");
            try ctx.wat_output.appendSlice(value_types.TypeTag.boolean.toWAT());
            try ctx.wat_output.appendSlice(")\n");
            try ctx.wat_output.appendSlice("      (union.new $ValueData $boolean (i32.const ");
            try ctx.wat_output.appendSlice(if (b) "1" else "0");
            try ctx.wat_output.appendSlice(")))");
        },
        .long => |n| {
            try ctx.wat_output.appendSlice("(struct.new $Value\n");
            try ctx.wat_output.appendSlice("      (i32.const ");
            try ctx.wat_output.appendSlice(value_types.TypeTag.long.toWAT());
            try ctx.wat_output.appendSlice(")\n");
            try ctx.wat_output.appendSlice("      (union.new $ValueData $long (i64.const ");
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{n});
            try ctx.wat_output.appendSlice(str);
            try ctx.wat_output.appendSlice(")))");
        },
        .double => |f| {
            try ctx.wat_output.appendSlice("(struct.new $Value\n");
            try ctx.wat_output.appendSlice("      (i32.const ");
            try ctx.wat_output.appendSlice(value_types.TypeTag.double.toWAT());
            try ctx.wat_output.appendSlice(")\n");
            try ctx.wat_output.appendSlice("      (union.new $ValueData $double (f64.const ");
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{f});
            try ctx.wat_output.appendSlice(str);
            try ctx.wat_output.appendSlice(str);
            try ctx.wat_output.appendSlice(")))");
        },
        .string => |s| {
            try ctx.wat_output.appendSlice("(call $rt_make_string (array.new_fixed $String ");
            var buf: [16]u8 = undefined;
            const len_str = try std.fmt.bufPrint(&buf, "{d}", .{s.len});
            try ctx.wat_output.appendSlice(len_str);
            // Emit each byte
            for (s) |byte| {
                try ctx.wat_output.appendSlice(" (i32.const ");
                const byte_str = try std.fmt.bufPrint(&buf, "{d}", .{byte});
                try ctx.wat_output.appendSlice(byte_str);
                try ctx.wat_output.appendSlice(")");
            }
            try ctx.wat_output.appendSlice("))");
        },
    }
}

/// Compile a variable reference
fn compileVarRef(ctx: *CompileContext, v: VarRef) !void {
    // Check local bindings first
    if (ctx.current_func) |func| {
        if (func.locals.get(v.name)) |local| {
            try ctx.wat_output.appendSlice("(local.get $");
            try ctx.wat_output.appendSlice(v.name);
            try ctx.wat_output.appendSlice(")");
            _ = local;
            return;
        }
    }

    // Check globals
    if (ctx.globals.get(v.name)) |_| {
        try ctx.wat_output.appendSlice("(global.get $");
        try ctx.wat_output.appendSlice(v.name);
        try ctx.wat_output.appendSlice(")");
        return;
    }

    return error.UndefinedVariable;
}

/// Compile a function call
fn compileFnCall(ctx: *CompileContext, call: FnCall) !void {
    // Compile arguments
    for (call.args) |arg| {
        try compileExpr(ctx, arg);
        try ctx.wat_output.appendSlice(" ");
    }

    // Compile function expression
    try ctx.wat_output.appendSlice("(call ");
    try compileExpr(ctx, call.func.*);
    try ctx.wat_output.appendSlice(")");
}

/// Compile an if expression
fn compileIf(ctx: *CompileContext, if_expr: IfExpr) !void {
    try ctx.wat_output.appendSlice("(if (result (ref $Value))\n");
    try ctx.wat_output.appendSlice("      ");

    // Test expression (need to check truthiness)
    try compileExpr(ctx, if_expr.test_expr.*);
    try ctx.wat_output.appendSlice("\n      (then\n        ");

    // Then branch
    try compileExpr(ctx, if_expr.then_expr.*);
    try ctx.wat_output.appendSlice(")\n      (else\n        ");

    // Else branch
    if (if_expr.else_expr) |else_expr| {
        try compileExpr(ctx, else_expr.*);
    } else {
        // Default to nil
        try compileLiteral(ctx, .{ .value = .nil });
    }

    try ctx.wat_output.appendSlice("))");
}

/// Compile a let expression
fn compileLet(ctx: *CompileContext, let_expr: LetExpr) !void {
    try ctx.wat_output.appendSlice("(block $let_block (result (ref $Value))\n");

    // Compile and bind each binding
    for (let_expr.bindings) |binding| {
        const local_idx = if (ctx.current_func) |func| func.next_local_index else return error.LetOutsideFunction;

        try ctx.wat_output.appendSlice("      (local.set $");
        try ctx.wat_output.appendSlice(binding.name);
        try ctx.wat_output.appendSlice(" ");
        try compileExpr(ctx, binding.init.*);
        try ctx.wat_output.appendSlice(")\n");

        // Register local
        if (ctx.current_func) |func| {
            try func.locals.put(binding.name, .{
                .index = local_idx,
                .wat_type = "(ref $Value)",
            });
            func.next_local_index += 1;
        }
    }

    // Compile body
    for (let_expr.body, 0..) |expr, i| {
        try ctx.wat_output.appendSlice("      ");
        try compileExpr(ctx, expr);
        if (i < let_expr.body.len - 1) {
            try ctx.wat_output.appendSlice("\n      drop\n");
        }
    }

    try ctx.wat_output.appendSlice(")");
}

/// Compile a do expression
fn compileDo(ctx: *CompileContext, do_expr: DoExpr) !void {
    try ctx.wat_output.appendSlice("(block $do_block (result (ref $Value))\n");

    for (do_expr.exprs, 0..) |expr, i| {
        try ctx.wat_output.appendSlice("      ");
        try compileExpr(ctx, expr);
        if (i < do_expr.exprs.len - 1) {
            try ctx.wat_output.appendSlice("\n      drop\n");
        }
    }

    try ctx.wat_output.appendSlice(")");
}

/// Compile a fn expression (lambda)
fn compileFn(ctx: *CompileContext, fn_expr: FnExpr) !void {
    // Generate unique function name
    var func_name_buf: [64]u8 = undefined;
    const func_name = try std.fmt.bufPrint(&func_name_buf, "fn_{d}", .{ctx.functions.items.len});

    // Create function context
    var func_ctx = try FunctionContext.init(ctx.allocator, func_name, @intCast(fn_expr.params.len), ctx.current_func);
    defer func_ctx.deinit();

    // Analyze captures from parent scope
    if (ctx.current_func) |parent| {
        for (fn_expr.params) |param_name| {
            if (parent.lookupVar(param_name)) |loc| {
                switch (loc) {
                    .local => |local| {
                        try func_ctx.captures.put(param_name, .{
                            .name = param_name,
                            .capture_index = @intCast(func_ctx.captures.count()),
                            .wat_type = local.wat_type,
                        });
                    },
                    .capture => {},
                    .global => {},
                }
            }
        }
    }

    // Register parameters as locals
    for (fn_expr.params, 0..) |param_name, i| {
        try func_ctx.locals.put(param_name, .{
            .index = @intCast(i),
            .wat_type = "(ref $Value)",
        });
    }

    // Compile function body to temporary buffer
    var body_output = std.array_list.Managed(u8).init(ctx.allocator);
    defer body_output.deinit();

    const saved_func = ctx.current_func;
    const saved_output = ctx.wat_output;
    ctx.current_func = &func_ctx;
    ctx.wat_output = body_output;

    for (fn_expr.body, 0..) |expr, i| {
        try compileExpr(ctx, expr);
        if (i < fn_expr.body.len - 1) {
            try ctx.wat_output.appendSlice("\n      drop\n      ");
        }
    }

    const body = try ctx.wat_output.toOwnedSlice();
    ctx.current_func = saved_func;
    ctx.wat_output = saved_output;

    // Register the function
    try ctx.functions.append(ctx.allocator, .{
        .name = try ctx.allocator.dupe(u8, func_name),
        .arity = @intCast(fn_expr.params.len),
        .params = try ctx.allocator.dupe([]const u8, fn_expr.params),
        .body = body,
        .captures = try ctx.allocator.alloc(CapturedVar, func_ctx.captures.count()),
    });

    // Emit closure construction (struct.new $Function)
    try ctx.wat_output.appendSlice("(struct.new $Function\n");
    try ctx.wat_output.appendSlice("      (ref.func $");
    try ctx.wat_output.appendSlice(func_name);
    try ctx.wat_output.appendSlice(")\n");

    // Capture array
    if (func_ctx.captures.count() > 0) {
        try ctx.wat_output.appendSlice("      (array.new_fixed $CaptureArray ");
        var buf: [16]u8 = undefined;
        const count_str = try std.fmt.bufPrint(&buf, "{d}", .{func_ctx.captures.count()});
        try ctx.wat_output.appendSlice(count_str);

        var it = func_ctx.captures.iterator();
        while (it.next()) |entry| {
            try ctx.wat_output.appendSlice(" (local.get $");
            try ctx.wat_output.appendSlice(entry.key_ptr.*);
            try ctx.wat_output.appendSlice(")");
        }
        try ctx.wat_output.appendSlice(")");
    } else {
        try ctx.wat_output.appendSlice("      (ref.null $CaptureArray)");
    }

    try ctx.wat_output.appendSlice(")");
}

/// Compile a loop expression
fn compileLoop(ctx: *CompileContext, loop_expr: LoopExpr) !void {
    const func = ctx.current_func orelse return error.LoopOutsideFunction;

    // Push loop context for recur
    const loop_label = "loop_recur";
    try func.loop_stack.append(ctx.allocator, .{
        .label = loop_label,
        .arity = @intCast(loop_expr.bindings.len),
    });
    defer _ = func.loop_stack.pop();

    try ctx.wat_output.appendSlice("(block $");
    try ctx.wat_output.appendSlice(loop_label);
    try ctx.wat_output.appendSlice("_exit (result (ref $Value))\n");
    try ctx.wat_output.appendSlice("      (loop $");
    try ctx.wat_output.appendSlice(loop_label);
    try ctx.wat_output.appendSlice("\n");

    // Initialize loop bindings
    for (loop_expr.bindings) |binding| {
        try ctx.wat_output.appendSlice("        (local.set $");
        try ctx.wat_output.appendSlice(binding.name);
        try ctx.wat_output.appendSlice(" ");
        try compileExpr(ctx, binding.init.*);
        try ctx.wat_output.appendSlice(")\n");
    }

    // Compile body
    for (loop_expr.body, 0..) |expr, i| {
        try ctx.wat_output.appendSlice("        ");
        try compileExpr(ctx, expr);
        if (i < loop_expr.body.len - 1) {
            try ctx.wat_output.appendSlice("\n        drop\n");
        }
    }

    try ctx.wat_output.appendSlice("))");
}

/// Compile a recur expression
fn compileRecur(ctx: *CompileContext, recur: Recur) !void {
    const func = ctx.current_func orelse return error.RecurOutsideFunction;
    const loop_ctx = if (func.loop_stack.items.len > 0)
        func.loop_stack.items[func.loop_stack.items.len - 1]
    else
        return error.RecurWithoutLoop;

    // Compile recur arguments and update loop bindings
    for (recur.args) |arg| {
        try compileExpr(ctx, arg);
        try ctx.wat_output.appendSlice("\n        ");
    }

    try ctx.wat_output.appendSlice("(br $");
    try ctx.wat_output.appendSlice(loop_ctx.label);
    try ctx.wat_output.appendSlice(")");
}
