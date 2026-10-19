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
    num_globals: u32,
    // Phase 3: linear memory for heap types
    linear_memory_size: u32,
    // Phase 4: function table for indirect calls
    function_table_size: u32,

    pub fn init(allocator: std.mem.Allocator) WasmModuleBuilder {
        return .{
            .allocator = allocator,
            .code = .empty,
            .num_locals = 0,
            .num_globals = 0,
            .linear_memory_size = 65536, // 1 page = 64KB
            .function_table_size = 256,
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

        std.debug.print("[WASM] Building module for {} instructions\n", .{chunk.instructions.len});
        for (chunk.instructions, 0..) |instr, i| {
            std.debug.print("  [{d}] {s} operand={d}\n", .{ i, @tagName(instr.opcode), instr.operand });
        }

        // Magic number + version
        try module.appendSlice(self.allocator, &[_]u8{ 0x00, 0x61, 0x73, 0x6D }); // "\0asm"
        try module.appendSlice(self.allocator, &[_]u8{ 0x01, 0x00, 0x00, 0x00 }); // version 1

        // Type section: 定義函數簽名 [] -> [f64]
        try self.writeTypeSection(&module);

        // Import section: builtin functions (Phase 2/4)
        try self.writeImportSection(&module, chunk);

        // Function section: 函數使用嘅類型
        try self.writeFunctionSection(&module);

        // Table section: function table for indirect calls (Phase 4)
        try self.writeTableSection(&module);

        // Memory section: linear memory for heap types (Phase 3)
        try self.writeMemorySection(&module);

        // Global section: global variables (Phase 1)
        try self.writeGlobalSection(&module, chunk);

        // Export section: 導出 "main" 函數
        try self.writeExportSection(&module, chunk);

        // Code section: 函數體
        try self.writeCodeSection(&module, chunk);

        return try module.toOwnedSlice(self.allocator);
    }

    fn writeImportSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 2 (import)
        // 掃描 chunk 以確定需要導入邊啲 builtin functions
        const num_builtins = self.scanBuiltins(chunk);

        if (num_builtins == 0) return; // 冇 builtins 就跳過

        try module.append(self.allocator, 0x02);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        try self.writeLEB128(&payload, num_builtins);

        // 簡化：為每個 builtin index 導入一個 (f64...) → (f64) 函數
        for (0..num_builtins) |i| {
            // module name: "env"
            try self.writeLEB128(&payload, 3);
            try payload.appendSlice(self.allocator, "env");

            // field name: "builtin<i>"
            const name = try std.fmt.allocPrint(self.allocator, "builtin{d}", .{i});
            defer self.allocator.free(name);
            try self.writeLEB128(&payload, @intCast(name.len));
            try payload.appendSlice(self.allocator, name);

            // import kind: function (0x00)
            try payload.append(self.allocator, 0x00);
            // type index: 2 (variadic function type - 簡化為單參數)
            try self.writeLEB128(&payload, 2);
        }

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn scanBuiltins(_: *WasmModuleBuilder, chunk: BytecodeChunk) u32 {
        var max_builtin: u32 = 0;
        for (chunk.instructions) |instr| {
            if (instr.opcode == .op_invoke_builtin) {
                const idx = @as(u32, instr.operand);
                if (idx >= max_builtin) max_builtin = idx + 1;
            }
        }
        return max_builtin;
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

        // limits: min=function_table_size, max=none
        try payload.append(self.allocator, 0x00); // flags: no maximum
        try self.writeLEB128(&payload, self.function_table_size);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeMemorySection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 5 (memory)
        try module.append(self.allocator, 0x05);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 1 個 memory
        try self.writeLEB128(&payload, 1);

        // limits: min=(linear_memory_size / 65536) pages, max=none
        try payload.append(self.allocator, 0x00); // flags: no maximum
        const pages = self.linear_memory_size / 65536;
        try self.writeLEB128(&payload, pages);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeGlobalSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 6 (global)
        // 掃描所有 op_def / op_set_var / op_get_var 以確定需要幾多 globals
        self.num_globals = try self.scanGlobals(chunk);

        if (self.num_globals == 0) return; // 冇 globals 就跳過

        try module.append(self.allocator, 0x06);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        try self.writeLEB128(&payload, self.num_globals);

        // 每個 global: (mut f64) 初始化為 0.0
        for (0..self.num_globals) |_| {
            try payload.append(self.allocator, 0x7C); // f64
            try payload.append(self.allocator, 0x01); // mutable

            // init expr: f64.const 0.0
            try payload.append(self.allocator, 0x44); // f64.const
            const zero: f64 = 0.0;
            const bytes = @as([8]u8, @bitCast(zero));
            try payload.appendSlice(self.allocator, &bytes);
            try payload.append(self.allocator, 0x0B); // end
        }

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn scanGlobals(_: *WasmModuleBuilder, chunk: BytecodeChunk) !u32 {
        var max_global: u32 = 0;
        for (chunk.instructions) |instr| {
            switch (instr.opcode) {
                .op_def, .op_def_unbound, .op_get_var, .op_set_var => {
                    // operand 係 name_idx，簡化：直接當 global_idx
                    const idx = @as(u32, instr.operand);
                    if (idx >= max_global) max_global = idx + 1;
                },
                else => {},
            }
        }
        return max_global;
    }

    fn writeTypeSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 1 (type)
        try module.append(self.allocator, 0x01);

        // Section payload
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 3 個類型
        try self.writeLEB128(&payload, 3);

        // Type 0: main 函數 [] -> [f64]
        try payload.append(self.allocator, 0x60);
        // 0 個參數
        try self.writeLEB128(&payload, 0);
        // 1 個返回值 (f64)
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7C); // f64

        // Type 1: variadic function (簡化為單參數) [f64] -> [f64]
        try payload.append(self.allocator, 0x60);
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7C); // f64
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7C); // f64

        // Type 2: builtin function [f64] -> [f64]
        try payload.append(self.allocator, 0x60);
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7C); // f64
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7C); // f64

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

    fn writeExportSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 7 (export)
        try module.append(self.allocator, 0x07);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 2 個導出：main 函數 + memory
        try self.writeLEB128(&payload, 2);

        // 導出 1: "main" 函數
        const name = "main";
        try self.writeLEB128(&payload, @intCast(name.len));
        try payload.appendSlice(self.allocator, name);
        // 導出類型: 函數
        try payload.append(self.allocator, 0x00);
        // 函數索引 = num_builtins (因為 imports 排先)
        const num_builtins = self.scanBuiltins(chunk);
        try self.writeLEB128(&payload, num_builtins);

        // 導出 2: "memory" (Phase 3: 俾 JS host 存取)
        const mem_name = "memory";
        try self.writeLEB128(&payload, @intCast(mem_name.len));
        try payload.appendSlice(self.allocator, mem_name);
        // 導出類型: memory (0x02)
        try payload.append(self.allocator, 0x02);
        // memory 索引 0
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
                    // Phase 3: Heap types (String, List, Map, Vector, Set, etc.)
                    // 簡化實現：將 heap pointer 轉換為 f64
                    // 真正實現需要 linear memory allocation + GC
                    //
                    // 暫時：將整個 64-bit Value 當 f64 pushstackStack
                    // （唔正確但可以 passthrough）
                    const bits_as_f64: f64 = @bitCast(val_int);
                    try code.append(self.allocator, 0x44); // f64.const
                    const bytes = @as([8]u8, @bitCast(bits_as_f64));
                    try code.appendSlice(self.allocator, &bytes);
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
            .op_dup => {
                // Duplicate top of stack
                // Stack: [x] → [x x]
                try code.append(self.allocator, 0x20); // local.get 0
                try code.append(self.allocator, 0x00);
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
            .op_mod => {
                // f64 modulo: a - (b * floor(a/b))
                // Stack: [a b] → [a mod b]
                try code.append(self.allocator, 0x1C); // local.tee $tmp_b
                try self.writeLEB128(code, self.num_locals);
                try code.append(self.allocator, 0xA3); // f64.div (a/b on stack)
                try code.append(self.allocator, 0x9C); // f64.floor
                try code.append(self.allocator, 0x20); // local.get $tmp_b
                try code.append(self.allocator, 0xA2); // f64.mul (floor * b)
                try code.append(self.allocator, 0xA1); // f64.sub (a - result)
            },
            .op_quot => {
                // Quotient (truncated division): trunc(a/b)
                // Stack: [a b] → [quot]
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9A); // f64.trunc
            },
            .op_rem => {
                // Remainder (same as mod for positive; differs for negative)
                // WASM f64 semantics: IEEE 754 remainder
                // Stack: [a b] → [rem]
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9A); // f64.trunc
                try code.append(self.allocator, 0x1C); // local.tee $quot
                try self.writeLEB128(code, self.num_locals);
                try code.append(self.allocator, 0xA2); // f64.mul (quot * b)
                try code.append(self.allocator, 0xA1); // f64.sub (a - quot*b)
            },
            .op_ge => {
                // f64.ge
                try code.append(self.allocator, 0xC6);
                // Convert i32 result to f64 (0.0 or 1.0)
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_le => {
                // f64.le
                try code.append(self.allocator, 0xC4);
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },

            // Phase 5-14: Advanced opcodes
            .op_jump => {
                // Unconditional branch
                // operand = target bytecode offset (TBD: needs label resolution)
                // Wasm br takes a depth index; single-block stub: br 0 (break current block)
                try code.append(self.allocator, 0x0C); // br
                try self.writeLEB128(code, 0);
            },
            .op_branch_true => {
                // Conditional branch if top of stack is truthy
                // Stack: [cond] → []
                // STUB: stub — br_if 0
                try code.append(self.allocator, 0x0D); // br_if
                try self.writeLEB128(code, 0);
            },
            .op_branch_false => {
                // Conditional branch if top of stack is falsey
                // Stack: [cond] → []
                // STUB: needs NOT + br_if or dedicated logic
                // Stub: drop (ignore condition)
                try code.append(self.allocator, 0x1A); // drop
            },

            // Fusion comparison-branch opcodes (Group 2)
            .op_branch_ge_local_const, .op_branch_ge_locals => {
                // ge comparison + conditional branch
                // Stack: [a b] → [] (branch if a >= b)
                try code.append(self.allocator, 0xC6); // f64.ge
                try code.append(self.allocator, 0x0D); // br_if 0
                try self.writeLEB128(code, 0);
            },
            .op_branch_gt_local_const, .op_branch_gt_locals => {
                // gt comparison + conditional branch
                try code.append(self.allocator, 0xC5); // f64.gt
                try code.append(self.allocator, 0x0D); // br_if 0
                try self.writeLEB128(code, 0);
            },
            .op_branch_ne_local_const, .op_branch_ne_locals => {
                // ne comparison + conditional branch
                try code.append(self.allocator, 0xC2); // f64.ne
                try code.append(self.allocator, 0x0D); // br_if 0
                try self.writeLEB128(code, 0);
            },

            // Local-optimized arithmetic variants (Group 1 continued)
            .op_add_local_const => {
                // add with one arg from local
                // PERF: inline local.get + f64.add [refs: O-TBD]
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xA0); // f64.add
            },
            .op_add_locals => {
                // add with both args from locals
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, instr.operand >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xA0); // f64.add
            },
            .op_mul_local_const, .op_mul_locals => {
                // Simplified: treat as generic mul (TBD)
                try code.append(self.allocator, 0xA2); // f64.mul
            },
            .op_mod_local_const, .op_mod_locals => {
                // Simplified: treat as generic mod
                try code.append(self.allocator, 0x1C); // local.tee (reuse mod sequence)
                try self.writeLEB128(code, self.num_locals);
                try code.append(self.allocator, 0xA3);
                try code.append(self.allocator, 0x9C);
                try code.append(self.allocator, 0x20);
                try code.append(self.allocator, 0xA2);
                try code.append(self.allocator, 0xA1);
            },
            .op_eq_local_const, .op_eq_locals,
            .op_ge_local_const, .op_ge_locals,
            .op_le_local_const, .op_le_locals,
            .op_lt_local_const, .op_lt_locals,
            .op_gt_local_const, .op_gt_locals => {
                // Local-optimized comparison (TBD: all as generic)
                // Each should inline local.get, but for now: assume args on stack
                const cmp_code: u8 = switch (instr.opcode) {
                    .op_eq_local_const, .op_eq_locals => 0xC1,
                    .op_ge_local_const, .op_ge_locals => 0xC6,
                    .op_le_local_const, .op_le_locals => 0xC4,
                    .op_lt_local_const, .op_lt_locals => 0xC3,
                    .op_gt_local_const, .op_gt_locals => 0xC5,
                    else => unreachable,
                };
                try code.append(self.allocator, cmp_code);
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },

            // Group 3: Collections (get/nth + exceptions)
            .op_get => {
                // (get coll key [default])
                // STUB: call import function $builtin_get
                try code.append(self.allocator, 0x10); // call
                try self.writeLEB128(code, 0); // import idx (placeholder)
            },
            .op_nth => {
                // (nth coll index [default])
                // STUB: call import function $builtin_nth
                try code.append(self.allocator, 0x10); // call
                try self.writeLEB128(code, 1); // import idx (placeholder)
            },
            .op_throw => {
                // throw exception
                // STUB: Wasm has no native exceptions; use unreachable
                try code.append(self.allocator, 0x00); // unreachable
            },
            .op_reraise => {
                // re-throw caught exception
                try code.append(self.allocator, 0x00); // unreachable
            },
            .op_push_handler => {
                // Push exception handler (try-catch setup)
                // STUB: no-op stub
            },
            .op_handler => {
                // Exception handler block
                // STUB: no-op stub
            },
            .op_push_cleanup => {
                // Push cleanup frame (finally)
                // STUB: no-op stub
            },
            .op_recur_loop => {
                // recur loop marker
                // STUB: no-op (loop structure handled elsewhere)
            },

            // Group 4: Closures & function objects
            .op_make_fn => {
                // Create closure object
                // STUB: push 0.0 (placeholder fn handle)
                try code.append(self.allocator, 0x44); // f64.const
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_letfn_patch => {
                // Patch mutual-recursive letfn bindings
                // STUB: no-op stub
            },
            .op_binding_frame => {
                // Create dynamic binding frame
                // STUB: no-op stub
            },
            .op_push_binding_frame => {
                // Push binding frame onto stack
                // STUB: no-op stub
            },

            // Group 5: Interop (JVM-style calls)
            .op_ctor_call => {
                // Constructor call
                // STUB: unsupported — push 0.0
                try code.append(self.allocator, 0x44); // f64.const 0.0
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_method_call => {
                // Instance method call
                // STUB: unsupported — push 0.0
                try code.append(self.allocator, 0x44);
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_static_method_call => {
                // Static method call
                // STUB: unsupported — push 0.0
                try code.append(self.allocator, 0x44);
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_set_field => {
                // Set instance field
                // STUB: no-op stub
            },

            // Group 6: Namespace ops
            .op_in_ns => {
                // Switch to namespace
                // STUB: no-op stub
            },
            .op_ns_with_refer_clojure => {
                // ns with refer-clojure
                // STUB: no-op stub
            },
            .op_ns_with_filter => {
                // ns with :only/:exclude filter
                // STUB: no-op stub
            },
            .op_ns_import => {
                // ns import statement
                // STUB: no-op stub
            },

            // Type checking / pattern matching
            .op_match_class => {
                // Match JVM class
                // STUB: push false (0.0)
                try code.append(self.allocator, 0x44);
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_match_type_keyword => {
                // Match type keyword (:int/:string/etc)
                // STUB: push false (0.0)
                try code.append(self.allocator, 0x44);
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },

            // Remaining local-optimized variants (Group 1 final sweep)
            .op_sub_local_const, .op_sub_locals => {
                // sub with local optimization
                try code.append(self.allocator, 0xA1); // f64.sub (TBD: generic)
            },
            .op_quot_local_const, .op_quot_locals => {
                // quot with local optimization
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9A); // f64.trunc
            },
            .op_rem_local_const, .op_rem_locals => {
                // rem with local optimization
                try code.append(self.allocator, 0xA3); // f64.div (reuse rem sequence)
                try code.append(self.allocator, 0x9A);
                try code.append(self.allocator, 0x1C);
                try self.writeLEB128(code, self.num_locals);
                try code.append(self.allocator, 0xA2);
                try code.append(self.allocator, 0xA1);
            },
            .op_ne_local_const, .op_ne_locals => {
                // ne with local optimization
                try code.append(self.allocator, 0xC2); // f64.ne
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },

            // Binding frame ops
            .op_pop_binding_frame => {
                // Pop binding frame
                // STUB: no-op stub
            },
            .op_pop_handler => {
                // Pop exception handler
                // STUB: no-op stub
            },

            // Collection accessors
            .op_nth2 => {
                // (nth coll index) — 2-arg variant without default
                // STUB: call import $builtin_nth (same as op_nth)
                try code.append(self.allocator, 0x10); // call
                try self.writeLEB128(code, 1);
            },

            // Phase 1: Variables
            .op_def, .op_def_unbound => {
                // def: pop value from stack, store to global
                // operand = name_idx (簡化：直接當 global_idx)
                const global_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x24); // global.set
                try self.writeLEB128(code, global_idx);
                // def 返回 Var ref (簡化：push nil = 0.0)
                try code.append(self.allocator, 0x44); // f64.const
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_get_var => {
                // Stack: [] → [var_value]
                // operand = var index
                const global_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x23); // global.get
                try self.writeLEB128(code, global_idx);
            },
            .op_set_var => {
                // store to global (set!)
                const global_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x24); // global.set
                try self.writeLEB128(code, global_idx);
            },

            // Phase 2: Namespace (stub implementation)
            .op_require, .op_require_with_libspec => {
                // 簡化：require 係 no-op（假設所有 namespace 已經存在）
                // 真正實現需要動態模組載入
            },

            // Phase 3: Comparisons & Logic
            .op_eq => {
                // f64.eq
                try code.append(self.allocator, 0xC1);
                // 轉換 i32 結果為 f64 (0.0 or 1.0)
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_ne => {
                // f64.ne
                try code.append(self.allocator, 0xC2);
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_lt => {
                // f64.lt
                try code.append(self.allocator, 0xC3);
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_gt => {
                // f64.gt
                try code.append(self.allocator, 0xC5);
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },

            // Phase 4: Function calls (stub — 未有 function table setup)
            .op_call => {
                // Stack: [arg0, arg1, ..., fn_value] → [result]
                // operand = arity (arg count)
                // Stub: pop all args + fn, push dummy result (0.0)
                const arity = instr.operand;
                for (0..arity + 1) |_| { // +1 for function value
                    try code.append(self.allocator, 0x1A); // drop
                }
                // Push dummy result (0.0)
                try code.append(self.allocator, 0x44); // f64.const
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_invoke_builtin => {
                // Import builtin functions: call imported function
                // operand = builtin index
                const builtin_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x10); // call
                try self.writeLEB128(code, builtin_idx); // function index (import 0)
            },

            // Phase 3: Data structure literals (stubs)
            .op_vector_literal => {
                // Stack: [v1, v2, ..., vN] → [vector]
                // operand = element count
                // Phase B stub: pop elements, push NaN-boxed heap-A placeholder
                // (real heap allocation deferred)
                const elem_count = instr.operand;
                for (0..elem_count) |_| {
                    try code.append(self.allocator, 0x1A); // drop
                }
                // Push NaN-boxed heap-A tag (0xFFF8_0000_0000_0000) as placeholder
                try code.append(self.allocator, 0x44); // f64.const
                const heap_a_tag: u64 = 0xFFF8_0000_0000_0000;
                const vec_placeholder: f64 = @bitCast(heap_a_tag);
                const bytes = @as([8]u8, @bitCast(vec_placeholder));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_set_literal => {
                // Stack: [v1, v2, ..., vN] → [set]
                // operand = element count
                // Stub: same as vector
                const elem_count = instr.operand;
                for (0..elem_count) |_| {
                    try code.append(self.allocator, 0x1A); // drop
                }
                try code.append(self.allocator, 0x44); // f64.const
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_map_literal => {
                // Stack: [k1, v1, k2, v2, ...] → [map]
                // operand = value count (= 2 * pair_count)
                // Phase C stub: pop all key-value pairs, push NaN-boxed heap-A placeholder
                const value_count = instr.operand;
                for (0..value_count) |_| {
                    try code.append(self.allocator, 0x1A); // drop
                }
                // Push NaN-boxed heap-A tag (0xFFF8_0000_0000_0000) as placeholder
                try code.append(self.allocator, 0x44); // f64.const
                const heap_a_tag: u64 = 0xFFF8_0000_0000_0000;
                const map_placeholder: f64 = @bitCast(heap_a_tag);
                const bytes = @as([8]u8, @bitCast(map_placeholder));
                try code.appendSlice(self.allocator, &bytes);
            },
            .op_var_meta => {
                // Stack: [var_value] → [var_value, metadata_map]
                // Stub: duplicate value, push dummy metadata (0.0)
                // Wasm doesn't have dup; workaround: use local.tee + local.get
                // For now: just push 0.0 (incorrect but simplest stub)
                try code.append(self.allocator, 0x44); // f64.const
                const zero: f64 = 0.0;
                const bytes = @as([8]u8, @bitCast(zero));
                try code.appendSlice(self.allocator, &bytes);
            },

            else => {
                std.debug.print("[WASM] Unsupported opcode: {s}\n", .{@tagName(instr.opcode)});
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
    return builder.build(chunk) catch |err| {
        std.debug.print("[WASM BUILD ERROR] {}\n", .{err});
        return err;
    };
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
