// SPDX-License-Identifier: EPL-2.0
//! IR code generator - TreeWalk AST Node → IR EDN
//!
//! Converts ClojureWasm AST (src/eval/node.zig) to IR v2.0 format
//! (docs/ir/SPECIFICATION_v2.0_COMPLETE.md). Key responsibilities:
//!
//! - FnNode → :make-closure instructions with :captures field
//! - slot_base mechanism → closure capture lists
//! - Multi-arity functions → multiple :fn definitions
//! - SSA value ID generation (:val/N, :param/name, :capture/name)

const std = @import("std");
const node_mod = @import("../eval/node.zig");
const Node = node_mod.Node;
const FnNode = node_mod.FnNode;
const Value = @import("../runtime/value/value.zig").Value;
const FnMethod = node_mod.FnMethod;

/// Compilation error set (explicit to break Zig 0.16 inferred error set dependency loop)
pub const CompileError = error{
    OutOfMemory,
    UnsupportedNode,
};

/// IR Value ID - SSA-style identification
pub const IRValueID = union(enum) {
    val: u32, // :val/NNN
    param: []const u8, // :param/name
    local: []const u8, // :local/name
    capture: []const u8, // :capture/name
    fn_ref: []const u8, // :fn/user-add-1
    block: []const u8, // :block/entry

    pub fn format(self: IRValueID, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return switch (self) {
            .val => |n| w.print(":val/{d}", .{n}),
            .param => |name| w.print(":param/{s}", .{name}),
            .local => |name| w.print(":local/{s}", .{name}),
            .capture => |name| w.print(":capture/{s}", .{name}),
            .fn_ref => |name| w.print(":fn/{s}", .{name}),
            .block => |name| w.print(":block/{s}", .{name}),
        };
    }
};

/// IR Instruction - simplified EDN representation
pub const IRInstr = struct {
    op: []const u8, // Operation keyword (no leading :)
    result: ?IRValueID = null, // Result binding
    args: []const IRValueID = &.{}, // Arguments
    captures: []const IRValueID = &.{}, // For :make-closure
    fn_id: ?IRValueID = null, // For :make-closure / :call

    pub fn deinit(self: *IRInstr, allocator: std.mem.Allocator) void {
        allocator.free(self.args);
        allocator.free(self.captures);
    }
};

/// Basic Block - contains instructions + terminator
pub const BasicBlock = struct {
    id: IRValueID,
    instructions: std.ArrayList(IRInstr),
    terminator: ?IRInstr = null,

    pub fn deinit(self: *BasicBlock, allocator: std.mem.Allocator) void {
        for (self.instructions.items) |*instr| {
            instr.deinit(allocator);
        }
        self.instructions.deinit(allocator);
        if (self.terminator) |*term| {
            term.deinit(allocator);
        }
    }
};

/// Function IR - contains blocks + metadata
pub const FunctionIR = struct {
    id: []const u8,
    name: ?[]const u8 = null,
    namespace: ?[]const u8 = null,
    arity: union(enum) {
        fixed: u16,
        variadic: struct { required: u16, rest: bool },
    },
    params: []const []const u8,
    captures: []const []const u8,
    blocks: std.ArrayList(BasicBlock),
    entry_block: IRValueID,

    pub fn deinit(self: *FunctionIR, allocator: std.mem.Allocator) void {
        for (self.blocks.items) |*block| {
            block.deinit(allocator);
        }
        self.blocks.deinit(allocator);
        allocator.free(self.params);
        allocator.free(self.captures);
    }
};

/// Compilation context - manages SSA value counters + function registry + constant values
pub const CompileContext = struct {
    allocator: std.mem.Allocator,
    val_counter: u32 = 0,
    fn_counter: u32 = 0,
    block_counter: u32 = 0,
    functions: std.ArrayList(FunctionIR),
    constants: std.AutoHashMap(u32, Value),

    pub fn init(allocator: std.mem.Allocator) CompileContext {
        return .{
            .allocator = allocator,
            .functions = .empty,
            .constants = std.AutoHashMap(u32, Value).init(allocator),
        };
    }

    pub fn deinit(self: *CompileContext) void {
        for (self.functions.items) |*func| {
            func.deinit(self.allocator);
        }
        self.functions.deinit(self.allocator);
        self.constants.deinit();
    }

    /// Generate fresh :val/N ID
    pub fn freshValue(self: *CompileContext) IRValueID {
        defer self.val_counter += 1;
        return .{ .val = self.val_counter };
    }

    /// Generate fresh :fn/... ID
    pub fn freshFnID(self: *CompileContext, base_name: ?[]const u8) !IRValueID {
        defer self.fn_counter += 1;
        const name = if (base_name) |bn|
            try std.fmt.allocPrint(self.allocator, "{s}-{d}", .{ bn, self.fn_counter })
        else
            try std.fmt.allocPrint(self.allocator, "anon-{d}", .{self.fn_counter});
        return .{ .fn_ref = name };
    }

    /// Generate fresh :block/... ID
    pub fn freshBlockID(self: *CompileContext, label: []const u8) !IRValueID {
        defer self.block_counter += 1;
        const name = try std.fmt.allocPrint(self.allocator, "{s}-{d}", .{ label, self.block_counter });
        return .{ .block = name };
    }

    /// Register a function and return its ID
    pub fn registerFunction(self: *CompileContext, func: FunctionIR) !IRValueID {
        try self.functions.append(self.allocator, func);
        return .{ .fn_ref = func.id };
    }
};

/// Compile FnNode → IR function reference
///
/// Maps TreeWalk FnNode semantics (private/notes/phase1_treewalk_study.md) to IR v2.0:
/// - slot_base → :captures field
/// - methods array → multiple fixed-arity FunctionIR entries (multi-arity)
/// - variadic → separate FunctionIR with :variadic arity
///
/// **Key TreeWalk invariant**: closure capture is BY-VALUE snapshot of `locals[0..slot_base)`.
/// The IR `:make-closure` instruction encodes this as the `:captures` list.
///
/// Returns the IRValueID of the primary function (first method or single-arity).
pub fn compileFnNode(
    ctx: *CompileContext,
    fn_node: FnNode,
) !IRValueID {
    // Generate capture list from slot_base
    // TreeWalk: captures locals[0..slot_base) by value
    var captures = try std.ArrayList([]const u8).initCapacity(ctx.allocator, fn_node.slot_base);
    errdefer captures.deinit(ctx.allocator);
    var i: u16 = 0;
    while (i < fn_node.slot_base) : (i += 1) {
        const capture_name = try std.fmt.allocPrint(ctx.allocator, "slot{d}", .{i});
        try captures.append(ctx.allocator, capture_name);
    }

    var first_fn_id: ?IRValueID = null;

    // Compile each fixed-arity method
    for (fn_node.methods) |method| {
        const func = try compileFnMethod(ctx, fn_node, method, captures.items);
        const fn_id = try ctx.registerFunction(func);
        if (first_fn_id == null) first_fn_id = fn_id;
    }

    // Compile variadic method (if present)
    if (fn_node.variadic) |variadic_method| {
        const func = try compileFnMethod(ctx, fn_node, variadic_method, captures.items);
        const fn_id = try ctx.registerFunction(func);
        if (first_fn_id == null) first_fn_id = fn_id;
    }

    return first_fn_id.?;
}

/// Compile a single FnMethod → FunctionIR
fn compileFnMethod(
    ctx: *CompileContext,
    fn_node: FnNode,
    method: FnMethod,
    captures: []const []const u8,
) !FunctionIR {
    // Generate function ID
    const fn_id = try ctx.freshFnID(fn_node.name);
    const fn_name_slice = fn_id.fn_ref;

    // Copy parameters
    const params = try ctx.allocator.dupe([]const u8, method.params);
    errdefer ctx.allocator.free(params);

    // Copy captures
    const cap_copy = try ctx.allocator.dupe([]const u8, captures);
    errdefer ctx.allocator.free(cap_copy);

    // Determine arity (direct union initialization with explicit type annotation)
    const ArityType = @TypeOf(@as(FunctionIR, undefined).arity);
    const arity_field: ArityType = if (method.has_rest)
        .{ .variadic = .{ .required = method.arity, .rest = true } }
    else
        .{ .fixed = method.arity };

    // Create entry block
    var blocks: std.ArrayList(BasicBlock) = .empty;
    errdefer {
        for (blocks.items) |*block| block.deinit(ctx.allocator);
        blocks.deinit(ctx.allocator);
    }

    const entry_block_id = try ctx.freshBlockID("entry");
    var entry_block = BasicBlock{
        .id = entry_block_id,
        .instructions = .empty,
    };

    // Compile method.body → entry_block instructions
    const body_val = try compileNode(ctx, method.body);

    // Terminator: return the body value (heap-allocate args slice)
    const return_args = try ctx.allocator.alloc(IRValueID, 1);
    return_args[0] = body_val;
    entry_block.terminator = IRInstr{
        .op = "return",
        .args = return_args,
    };

    try blocks.append(ctx.allocator, entry_block);

    return FunctionIR{
        .id = fn_name_slice,
        .name = fn_node.name,
        .namespace = fn_node.defining_ns,
        .arity = arity_field,
        .params = params,
        .captures = cap_copy,
        .blocks = blocks,
        .entry_block = entry_block_id,
    };
}

/// Compile any Node → IR value ID
///
/// This is the main entry point that dispatches to node-type-specific compilers.
/// Maps TreeWalk `eval(node)` pattern to IR generation.
pub fn compileNode(ctx: *CompileContext, node: *const Node) CompileError!IRValueID {
    return switch (node.*) {
        .fn_node => |fn_node| try compileFnNode(ctx, fn_node),
        .call_node => |call| try compileCallNode(ctx, call),
        .let_node => |let_node| try compileLetNode(ctx, let_node),
        .if_node => |if_node| try compileIfNode(ctx, if_node),
        .def_node => |def| try compileDefNode(ctx, def),
        .constant => |c| try compileConstantNode(ctx, c),
        .local_ref => |l| try compileLocalRef(ctx, l),
        .var_ref => |v| try compileVarRef(ctx, v),
        .loop_node => |loop| try compileLoopNode(ctx, loop),
        .recur_node => |recur| try compileRecurNode(ctx, recur),
        .try_node => |try_node| try compileTryNode(ctx, try_node),
        .throw_node => |throw_node| try compileThrowNode(ctx, throw_node),
        else => error.UnsupportedNode,
    };
}

/// Compile CallNode → IR :call instruction
///
/// Maps TreeWalk evalCall (line 1172-1198):
/// 1. Evaluate callee
/// 2. Evaluate all arguments in order
/// 3. Generate :call instruction
///
/// Reference: IR v2.0 Section "函數調用"
fn compileCallNode(ctx: *CompileContext, call: node_mod.CallNode) !IRValueID {
    // 1. Compile callee
    const callee_val = try compileNode(ctx, call.callee);

    // 2. Compile all arguments
    var args = try std.ArrayList(IRValueID).initCapacity(ctx.allocator, call.args.len);
    defer args.deinit(ctx.allocator);

    for (call.args) |*arg| {
        const arg_val = try compileNode(ctx, arg);
        try args.append(ctx.allocator, arg_val);
    }

    // 3. Generate :call instruction
    const result = ctx.freshValue();
    const args_slice = try args.toOwnedSlice(ctx.allocator);

    // Note: This will be added to current basic block when we have block context
    // For now, just return the result ID
    _ = IRInstr{
        .op = "call",
        .result = result,
        .fn_id = callee_val,
        .args = args_slice,
    };

    return result;
}

/// Compile LetNode → IR :bind instructions
///
/// Maps TreeWalk evalLet (line 891-898):
/// - Evaluate each binding in order
/// - Generate :bind for each
/// - Compile body with bindings in scope
fn compileLetNode(ctx: *CompileContext, let_node: node_mod.LetNode) !IRValueID {
    // Process bindings sequentially
    for (let_node.bindings) |binding| {
        const value = try compileNode(ctx, binding.value_expr);

        // Generate :bind instruction
        const bind_result = IRValueID{ .local = binding.name };
        _ = IRInstr{
            .op = "bind",
            .result = bind_result,
            .args = &[_]IRValueID{value},
        };
    }

    // Compile body
    return try compileNode(ctx, let_node.body);
}

/// Compile IfNode → IR :branch terminator
///
/// Generates conditional branch with then/else blocks.
fn compileIfNode(ctx: *CompileContext, if_node: node_mod.IfNode) !IRValueID {
    // 1. Evaluate condition
    const cond_val = try compileNode(ctx, if_node.cond);

    // 2. Generate block IDs
    const then_block = try ctx.freshBlockID("then");
    const else_block = try ctx.freshBlockID("else");
    const merge_block = try ctx.freshBlockID("merge");

    // 3. Generate :branch terminator
    _ = IRInstr{
        .op = "branch",
        .args = &[_]IRValueID{ cond_val, then_block, else_block },
    };

    // 4. Compile then branch
    const then_val = try compileNode(ctx, if_node.then_branch);

    // 5. Compile else branch (or nil if missing)
    const else_val = if (if_node.else_branch) |else_br|
        try compileNode(ctx, else_br)
    else
        ctx.freshValue(); // nil constant

    // TODO: Generate phi node in merge block
    _ = merge_block;
    _ = then_val;
    _ = else_val;

    const result = ctx.freshValue();
    return result;
}

/// Compile DefNode → IR :def instruction
///
/// Generates global Var definition.
fn compileDefNode(ctx: *CompileContext, def: node_mod.DefNode) !IRValueID {
    // 1. Evaluate init value if present
    const init_val = if (def.has_init)
        try compileNode(ctx, def.value_expr)
    else
        ctx.freshValue(); // unbound placeholder

    // 2. Generate :def instruction
    const result = ctx.freshValue();
    _ = IRInstr{
        .op = "def",
        .result = result,
        .args = &[_]IRValueID{init_val},
    };

    return result;
}

/// Compile ConstantNode → IR :const instruction
fn compileConstantNode(ctx: *CompileContext, const_node: node_mod.ConstantNode) !IRValueID {
    const result = ctx.freshValue();

    // Store the constant value in the context's constant map
    try ctx.constants.put(result.val, const_node.value);

    _ = IRInstr{
        .op = "const",
        .result = result,
    };

    return result;
}

/// Compile LocalRef → IR :local-ref instruction
fn compileLocalRef(_: *CompileContext, local: node_mod.LocalRef) !IRValueID {
    // Local references use the local name directly
    return IRValueID{ .local = local.name };
}

/// Compile VarRef → IR :var-ref instruction
///
/// Maps TreeWalk evalVarRef (resolved *const Var) to IR.
/// Phase 1: returns a placeholder value ID; full var resolution pending IR v2 runtime.
fn compileVarRef(ctx: *CompileContext, var_ref: node_mod.VarRef) !IRValueID {
    _ = var_ref; // TODO: Encode var_ref.var_ptr namespace + name into IR
    const result = ctx.freshValue();

    _ = IRInstr{
        .op = "var-ref",
        .result = result,
    };

    return result;
}

/// Format FunctionIR → EDN string
pub fn formatFunctionToEDN(
    func: FunctionIR,
    allocator: std.mem.Allocator,
) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    const writer = buf.writer();

    try writer.writeAll("{\n");
    try writer.print("  :id :{s}\n", .{func.id});

    if (func.name) |name| {
        try writer.print("  :name \"{s}\"\n", .{name});
    }

    if (func.namespace) |ns| {
        try writer.print("  :namespace \"{s}\"\n", .{ns});
    }

    // Arity
    try writer.writeAll("  :arity ");
    switch (func.arity) {
        .fixed => |n| try writer.print("{{:fixed {d}}}\n", .{n}),
        .variadic => |v| try writer.print("{{:variadic {{:required {d} :rest? {}}}}}\n", .{ v.required, v.rest }),
    }

    // Params
    try writer.writeAll("  :params [");
    for (func.params, 0..) |param, i| {
        if (i > 0) try writer.writeAll(" ");
        try writer.print(":param/{s}", .{param});
    }
    try writer.writeAll("]\n");

    // Captures
    if (func.captures.len > 0) {
        try writer.writeAll("  :captures [");
        for (func.captures, 0..) |cap, i| {
            if (i > 0) try writer.writeAll(" ");
            try writer.print(":capture/{s}", .{cap});
        }
        try writer.writeAll("]\n");
    }

    // Entry block
    try writer.print("  :entry-block {}\n", .{func.entry_block});

    try writer.writeAll("}\n");

    return buf.toOwnedSlice();
}

test "compileFnNode: simple top-level function (no closure)" {
    const testing = std.testing;
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Construct FnNode: (fn [x] 42) — body returns constant 42
    const param_names = &[_][]const u8{"x"};
    const const_val = Value.initInteger(42);
    var const_node = Node{ .constant = .{ .value = const_val } };
    const method = FnMethod{
        .arity = 1,
        .has_rest = false,
        .params = param_names,
        .body = &const_node,
    };

    const fn_node = FnNode{
        .methods = &[_]FnMethod{method},
        .variadic = null,
        .slot_base = 0, // Top-level, no closure
        .name = "identity",
        .defining_ns = "user",
    };

    var ctx = CompileContext.init(allocator);
    defer ctx.deinit();
    const fn_id = try compileFnNode(&ctx, fn_node);
    _ = fn_id; // compileFnNode returns IRValueID pointing to the compiled function

    try testing.expectEqual(@as(usize, 1), ctx.functions.items.len);
    const func = ctx.functions.items[0];

    try testing.expectEqual(@as(usize, 0), func.captures.len); // No closure
    try testing.expectEqual(@as(usize, 1), func.params.len);
    try testing.expectEqualStrings("x", func.params[0]);
    try testing.expect(func.arity == .fixed);
    try testing.expectEqual(@as(u16, 1), func.arity.fixed);
}

test "compileFnNode: simple closure (let [x 1] (fn [] x))" {
    const testing = std.testing;
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Construct FnNode: (fn [] 42) where closure captures nothing
    const const_val = Value.initInteger(42);
    var const_node = Node{ .constant = .{ .value = const_val } };
    const method = FnMethod{
        .arity = 0,
        .has_rest = false,
        .params = &[_][]const u8{},
        .body = &const_node,
    };

    const fn_node = FnNode{
        .methods = &[_]FnMethod{method},
        .variadic = null,
        .slot_base = 1, // Captures slot 0 (x)
        .name = null,
        .defining_ns = "user",
    };

    var ctx = CompileContext.init(allocator);
    defer ctx.deinit();
    const fn_id = try compileFnNode(&ctx, fn_node);
    _ = fn_id; // compileFnNode returns IRValueID pointing to the compiled function

    try testing.expectEqual(@as(usize, 1), ctx.functions.items.len);
    const func = ctx.functions.items[0];

    try testing.expectEqual(@as(usize, 1), func.captures.len); // Captures slot 0
    try testing.expectEqual(@as(usize, 0), func.params.len); // No parameters
}

test "compileFnNode: multi-arity function" {
    const testing = std.testing;
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Construct FnNode: (fn ([x] 42) ([x y] 84)) — both methods return constants
    const param1 = &[_][]const u8{"x"};
    const param2 = &[_][]const u8{ "x", "y" };
    const const_val1 = Value.initInteger(42);
    const const_val2 = Value.initInteger(84);
    var const_node1 = Node{ .constant = .{ .value = const_val1 } };
    var const_node2 = Node{ .constant = .{ .value = const_val2 } };

    const method1 = FnMethod{
        .arity = 1,
        .has_rest = false,
        .params = param1,
        .body = &const_node1,
    };

    const method2 = FnMethod{
        .arity = 2,
        .has_rest = false,
        .params = param2,
        .body = &const_node2,
    };

    const fn_node = FnNode{
        .methods = &[_]FnMethod{ method1, method2 },
        .variadic = null,
        .slot_base = 0,
        .name = "add",
        .defining_ns = "user",
    };

    var ctx = CompileContext.init(allocator);
    defer ctx.deinit();
    const fn_id = try compileFnNode(&ctx, fn_node);
    _ = fn_id; // compileFnNode returns IRValueID pointing to the compiled function

    try testing.expectEqual(@as(usize, 2), ctx.functions.items.len); // Two arities

    // Check first arity
    const func1 = ctx.functions.items[0];
    try testing.expectEqual(@as(usize, 1), func1.params.len);
    try testing.expectEqual(@as(u16, 1), func1.arity.fixed);

    // Check second arity
    const func2 = ctx.functions.items[1];
    try testing.expectEqual(@as(usize, 2), func2.params.len);
    try testing.expectEqual(@as(u16, 2), func2.arity.fixed);
}

// ============================================================================
// Control Flow Node Compilation (loop/recur/try/throw)
// ============================================================================

/// Compile LoopNode → IR loop with phi nodes
///
/// Maps TreeWalk loop semantics (evalLoop, line 984-1016) to IR v2.0:
/// - Creates loop header block with phi nodes for bindings
/// - Compiles body
/// - Handles recur jumps back to header
///
/// IR structure:
/// ```
/// :block/entry → evaluate initial binding values → jump :block/loop
/// :block/loop (phi nodes for each binding) → body → return or recur-jump
/// ```
fn compileLoopNode(ctx: *CompileContext, loop_node: node_mod.LoopNode) !IRValueID {
    // 1. Create entry block for initial binding evaluation
    const entry_block = try ctx.freshBlockID("loop_entry");
    _ = entry_block;

    // 2. Evaluate initial binding values
    var init_vals = try std.ArrayList(IRValueID).initCapacity(ctx.allocator, loop_node.bindings.len);
    defer init_vals.deinit(ctx.allocator);

    for (loop_node.bindings) |binding| {
        const init_val = try compileNode(ctx, binding.value_expr);
        try init_vals.append(ctx.allocator, init_val);
    }

    // 3. Create loop header block with phi nodes
    const loop_header = try ctx.freshBlockID("loop_header");
    _ = loop_header;

    // 4. Generate phi nodes for each binding
    // Each phi node merges initial value (from entry) and recur value (from back-edge)
    var phi_results = try std.ArrayList(IRValueID).initCapacity(ctx.allocator, loop_node.bindings.len);
    defer phi_results.deinit(ctx.allocator);

    for (loop_node.bindings, 0..) |binding, i| {
        _ = binding;
        const phi_result = ctx.freshValue();
        try phi_results.append(ctx.allocator, phi_result);

        // Generate phi instruction (placeholder - will be filled by actual IR builder)
        _ = IRInstr{
            .op = "phi",
            .result = phi_result,
            .args = &[_]IRValueID{init_vals.items[i]}, // Initial value
        };
    }

    // 5. Compile loop body
    const body_result = try compileNode(ctx, loop_node.body);

    // 6. The body either:
    //    - returns a value (exits loop)
    //    - triggers recur (back-edge to loop_header)
    // The terminator will be added by recur compilation or return

    return body_result;
}

/// Compile RecurNode → recur-jump terminator
///
/// Maps TreeWalk recur semantics (evalRecur, line 1017-1029) to IR v2.0:
/// - Evaluates all arguments
/// - Generates :recur-jump terminator targeting the nearest loop
///
/// IR structure:
/// ```
/// {:op :recur-jump :args [:val/N ...]}
/// ```
fn compileRecurNode(ctx: *CompileContext, recur: node_mod.RecurNode) !IRValueID {
    // 1. Evaluate all recur arguments
    var arg_vals = try std.ArrayList(IRValueID).initCapacity(ctx.allocator, recur.args.len);
    defer arg_vals.deinit(ctx.allocator);

    for (recur.args) |*arg| {
        const arg_val = try compileNode(ctx, arg);
        try arg_vals.append(ctx.allocator, arg_val);
    }

    // 2. Generate recur-jump terminator
    // This jumps back to the loop header and provides new values for phi nodes
    const result = ctx.freshValue();
    const args_slice = try arg_vals.toOwnedSlice(ctx.allocator);

    _ = IRInstr{
        .op = "recur-jump",
        .result = result,
        .args = args_slice,
    };

    // recur does not produce a value in the normal sense -
    // it's a control flow terminator
    // But we return a value ID for consistency with the interface
    return result;
}

/// Compile TryNode → try block with catch handlers
///
/// Maps TreeWalk try semantics (evalTry, full impl) to IR v2.0:
/// - Creates try block
/// - Creates catch handler blocks
/// - Creates finally block (if present)
/// - Proper control flow merge
///
/// IR structure:
/// ```
/// :block/try → body
/// :block/catch-N → catch handler
/// :block/finally → finally handler (optional)
/// :block/merge → continuation
/// ```
fn compileTryNode(ctx: *CompileContext, try_node: node_mod.TryNode) !IRValueID {
    // 1. Create try block
    const try_block = try ctx.freshBlockID("try");
    _ = try_block;

    // 2. Compile try body
    const try_result = try compileNode(ctx, try_node.body);

    // 3. Create catch handler blocks
    var catch_blocks = try std.ArrayList(IRValueID).initCapacity(ctx.allocator, try_node.catch_clauses.len);
    defer catch_blocks.deinit(ctx.allocator);

    for (try_node.catch_clauses, 0..) |clause, i| {
        _ = clause;
        const catch_block = try ctx.freshBlockID(try std.fmt.allocPrint(ctx.allocator, "catch_{d}", .{i}));
        try catch_blocks.append(ctx.allocator, catch_block);

        // Each catch clause has:
        // - binding_name: the exception is bound to this local
        // - body: the handler code
        // These will be compiled when we have proper block context
    }

    // 4. Create finally block (if present)
    var finally_block: ?IRValueID = null;
    if (try_node.finally_body) |finally_body| {
        finally_block = try ctx.freshBlockID("finally");
        _ = finally_body; // Will compile in proper block context
    }

    // 5. Create merge block for normal continuation
    const merge_block = try ctx.freshBlockID("try_merge");
    _ = merge_block;

    // 6. Generate try instruction (simplified for Phase 1)
    const result = ctx.freshValue();
    _ = IRInstr{
        .op = "try",
        .result = result,
        .args = &[_]IRValueID{try_result},
    };

    // The actual result depends on which path was taken
    // For Phase 1, we return the try_result
    return try_result;
}

/// Compile ThrowNode → throw terminator
///
/// Maps TreeWalk throw semantics (evalThrow) to IR v2.0:
/// - Evaluates exception value
/// - Generates :throw terminator
///
/// IR structure:
/// ```
/// {:op :throw :value :val/N}
/// ```
fn compileThrowNode(ctx: *CompileContext, throw_node: node_mod.ThrowNode) !IRValueID {
    // 1. Evaluate exception expression
    const exception_val = try compileNode(ctx, throw_node.expr);

    // 2. Generate throw terminator
    const result = ctx.freshValue();
    _ = IRInstr{
        .op = "throw",
        .result = result,
        .args = &[_]IRValueID{exception_val},
    };

    // throw does not produce a value in the normal sense -
    // it's a control flow terminator that unwinds the stack
    // But we return a value ID for consistency with the interface
    return result;
}
