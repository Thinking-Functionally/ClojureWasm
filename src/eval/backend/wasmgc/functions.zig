// SPDX-License-Identifier: EPL-2.0
//! Function and closure compilation for WasmGC backend
//!
//! This module handles:
//! - fn* (anonymous functions) compilation
//! - Closure capture mechanism
//! - Function table management
//! - Higher-order function support
//!
//! Spec reference: Phase 4 Month 3 Week 1-2

const std = @import("std");
const compiler = @import("compiler");
const value_types = @import("value_types");
const Allocator = std.mem.Allocator;

/// Function table entry
pub const FunctionTableEntry = struct {
    /// Function index in table
    index: u32,
    /// Arity (parameter count)
    arity: u32,
    /// Function name (for debugging)
    name: []const u8,
};

/// Function table manager
pub const FunctionTable = struct {
    allocator: Allocator,
    entries: std.ArrayList(FunctionTableEntry),
    next_index: u32,

    pub fn init(allocator: Allocator) FunctionTable {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(FunctionTableEntry).init(allocator),
            .next_index = 0,
        };
    }

    pub fn deinit(self: *FunctionTable) void {
        self.entries.deinit();
    }

    /// Register a function and get its table index
    pub fn registerFunction(self: *FunctionTable, name: []const u8, arity: u32) !u32 {
        const index = self.next_index;
        self.next_index += 1;

        try self.entries.append(.{
            .index = index,
            .arity = arity,
            .name = name,
        });

        return index;
    }

    /// Emit function table declaration in WAT
    pub fn emitTableDecl(self: *FunctionTable, buf: *std.ArrayList(u8)) !void {
        if (self.entries.items.len == 0) return;

        try buf.appendSlice("  ;; Function table\n");
        const len = self.entries.items.len;
        try buf.writer().print("  (table $func_table {d} funcref)\n", .{len});
    }

    /// Emit table initialization (elem section)
    pub fn emitTableInit(self: *FunctionTable, buf: *std.ArrayList(u8)) !void {
        if (self.entries.items.len == 0) return;

        try buf.appendSlice("  ;; Initialize function table\n");
        try buf.appendSlice("  (elem $func_table (i32.const 0)");

        for (self.entries.items) |entry| {
            try buf.appendSlice(" $");
            try buf.appendSlice(entry.name);
        }

        try buf.appendSlice(")\n");
    }
};

/// Compile fn* expression (anonymous function)
///
/// Example: (fn* [x y] (+ x y))
/// Compiles to:
///   1. Generate unique function name
///   2. Emit function definition with captures
///   3. Return $Function value with func_index and captures
pub fn compileFnExpr(
    ctx: *compiler.CompileContext,
    fn_expr: compiler.FnExpr,
    parent_func: ?*compiler.FunctionContext,
) !void {
    // Generate unique function name
    const fn_name = try std.fmt.allocPrint(
        ctx.allocator,
        "lambda${d}",
        .{ctx.functions.items.len},
    );
    defer ctx.allocator.free(fn_name);

    // Analyze free variables (need to be captured)
    var free_vars = std.StringHashMap(void).init(ctx.allocator);
    defer free_vars.deinit();

    try findFreeVars(fn_expr, parent_func, &free_vars);

    // Create function context with captures
    var func_ctx = try compiler.FunctionContext.init(
        ctx.allocator,
        fn_name,
        @intCast(fn_expr.params.len),
        parent_func,
    );
    defer func_ctx.deinit();

    // Register parameters as locals
    for (fn_expr.params, 0..) |param, i| {
        try func_ctx.locals.put(param, .{
            .index = @intCast(i),
            .wat_type = "(ref $Value)",
        });
    }

    // Register captures
    var capture_index: u32 = 0;
    var captures_iter = free_vars.keyIterator();
    while (captures_iter.next()) |var_name| {
        try func_ctx.captures.put(var_name.*, .{
            .capture_index = capture_index,
            .name = var_name.*,
            .wat_type = "(ref $Value)",
        });
        capture_index += 1;
    }

    // Emit function definition
    try ctx.wat_output.appendSlice("  (func $");
    try ctx.wat_output.appendSlice(fn_name);

    // Parameters: (param $captures (ref (array (ref $Value)))) (param $arg0) ...
    try ctx.wat_output.appendSlice(" (param $captures (ref null (array (ref $Value))))");
    for (fn_expr.params, 0..) |_, i| {
        try ctx.wat_output.writer().print(" (param $arg{d} (ref $Value))", .{i});
    }
    try ctx.wat_output.appendSlice(" (result (ref $Value))\n");

    // Function body
    ctx.current_func = &func_ctx;
    defer ctx.current_func = null;

    for (fn_expr.body) |expr| {
        try ctx.wat_output.appendSlice("    ");
        try compiler.compileExpr(ctx, expr);
        try ctx.wat_output.appendSlice("\n");
    }

    try ctx.wat_output.appendSlice("  )\n\n");

    // Now emit code to create the $Function value at the call site
    // This happens in the parent function's context

    // 1. Build captures array
    if (free_vars.count() > 0) {
        try ctx.wat_output.appendSlice("    ;; Build captures array\n");
        try ctx.wat_output.writer().print("    (array.new $Value {d}\n", .{free_vars.count()});

        var cap_iter = free_vars.keyIterator();
        while (cap_iter.next()) |var_name| {
            // Look up variable in parent context
            if (parent_func) |pf| {
                if (pf.locals.get(var_name.*)) |local| {
                    try ctx.wat_output.writer().print("      (local.get ${s})\n", .{var_name.*});
                }
            }
        }
        try ctx.wat_output.appendSlice("    )\n");
    } else {
        try ctx.wat_output.appendSlice("    (ref.null (array (ref $Value)))\n");
    }

    // 2. Create $Function struct
    try ctx.wat_output.appendSlice("    (struct.new $Function\n");
    try ctx.wat_output.writer().print("      (i32.const {d})  ;; func_index\n", .{
        ctx.functions.items.len,
    });
    try ctx.wat_output.appendSlice("      ;; captures array (from above)\n");
    try ctx.wat_output.writer().print("      (i32.const {d})  ;; arity\n", .{fn_expr.params.len});
    try ctx.wat_output.appendSlice("    )\n");

    // 3. Wrap in $Value
    try ctx.wat_output.appendSlice("    (struct.new $Value\n");
    try ctx.wat_output.writer().print("      (i32.const {s})  ;; tag = function\n", .{
        value_types.TypeTag.function.toWAT(),
    });
    try ctx.wat_output.appendSlice("      (union.new $ValueData $function)\n");
    try ctx.wat_output.appendSlice("    )\n");
}

/// Find free variables in function expression (variables not in params)
fn findFreeVars(
    fn_expr: compiler.FnExpr,
    parent_func: ?*compiler.FunctionContext,
    free_vars: *std.StringHashMap(void),
) !void {
    // Create set of bound parameters
    var bound = std.StringHashMap(void).init(free_vars.allocator);
    defer bound.deinit();

    for (fn_expr.params) |param| {
        try bound.put(param, {});
    }

    // Scan body for var_ref nodes
    for (fn_expr.body) |expr| {
        try findFreeVarsInExpr(expr, &bound, free_vars, parent_func);
    }
}

/// Recursively find free variables in an expression
fn findFreeVarsInExpr(
    expr: compiler.ASTNode,
    bound: *std.StringHashMap(void),
    free_vars: *std.StringHashMap(void),
    parent_func: ?*compiler.FunctionContext,
) error{OutOfMemory}!void {
    switch (expr) {
        .var_ref => |vr| {
            // If not bound in current scope, it's free
            if (!bound.contains(vr.name)) {
                // Only capture if it exists in parent scope
                if (parent_func) |pf| {
                    if (pf.locals.contains(vr.name) or pf.captures.contains(vr.name)) {
                        try free_vars.put(vr.name, {});
                    }
                }
            }
        },
        .let_expr => |let| {
            // Let introduces new bindings
            var new_bound = try bound.clone();
            defer new_bound.deinit();

            for (let.bindings) |binding| {
                try findFreeVarsInExpr(binding.init.*, bound, free_vars, parent_func);
                try new_bound.put(binding.name, {});
            }

            for (let.body) |body_expr| {
                try findFreeVarsInExpr(body_expr, &new_bound, free_vars, parent_func);
            }
        },
        .fn_call => |call| {
            try findFreeVarsInExpr(call.func.*, bound, free_vars, parent_func);
            for (call.args) |arg| {
                try findFreeVarsInExpr(arg, bound, free_vars, parent_func);
            }
        },
        .if_expr => |if_e| {
            try findFreeVarsInExpr(if_e.test_expr.*, bound, free_vars, parent_func);
            try findFreeVarsInExpr(if_e.then_expr.*, bound, free_vars, parent_func);
            if (if_e.else_expr) |else_e| {
                try findFreeVarsInExpr(else_e.*, bound, free_vars, parent_func);
            }
        },
        .do_expr => |do_e| {
            for (do_e.exprs) |e| {
                try findFreeVarsInExpr(e, bound, free_vars, parent_func);
            }
        },
        .loop_expr => |loop| {
            var new_bound = try bound.clone();
            defer new_bound.deinit();

            for (loop.bindings) |binding| {
                try findFreeVarsInExpr(binding.init.*, bound, free_vars, parent_func);
                try new_bound.put(binding.name, {});
            }

            for (loop.body) |body_expr| {
                try findFreeVarsInExpr(body_expr, &new_bound, free_vars, parent_func);
            }
        },
        .recur => |rec| {
            for (rec.args) |arg| {
                try findFreeVarsInExpr(arg, bound, free_vars, parent_func);
            }
        },
        else => {}, // literals, def, defn don't contain var refs
    }
}
