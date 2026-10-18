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
    InvalidJumpTarget,
    TooManyBlocks,
    UnmatchedBlock,
} || std.mem.Allocator.Error;

/// Wasm 模組建造器
pub const WasmModuleBuilder = struct {
    allocator: std.mem.Allocator,
    code: std.ArrayList(u8),
    num_locals: u32,

    pub fn init(allocator: std.mem.Allocator) WasmModuleBuilder {
        return .{
            .allocator = allocator,
            .code = .empty,
            .num_locals = 0,
        };
    }

    pub fn deinit(self: *WasmModuleBuilder) void {
        self.code.deinit(self.allocator);
    }

    /// 構建完整嘅 Wasm 模組
    ///
    /// 返回可以直接俾 zwasm 載入嘅字節碼
    pub fn build(self: *WasmModuleBuilder, chunk: BytecodeChunk) BuildError![]const u8 {
        var module: std.ArrayList(u8) = .empty;
        errdefer module.deinit(self.allocator);

        // Magic number + version
        try module.appendSlice(self.allocator, &[_]u8{ 0x00, 0x61, 0x73, 0x6D }); // "\0asm"
        try module.appendSlice(self.allocator, &[_]u8{ 0x01, 0x00, 0x00, 0x00 }); // version 1

        // Type section: 定義函數簽名 [] -> [f64]
        try self.writeTypeSection(&module);

        // Import section: builtin functions (Tier 2)
        // Phase 1: 跳過 import section（測試用例唔需要）
        // try self.writeImportSection(&module, chunk);

        // Function section: 函數使用嘅類型
        try self.writeFunctionSection(&module);

        // Table section: function table for indirect calls (Tier 2)
        // Phase 1: 跳過 table section（測試用例唔需要）
        // try self.writeTableSection(&module);

        // Export section: 導出 "main" 函數
        try self.writeExportSection(&module);

        // Code section: 函數體
        try self.writeCodeSection(&module, chunk);

        return try module.toOwnedSlice(self.allocator);
    }

    fn writeImportSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 2 (import)
        // 簡化實現：導入一個 "env.print" 函數 (f64) → ()
        _ = chunk;

        try module.append(self.allocator, 0x02);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 1 個 import
        try self.writeLEB128(&payload, 1);

        // module name: "env"
        try self.writeLEB128(&payload, 3);
        try payload.appendSlice(self.allocator, "env");

        // field name: "print"
        try self.writeLEB128(&payload, 5);
        try payload.appendSlice(self.allocator, "print");

        // import kind: function (0x00)
        try payload.append(self.allocator, 0x00);
        // type index: 1 (需要添加到 type section)
        try self.writeLEB128(&payload, 1);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeTableSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 4 (table)
        try module.append(self.allocator, 0x04);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 1 個 table
        try self.writeLEB128(&payload, 1);

        // element type: funcref (0x70)
        try payload.append(self.allocator, 0x70);

        // limits: min=16, max=none
        try payload.append(self.allocator, 0x00); // flags: no maximum
        try self.writeLEB128(&payload, 16);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeTypeSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 1 (type)
        try module.append(self.allocator, 0x01);

        // Section payload
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 2 個類型
        try self.writeLEB128(&payload, 2);

        // Type 0: main 函數 [] -> [f64]
        try payload.append(self.allocator, 0x60);
        // 0 個參數
        try self.writeLEB128(&payload, 0);
        // 1 個返回值 (f64)
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7C); // f64

        // Type 1: print 函數 [f64] -> []
        try payload.append(self.allocator, 0x60);
        // 1 個參數 (f64)
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7C); // f64
        // 0 個返回值
        try self.writeLEB128(&payload, 0);

        // 寫入 payload 長度同內容
        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeFunctionSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 3 (function)
        try module.append(self.allocator, 0x03);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 1 個函數
        try self.writeLEB128(&payload, 1);
        // 使用類型 0
        try self.writeLEB128(&payload, 0);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeExportSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 7 (export)
        try module.append(self.allocator, 0x07);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 1 個導出
        try self.writeLEB128(&payload, 1);

        // 導出名稱 "main"
        const name = "main";
        try self.writeLEB128(&payload, @intCast(name.len));
        try payload.appendSlice(self.allocator, name);

        // 導出類型: 函數
        try payload.append(self.allocator, 0x00);
        // 函數索引 0 (Phase 1: 無 import section，所以本地函數從 0 開始)
        try self.writeLEB128(&payload, 0);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeCodeSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 10 (code)
        try module.append(self.allocator, 0x0A);

        var section_payload: std.ArrayList(u8) = .empty;
        defer section_payload.deinit(self.allocator);

        // 1 個函數體
        try self.writeLEB128(&section_payload, 1);

        // 函數體
        var func_body: std.ArrayList(u8) = .empty;
        defer func_body.deinit(self.allocator);

        // Locals 聲明 (先掃描需要幾多 locals)
        self.num_locals = try self.scanLocals(chunk);

        // Local 聲明：num_locals 個 f64
        if (self.num_locals > 0) {
            try self.writeLEB128(&func_body, 1); // 1 組 locals
            try self.writeLEB128(&func_body, self.num_locals); // 數量
            try func_body.append(self.allocator, 0x7C); // f64
        } else {
            try self.writeLEB128(&func_body, 0); // 0 組 locals
        }

        // 第一遍：控制流分析
        var cf_analysis = ControlFlowAnalysis.init(self.allocator);
        defer cf_analysis.deinit();
        try cf_analysis.analyze(chunk);

        // 第二遍：翻譯指令 (帶控制流結構)
        try self.translateWithControlFlow(&func_body, chunk, &cf_analysis);

        // end
        try func_body.append(self.allocator, 0x0B);

        // 寫入函數體長度同內容
        try self.writeLEB128(&section_payload, @intCast(func_body.items.len));
        try section_payload.appendSlice(self.allocator, func_body.items);

        // 寫入 section 長度同內容
        try self.writeLEB128(module, @intCast(section_payload.items.len));
        try module.appendSlice(self.allocator, section_payload.items);
    }

    /// 帶控制流結構嘅指令翻譯
    fn translateWithControlFlow(
        self: *WasmModuleBuilder,
        code: *std.ArrayList(u8),
        chunk: BytecodeChunk,
        cf_analysis: *ControlFlowAnalysis,
    ) !void {
        var block_stack = BlockStack.init(self.allocator);
        defer block_stack.deinit();

        // IP → label 映射 (第二遍分配 label)
        var ip_to_label = std.AutoHashMap(usize, u32).init(self.allocator);
        defer ip_to_label.deinit();

        // 檢查係咪有 recur (需要外層 loop)
        const has_recur = cf_analysis.loop_starts.count() > 0;
        if (has_recur) {
            // loop (result type 同 func 一致: [] → [f64])
            try code.append(self.allocator, 0x03); // loop
            try code.append(self.allocator, 0x7C); // result type: f64
            const loop_label = try block_stack.push(.loop, 0);
            try ip_to_label.put(0, loop_label);
        }

        for (chunk.instructions, 0..) |instr, ip| {
            // 檢查當前 IP 係咪跳轉目標 → 插入 block
            if (cf_analysis.jump_targets.contains(ip)) {
                // block (result type: [] → [])
                try code.append(self.allocator, 0x02); // block
                try code.append(self.allocator, 0x40); // void
                const label = try block_stack.push(.block, ip);
                try ip_to_label.put(ip, label);
            }

            // 翻譯指令
            switch (instr.opcode) {
                .op_jump => {
                    // 計算目標 IP
                    const target_ip = try cf_analysis.computeJumpTarget(ip, instr.operand);
                    // 揾目標 block label
                    const target_label = ip_to_label.get(target_ip) orelse return BuildError.UnsupportedOpcode;
                    // br <depth>
                    const depth = block_stack.computeBranchDepth(target_label) orelse return BuildError.UnsupportedOpcode;
                    try code.append(self.allocator, 0x0C); // br
                    try self.writeLEB128(code, depth);
                },
                .op_jump_if_false => {
                    // stack: [cond] → []
                    // if cond == 0, jump to target
                    const target_ip = try cf_analysis.computeJumpTarget(ip, instr.operand);
                    const target_label = ip_to_label.get(target_ip) orelse return BuildError.UnsupportedOpcode;
                    const depth = block_stack.computeBranchDepth(target_label) orelse return BuildError.UnsupportedOpcode;

                    // i32.eqz (f64 → i32 cast + eqz)
                    try code.append(self.allocator, 0xAA); // i32.trunc_f64_s
                    try code.append(self.allocator, 0x45); // i32.eqz
                    // br_if <depth>
                    try code.append(self.allocator, 0x0D); // br_if
                    try self.writeLEB128(code, depth);
                },
                .op_recur => {
                    // recur 跳到最近嘅 loop 開始
                    const loop_label = block_stack.findNearestLoop() orelse return BuildError.UnsupportedOpcode;
                    const depth = block_stack.computeBranchDepth(loop_label) orelse return BuildError.UnsupportedOpcode;
                    try code.append(self.allocator, 0x0C); // br (跳到 loop 開始)
                    try self.writeLEB128(code, depth);
                },
                else => {
                    // 普通指令: 將 WireInstr 轉換為 Instruction
                    const decoded_instr = opcode_mod.Instruction{
                        .opcode = instr.opcode,
                        .operand = instr.operand,
                    };
                    try self.translateInstruction(code, chunk, decoded_instr);
                },
            }

            // 檢查係咪需要關閉 block (簡化：喺下一個跳轉目標前關閉)
            // TODO: 正確實現需要追蹤 block 生命週期
        }

        // 關閉所有未關閉嘅 block
        while (block_stack.pop()) |_| {
            try code.append(self.allocator, 0x0B); // end
        }
    }

    fn scanLocals(_: *WasmModuleBuilder, chunk: BytecodeChunk) !u32 {
        var max_local: u32 = 0;
        for (chunk.instructions) |instr| {
            switch (instr.opcode) {
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
        switch (instr.opcode) {
            .op_const => {
                const val = chunk.constants[instr.operand];
                // Value is enum(u64), check tag via top16 bits
                const val_int = @intFromEnum(val);
                const top16: u16 = @truncate(val_int >> 48);

                // 0xFFFC = integer, 0xFFF8-0xFFFB = heap types, < 0xFFF8 = raw f64
                if (top16 == 0xFFFC) {
                    // Integer: extract i48 and convert to f64
                    const i = val.asInteger();
                    try code.append(self.allocator, 0x44); // f64.const
                    const f: f64 = @floatFromInt(i);
                    const bytes = @as([8]u8, @bitCast(f));
                    try code.appendSlice(self.allocator, &bytes);
                } else if (top16 < 0xFFF8) {
                    // Raw f64: extract and emit
                    const f = val.asFloat();
                    try code.append(self.allocator, 0x44); // f64.const
                    const bytes = @as([8]u8, @bitCast(f));
                    try code.appendSlice(self.allocator, &bytes);
                } else {
                    // Heap type / constant / char / builtin_fn not yet supported
                    return BuildError.UnsupportedOpcode;
                }
            },
            .op_load_local => {
                // local.get
                try code.append(self.allocator, 0x20);
                try self.writeLEB128(code, @as(u32, instr.operand));
            },
            .op_store_local => {
                // local.set
                try code.append(self.allocator, 0x21);
                try self.writeLEB128(code, @as(u32, instr.operand));
            },
            .op_ret => {
                // return
                try code.append(self.allocator, 0x0F);
            },
            .op_pop => {
                // drop
                try code.append(self.allocator, 0x1A);
            },
            .op_add => {
                // f64.add
                try code.append(self.allocator, 0xA0);
            },
            .op_sub => {
                // f64.sub
                try code.append(self.allocator, 0xA1);
            },
            .op_mul => {
                // f64.mul
                try code.append(self.allocator, 0xA2);
            },

            // Tier 1: Control flow
            .op_jump => {
                // 實現為 br (unconditional branch)
                // TODO: 需要 control flow analysis 計算正確嘅 label depth
                return BuildError.UnsupportedOpcode;
            },
            .op_jump_if_false => {
                // 實現為 if + br_if
                // TODO: 需要 control flow analysis
                return BuildError.UnsupportedOpcode;
            },
            .op_recur => {
                // 實現為 br (跳到最近嘅 loop)
                // TODO: 需要 control flow analysis
                return BuildError.UnsupportedOpcode;
            },

            // Tier 2: Function calls
            .op_call => {
                // call_indirect with function table
                // operand = arity (arg count)
                const arity = @as(u32, instr.operand);
                // 簡化：table index 喺 stack 頂 — [arg0, arg1, ..., fn_idx]
                // call_indirect $type_idx $table_idx
                try code.append(self.allocator, 0x11); // call_indirect
                try self.writeLEB128(code, 0); // type index 0 (假設單一類型)
                try self.writeLEB128(code, 0); // table index 0
                _ = arity; // TODO: 根據 arity 調整 type index
            },
            .op_invoke_builtin => {
                // Import builtin functions: call imported function
                // operand = builtin index (假設 0 = 我哋導入嘅 "env.print")
                const builtin_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x10); // call
                try self.writeLEB128(code, builtin_idx); // function index (import 0)
            },

            else => {
                return BuildError.UnsupportedOpcode;
            },
        }
    }

    fn writeLEB128(self: *WasmModuleBuilder, buffer: *std.ArrayList(u8), value: u32) !void {
        var v = value;
        while (true) {
            const byte = @as(u8, @intCast(v & 0x7F));
            v >>= 7;
            if (v == 0) {
                try buffer.append(self.allocator, byte);
                break;
            } else {
                try buffer.append(self.allocator, byte | 0x80);
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

/// Save Wasm module bytes to a file (for AOT compilation)
pub fn saveWasmToFile(io: std.Io, wasm_bytes: []const u8, file_path: []const u8) !void {
    const file = try std.Io.Dir.cwd().createFile(io, file_path, .{ .truncate = true });
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var writer = file.writer(io, &buf);
    try writer.interface.writeAll(wasm_bytes);
    try writer.interface.flush();
}

// ===== Tests =====

test "buildWasmModule: simple constant" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 構造簡單嘅 BytecodeChunk: [(const 42), (ret)]
    const instructions = try allocator.alloc(opcode_mod.WireInstr, 2);
    errdefer allocator.free(instructions);
    instructions[0] = .{ .opcode = .op_const, .operand = 0 };
    instructions[1] = .{ .opcode = .op_ret, .operand = 0 };

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
        .source_file = "",
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
    const instructions = try allocator.alloc(opcode_mod.WireInstr, 4);
    errdefer allocator.free(instructions);
    instructions[0] = .{ .opcode = .op_const, .operand = 0 };
    instructions[1] = .{ .opcode = .op_const, .operand = 1 };
    instructions[2] = .{ .opcode = .op_add, .operand = 0 };
    instructions[3] = .{ .opcode = .op_ret, .operand = 0 };

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
        .source_file = "",
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
