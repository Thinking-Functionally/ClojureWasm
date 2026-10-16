// SPDX-License-Identifier: EPL-2.0
//! Minimal Zig backend for Phase 1 PoC
//! Compiles IR (EDN) to executable code via interpretation

const std = @import("std");
const edn = @import("edn_parser.zig");

pub const IRError = error{
    InvalidIR,
    UnsupportedOperation,
    MissingField,
    TypeMismatch,
} || edn.ParseError || std.mem.Allocator.Error;

/// Simple interpreter that executes IR directly
pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    values: std.StringHashMap(f64),
    blocks: std.StringHashMap(edn.EDNValue),
    functions: std.StringHashMap(edn.EDNValue),
    last_block: []const u8,

    pub fn init(allocator: std.mem.Allocator) Interpreter {
        return .{
            .allocator = allocator,
            .values = std.StringHashMap(f64).init(allocator),
            .blocks = std.StringHashMap(edn.EDNValue).init(allocator),
            .functions = std.StringHashMap(edn.EDNValue).init(allocator),
            .last_block = "",
        };
    }

    pub fn deinit(self: *Interpreter) void {
        self.values.deinit();
        self.blocks.deinit();
        self.functions.deinit();
    }

    /// Register a function in the function table
    pub fn registerFunction(self: *Interpreter, ir: edn.EDNValue) !void {
        if (ir != .map) return IRError.InvalidIR;

        const id_val = ir.map.get("id") orelse return IRError.MissingField;
        if (id_val != .keyword) return IRError.TypeMismatch;

        // Copy the function ID key to permanent storage
        const id_copy = try self.allocator.dupe(u8, id_val.keyword);
        errdefer self.allocator.free(id_copy);

        try self.functions.put(id_copy, ir);
    }

    /// Execute a function IR with given arguments
    pub fn executeFunction(self: *Interpreter, ir_edn: []const u8, args: []const f64) !f64 {
        // Parse IR with permanent allocator (not arena)
        var ir = try edn.parse(self.allocator, ir_edn);
        // Note: We don't defer deinit here because we store the IR in the function table

        if (ir != .map) return IRError.InvalidIR;

        // Register this function
        try self.registerFunction(ir);

        // Extract function ID for execution
        const id_val = ir.map.get("id") orelse return IRError.MissingField;
        if (id_val != .keyword) return IRError.TypeMismatch;

        // Execute the function
        return try self.callFunction(id_val.keyword, args);
    }

    /// Call a function by ID with arguments
    fn callFunction(self: *Interpreter, fn_id: []const u8, args: []const f64) IRError!f64 {
        const ir = self.functions.get(fn_id) orelse return IRError.MissingField;
        if (ir != .map) return IRError.TypeMismatch;

        // Extract params
        const params_val = ir.map.get("params") orelse return IRError.MissingField;
        if (params_val != .vector) return IRError.TypeMismatch;

        // Save current values (for recursion)
        var saved_values = std.StringHashMap(f64).init(self.allocator);
        defer saved_values.deinit();

        var it = self.values.iterator();
        while (it.next()) |entry| {
            try saved_values.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Bind parameters
        self.values.clearRetainingCapacity();
        for (params_val.vector, 0..) |param, i| {
            if (param != .keyword) return IRError.TypeMismatch;
            try self.values.put(param.keyword, args[i]);
        }

        // Get block-defs and load all blocks
        const block_defs = ir.map.get("block-defs") orelse return IRError.MissingField;
        if (block_defs != .map) return IRError.TypeMismatch;

        self.blocks.clearRetainingCapacity();
        var block_it = block_defs.map.iterator();
        while (block_it.next()) |entry| {
            try self.blocks.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Get entry block ID
        const entry_block_id = ir.map.get("entry-block") orelse return IRError.MissingField;
        if (entry_block_id != .keyword) return IRError.TypeMismatch;

        // Execute from entry block
        const result = try self.executeBlockChain(entry_block_id.keyword);

        // Restore values (for recursion)
        self.values.clearRetainingCapacity();
        var restore_it = saved_values.iterator();
        while (restore_it.next()) |entry| {
            try self.values.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        return result;
    }

    fn executeBlockChain(self: *Interpreter, block_id: []const u8) IRError!f64 {
        var current_block_id = block_id;

        while (true) {
            const block = self.blocks.get(current_block_id) orelse return IRError.MissingField;
            if (block != .map) return IRError.TypeMismatch;

            // Execute instructions
            const instrs_val = block.map.get("instructions") orelse return IRError.MissingField;
            if (instrs_val != .vector) return IRError.TypeMismatch;

            for (instrs_val.vector) |instr_val| {
                if (instr_val != .map) return IRError.TypeMismatch;
                try self.executeInstruction(instr_val);
            }

            // Execute terminator
            const terminator = block.map.get("terminator") orelse return IRError.MissingField;
            if (terminator == .nil) {
                // Merge block with no terminator - use phi result
                if (instrs_val.vector.len == 0) return IRError.InvalidIR;
                const last_instr = instrs_val.vector[instrs_val.vector.len - 1];
                if (last_instr != .map) return IRError.TypeMismatch;

                // Check if last instruction is a phi
                const last_op = last_instr.map.get("op") orelse return IRError.MissingField;
                if (last_op != .keyword) return IRError.TypeMismatch;
                if (!std.mem.eql(u8, last_op.keyword, "phi")) return IRError.InvalidIR;

                const result_val = last_instr.map.get("result") orelse return IRError.MissingField;
                if (result_val != .keyword) return IRError.TypeMismatch;
                return self.values.get(result_val.keyword) orelse return IRError.MissingField;
            }

            if (terminator != .map) return IRError.TypeMismatch;

            const op_val = terminator.map.get("op") orelse return IRError.MissingField;
            if (op_val != .keyword) return IRError.TypeMismatch;
            const op = op_val.keyword;

            if (std.mem.eql(u8, op, "return")) {
                const value_val = terminator.map.get("value") orelse return IRError.MissingField;
                if (value_val != .keyword) return IRError.TypeMismatch;
                return self.values.get(value_val.keyword) orelse return IRError.MissingField;
            } else if (std.mem.eql(u8, op, "branch")) {
                const cond_val = terminator.map.get("condition") orelse return IRError.MissingField;
                if (cond_val != .keyword) return IRError.TypeMismatch;
                const cond = self.values.get(cond_val.keyword) orelse return IRError.MissingField;

                const then_val = terminator.map.get("then") orelse return IRError.MissingField;
                if (then_val != .keyword) return IRError.TypeMismatch;

                const else_val = terminator.map.get("else") orelse return IRError.MissingField;
                if (else_val != .keyword) return IRError.TypeMismatch;

                // Set last_block BEFORE jumping
                self.last_block = current_block_id;
                current_block_id = if (cond != 0) then_val.keyword else else_val.keyword;
            } else if (std.mem.eql(u8, op, "jump")) {
                const target_val = terminator.map.get("target") orelse return IRError.MissingField;
                if (target_val != .keyword) return IRError.TypeMismatch;

                // Set last_block to current block BEFORE jumping
                self.last_block = current_block_id;
                current_block_id = target_val.keyword;
            } else {
                return IRError.UnsupportedOperation;
            }
        }
    }

    fn executeBlock(self: *Interpreter, block: edn.EDNValue) !f64 {
        const instrs_val = block.map.get("instructions") orelse return IRError.MissingField;
        if (instrs_val != .vector) return IRError.TypeMismatch;

        // Execute each instruction
        for (instrs_val.vector) |instr_val| {
            if (instr_val != .map) return IRError.TypeMismatch;
            try self.executeInstruction(instr_val);
        }

        // Execute terminator
        const terminator = block.map.get("terminator") orelse return IRError.MissingField;
        if (terminator != .map) return IRError.TypeMismatch;

        return try self.executeTerminator(terminator);
    }

    fn executeInstruction(self: *Interpreter, instr: edn.EDNValue) IRError!void {
        const op_val = instr.map.get("op") orelse return IRError.MissingField;
        if (op_val != .keyword) return IRError.TypeMismatch;
        const op = op_val.keyword;

        if (std.mem.eql(u8, op, "const")) {
            const result_val = instr.map.get("result") orelse return IRError.MissingField;
            if (result_val != .keyword) return IRError.TypeMismatch;
            const result = result_val.keyword;
            const value_val = instr.map.get("value") orelse return IRError.MissingField;
            if (value_val != .number) return IRError.TypeMismatch;
            try self.values.put(result, value_val.number);
        } else if (std.mem.eql(u8, op, "var-ref")) {
            const result_val = instr.map.get("result") orelse return IRError.MissingField;
            if (result_val != .keyword) return IRError.TypeMismatch;
            const result = result_val.keyword;
            const var_val = instr.map.get("var") orelse return IRError.MissingField;
            if (var_val != .keyword) return IRError.TypeMismatch;
            const val = self.values.get(var_val.keyword) orelse return IRError.MissingField;
            try self.values.put(result, val);
        } else if (std.mem.eql(u8, op, "let-bind")) {
            const name_val = instr.map.get("name") orelse return IRError.MissingField;
            if (name_val != .keyword) return IRError.TypeMismatch;
            const value_val = instr.map.get("value") orelse return IRError.MissingField;
            if (value_val != .keyword) return IRError.TypeMismatch;
            const val = self.values.get(value_val.keyword) orelse return IRError.MissingField;
            try self.values.put(name_val.keyword, val);
        } else if (std.mem.eql(u8, op, "phi")) {
            const result_val = instr.map.get("result") orelse return IRError.MissingField;
            if (result_val != .keyword) return IRError.TypeMismatch;
            const result = result_val.keyword;
            const sources_val = instr.map.get("sources") orelse return IRError.MissingField;
            if (sources_val != .vector) return IRError.TypeMismatch;

            // Phi node: select value based on which block we came from
            for (sources_val.vector) |source| {
                if (source != .map) return IRError.TypeMismatch;
                const block_val = source.map.get("block") orelse return IRError.MissingField;
                if (block_val != .keyword) return IRError.TypeMismatch;

                if (std.mem.eql(u8, block_val.keyword, self.last_block)) {
                    const value_val = source.map.get("value") orelse return IRError.MissingField;
                    if (value_val != .keyword) return IRError.TypeMismatch;
                    const val = self.values.get(value_val.keyword) orelse return IRError.MissingField;
                    try self.values.put(result, val);
                    break;
                }
            }
        } else if (std.mem.eql(u8, op, "call")) {
            const result_val = instr.map.get("result") orelse return IRError.MissingField;
            if (result_val != .keyword) return IRError.TypeMismatch;
            const result = result_val.keyword;
            const func_val = instr.map.get("fn") orelse return IRError.MissingField;
            if (func_val != .keyword) return IRError.TypeMismatch;

            const args_val = instr.map.get("args") orelse return IRError.MissingField;
            if (args_val != .vector) return IRError.TypeMismatch;

            // Get argument values
            var arg_values: std.ArrayList(f64) = .empty;
            defer arg_values.deinit(self.allocator);

            for (args_val.vector) |arg| {
                if (arg != .keyword) return IRError.TypeMismatch;
                const val = self.values.get(arg.keyword) orelse return IRError.MissingField;
                try arg_values.append(self.allocator, val);
            }

            // Check if builtin or user-defined function
            const result_val_computed = if (std.mem.startsWith(u8, func_val.keyword, "builtin/"))
                try self.executeBuiltin(func_val.keyword, arg_values.items)
            else if (std.mem.startsWith(u8, func_val.keyword, "fn/user-"))
                try self.callFunction(func_val.keyword, arg_values.items)
            else
                return IRError.UnsupportedOperation;

            try self.values.put(result, result_val_computed);
        } else {
            return IRError.UnsupportedOperation;
        }
    }

    fn executeBuiltin(self: *Interpreter, func: []const u8, args: []const f64) IRError!f64 {
        _ = self;

        if (std.mem.eql(u8, func, "builtin/+")) {
            if (args.len != 2) return IRError.InvalidIR;
            return args[0] + args[1];
        } else if (std.mem.eql(u8, func, "builtin/-")) {
            if (args.len == 1) return -args[0];
            if (args.len != 2) return IRError.InvalidIR;
            return args[0] - args[1];
        } else if (std.mem.eql(u8, func, "builtin/*")) {
            if (args.len != 2) return IRError.InvalidIR;
            return args[0] * args[1];
        } else if (std.mem.eql(u8, func, "builtin/=")) {
            if (args.len != 2) return IRError.InvalidIR;
            return if (args[0] == args[1]) 1.0 else 0.0;
        } else if (std.mem.eql(u8, func, "builtin/<")) {
            if (args.len != 2) return IRError.InvalidIR;
            return if (args[0] < args[1]) 1.0 else 0.0;
        } else if (std.mem.eql(u8, func, "builtin/>")) {
            if (args.len != 2) return IRError.InvalidIR;
            return if (args[0] > args[1]) 1.0 else 0.0;
        } else if (std.mem.eql(u8, func, "builtin/<=")) {
            if (args.len != 2) return IRError.InvalidIR;
            return if (args[0] <= args[1]) 1.0 else 0.0;
        } else if (std.mem.eql(u8, func, "builtin/>=")) {
            if (args.len != 2) return IRError.InvalidIR;
            return if (args[0] >= args[1]) 1.0 else 0.0;
        } else if (std.mem.eql(u8, func, "builtin/not")) {
            if (args.len != 1) return IRError.InvalidIR;
            return if (args[0] == 0) 1.0 else 0.0;
        } else {
            return IRError.UnsupportedOperation;
        }
    }

    fn executeTerminator(self: *Interpreter, term: edn.EDNValue) !f64 {
        const op_val = term.map.get("op") orelse return IRError.MissingField;
        if (op_val != .keyword) return IRError.TypeMismatch;
        const op = op_val.keyword;

        if (std.mem.eql(u8, op, "return")) {
            const value_val = term.map.get("value") orelse return IRError.MissingField;
            if (value_val != .keyword) return IRError.TypeMismatch;
            return self.values.get(value_val.keyword) orelse return IRError.MissingField;
        }

        return IRError.UnsupportedOperation;
    }
};

// ========== Tests ==========

test "execute add function" {
    const ir_edn =
        \\{:id :fn/user-add-1
        \\ :name "add"
        \\ :namespace "user"
        \\ :arity {:fixed 2}
        \\ :params [:param/x :param/y]
        \\ :blocks [:block/entry]
        \\ :entry-block :block/entry
        \\ :block-defs {:block/entry
        \\   {:id :block/entry
        \\    :instructions [{:op :var-ref :result :val/2 :var :param/x}
        \\                   {:op :var-ref :result :val/3 :var :param/y}
        \\                   {:op :call :result :val/5 :fn :builtin/+ :args [:val/2 :val/3]}]
        \\    :terminator {:op :return :value :val/5}}}}
    ;

    var interp = Interpreter.init(std.testing.allocator);
    defer interp.deinit();

    const args = [_]f64{ 10, 32 };
    const result = try interp.executeFunction(ir_edn, &args);

    try std.testing.expectEqual(@as(f64, 42), result);
}

test "execute multiply function" {
    const ir_edn =
        \\{:id :fn/user-mul-1
        \\ :name "mul"
        \\ :namespace "user"
        \\ :arity {:fixed 2}
        \\ :params [:param/a :param/b]
        \\ :blocks [:block/entry]
        \\ :entry-block :block/entry
        \\ :block-defs {:block/entry
        \\   {:id :block/entry
        \\    :instructions [{:op :var-ref :result :val/2 :var :param/a}
        \\                   {:op :var-ref :result :val/3 :var :param/b}
        \\                   {:op :call :result :val/5 :fn :builtin/* :args [:val/2 :val/3]}]
        \\    :terminator {:op :return :value :val/5}}}}
    ;

    var interp = Interpreter.init(std.testing.allocator);
    defer interp.deinit();

    const args = [_]f64{ 6, 7 };
    const result = try interp.executeFunction(ir_edn, &args);

    try std.testing.expectEqual(@as(f64, 42), result);
}
