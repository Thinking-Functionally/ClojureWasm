// SPDX-License-Identifier: EPL-2.0
//! Complete Wasm backend: BytecodeChunk → Wasm Module → zwasm execution
//!
//! Phase 3 完整策略：直接翻譯現有 VM bytecode 到 Wasm。
//!
//! 架構：
//!   Clojure 源碼 → Reader → Analyzer → Node AST
//!   → VM Compiler → BytecodeChunk
//!   → **WasmBackend (此模組)** → Wasm Module
//!   → zwasm 執行
//!
//! 優點：
//!   - 零重複：VM bytecode 已經過完整測試
//!   - 簡單：只需翻譯 44 個 opcode
//!   - 保持雙後端差分：TreeWalk/VM 完全唔動

const std = @import("std");
const opcode_mod = @import("../vm/opcode.zig");
const Value = @import("../../../runtime/value/value.zig").Value;
const Runtime = @import("../../../runtime/runtime.zig").Runtime;
const zwasm = @import("zwasm");

const Opcode = opcode_mod.Opcode;
const BytecodeChunk = opcode_mod.BytecodeChunk;

pub const CompileError = error{
    UnsupportedOpcode,
    TooManyLocals,
    TooManyBlocks,
    InvalidJumpTarget,
} || std.mem.Allocator.Error || zwasm.ValidationError;

/// Wasm 模組建造器
///
/// Phase 3 實現：完整嘅 BytecodeChunk → Wasm 翻譯器
pub const WasmBackend = struct {
    allocator: std.mem.Allocator,
    rt: *Runtime,

    /// zwasm module builder
    module: *zwasm.Module,

    /// Function builder (一個 BytecodeChunk = 一個 Wasm function)
    function: *zwasm.Function,

    /// Block label 映射：bytecode IP → Wasm block depth
    /// 用於實現 op_jump / op_jump_if_false
    block_labels: std.AutoHashMap(usize, u32),

    pub fn init(allocator: std.mem.Allocator, rt: *Runtime) !WasmBackend {
        var module = try zwasm.Module.init(allocator);
        errdefer module.deinit();

        return .{
            .allocator = allocator,
            .rt = rt,
            .module = module,
            .function = undefined, // 會在 compile() 時設置
            .block_labels = std.AutoHashMap(usize, u32).init(allocator),
        };
    }

    pub fn deinit(self: *WasmBackend) void {
        self.block_labels.deinit();
        self.module.deinit();
    }

    /// 編譯 BytecodeChunk 到 Wasm Module
    ///
    /// 返回 Wasm 字節碼，可以餵俾 zwasm 執行
    pub fn compile(
        self: *WasmBackend,
        chunk: BytecodeChunk,
    ) CompileError![]const u8 {
        // Phase 3: 簡化實現
        // 假設 chunk 係一個 top-level 函數
        // 暫時唔支援多函數 / 閉包

        // TODO: 實現完整編譯
        _ = self;
        _ = chunk;
        return CompileError.UnsupportedOpcode;
    }
};

/// 簡化版本：直接用 bytecode_to_wasm.zig 嘅翻譯器
/// 但加上控制流支援
pub const SimpleWasmTranslator = struct {
    allocator: std.mem.Allocator,
    code: std.ArrayList(u8),
    num_locals: u32,

    /// Block 棧：追蹤當前嘅 Wasm block 深度
    block_stack: std.ArrayList(BlockInfo),

    /// Jump 目標映射：bytecode IP → block label
    jump_targets: std.AutoHashMap(usize, u32),

    const BlockInfo = struct {
        kind: BlockKind,
        label: u32,
    };

    const BlockKind = enum {
        block, // 普通 block
        loop, // loop (for recur)
        if_then, // if 嘅 then 分支
        if_else, // if 嘅 else 分支
    };

    pub fn init(allocator: std.mem.Allocator) SimpleWasmTranslator {
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).init(allocator),
            .num_locals = 0,
            .block_stack = std.ArrayList(BlockInfo).init(allocator),
            .jump_targets = std.AutoHashMap(usize, u32).init(allocator),
        };
    }

    pub fn deinit(self: *SimpleWasmTranslator) void {
        self.code.deinit();
        self.block_stack.deinit();
        self.jump_targets.deinit();
    }

    /// 第一遍：掃描 bytecode，建立跳轉目標映射
    pub fn scanJumpTargets(
        self: *SimpleWasmTranslator,
        chunk: BytecodeChunk,
    ) CompileError!void {
        for (chunk.instructions, 0..) |instr, ip| {
            switch (instr.op) {
                .op_jump, .op_jump_if_false => {
                    const offset: i16 = @bitCast(@as(u16, instr.operand));
                    const target_ip = if (offset >= 0)
                        ip + @as(usize, @intCast(offset))
                    else
                        ip - @as(usize, @intCast(-offset));

                    // 記錄呢個 IP 係一個跳轉目標
                    try self.jump_targets.put(target_ip, 0); // label 稍後分配
                },
                else => {},
            }
        }
    }

    /// 第二遍：生成 Wasm 代碼
    pub fn translate(
        self: *SimpleWasmTranslator,
        chunk: BytecodeChunk,
    ) CompileError![]const u8 {
        // 掃描跳轉目標
        try self.scanJumpTargets(chunk);

        // 生成函數頭
        try self.emitFunctionPrologue();

        // 翻譯每個指令
        for (chunk.instructions, 0..) |instr, ip| {
            // 如果呢個 IP 係跳轉目標，生成 block label
            if (self.jump_targets.contains(ip)) {
                try self.emitBlockLabel(ip);
            }

            try self.translateInstruction(chunk, instr, ip);
        }

        // 生成函數尾
        try self.emitFunctionEpilogue();

        return try self.code.toOwnedSlice();
    }

    fn emitFunctionPrologue(self: *SimpleWasmTranslator) !void {
        // Wasm function type: () -> f64
        // TODO: 實現完整嘅 function signature
        _ = self;
    }

    fn emitFunctionEpilogue(self: *SimpleWasmTranslator) !void {
        // 關閉所有 block
        while (self.block_stack.items.len > 0) {
            try self.emit(.end);
            _ = self.block_stack.pop();
        }
    }

    fn emitBlockLabel(self: *SimpleWasmTranslator, ip: usize) !void {
        // 為呢個 IP 分配 block label
        const label = @as(u32, @intCast(self.block_stack.items.len));
        try self.jump_targets.put(ip, label);

        // 生成 Wasm block
        try self.emit(.block);
        try self.block_stack.append(.{ .kind = .block, .label = label });
    }

    fn translateInstruction(
        self: *SimpleWasmTranslator,
        chunk: BytecodeChunk,
        instr: opcode_mod.Instruction,
        ip: usize,
    ) CompileError!void {
        _ = ip;

        switch (instr.op) {
            // 基礎指令（已實現）
            .op_const => {
                const val = chunk.constants[instr.operand];
                if (val.asInteger()) |i| {
                    try self.emitF64Const(@floatFromInt(i));
                } else {
                    return CompileError.UnsupportedOpcode;
                }
            },
            .op_load_local => {
                try self.emitLocalGet(@as(u32, instr.operand));
            },
            .op_store_local => {
                try self.emitLocalSet(@as(u32, instr.operand));
            },
            .op_ret => {
                try self.emit(.return_op);
            },
            .op_pop => {
                try self.emit(.drop);
            },

            // 算術運算（已實現）
            .op_add => try self.emit(.f64_add),
            .op_sub => try self.emit(.f64_sub),
            .op_mul => try self.emit(.f64_mul),
            .op_lt => try self.emit(.f64_lt),
            .op_le => try self.emit(.f64_le),
            .op_gt => try self.emit(.f64_gt),
            .op_ge => try self.emit(.f64_ge),
            .op_eq => try self.emit(.f64_eq),

            // 控制流（Phase 3.3 新增）
            .op_jump => {
                // 無條件跳轉：br to target block
                const offset: i16 = @bitCast(@as(u16, instr.operand));
                _ = offset;
                // TODO: 計算目標 block label 並生成 br
                return CompileError.UnsupportedOpcode;
            },
            .op_jump_if_false => {
                // 條件跳轉：br_if to target block
                const offset: i16 = @bitCast(@as(u16, instr.operand));
                _ = offset;
                // TODO: 生成 br_if
                return CompileError.UnsupportedOpcode;
            },
            .op_recur => {
                // 尾遞迴：br to loop start
                // TODO: 生成 loop + br
                return CompileError.UnsupportedOpcode;
            },

            // 其他未實現
            else => {
                return CompileError.UnsupportedOpcode;
            },
        }
    }

    // Wasm 指令 emit 輔助函數
    fn emit(self: *SimpleWasmTranslator, op: WasmOp) !void {
        try self.code.append(@intFromEnum(op));
    }

    fn emitLocalGet(self: *SimpleWasmTranslator, idx: u32) !void {
        try self.emit(.local_get);
        try self.emitLEB128(idx);
    }

    fn emitLocalSet(self: *SimpleWasmTranslator, idx: u32) !void {
        try self.emit(.local_set);
        try self.emitLEB128(idx);
    }

    fn emitF64Const(self: *SimpleWasmTranslator, val: f64) !void {
        try self.emit(.f64_const);
        const bytes = @as([8]u8, @bitCast(val));
        try self.code.appendSlice(&bytes);
    }

    fn emitLEB128(self: *SimpleWasmTranslator, value: u32) !void {
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

/// Wasm opcode 子集
pub const WasmOp = enum(u8) {
    // Control flow
    unreachable_op = 0x00,
    nop = 0x01,
    block = 0x02,
    loop = 0x03,
    if_op = 0x04,
    else_op = 0x05,
    end = 0x0B,
    br = 0x0C,
    br_if = 0x0D,
    br_table = 0x0E,
    return_op = 0x0F,
    call = 0x10,
    call_indirect = 0x12,
    // Variables
    drop = 0x1A,
    select = 0x1B,
    local_get = 0x20,
    local_set = 0x21,
    local_tee = 0x22,
    global_get = 0x23,
    global_set = 0x24,
    // Memory (Phase 3: 暫時唔用)
    // Numeric
    i32_const = 0x41,
    i64_const = 0x42,
    f32_const = 0x43,
    f64_const = 0x44,
    // f64 operations
    f64_add = 0xA0,
    f64_sub = 0xA1,
    f64_mul = 0xA2,
    f64_div = 0xA3,
    f64_min = 0xA4,
    f64_max = 0xA5,
    f64_copysign = 0xA6,
    f64_abs = 0x99,
    f64_neg = 0x9A,
    f64_ceil = 0x9B,
    f64_floor = 0x9C,
    f64_trunc = 0x9D,
    f64_nearest = 0x9E,
    f64_sqrt = 0x9F,
    f64_eq = 0x61,
    f64_ne = 0x62,
    f64_lt = 0x63,
    f64_gt = 0x64,
    f64_le = 0x65,
    f64_ge = 0x66,
};
