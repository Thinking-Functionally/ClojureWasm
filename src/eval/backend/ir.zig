// SPDX-License-Identifier: EPL-2.0
//! IR Backend — compile Analyzer Node tree to EDN-based IR format.
//!
//! This backend translates the typed AST (Node union) into an intermediate
//! representation suitable for further compilation to WASM or interpretation.
//! The IR is SSA-form with explicit control flow (basic blocks, phi nodes).
//!
//! ### Design
//!
//! - **Input**: Analyzer Node tree (from `src/eval/node.zig`)
//! - **Output**: EDN string representing IR (consumed by `src/ir/ir_to_wasm.zig`)
//! - **SSA form**: Each value has unique ID (`:v0`, `:v1`, ...)
//! - **Multi-block CFG**: Functions composed of basic blocks with terminators
//!
//! ### Node → IR mapping
//!
//! - `constant` → `{:op "const" :result :v0 :value 42}`
//! - `local_ref` → `{:op "var-ref" :result :v1 :var :param0}`
//! - `if_node` → branch terminator with then/else blocks + phi merge
//! - `fn_node` → function with params + entry block
//! - `call_node` → `{:op "call" :result :v2 :fn "builtin/+" :args [:v0 :v1]}`
//!
//! This is an **experimental backend** on the `experimental/ir-rewrite` branch.
//! It will NOT merge to main until proven stable.

const std = @import("std");
const node_mod = @import("../node.zig");
const Node = node_mod.Node;
const Value = @import("../../runtime/value/value.zig").Value;

pub const CompileError = error{
    OutOfMemory,
    UnsupportedNode,
    InvalidNode,
};

/// IR Compiler state
pub const IRCompiler = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    next_value_id: u32,
    next_block_id: u32,
    blocks: std.ArrayList(Block),
    current_block: ?*Block,
    /// Track all allocated value IDs for cleanup
    value_ids: std.ArrayList([]const u8),

    pub const Block = struct {
        id: []const u8,
        instructions: std.ArrayList([]const u8),
        terminator: ?[]const u8,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, id: []const u8) Block {
            return .{
                .id = id,
                .instructions = .empty,
                .terminator = null,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Block) void {
            self.allocator.free(self.id);
            for (self.instructions.items) |instr| {
                self.allocator.free(instr);
            }
            self.instructions.deinit(self.allocator);
            if (self.terminator) |t| {
                self.allocator.free(t);
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator) IRCompiler {
        return .{
            .allocator = allocator,
            .output = .empty,
            .next_value_id = 0,
            .next_block_id = 0,
            .blocks = .empty,
            .current_block = null,
            .value_ids = .empty,
        };
    }

    pub fn deinit(self: *IRCompiler) void {
        self.output.deinit(self.allocator);
        for (self.blocks.items) |*block| {
            block.deinit();
        }
        self.blocks.deinit(self.allocator);
        for (self.value_ids.items) |vid| {
            self.allocator.free(vid);
        }
        self.value_ids.deinit(self.allocator);
    }

    /// Generate next value ID (caller owns the returned memory)
    fn nextValueId(self: *IRCompiler) ![]const u8 {
        const id = self.next_value_id;
        self.next_value_id += 1;
        const vid = try std.fmt.allocPrint(self.allocator, ":v{d}", .{id});
        try self.value_ids.append(self.allocator, vid);
        return vid;
    }

    /// Generate next block ID (caller owns the returned memory)
    fn nextBlockId(self: *IRCompiler) ![]const u8 {
        const id = self.next_block_id;
        self.next_block_id += 1;
        return try std.fmt.allocPrint(self.allocator, ":block{d}", .{id});
    }

    /// Create a new basic block
    fn createBlock(self: *IRCompiler, id: []const u8) !*Block {
        const block = Block.init(self.allocator, id);
        try self.blocks.append(self.allocator, block);
        return &self.blocks.items[self.blocks.items.len - 1];
    }

    /// Emit instruction to current block
    fn emitInstruction(self: *IRCompiler, instr: []const u8) !void {
        if (self.current_block) |block| {
            try block.instructions.append(self.allocator, instr);
        } else {
            return error.InvalidNode;
        }
    }

    /// Set terminator for current block
    fn setTerminator(self: *IRCompiler, term: []const u8) !void {
        if (self.current_block) |block| {
            if (block.terminator != null) {
                return error.InvalidNode; // Block already has terminator
            }
            block.terminator = term;
        } else {
            return error.InvalidNode;
        }
    }

    /// Compile a Node to IR and return the result value ID
    pub fn compileNode(self: *IRCompiler, node: *const Node, params: []const []const u8) CompileError![]const u8 {
        return switch (node.*) {
            .constant => |n| try self.compileConstant(n),
            .local_ref => |n| try self.compileLocalRef(n, params),
            .var_ref => return error.UnsupportedNode, // TODO: global vars
            .call_node => |n| try self.compileCall(n, params),
            .if_node => |n| try self.compileIf(n, params),
            .fn_node => return error.UnsupportedNode, // Nested functions handled separately
            .do_node => |n| try self.compileDo(n, params),
            .let_node => |n| try self.compileLet(n, params),
            .quote_node => |n| try self.compileQuote(n),
            else => error.UnsupportedNode,
        };
    }

    fn compileConstant(self: *IRCompiler, n: node_mod.ConstantNode) ![]const u8 {
        const result = try self.nextValueId();
        const value_str = try self.valueToString(n.value);
        defer self.allocator.free(value_str);

        const instr = try std.fmt.allocPrint(
            self.allocator,
            "{{:op \"const\" :result {s} :value {s}}}",
            .{ result, value_str }
        );
        try self.emitInstruction(instr);
        return result;
    }

    fn compileLocalRef(self: *IRCompiler, n: node_mod.LocalRef, params: []const []const u8) ![]const u8 {
        const result = try self.nextValueId();

        // Map local index to parameter name
        if (n.index >= params.len) {
            return error.InvalidNode;
        }
        const var_id = params[n.index];

        const instr = try std.fmt.allocPrint(
            self.allocator,
            "{{:op \"var-ref\" :result {s} :var {s}}}",
            .{ result, var_id }
        );
        try self.emitInstruction(instr);
        return result;
    }

    fn compileCall(self: *IRCompiler, n: node_mod.CallNode, params: []const []const u8) ![]const u8 {
        const result = try self.nextValueId();

        // Compile arguments
        var args: std.ArrayList([]const u8) = .empty;
        defer args.deinit(self.allocator);

        for (n.args) |arg| {
            const arg_val = try self.compileNode(&arg, params);
            try args.append(self.allocator, arg_val);
        }

        // Determine function name
        const fn_name = try self.getFunctionName(n.callee, params);
        defer self.allocator.free(fn_name);

        // Build args list string
        var args_str: std.ArrayList(u8) = .empty;
        defer args_str.deinit(self.allocator);
        try args_str.appendSlice(self.allocator, "[");
        for (args.items, 0..) |arg, i| {
            if (i > 0) try args_str.appendSlice(self.allocator, " ");
            try args_str.appendSlice(self.allocator, arg);
        }
        try args_str.appendSlice(self.allocator, "]");

        const instr = try std.fmt.allocPrint(
            self.allocator,
            "{{:op \"call\" :result {s} :fn \"{s}\" :args {s}}}",
            .{ result, fn_name, args_str.items }
        );
        try self.emitInstruction(instr);
        return result;
    }

    fn compileIf(self: *IRCompiler, n: node_mod.IfNode, params: []const []const u8) ![]const u8 {
        // Compile condition
        const cond_val = try self.compileNode(n.cond, params);

        // Create blocks for then, else, and merge
        const then_id = try self.nextBlockId();
        const else_id = try self.nextBlockId();
        const merge_id = try self.nextBlockId();

        // Emit branch terminator in current block
        const branch_term = try std.fmt.allocPrint(
            self.allocator,
            "{{:op \"branch\" :condition {s} :then {s} :else {s}}}",
            .{ cond_val, then_id, else_id }
        );
        try self.setTerminator(branch_term);

        // Then block
        const then_block = try self.createBlock(then_id);
        self.current_block = then_block;
        const then_val = try self.compileNode(n.then_branch, params);
        const then_jump = try std.fmt.allocPrint(
            self.allocator,
            "{{:op \"jump\" :target {s} :value {s}}}",
            .{ merge_id, then_val }
        );
        try self.setTerminator(then_jump);

        // Else block
        const else_block = try self.createBlock(else_id);
        self.current_block = else_block;
        const else_val = if (n.else_branch) |eb|
            try self.compileNode(eb, params)
        else
            try self.compileConstant(.{ .value = Value.nil_val, .loc = .{} });

        const else_jump = try std.fmt.allocPrint(
            self.allocator,
            "{{:op \"jump\" :target {s} :value {s}}}",
            .{ merge_id, else_val }
        );
        try self.setTerminator(else_jump);

        // Merge block with phi
        const merge_block = try self.createBlock(merge_id);
        self.current_block = merge_block;

        const result = try self.nextValueId();
        const phi_instr = try std.fmt.allocPrint(
            self.allocator,
            "{{:op \"phi\" :result {s} :sources [{{:block {s} :value {s}}} {{:block {s} :value {s}}}]}}",
            .{ result, then_id, then_val, else_id, else_val }
        );
        try self.emitInstruction(phi_instr);

        return result;
    }

    fn compileDo(self: *IRCompiler, n: node_mod.DoNode, params: []const []const u8) ![]const u8 {
        if (n.forms.len == 0) {
            return try self.compileConstant(.{ .value = Value.nil_val, .loc = .{} });
        }

        var last_val: []const u8 = undefined;
        for (n.forms) |form| {
            last_val = try self.compileNode(&form, params);
        }
        return last_val;
    }

    fn compileLet(self: *IRCompiler, n: node_mod.LetNode, params: []const []const u8) ![]const u8 {
        // Create extended params list including let bindings
        const new_params_len = params.len + n.bindings.len;
        var new_params = try self.allocator.alloc([]const u8, new_params_len);
        defer {
            // Free the local_id strings we allocated
            for (new_params[params.len..]) |local_id| {
                self.allocator.free(local_id);
            }
            self.allocator.free(new_params);
        }

        // Copy original params
        @memcpy(new_params[0..params.len], params);

        // Compile each binding and add to params
        for (n.bindings, 0..) |binding, i| {
            const binding_val = try self.compileNode(binding.value_expr, new_params[0..params.len + i]);

            // Create local binding instruction
            const local_id = try std.fmt.allocPrint(
                self.allocator,
                ":local{d}",
                .{binding.index}
            );
            new_params[params.len + i] = local_id;

            const bind_instr = try std.fmt.allocPrint(
                self.allocator,
                "{{:op \"bind\" :local {s} :value {s}}}",
                .{ local_id, binding_val }
            );
            try self.emitInstruction(bind_instr);
        }

        // Compile body with extended params
        return try self.compileNode(n.body, new_params);
    }

    fn compileQuote(self: *IRCompiler, n: node_mod.QuoteNode) ![]const u8 {
        // QuoteNode already has the quoted value reified by the analyzer
        // Just emit it as a constant
        const result = try self.nextValueId();
        const value_str = try self.valueToString(n.quoted);
        defer self.allocator.free(value_str);

        const instr = try std.fmt.allocPrint(
            self.allocator,
            "{{:op \"const\" :result {s} :value {s}}}",
            .{ result, value_str }
        );
        try self.emitInstruction(instr);
        return result;
    }

    fn getFunctionName(self: *IRCompiler, callee: *const Node, params: []const []const u8) ![]const u8 {
        return switch (callee.*) {
            .var_ref => |vr| {
                // Extract function name from var
                const name = vr.var_ptr.name;
                return try std.fmt.allocPrint(self.allocator, "builtin/{s}", .{name});
            },
            else => {
                _ = params;
                return error.UnsupportedNode;
            },
        };
    }

    fn valueToString(self: *IRCompiler, v: Value) ![]const u8 {
        if (v.isNumber()) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{v.asFloat()});
        } else if (v == Value.nil_val) {
            return try std.fmt.allocPrint(self.allocator, "nil", .{});
        } else if (v == Value.true_val) {
            return try std.fmt.allocPrint(self.allocator, "true", .{});
        } else if (v == Value.false_val) {
            return try std.fmt.allocPrint(self.allocator, "false", .{});
        }
        return error.UnsupportedNode;
    }

    /// Generate final EDN IR string
    pub fn finalize(self: *IRCompiler, params: []const []const u8, entry_block: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        defer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, "{:entry-block ");
        try result.appendSlice(self.allocator, entry_block);
        try result.appendSlice(self.allocator, " :params [");
        for (params, 0..) |p, i| {
            if (i > 0) try result.appendSlice(self.allocator, " ");
            try result.appendSlice(self.allocator, p);
        }
        try result.appendSlice(self.allocator, "] :block-defs {");

        for (self.blocks.items, 0..) |block, i| {
            if (i > 0) try result.appendSlice(self.allocator, " ");
            try result.appendSlice(self.allocator, block.id);
            try result.appendSlice(self.allocator, " {:instructions [");

            for (block.instructions.items, 0..) |instr, j| {
                if (j > 0) try result.appendSlice(self.allocator, " ");
                try result.appendSlice(self.allocator, instr);
            }

            try result.appendSlice(self.allocator, "] :terminator ");
            if (block.terminator) |t| {
                try result.appendSlice(self.allocator, t);
            } else {
                try result.appendSlice(self.allocator, "nil");
            }
            try result.appendSlice(self.allocator, "}");
        }

        try result.appendSlice(self.allocator, "}}");

        return try result.toOwnedSlice(self.allocator);
    }
};

/// Compile a function Node to IR EDN string
pub fn compileFunctionToIR(allocator: std.mem.Allocator, fn_node: node_mod.FnNode) ![]const u8 {
    var compiler = IRCompiler.init(allocator);
    defer compiler.deinit();

    // For now, only handle single-arity functions
    if (fn_node.methods.len != 1) {
        return error.UnsupportedNode;
    }

    const method = fn_node.methods[0];

    // Create parameter IDs
    var params = try allocator.alloc([]const u8, method.arity);
    defer {
        for (params) |p| {
            allocator.free(p);
        }
        allocator.free(params);
    }

    for (0..method.arity) |i| {
        params[i] = try std.fmt.allocPrint(allocator, ":param{d}", .{i});
    }

    // Create entry block
    const entry_id = try compiler.nextBlockId();
    const entry_block = try compiler.createBlock(entry_id);
    compiler.current_block = entry_block;

    // Compile function body
    const result_val = try compiler.compileNode(method.body, params);

    // Add return terminator
    const return_term = try std.fmt.allocPrint(
        allocator,
        "{{:op \"return\" :value {s}}}",
        .{result_val}
    );
    try compiler.setTerminator(return_term);

    // Generate final IR
    return try compiler.finalize(params, entry_id);
}

// --- Tests ---

test "IR Backend: compile constant" {
    const testing = std.testing;
    const body = Node{ .constant = .{ .value = Value.initFloat(42) } };
    const fn_node = node_mod.FnNode{
        .methods = &[_]node_mod.FnMethod{.{
            .arity = 0,
            .params = &[_][]const u8{},
            .body = &body,
        }},
    };

    const ir = try compileFunctionToIR(testing.allocator, fn_node);
    defer testing.allocator.free(ir);

    // Check that IR contains expected elements
    try testing.expect(std.mem.indexOf(u8, ir, ":entry-block") != null);
    try testing.expect(std.mem.indexOf(u8, ir, "\"const\"") != null);
    try testing.expect(std.mem.indexOf(u8, ir, "42") != null);
}

test "IR Backend: compile local ref" {
    const testing = std.testing;
    const param0 = Node{ .local_ref = .{ .name = "x", .index = 0 } };
    const fn_node = node_mod.FnNode{
        .methods = &[_]node_mod.FnMethod{.{
            .arity = 1,
            .params = &[_][]const u8{"x"},
            .body = &param0,
        }},
    };

    const ir = try compileFunctionToIR(testing.allocator, fn_node);
    defer testing.allocator.free(ir);

    try testing.expect(std.mem.indexOf(u8, ir, "\"var-ref\"") != null);
    try testing.expect(std.mem.indexOf(u8, ir, ":param0") != null);
}

test "IR Backend: compile if expression" {
    const testing = std.testing;
    const cond = Node{ .constant = .{ .value = Value.true_val } };
    const then_branch = Node{ .constant = .{ .value = Value.initFloat(1) } };
    const else_branch = Node{ .constant = .{ .value = Value.initFloat(2) } };
    const if_node = Node{ .if_node = .{
        .cond = &cond,
        .then_branch = &then_branch,
        .else_branch = &else_branch,
    } };

    const fn_node = node_mod.FnNode{
        .methods = &[_]node_mod.FnMethod{.{
            .arity = 0,
            .params = &[_][]const u8{},
            .body = &if_node,
        }},
    };

    const ir = try compileFunctionToIR(testing.allocator, fn_node);
    defer testing.allocator.free(ir);

    try testing.expect(std.mem.indexOf(u8, ir, "\"branch\"") != null);
    try testing.expect(std.mem.indexOf(u8, ir, "\"phi\"") != null);
    try testing.expect(std.mem.indexOf(u8, ir, ":block") != null);
}

test "IR Backend: compile let expression" {
    const testing = std.testing;

    // (let [x 42] x) - bind 42 to x, then return x
    const binding_val = Node{ .constant = .{ .value = Value.initFloat(42) } };
    const body = Node{ .local_ref = .{ .name = "x", .index = 0 } };

    const bindings = [_]node_mod.LetNode.Binding{.{
        .name = "x",
        .index = 0,
        .value_expr = &binding_val,
    }};

    const let_node = Node{ .let_node = .{
        .bindings = &bindings,
        .body = &body,
    } };

    const fn_node = node_mod.FnNode{
        .methods = &[_]node_mod.FnMethod{.{
            .arity = 0,
            .params = &[_][]const u8{},
            .body = &let_node,
        }},
    };

    const ir = try compileFunctionToIR(testing.allocator, fn_node);
    defer testing.allocator.free(ir);

    try testing.expect(std.mem.indexOf(u8, ir, "\"bind\"") != null);
    try testing.expect(std.mem.indexOf(u8, ir, ":local0") != null);
    try testing.expect(std.mem.indexOf(u8, ir, "42") != null);
}
