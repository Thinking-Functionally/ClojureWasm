// SPDX-License-Identifier: EPL-2.0
//! Complete Wasm module builder: generates valid Wasm binary format
//!
//! Phase 3 PoC: 由 BytecodeChunk 生成完整嘅 Wasm 模組，
//! 可以直接餵俾 zwasm 執行。
//!
//! Wasm 模組格式：
//!   magic + version
//!   type section (函數簽名)
//!   function section (函數類型索引)
//!   export section (導出函數)
//!   code section (函數體)

const std = @import("std");
const opcode_mod = @import("vm/opcode.zig");
const Value = @import("../../runtime/value/value.zig").Value;
const control_flow = @import("wasm_control_flow.zig");

const Opcode = opcode_mod.Opcode;
const BytecodeChunk = opcode_mod.BytecodeChunk;
const ControlFlowAnalysis = control_flow.ControlFlowAnalysis;
const BlockStack = control_flow.BlockStack;

pub const BuildError = error{
    UnsupportedOpcode,
    TooManyLocals,
    TooManyConstants,
} || std.mem.Allocator.Error;

/// Wasm 模組建造器
pub const WasmModuleBuilder = struct {
    allocator: std.mem.Allocator,
    code: std.ArrayList(u8),
    num_locals: u32,

    pub fn init(allocator: std.mem.Allocator) WasmModuleBuilder {
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).init(allocator),
            .num_locals = 0,
        };
    }

    pub fn deinit(self: *WasmModuleBuilder) void {
        self.code.deinit();
    }

    /// 構建完整嘅 Wasm 模組
    ///
    /// 返回可以直接俾 zwasm 載入嘅字節碼
    pub fn build(self: *WasmModuleBuilder, chunk: BytecodeChunk) BuildError![]const u8 {
        var module = std.ArrayList(u8).init(self.allocator);
        errdefer module.deinit();

        // Magic number + version
        try module.appendSlice(&[_]u8{ 0x00, 0x61, 0x73, 0x6D }); // "\0asm"
        try module.appendSlice(&[_]u8{ 0x01, 0x00, 0x00, 0x00 }); // version 1

        // Type section: 定義函數簽名 [] -> [f64]
        try self.writeTypeSection(&module);

        // Function section: 函數使用嘅類型
        try self.writeFunctionSection(&module);

        // Export section: 導出 "main" 函數
        try self.writeExportSection(&module);

        // Code section: 函數體
        try self.writeCodeSection(&module, chunk);

        return try module.toOwnedSlice();
    }

    fn writeTypeSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 1 (type)
        try module.append(0x01);

        // Section payload
        var payload = std.ArrayList(u8).init(module.allocator);
        defer payload.deinit();

        // 1 個類型
        try self.writeLEB128(&payload, 1);

        // func type
        try payload.append(0x60);
        // 0 個參數
        try self.writeLEB128(&payload, 0);
        // 1 個返回值 (f64)
        try self.writeLEB128(&payload, 1);
        try payload.append(0x7C); // f64

        // 寫入 payload 長度同內容
        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(payload.items);
    }

    fn writeFunctionSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 3 (function)
        try module.append(0x03);

        var payload = std.ArrayList(u8).init(module.allocator);
        defer payload.deinit();

        // 1 個函數
        try self.writeLEB128(&payload, 1);
        // 使用類型 0
        try self.writeLEB128(&payload, 0);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(payload.items);
    }

    fn writeExportSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 7 (export)
        try module.append(0x07);

        var payload = std.ArrayList(u8).init(module.allocator);
        defer payload.deinit();

        // 1 個導出
        try self.writeLEB128(&payload, 1);

        // 導出名稱 "main"
        const name = "main";
        try self.writeLEB128(&payload, @intCast(name.len));
        try payload.appendSlice(name);

        // 導出類型: 函數
        try payload.append(0x00);
        // 函數索引 0
        try self.writeLEB128(&payload, 0);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(payload.items);
    }

    fn writeCodeSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 10 (code)
        try module.append(0x0A);

        var section_payload = std.ArrayList(u8).init(module.allocator);
        defer section_payload.deinit();

        // 1 個函數體
        try self.writeLEB128(&section_payload, 1);

        // 函數體
        var func_body = std.ArrayList(u8).init(self.allocator);
        defer func_body.deinit();

        // Locals 聲明 (先掃描需要幾多 locals)
        self.num_locals = try self.scanLocals(chunk);

        // Local 聲明：num_locals 個 f64
        if (self.num_locals > 0) {
            try self.writeLEB128(&func_body, 1); // 1 組 locals
            try self.writeLEB128(&func_body, self.num_locals); // 數量
            try func_body.append(0x7C); // f64
        } else {
            try self.writeLEB128(&func_body, 0); // 0 組 locals
        }

        // 翻譯指令
        for (chunk.instructions) |instr| {
            try self.translateInstruction(&func_body, chunk, instr);
        }

        // end
        try func_body.append(0x0B);

        // 寫入函數體長度同內容
        try self.writeLEB128(&section_payload, @intCast(func_body.items.len));
        try section_payload.appendSlice(func_body.items);

        // 寫入 section 長度同內容
        try self.writeLEB128(module, @intCast(section_payload.items.len));
        try module.appendSlice(section_payload.items);
    }

    fn scanLocals(_: *WasmModuleBuilder, chunk: BytecodeChunk) !u32 {
        var max_local: u32 = 0;
        for (chunk.instructions) |instr| {
            switch (instr.op) {
                .op_load_local, .op_store_local => {
                    const idx = @as(u32, instr.operand);
                    if (idx >= max_local) max_local = idx + 1;
                },
                else => {},
            }
        }
        return max_local;
    }

    fn translateInstruction(
        self: *WasmModuleBuilder,
        code: *std.ArrayList(u8),
        chunk: BytecodeChunk,
        instr: opcode_mod.Instruction,
    ) BuildError!void {
        switch (instr.op) {
            .op_const => {
                const val = chunk.constants[instr.operand];
                if (val.asInteger()) |i| {
                    // f64.const
                    try code.append(0x44);
                    const f: f64 = @floatFromInt(i);
                    const bytes = @as([8]u8, @bitCast(f));
                    try code.appendSlice(&bytes);
                } else {
                    return BuildError.UnsupportedOpcode;
                }
            },
            .op_load_local => {
                // local.get
                try code.append(0x20);
                try self.writeLEB128(code, @as(u32, instr.operand));
            },
            .op_store_local => {
                // local.set
                try code.append(0x21);
                try self.writeLEB128(code, @as(u32, instr.operand));
            },
            .op_ret => {
                // return
                try code.append(0x0F);
            },
            .op_pop => {
                // drop
                try code.append(0x1A);
            },
            .op_add => {
                // f64.add
                try code.append(0xA0);
            },
            .op_sub => {
                // f64.sub
                try code.append(0xA1);
            },
            .op_mul => {
                // f64.mul
                try code.append(0xA2);
            },
            else => {
                return BuildError.UnsupportedOpcode;
            },
        }
    }

    fn writeLEB128(self: *WasmModuleBuilder, buffer: *std.ArrayList(u8), value: u32) !void {
        _ = self;
        var v = value;
        while (true) {
            const byte = @as(u8, @intCast(v & 0x7F));
            v >>= 7;
            if (v == 0) {
                try buffer.append(byte);
                break;
            } else {
                try buffer.append(byte | 0x80);
            }
        }
    }
};

/// 便捷函數：由 BytecodeChunk 生成完整 Wasm 模組
pub fn buildWasmModule(allocator: std.mem.Allocator, chunk: BytecodeChunk) ![]const u8 {
    var builder = WasmModuleBuilder.init(allocator);
    defer builder.deinit();
    return try builder.build(chunk);
}

// ===== Tests =====

test "buildWasmModule: simple constant" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 構造簡單嘅 BytecodeChunk: [(const 42), (ret)]
    const instructions = try allocator.alloc(opcode_mod.Instruction, 2);
    errdefer allocator.free(instructions);
    instructions[0] = .{ .op = .op_const, .operand = 0, .loc = null };
    instructions[1] = .{ .op = .op_ret, .operand = 0, .loc = null };

    const constants = try allocator.alloc(Value, 1);
    errdefer allocator.free(constants);
    constants[0] = Value.initInteger(42);

    const chunk = BytecodeChunk{
        .instructions = instructions,
        .constants = constants,
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

    const wasm_bytes = try buildWasmModule(allocator, chunk);
    defer allocator.free(wasm_bytes);

    // 驗證 magic number
    try testing.expectEqual(@as(u8, 0x00), wasm_bytes[0]);
    try testing.expectEqual(@as(u8, 0x61), wasm_bytes[1]);
    try testing.expectEqual(@as(u8, 0x73), wasm_bytes[2]);
    try testing.expectEqual(@as(u8, 0x6D), wasm_bytes[3]);

    // 驗證 version
    try testing.expectEqual(@as(u8, 0x01), wasm_bytes[4]);
    try testing.expectEqual(@as(u8, 0x00), wasm_bytes[5]);
    try testing.expectEqual(@as(u8, 0x00), wasm_bytes[6]);
    try testing.expectEqual(@as(u8, 0x00), wasm_bytes[7]);

    // 驗證有 section (type / function / export / code)
    try testing.expect(wasm_bytes.len > 8);
}

test "buildWasmModule: addition (+ 1 2)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // BytecodeChunk for: (+ 1 2)
    // [(const 1), (const 2), (add), (ret)]
    const instructions = try allocator.alloc(opcode_mod.Instruction, 4);
    errdefer allocator.free(instructions);
    instructions[0] = .{ .op = .op_const, .operand = 0, .loc = null };
    instructions[1] = .{ .op = .op_const, .operand = 1, .loc = null };
    instructions[2] = .{ .op = .op_add, .operand = 0, .loc = null };
    instructions[3] = .{ .op = .op_ret, .operand = 0, .loc = null };

    const constants = try allocator.alloc(Value, 2);
    errdefer allocator.free(constants);
    constants[0] = Value.initInteger(1);
    constants[1] = Value.initInteger(2);

    const chunk = BytecodeChunk{
        .instructions = instructions,
        .constants = constants,
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

    const wasm_bytes = try buildWasmModule(allocator, chunk);
    defer allocator.free(wasm_bytes);

    // 驗證 magic + version
    try testing.expect(std.mem.eql(u8, wasm_bytes[0..4], &[_]u8{ 0x00, 0x61, 0x73, 0x6D }));
    try testing.expect(std.mem.eql(u8, wasm_bytes[4..8], &[_]u8{ 0x01, 0x00, 0x00, 0x00 }));

    // 驗證長度 > header
    try testing.expect(wasm_bytes.len > 50); // type + function + export + code sections
}
