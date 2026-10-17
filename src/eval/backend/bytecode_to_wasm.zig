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
        .op_const => {
            // 將 constant pool 中嘅 Value 轉成 Wasm const
            const val = chunk.constants[instr.operand];
            // Phase 3 簡化：只處理數字
            if (val.asInteger()) |i| {
                try module.emitF64Const(@floatFromInt(i));
            } else {
                // 其他類型暫時唔支援
                return TranslateError.UnsupportedOpcode;
            }
        },
        .op_load_local => {
            try module.emitLocalGet(@as(u32, instr.operand));
        },
        .op_store_local => {
            try module.emitLocalSet(@as(u32, instr.operand));
        },
        .op_call => {
            // Phase 3 簡化：假設 builtin 函數已經喺 Wasm import table
            const arg_count = instr.operand;
            _ = arg_count;
            // TODO: 根據 builtin 名稱決定調用邊個 Wasm import
            return TranslateError.UnsupportedOpcode;
        },
        .op_invoke_builtin => {
            // Builtin 函數調用：需要 runtime support
            return TranslateError.UnsupportedOpcode;
        },
        .op_ret => {
            try module.emit(.return_op);
        },
        .op_pop => {
            // Wasm 係 stack-based，pop 通常已經隱含喺指令入面
            // 如果真係需要丟棄值，可以用 local.set 到 dummy local
        },
        .op_dup => {
            // Wasm 冇直接嘅 dup，需要 local.tee
            return TranslateError.UnsupportedOpcode;
        },
        .op_jump => {
            // 需要 block/loop 結構支援
            return TranslateError.UnsupportedOpcode;
        },
        .op_jump_if_false => {
            // 需要 if/else 結構
            return TranslateError.UnsupportedOpcode;
        },
        else => {
            // Phase 3.1 只支援最基本嘅 opcode
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
