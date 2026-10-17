// SPDX-License-Identifier: EPL-2.0
//! IR to WASM compiler
//! Translates EDN-based IR to WASM bytecode with multi-block control flow and recursion

const std = @import("std");
const edn = @import("edn_parser.zig");
const wasm = @import("wasm_codegen.zig");

pub const CompileError = error{
    InvalidIR,
    UnsupportedOperation,
    MissingField,
    TypeMismatch,
} || edn.ParseError || std.mem.Allocator.Error;

/// Compile IR (EDN string) to WASM module
pub fn compile(allocator: std.mem.Allocator, ir_edn: []const u8) CompileError!wasm.WasmModule {
    var ir = try edn.parse(allocator, ir_edn);
    defer ir.deinit(allocator);

    if (ir != .map) return CompileError.InvalidIR;

    var module = wasm.WasmModule.init(allocator);
    errdefer module.deinit();

    // Get function entry block
    const entry_block_id = ir.map.get("entry-block") orelse return CompileError.MissingField;
    if (entry_block_id != .keyword) return CompileError.TypeMismatch;

    // Get block definitions
    const block_defs = ir.map.get("block-defs") orelse return CompileError.MissingField;
    if (block_defs != .map) return CompileError.TypeMismatch;

    // Value ID to local index mapping
    var value_map = std.StringHashMap(u32).init(allocator);
    defer value_map.deinit();

    var next_local: u32 = 0;

    // Parameters start at index 0
    const params_val = ir.map.get("params") orelse return CompileError.MissingField;
    if (params_val != .vector) return CompileError.TypeMismatch;
    for (params_val.vector) |param| {
        if (param != .keyword) return CompileError.TypeMismatch;
        try value_map.put(param.keyword, next_local);
        next_local += 1;
    }

    module.num_params = next_local;

    const params_count = next_local;

    // Build control flow graph
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    try compileBlockChain(allocator, &module, entry_block_id.keyword, block_defs, &value_map, &next_local, &visited);

    // num_locals = total locals - params
    module.num_locals = next_local - params_count;

    return module;
}

fn compileBlockChain(
    allocator: std.mem.Allocator,
    module: *wasm.WasmModule,
    block_id: []const u8,
    block_defs: edn.EDNValue,
    value_map: *std.StringHashMap(u32),
    next_local: *u32,
    visited: *std.StringHashMap(void),
) CompileError!void {
    if (visited.contains(block_id)) return; // Already compiled
    try visited.put(block_id, {});

    const block = block_defs.map.get(block_id) orelse return CompileError.MissingField;
    if (block != .map) return CompileError.TypeMismatch;

    // Get instructions
    const instrs_val = block.map.get("instructions") orelse return CompileError.MissingField;
    if (instrs_val != .vector) return CompileError.TypeMismatch;

    // Compile each instruction
    for (instrs_val.vector) |instr_val| {
        if (instr_val != .map) return CompileError.TypeMismatch;
        try compileInstruction(module, instr_val, value_map, next_local);
    }

    // Compile terminator
    const terminator = block.map.get("terminator") orelse return CompileError.MissingField;

    if (terminator == .nil) {
        // Merge block with phi - just return the phi result
        if (instrs_val.vector.len > 0) {
            const last_instr = instrs_val.vector[instrs_val.vector.len - 1];
            if (last_instr != .map) return CompileError.TypeMismatch;
            const last_op = last_instr.map.get("op") orelse return CompileError.MissingField;
            if (last_op != .keyword) return CompileError.TypeMismatch;
            if (std.mem.eql(u8, last_op.keyword, "phi")) {
                const result_val = last_instr.map.get("result") orelse return CompileError.MissingField;
                if (result_val != .keyword) return CompileError.TypeMismatch;
                const result_idx = value_map.get(result_val.keyword) orelse return CompileError.MissingField;
                try module.emitLocalGet(result_idx);
                try module.emit(.return_op);
                return;
            }
        }
        return CompileError.InvalidIR;
    }

    if (terminator != .map) return CompileError.TypeMismatch;

    const op_val = terminator.map.get("op") orelse return CompileError.MissingField;
    if (op_val != .keyword) return CompileError.TypeMismatch;
    const op = op_val.keyword;

    if (std.mem.eql(u8, op, "return")) {
        const value_val = terminator.map.get("value") orelse return CompileError.MissingField;
        if (value_val != .keyword) return CompileError.TypeMismatch;

        const value_idx = value_map.get(value_val.keyword) orelse return CompileError.MissingField;
        try module.emitLocalGet(value_idx);
        try module.emit(.return_op);
    } else if (std.mem.eql(u8, op, "branch")) {
        // Branch: if-then-else control flow
        // Strategy: compile both branches to leave result on stack, then store to phi result
        const cond_val = terminator.map.get("condition") orelse return CompileError.MissingField;
        if (cond_val != .keyword) return CompileError.TypeMismatch;
        const cond_idx = value_map.get(cond_val.keyword) orelse return CompileError.MissingField;

        const then_val = terminator.map.get("then") orelse return CompileError.MissingField;
        if (then_val != .keyword) return CompileError.TypeMismatch;
        const then_id = then_val.keyword;

        const else_val = terminator.map.get("else") orelse return CompileError.MissingField;
        if (else_val != .keyword) return CompileError.TypeMismatch;
        const else_id = else_val.keyword;

        // Get the merge block to find phi result
        const then_block = block_defs.map.get(then_id) orelse return CompileError.MissingField;
        if (then_block != .map) return CompileError.TypeMismatch;
        const then_term = then_block.map.get("terminator") orelse return CompileError.MissingField;
        if (then_term != .map) return CompileError.TypeMismatch;
        const then_target_val = then_term.map.get("target") orelse return CompileError.MissingField;
        if (then_target_val != .keyword) return CompileError.TypeMismatch;
        const merge_id = then_target_val.keyword;

        // Find phi result from merge block
        const merge_block = block_defs.map.get(merge_id) orelse return CompileError.MissingField;
        if (merge_block != .map) return CompileError.TypeMismatch;
        const merge_instrs = merge_block.map.get("instructions") orelse return CompileError.MissingField;
        if (merge_instrs != .vector) return CompileError.TypeMismatch;

        var phi_result_idx: ?u32 = null;
        if (merge_instrs.vector.len > 0) {
            const phi_instr = merge_instrs.vector[0];
            if (phi_instr == .map) {
                const phi_op = phi_instr.map.get("op");
                if (phi_op != null and phi_op.? == .keyword and std.mem.eql(u8, phi_op.?.keyword, "phi")) {
                    const phi_result_val = phi_instr.map.get("result") orelse return CompileError.MissingField;
                    if (phi_result_val != .keyword) return CompileError.TypeMismatch;
                    if (!value_map.contains(phi_result_val.keyword)) {
                        try value_map.put(phi_result_val.keyword, next_local.*);
                        next_local.* += 1;
                    }
                    phi_result_idx = value_map.get(phi_result_val.keyword).?;
                }
            }
        }

        // WASM: if (condition) { then-value } else { else-value } -> result
        try module.emitLocalGet(cond_idx);
        try module.emit(.i32_trunc_f64_s);
        try module.emit(.if_op);
        try module.emitU8(0x7C); // blocktype: f64

        // Compile then block: load its result value onto stack
        const then_instrs = then_block.map.get("instructions") orelse return CompileError.MissingField;
        if (then_instrs != .vector) return CompileError.TypeMismatch;
        for (then_instrs.vector) |instr| {
            if (instr != .map) return CompileError.TypeMismatch;
            try compileInstruction(module, instr, value_map, next_local);
        }
        // Load then block's result value
        const then_value_val = then_term.map.get("value") orelse return CompileError.MissingField;
        if (then_value_val != .keyword) return CompileError.TypeMismatch;
        const then_value_idx = value_map.get(then_value_val.keyword) orelse return CompileError.MissingField;
        try module.emitLocalGet(then_value_idx);

        try module.emit(.else_op);

        // Compile else block
        const else_block = block_defs.map.get(else_id) orelse return CompileError.MissingField;
        if (else_block != .map) return CompileError.TypeMismatch;
        const else_instrs = else_block.map.get("instructions") orelse return CompileError.MissingField;
        if (else_instrs != .vector) return CompileError.TypeMismatch;
        for (else_instrs.vector) |instr| {
            if (instr != .map) return CompileError.TypeMismatch;
            try compileInstruction(module, instr, value_map, next_local);
        }
        const else_term = else_block.map.get("terminator") orelse return CompileError.MissingField;
        if (else_term != .map) return CompileError.TypeMismatch;
        const else_value_val = else_term.map.get("value") orelse return CompileError.MissingField;
        if (else_value_val != .keyword) return CompileError.TypeMismatch;
        const else_value_idx = value_map.get(else_value_val.keyword) orelse return CompileError.MissingField;
        try module.emitLocalGet(else_value_idx);

        try module.emit(.end);

        // Store if result to phi result local
        if (phi_result_idx) |idx| {
            try module.emitLocalSet(idx);
        }

        // Compile merge block - mark it as visited and handle manually
        try visited.put(merge_id, {});

        // The merge block should just return the phi result
        if (phi_result_idx) |idx| {
            try module.emitLocalGet(idx);
            try module.emit(.return_op);
        }
    } else if (std.mem.eql(u8, op, "jump")) {
        // Unconditional jump - just compile target block inline
        const target_val = terminator.map.get("target") orelse return CompileError.MissingField;
        if (target_val != .keyword) return CompileError.TypeMismatch;
        try compileBlockChain(allocator, module, target_val.keyword, block_defs, value_map, next_local, visited);
    } else {
        return CompileError.UnsupportedOperation;
    }
}

fn compileInstruction(
    module: *wasm.WasmModule,
    instr: edn.EDNValue,
    value_map: *std.StringHashMap(u32),
    next_local: *u32,
) CompileError!void {
    const op_val = instr.map.get("op") orelse return CompileError.MissingField;
    if (op_val != .keyword) return CompileError.TypeMismatch;
    const op = op_val.keyword;

    if (std.mem.eql(u8, op, "const")) {
        const result_val = instr.map.get("result") orelse return CompileError.MissingField;
        if (result_val != .keyword) return CompileError.TypeMismatch;
        const result = result_val.keyword;

        const value_val = instr.map.get("value") orelse return CompileError.MissingField;
        if (value_val != .number) return CompileError.TypeMismatch;

        if (!value_map.contains(result)) {
            try value_map.put(result, next_local.*);
            next_local.* += 1;
        }

        try module.emitF64Const(value_val.number);
        const result_idx = value_map.get(result).?;
        try module.emitLocalSet(result_idx);
    } else if (std.mem.eql(u8, op, "var-ref")) {
        const result_val = instr.map.get("result") orelse return CompileError.MissingField;
        if (result_val != .keyword) return CompileError.TypeMismatch;
        const result = result_val.keyword;

        const var_val = instr.map.get("var") orelse return CompileError.MissingField;
        if (var_val != .keyword) return CompileError.TypeMismatch;
        const var_id = var_val.keyword;

        if (!value_map.contains(result)) {
            try value_map.put(result, next_local.*);
            next_local.* += 1;
        }

        const var_idx = value_map.get(var_id) orelse return CompileError.MissingField;
        try module.emitLocalGet(var_idx);

        const result_idx = value_map.get(result).?;
        try module.emitLocalSet(result_idx);
    } else if (std.mem.eql(u8, op, "phi")) {
        // Phi node: in WASM this is just identity (the value is already in the local)
        // The interpreter handles phi selection, but in WASM the control flow ensures
        // the right value is already set
        const result_val = instr.map.get("result") orelse return CompileError.MissingField;
        if (result_val != .keyword) return CompileError.TypeMismatch;
        const result = result_val.keyword;

        const sources_val = instr.map.get("sources") orelse return CompileError.MissingField;
        if (sources_val != .vector) return CompileError.TypeMismatch;

        if (!value_map.contains(result)) {
            try value_map.put(result, next_local.*);
            next_local.* += 1;
        }

        // For WASM: pick the first source value (both branches will set the same result local)
        // This is a simplified phi - proper SSA would need more sophisticated handling
        if (sources_val.vector.len > 0) {
            const first_source = sources_val.vector[0];
            if (first_source != .map) return CompileError.TypeMismatch;
            const value_val = first_source.map.get("value") orelse return CompileError.MissingField;
            if (value_val != .keyword) return CompileError.TypeMismatch;

            const value_idx = value_map.get(value_val.keyword) orelse return CompileError.MissingField;
            try module.emitLocalGet(value_idx);

            const result_idx = value_map.get(result).?;
            try module.emitLocalSet(result_idx);
        }
    } else if (std.mem.eql(u8, op, "call")) {
        const result_val = instr.map.get("result") orelse return CompileError.MissingField;
        if (result_val != .keyword) return CompileError.TypeMismatch;
        const result = result_val.keyword;

        const func_val = instr.map.get("fn") orelse return CompileError.MissingField;
        if (func_val != .keyword) return CompileError.TypeMismatch;
        const func = func_val.keyword;

        const args_val = instr.map.get("args") orelse return CompileError.MissingField;
        if (args_val != .vector) return CompileError.TypeMismatch;

        if (!value_map.contains(result)) {
            try value_map.put(result, next_local.*);
            next_local.* += 1;
        }

        // Load arguments onto stack
        for (args_val.vector) |arg| {
            if (arg != .keyword) return CompileError.TypeMismatch;
            const arg_idx = value_map.get(arg.keyword) orelse return CompileError.MissingField;
            try module.emitLocalGet(arg_idx);
        }

        // Emit operation
        if (std.mem.eql(u8, func, "builtin/+")) {
            try module.emit(.f64_add);
        } else if (std.mem.eql(u8, func, "builtin/-")) {
            if (args_val.vector.len == 1) {
                try module.emit(.f64_neg);
            } else {
                try module.emit(.f64_sub);
            }
        } else if (std.mem.eql(u8, func, "builtin/*")) {
            try module.emit(.f64_mul);
        } else if (std.mem.eql(u8, func, "builtin/=")) {
            try module.emit(.f64_eq);
            // Convert i32 result to f64 (0.0 or 1.0)
            try module.emit(.f64_convert_i32_s);
        } else if (std.mem.eql(u8, func, "builtin/<")) {
            try module.emit(.f64_lt);
            // Convert i32 result to f64 (0.0 or 1.0)
            try module.emit(.f64_convert_i32_s);
        } else if (std.mem.eql(u8, func, "builtin/>")) {
            try module.emit(.f64_gt);
            // Convert i32 result to f64 (0.0 or 1.0)
            try module.emit(.f64_convert_i32_s);
        } else if (std.mem.eql(u8, func, "builtin/<=")) {
            try module.emit(.f64_le);
            // Convert i32 result to f64 (0.0 or 1.0)
            try module.emit(.f64_convert_i32_s);
        } else if (std.mem.eql(u8, func, "builtin/>=")) {
            try module.emit(.f64_ge);
            // Convert i32 result to f64 (0.0 or 1.0)
            try module.emit(.f64_convert_i32_s);
        } else if (std.mem.startsWith(u8, func, "fn/user-")) {
            // User-defined function call (recursion)
            // For single-function module, call function 0
            try module.emitCall(0);
        } else {
            return CompileError.UnsupportedOperation;
        }

        const result_idx = value_map.get(result).?;
        try module.emitLocalSet(result_idx);
    } else if (std.mem.eql(u8, op, "let-bind")) {
        // Let binding: just alias the value
        const name_val = instr.map.get("name") orelse return CompileError.MissingField;
        if (name_val != .keyword) return CompileError.TypeMismatch;
        const name = name_val.keyword;

        const value_val = instr.map.get("value") orelse return CompileError.MissingField;
        if (value_val != .keyword) return CompileError.TypeMismatch;
        const value_id = value_val.keyword;

        if (!value_map.contains(name)) {
            try value_map.put(name, next_local.*);
            next_local.* += 1;
        }

        const value_idx = value_map.get(value_id) orelse return CompileError.MissingField;
        try module.emitLocalGet(value_idx);

        const name_idx = value_map.get(name).?;
        try module.emitLocalSet(name_idx);
    } else {
        return CompileError.UnsupportedOperation;
    }
}
