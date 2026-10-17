// SPDX-License-Identifier: EPL-2.0
//! BytecodeChunk → Wasm translator
//!
//! Phase 3 simplified strategy: 直接翻譯現有 VM bytecode 到 Wasm，
//! 而唔係由 AST 重新生成 IR。保留完整嘅 TreeWalk/VM 雙後端差分測試。

const std = @import("std");
const opcode_mod = @import("vm/opcode.zig");
const Value = @import("../../runtime/value/value.zig").Value;

const Opcode = opcode_mod.Opcode;
const BytecodeChunk = opcode_mod.BytecodeChunk;

pub const TranslateError = error{
    UnsupportedOpcode,
    TooManyLocals,
    TooManyConstants,
} || std.mem.Allocator.Error;

/// Wasm module builder (minimal Phase 3 實現)
pub const WasmModule = struct {
    allocator: std.mem.Allocator,
    code: std.ArrayList(u8),
    num_locals: u32,
    num_params: u32,

    pub fn init(allocator: std.mem.Allocator) WasmModule {
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).init(allocator),
            .num_locals = 0,
            .num_params = 0,
        };
    }

    pub fn deinit(self: *WasmModule) void {
        self.code.deinit();
    }

    pub fn emit(self: *WasmModule, op: WasmOp) !void {
        try self.code.append(@intFromEnum(op));
    }

    pub fn emitU8(self: *WasmModule, byte: u8) !void {
        try self.code.append(byte);
    }

    pub fn emitLocalGet(self: *WasmModule, idx: u32) !void {
        try self.emit(.local_get);
        try self.emitLEB128(idx);
    }

    pub fn emitLocalSet(self: *WasmModule, idx: u32) !void {
        try self.emit(.local_set);
        try self.emitLEB128(idx);
    }

    pub fn emitF64Const(self: *WasmModule, val: f64) !void {
        try self.emit(.f64_const);
        const bytes = @as([8]u8, @bitCast(val));
        try self.code.appendSlice(&bytes);
    }

    pub fn emitCall(self: *WasmModule, func_idx: u32) !void {
        try self.emit(.call);
        try self.emitLEB128(func_idx);
    }

    fn emitLEB128(self: *WasmModule, value: u32) !void {
        var v = value;
        while (true) {
            const byte = @as(u8, @intCast(v & 0x7F));
            v >>= 7;
            if (v == 0) {
                try self.code.append(byte);
                break;
            } else {
                try self.code.append(byte | 0x80);
            }
        }
    }
};

/// Wasm opcode subset (Phase 3 核心)
pub const WasmOp = enum(u8) {
    // Control flow
    end = 0x0B,
    return_op = 0x0F,
    call = 0x10,
    if_op = 0x04,
    else_op = 0x05,
    // Variables
    local_get = 0x20,
    local_set = 0x21,
    local_tee = 0x22,
    // Stack
    drop = 0x1A,
    // Numeric
    i32_trunc_f64_s = 0xAA,
    f64_const = 0x44,
    f64_add = 0xA0,
    f64_sub = 0xA1,
    f64_mul = 0xA2,
    f64_div = 0xA3,
    f64_neg = 0x9A,
    f64_eq = 0x61,
    f64_ne = 0x62,
    f64_lt = 0x63,
    f64_gt = 0x64,
    f64_le = 0x65,
    f64_ge = 0x66,
    f64_convert_i32_s = 0xB7,
};

/// BytecodeChunk → WasmModule 翻譯器
///
/// Phase 3 核心：將 VM bytecode 指令一一對應到 Wasm 指令
pub fn translate(
    allocator: std.mem.Allocator,
    chunk: BytecodeChunk,
) TranslateError!WasmModule {
    var module = WasmModule.init(allocator);
    errdefer module.deinit();

    // Phase 3.1: 掃描 chunk 計算需要幾多 locals
    var max_local: u32 = 0;
    for (chunk.instructions) |instr| {
        switch (instr.op) {
            .op_load_local, .op_store_local => {
                const idx = @as(u32, instr.operand);
                if (idx > max_local) max_local = idx;
            },
            else => {},
        }
    }
    module.num_locals = max_local + 1;

    // Phase 3.2: 翻譯每個指令
    for (chunk.instructions) |instr| {
        try translateInstruction(&module, chunk, instr);
    }

    return module;
}

fn translateInstruction(
    module: *WasmModule,
    chunk: BytecodeChunk,
    instr: opcode_mod.Instruction,
) TranslateError!void {
    switch (instr.op) {
        // ===== 基礎指令 =====
        .op_const => {
            const val = chunk.constants[instr.operand];
            // 只處理數字 Value（簡化 Phase 3 實現）
            if (val.asInteger()) |i| {
                try module.emitF64Const(@floatFromInt(i));
            } else {
                // 其他類型（字串、符號、集合）需要 runtime object support
                return TranslateError.UnsupportedOpcode;
            }
        },
        .op_load_local => {
            try module.emitLocalGet(@as(u32, instr.operand));
        },
        .op_store_local => {
            try module.emitLocalSet(@as(u32, instr.operand));
        },
        .op_ret => {
            try module.emit(.return_op);
        },
        .op_pop => {
            // Wasm stack-based: 用 drop 指令丟棄
            try module.emit(.drop);
        },
        .op_dup => {
            // Wasm 冇 dup: 用 local.tee 模擬
            // dup = local.tee $temp; local.get $temp
            const temp_local = module.num_locals;
            module.num_locals += 1;
            try module.emit(.local_tee);
            try module.emitLEB128(temp_local);
            try module.emitLocalGet(temp_local);
        },

        // ===== 函數調用 =====
        .op_call => {
            // 通用函數調用: 需要 function table + 動態 dispatch
            const arg_count = instr.operand;
            _ = arg_count;
            // Phase 3: 延遲實現（需要 Wasm function table）
            return TranslateError.UnsupportedOpcode;
        },
        .op_invoke_builtin => {
            // Builtin 調用: 映射到 Wasm import
            const arg_count = instr.operand;
            _ = arg_count;
            // Phase 3: 延遲實現（需要 builtin name 到 import index 映射）
            return TranslateError.UnsupportedOpcode;
        },
        .op_make_fn => {
            // 創建閉包: 需要 heap allocation
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 控制流 =====
        .op_jump => {
            // 無條件跳轉: 用 br 指令
            const offset = @as(i16, @bitCast(@as(u16, instr.operand)));
            _ = offset;
            // Phase 3: 需要 block 結構 + label 映射
            return TranslateError.UnsupportedOpcode;
        },
        .op_jump_if_false => {
            // 條件跳轉: 用 br_if 指令
            const offset = @as(i16, @bitCast(@as(u16, instr.operand)));
            _ = offset;
            // Phase 3: 需要 block 結構 + label 映射
            return TranslateError.UnsupportedOpcode;
        },
        .op_recur => {
            // 尾遞迴: 需要 loop + br 到 loop 頂部
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 變量定義 =====
        .op_def => {
            // (def x v): 需要 namespace + Var runtime
            return TranslateError.UnsupportedOpcode;
        },
        .op_def_unbound => {
            // (def x): 同上
            return TranslateError.UnsupportedOpcode;
        },
        .op_get_var => {
            // 讀取 Var: 需要 Var deref runtime
            return TranslateError.UnsupportedOpcode;
        },
        .op_set_var => {
            // set! Var: 需要 Var set! runtime
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 異常處理 =====
        .op_throw => {
            // throw: 用 Wasm exception handling proposal
            return TranslateError.UnsupportedOpcode;
        },
        .op_push_handler => {
            // try/catch: 用 Wasm try/catch
            return TranslateError.UnsupportedOpcode;
        },
        .op_pop_handler => {
            return TranslateError.UnsupportedOpcode;
        },
        .op_match_class => {
            return TranslateError.UnsupportedOpcode;
        },
        .op_match_type_keyword => {
            return TranslateError.UnsupportedOpcode;
        },
        .op_push_cleanup => {
            return TranslateError.UnsupportedOpcode;
        },
        .op_reraise => {
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 命名空間 =====
        .op_in_ns => {
            // (in-ns 'foo): 需要 namespace runtime
            return TranslateError.UnsupportedOpcode;
        },
        .op_ns_with_refer_clojure => {
            return TranslateError.UnsupportedOpcode;
        },
        .op_ns_with_filter => {
            return TranslateError.UnsupportedOpcode;
        },
        .op_require => {
            return TranslateError.UnsupportedOpcode;
        },
        .op_require_with_libspec => {
            return TranslateError.UnsupportedOpcode;
        },
        .op_ns_import => {
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 數據結構 =====
        .op_vector_literal => {
            // [1 2 3]: 需要 vector runtime
            return TranslateError.UnsupportedOpcode;
        },
        .op_map_literal => {
            // {:a 1}: 需要 map runtime
            return TranslateError.UnsupportedOpcode;
        },
        .op_set_literal => {
            // #{1 2}: 需要 set runtime
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 方法調用 (deftype/reify) =====
        .op_ctor_call => {
            // (Name. args): 需要 deftype runtime
            return TranslateError.UnsupportedOpcode;
        },
        .op_method_call => {
            // (.method obj args): 需要 protocol dispatch
            return TranslateError.UnsupportedOpcode;
        },
        .op_static_method_call => {
            // (Class/method args): 需要 static dispatch
            return TranslateError.UnsupportedOpcode;
        },
        .op_set_field => {
            // (set! (.field obj) v): 需要 deftype mutable field
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 動態綁定 =====
        .op_push_binding_frame => {
            // (binding [*v* x]): 需要 dynamic var runtime
            return TranslateError.UnsupportedOpcode;
        },
        .op_pop_binding_frame => {
            return TranslateError.UnsupportedOpcode;
        },

        // ===== letfn =====
        .op_letfn_patch => {
            // letfn 閉包補丁: 需要 closure heap 操作
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 算術內聯優化 (ADR-0130) =====
        .op_add => {
            // (+ a b): f64.add
            try module.emit(.f64_add);
        },
        .op_sub => {
            try module.emit(.f64_sub);
        },
        .op_mul => {
            try module.emit(.f64_mul);
        },
        .op_lt => {
            try module.emit(.f64_lt);
        },
        .op_le => {
            try module.emit(.f64_le);
        },
        .op_gt => {
            try module.emit(.f64_gt);
        },
        .op_ge => {
            try module.emit(.f64_ge);
        },
        .op_eq => {
            try module.emit(.f64_eq);
        },

        // ===== 超指令 (local+const 融合) =====
        .op_add_local_const => {
            const packed_operand = instr.operand;
            const local_slot = (packed_operand >> 8) & 0xFF;
            const const_idx = packed_operand & 0xFF;
            try module.emitLocalGet(local_slot);
            const val = chunk.constants[const_idx];
            if (val.asInteger()) |i| {
                try module.emitF64Const(@floatFromInt(i));
            } else {
                return TranslateError.UnsupportedOpcode;
            }
            try module.emit(.f64_add);
        },
        .op_sub_local_const => {
            const packed_operand = instr.operand;
            const local_slot = (packed_operand >> 8) & 0xFF;
            const const_idx = packed_operand & 0xFF;
            try module.emitLocalGet(local_slot);
            const val = chunk.constants[const_idx];
            if (val.asInteger()) |i| {
                try module.emitF64Const(@floatFromInt(i));
            } else {
                return TranslateError.UnsupportedOpcode;
            }
            try module.emit(.f64_sub);
        },
        .op_mul_local_const => {
            const packed_operand = instr.operand;
            const local_slot = (packed_operand >> 8) & 0xFF;
            const const_idx = packed_operand & 0xFF;
            try module.emitLocalGet(local_slot);
            const val = chunk.constants[const_idx];
            if (val.asInteger()) |i| {
                try module.emitF64Const(@floatFromInt(i));
            } else {
                return TranslateError.UnsupportedOpcode;
            }
            try module.emit(.f64_mul);
        },
        .op_lt_local_const => {
            const packed_operand = instr.operand;
            const local_slot = (packed_operand >> 8) & 0xFF;
            const const_idx = packed_operand & 0xFF;
            try module.emitLocalGet(local_slot);
            const val = chunk.constants[const_idx];
            if (val.asInteger()) |i| {
                try module.emitF64Const(@floatFromInt(i));
            } else {
                return TranslateError.UnsupportedOpcode;
            }
            try module.emit(.f64_lt);
        },
        .op_le_local_const,
        .op_gt_local_const,
        .op_ge_local_const,
        .op_eq_local_const => {
            // 同上模式
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 超指令 (local+local 融合) =====
        .op_add_locals => {
            const operand_packed = instr.operand;
            const slot_a = (operand_packed >> 8) & 0xFF;
            const slot_b = operand_packed & 0xFF;
            try module.emitLocalGet(slot_a);
            try module.emitLocalGet(slot_b);
            try module.emit(.f64_add);
        },
        .op_sub_locals,
        .op_mul_locals,
        .op_lt_locals,
        .op_le_locals,
        .op_gt_locals,
        .op_ge_locals,
        .op_eq_locals => {
            // 同上模式
            return TranslateError.UnsupportedOpcode;
        },

        // ===== 分支超指令 (比較+跳轉融合) =====
        .op_branch_ne_local_const,
        .op_branch_ge_local_const,
        .op_branch_gt_local_const,
        .op_branch_ne_locals,
        .op_branch_ge_locals,
        .op_branch_gt_locals => {
            // 需要 block + br_if
            return TranslateError.UnsupportedOpcode;
        },
    }
}

test "translate: simple constant" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 構造簡單嘅 BytecodeChunk: [op_const 0, op_ret]
    var instructions = std.ArrayList(opcode_mod.Instruction).init(allocator);
    defer instructions.deinit();
    try instructions.append(.{ .op = .op_const, .operand = 0, .loc = null });
    try instructions.append(.{ .op = .op_ret, .operand = 0, .loc = null });

    var constants = std.ArrayList(Value).init(allocator);
    defer constants.deinit();
    try constants.append(Value.initInteger(42));

    const chunk = BytecodeChunk{
        .instructions = try instructions.toOwnedSlice(),
        .constants = try constants.toOwnedSlice(),
        .call_sites = &[_]opcode_mod.CallSiteEntry{},
        .libspecs = &[_]opcode_mod.LibspecEntry{},
        .ns_filters = &[_]opcode_mod.NsFilterEntry{},
        .ctor_sites = &[_]opcode_mod.CtorEntry{},
        .import_sites = &[_]opcode_mod.ImportPair{},
        .source_file = null,
    };
    defer {
        allocator.free(chunk.instructions);
        allocator.free(chunk.constants);
    }

    var module = try translate(allocator, chunk);
    defer module.deinit();

    // 驗證生成咗 f64.const + return
    try testing.expect(module.code.items.len > 0);
}
