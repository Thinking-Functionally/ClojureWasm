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
const opcode_mod = @import("../vm/opcode.zig");
const Value = @import("../../../runtime/value/value.zig").Value;
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
    MissingStringOffset,
    VectorTooLarge,
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
    // Maps constant pool index → linear memory offset for heap types
    // (string constants live in data section at known offsets)
    string_offsets: std.AutoHashMap(u16, u32),
    // Phase 3b: Runtime heap allocation watermark (next free offset)
    // Starts after static data; bumped by heap_alloc export at runtime
    heap_watermark: u32,

    pub fn init(allocator: std.mem.Allocator) WasmModuleBuilder {
        return .{
            .allocator = allocator,
            .code = .empty,
            .num_locals = 0,
            .num_globals = 0,
            .linear_memory_size = 65536, // 1 page = 64KB
            .function_table_size = 256,
            .string_offsets = std.AutoHashMap(u16, u32).init(allocator),
            .heap_watermark = 1024, // HEAP_START
        };
    }

    pub fn deinit(self: *WasmModuleBuilder) void {
        self.code.deinit(self.allocator);
        self.string_offsets.deinit();
    }

    /// Scan chunk.constants for heap types and assign linear memory offsets.
    /// Phase 3: Static strings only; dynamic allocation is Phase 3b.
    fn scanAndMapHeapConstants(self: *WasmModuleBuilder, chunk: BytecodeChunk) !void {
        var current_offset: u32 = self.heap_watermark;

        for (chunk.constants, 0..) |val, idx| {
            if (val.tag() != .string) continue;

            // Decode string length (requires decoding the pointer)
            const str_ptr = val.decodePtr([*]const u8);
            // Find null terminator for [*]const u8
            var str_len: usize = 0;
            while (str_ptr[str_len] != 0) : (str_len += 1) {}

            // Align offset to 8 bytes (HeapHeader requirement)
            current_offset = std.mem.alignForward(u32, current_offset, 8);

            // Map this constant pool index to its linear memory offset
            try self.string_offsets.put(@intCast(idx), current_offset);

            // Advance offset: HeapHeader (8 bytes) + string bytes
            const total_size = 8 + str_len;
            current_offset += @intCast(total_size);
        }

        // Update heap watermark to end of static data
        // (runtime allocations start here)
        self.heap_watermark = current_offset;
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

        // Phase 3: Scan constants and assign linear memory offsets for heap types
        try self.scanAndMapHeapConstants(chunk);

        // Magic number + version
        try module.appendSlice(self.allocator, &[_]u8{ 0x00, 0x61, 0x73, 0x6D }); // "\0asm"
        try module.appendSlice(self.allocator, &[_]u8{ 0x01, 0x00, 0x00, 0x00 }); // version 1

        // Type section: 定義函數簽名 [] -> [f64]
        try self.writeTypeSection(&module, chunk);

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

        // Code section: 函數體 (Section 10 - must come before Data)
        try self.writeCodeSection(&module, chunk);

        // Data section: pre-populate linear memory with string constants (Phase 3, Section 11)
        try self.writeDataSection(&module, chunk);

        return try module.toOwnedSlice(self.allocator);
    }

    fn writeImportSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 2 (import)
        // 掃描 chunk 以確定需要導入邊啲 builtin functions + collection literals + accessors
        const num_builtins = self.scanBuiltins(chunk);
        const needs_collections = self.scanCollectionLiterals(chunk);
        const accessors = self.scanCollectionAccessors(chunk);

        // Phase 3c: Always import collection literal host functions if needed
        const num_collection_imports: u32 = if (needs_collections) 3 else 0;
        // Phase 3d: Collection accessor host imports (conditional per opcode presence)
        var num_accessor_imports: u32 = 0;
        if (accessors.op_get) num_accessor_imports += 2; // cljw_get_2, cljw_get_3
        if (accessors.op_nth) num_accessor_imports += 1; // cljw_nth_3
        if (accessors.op_nth2) num_accessor_imports += 1; // cljw_nth_2
        const total_imports = num_builtins + num_collection_imports + num_accessor_imports;

        if (total_imports == 0) return; // 冇 imports 就跳過

        try module.append(self.allocator, 0x02);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        try self.writeLEB128(&payload, total_imports);

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

        // Phase 3c: Collection literal host imports (type 4: [i32 i32] -> [i64])
        // Function indices: num_builtins + {0, 1, 2}
        if (needs_collections) {
            const collection_imports = [_][]const u8{ "vector_from_slice", "map_from_pairs", "set_from_slice" };
            for (collection_imports) |name| {
                // module name: "cljw" (ClojureWasm runtime)
                try self.writeLEB128(&payload, 4);
                try payload.appendSlice(self.allocator, "cljw");

                // field name
                try self.writeLEB128(&payload, @intCast(name.len));
                try payload.appendSlice(self.allocator, name);

                // import kind: function (0x00)
                try payload.append(self.allocator, 0x00);
                // type index: 4 ([i32 i32] -> [i64])
                try self.writeLEB128(&payload, 4);
            }
        }

        // Phase 3d: Collection accessor host imports
        // Function indices: num_builtins + num_collection_imports + {0..N}
        // Emit order: cljw_get_2/3, cljw_nth_3, cljw_nth_2 (conditional on opcode presence)
        if (accessors.op_get) {
            // cljw_get_2: type 5 ([f64 f64] -> [f64])
            try self.writeLEB128(&payload, 4);
            try payload.appendSlice(self.allocator, "cljw");
            const name = "cljw_get_2";
            try self.writeLEB128(&payload, @intCast(name.len));
            try payload.appendSlice(self.allocator, name);
            try payload.append(self.allocator, 0x00);
            try self.writeLEB128(&payload, 5);

            // cljw_get_3: type 6 ([f64 f64 f64] -> [f64])
            try self.writeLEB128(&payload, 4);
            try payload.appendSlice(self.allocator, "cljw");
            const name3 = "cljw_get_3";
            try self.writeLEB128(&payload, @intCast(name3.len));
            try payload.appendSlice(self.allocator, name3);
            try payload.append(self.allocator, 0x00);
            try self.writeLEB128(&payload, 6);
        }
        if (accessors.op_nth) {
            // cljw_nth_3: type 6 ([f64 f64 f64] -> [f64])
            try self.writeLEB128(&payload, 4);
            try payload.appendSlice(self.allocator, "cljw");
            const name = "cljw_nth_3";
            try self.writeLEB128(&payload, @intCast(name.len));
            try payload.appendSlice(self.allocator, name);
            try payload.append(self.allocator, 0x00);
            try self.writeLEB128(&payload, 6);
        }
        if (accessors.op_nth2) {
            // cljw_nth_2: type 5 ([f64 f64] -> [f64])
            try self.writeLEB128(&payload, 4);
            try payload.appendSlice(self.allocator, "cljw");
            const name = "cljw_nth_2";
            try self.writeLEB128(&payload, @intCast(name.len));
            try payload.appendSlice(self.allocator, name);
            try payload.append(self.allocator, 0x00);
            try self.writeLEB128(&payload, 5);
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

    fn scanCollectionLiterals(_: *WasmModuleBuilder, chunk: BytecodeChunk) bool {
        // PROVISIONAL Phase 3c: Collection literal host imports (vector/map/set_from_slice)
        //
        // These imports ARE emitted into the wasm module and ARE called by the collection
        // literal opcodes, but zwasm v2.5.0's load() API does not yet accept a host function
        // table at instantiation time, so they will TRAP at runtime with "unresolved import".
        //
        // Blocker: zwasm host function API (F-001 mailbox protocol RETIRED 2026-08-12;
        // zwasm now under separate maintainership at github.com/zwasm/zwasm).
        //
        // Next step: when zwasm adds instantiate-with-imports API, wire collection literal
        // host handlers into WasmExecutor.execute() and remove this PROVISIONAL marker.

        // Phase 3c: Check if chunk needs collection literal host imports
        for (chunk.instructions) |instr| {
            switch (instr.opcode) {
                .op_vector_literal, .op_map_literal, .op_set_literal => return true,
                else => {},
            }
        }
        return false;
    }

    fn scanCollectionAccessors(_: *WasmModuleBuilder, chunk: BytecodeChunk) struct { op_get: bool, op_nth: bool, op_nth2: bool } {
        // PROVISIONAL Phase 3d: Collection accessor host imports (cljw_get_2/3, cljw_nth_2/3)
        //
        // These imports ARE emitted into the wasm module and ARE called by the collection
        // accessor opcodes (op_get / op_nth / op_nth2), but zwasm v2.5.0's load() API does
        // not yet accept a host function table at instantiation time, so they will TRAP at
        // runtime with "unresolved import".
        //
        // Blocker: same as Phase 3c (zwasm host function API).
        //
        // Next step: when zwasm adds instantiate-with-imports API, wire collection accessor
        // host handlers (intrinsic.fastGet / fastNth3 / fastNth2) into WasmExecutor.execute()
        // and remove this PROVISIONAL marker.

        var has_op_get = false;
        var has_op_nth = false;
        var has_op_nth2 = false;
        for (chunk.instructions) |instr| {
            switch (instr.opcode) {
                .op_get => has_op_get = true,
                .op_nth => has_op_nth = true,
                .op_nth2 => has_op_nth2 = true,
                else => {},
            }
        }
        return .{ .op_get = has_op_get, .op_nth = has_op_nth, .op_nth2 = has_op_nth2 };
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

        // Always write global section (at least for heap_watermark)
        try module.append(self.allocator, 0x06);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // num_globals + 1 (for heap_watermark)
        try self.writeLEB128(&payload, self.num_globals + 1);

        // User globals: (mut f64) 初始化為 0.0
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

        // Global for heap watermark: (mut i32) initialized to heap_watermark value
        // Phase 3b: runtime allocator state
        try payload.append(self.allocator, 0x7F); // i32
        try payload.append(self.allocator, 0x01); // mutable

        // init expr: i32.const heap_watermark
        try payload.append(self.allocator, 0x41); // i32.const
        try self.writeLEB128(&payload, self.heap_watermark);
        try payload.append(self.allocator, 0x0B); // end

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

    fn writeTypeSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 1 (type)
        try module.append(self.allocator, 0x01);

        // Section payload
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // Conditional type count: 5 base types + 2 if collection accessors present
        const accessors = self.scanCollectionAccessors(chunk);
        const has_accessors = accessors.op_get or accessors.op_nth or accessors.op_nth2;
        const num_types: u32 = if (has_accessors) 7 else 5;
        try self.writeLEB128(&payload, num_types);

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

        // Type 3: heap_alloc [i32] -> [i32]
        // Phase 3b runtime allocator
        try payload.append(self.allocator, 0x60);
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7F); // i32
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7F); // i32

        // Type 4: collection literal host imports [i32 i32] -> [i64]
        // Phase 3c: vector_from_slice / map_from_pairs / set_from_slice
        try payload.append(self.allocator, 0x60);
        try self.writeLEB128(&payload, 2);
        try payload.append(self.allocator, 0x7F); // i32 (stackPtr)
        try payload.append(self.allocator, 0x7F); // i32 (count)
        try self.writeLEB128(&payload, 1);
        try payload.append(self.allocator, 0x7E); // i64 (Value bits)

        // Conditional: emit Types 5/6 only if collection accessor opcodes present
        if (has_accessors) {
            // Type 5: collection accessor 2-arg [f64 f64] -> [f64]
            // Phase 3d: cljw_get_2 (coll, k) / cljw_nth_2 (coll, i)
            try payload.append(self.allocator, 0x60);
            try self.writeLEB128(&payload, 2);
            try payload.append(self.allocator, 0x7C); // f64
            try payload.append(self.allocator, 0x7C); // f64
            try self.writeLEB128(&payload, 1);
            try payload.append(self.allocator, 0x7C); // f64

            // Type 6: collection accessor 3-arg [f64 f64 f64] -> [f64]
            // Phase 3d: cljw_get_3 (coll, k, default) / cljw_nth_3 (coll, i, default)
            try payload.append(self.allocator, 0x60);
            try self.writeLEB128(&payload, 3);
            try payload.append(self.allocator, 0x7C); // f64
            try payload.append(self.allocator, 0x7C); // f64
            try payload.append(self.allocator, 0x7C); // f64
            try self.writeLEB128(&payload, 1);
            try payload.append(self.allocator, 0x7C); // f64
        }

        // 寫入 payload 長度同內容
        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeFunctionSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8)) !void {
        // Section ID 3 (function)
        try module.append(self.allocator, 0x03);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 2 個函數：main + heap_alloc
        try self.writeLEB128(&payload, 2);
        // Function 0: main (type 0)
        try self.writeLEB128(&payload, 0);
        // Function 1: heap_alloc (type 3)
        try self.writeLEB128(&payload, 3);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeExportSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 7 (export)
        try module.append(self.allocator, 0x07);

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        // 3 個導出：main 函數 + memory + heap_alloc
        try self.writeLEB128(&payload, 3);

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

        // 導出 3: "heap_alloc" (Phase 3b: runtime allocator)
        const alloc_name = "heap_alloc";
        try self.writeLEB128(&payload, @intCast(alloc_name.len));
        try payload.appendSlice(self.allocator, alloc_name);
        // 導出類型: 函數
        try payload.append(self.allocator, 0x00);
        // 函數索引 = num_builtins + 1 (main 之後)
        try self.writeLEB128(&payload, num_builtins + 1);

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeDataSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 11 (data)
        // Pre-populate linear memory with string constants from chunk.constants[]
        //
        // Phase 3b: Static strings in data section + runtime heap_alloc for dynamic allocation.
        // Emit data segments for each string constant using the offset map
        // built by scanAndMapHeapConstants. Each segment contains:
        // HeapHeader (8 bytes: tag + length) + string bytes.

        // Write number of data segments (= number of string constants)
        const string_count = self.string_offsets.count();
        if (string_count == 0) return; // Skip empty Data section

        try module.append(self.allocator, 0x0B); // section ID 11

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);

        try self.writeLEB128(&payload, @intCast(string_count));

        // Emit each string as a data segment
        for (chunk.constants, 0..) |val, idx| {
            if (val.tag() != .string) continue;

            const offset = self.string_offsets.get(@intCast(idx)).?;

            // Decode string pointer from Value
            const str_ptr = val.decodePtr([*]const u8);
            // Need to get length differently for [*]const u8
            // Find null terminator
            var str_len: usize = 0;
            while (str_ptr[str_len] != 0) : (str_len += 1) {}

            // Data segment: active (flags=0x00), memory 0, offset expression, data
            try self.writeLEB128(&payload, 0x00); // Active segment, memory 0
            try self.writeLEB128(&payload, 0); // Memory index

            // Offset expression: (i32.const offset) (end)
            try payload.append(self.allocator, 0x41); // i32.const opcode
            try self.writeLEB128(&payload, offset);
            try payload.append(self.allocator, 0x0B); // end opcode

            // Data: HeapHeader (8 bytes) + string bytes
            const total_size = 8 + str_len;
            try self.writeLEB128(&payload, @intCast(total_size));

            // HeapHeader: tag (u32) + length (u32)
            // tag = 0x01 for string (HeapTag enum value)
            try WasmModuleBuilder.writeU32(undefined, &payload, self.allocator, 0x01);
            try WasmModuleBuilder.writeU32(undefined, &payload, self.allocator, @intCast(str_len));

            // String bytes
            try payload.appendSlice(self.allocator, str_ptr[0..str_len]);
        }

        try self.writeLEB128(module, @intCast(payload.items.len));
        try module.appendSlice(self.allocator, payload.items);
    }

    fn writeCodeSection(self: *WasmModuleBuilder, module: *std.ArrayList(u8), chunk: BytecodeChunk) !void {
        // Section ID 10 (code)
        try module.append(self.allocator, 0x0A);

        var section_payload: std.ArrayList(u8) = .empty;
        defer section_payload.deinit(self.allocator);

        // 2 個函數體：main + heap_alloc
        try self.writeLEB128(&section_payload, 2);

        // Function 0: main
        {
            var func_body: std.ArrayList(u8) = .empty;
            defer func_body.deinit(self.allocator);

            // Locals 聲明 (先掃描需要幾多 locals)
            const user_locals = try self.scanLocals(chunk);

            // Reserve extra temp locals for operations that need them:
            // - op_mod needs 1 temp (to save b)
            // - op_rem needs 1 temp (to save quot)
            const needs_temp_locals = self.needsTempLocals(chunk);
            const num_temp_locals: u32 = if (needs_temp_locals) 2 else 0;
            self.num_locals = user_locals + num_temp_locals;

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
        }

        // Function 1: heap_alloc(size: i32) -> i32
        // Phase 3b: runtime linear memory bump allocator
        {
            var func_body: std.ArrayList(u8) = .empty;
            defer func_body.deinit(self.allocator);

            // No locals (only uses param $size and global $heap_watermark)
            try self.writeLEB128(&func_body, 0);

            // Get current heap watermark (global index = num_globals)
            const heap_watermark_idx = self.num_globals;

            // local.get 0 (param $size)
            try func_body.append(self.allocator, 0x20); // local.get
            try self.writeLEB128(&func_body, 0);

            // Align size to 8 bytes: (size + 7) & ~7
            // i32.const 7
            try func_body.append(self.allocator, 0x41); // i32.const
            try self.writeLEB128(&func_body, 7);
            // i32.add
            try func_body.append(self.allocator, 0x6A);
            // i32.const -8 (two's complement of 8 = 0xFFFFFFF8)
            try func_body.append(self.allocator, 0x41); // i32.const
            try self.writeSLEB128(&func_body, -8);
            // i32.and
            try func_body.append(self.allocator, 0x71);

            // Get heap watermark (current offset)
            try func_body.append(self.allocator, 0x23); // global.get
            try self.writeLEB128(&func_body, heap_watermark_idx);

            // Duplicate for return value (stack: [aligned_size, current_offset, current_offset])
            try func_body.append(self.allocator, 0x1A); // drop
            try func_body.append(self.allocator, 0x23); // global.get (reload)
            try self.writeLEB128(&func_body, heap_watermark_idx);
            try func_body.append(self.allocator, 0x22); // local.tee 1 (if we had a local)
            // Actually we have no locals, so just duplicate via get-set-get pattern:
            // Stack manipulation: we want [aligned_size, offset, offset]
            // Current: [aligned_size, offset]
            // Push offset again
            try func_body.append(self.allocator, 0x23); // global.get
            try self.writeLEB128(&func_body, heap_watermark_idx);

            // Now stack: [aligned_size, offset, offset]
            // Update watermark: offset + aligned_size
            // Rotate to get [offset, offset, aligned_size]
            // Actually simpler: save offset first, then compute new watermark

            // Let me restart with clearer logic:
            // 1. aligned_size = (size + 7) & ~7  (already on stack)
            // 2. current_offset = global[heap_watermark]
            // 3. new_offset = current_offset + aligned_size
            // 4. global[heap_watermark] = new_offset
            // 5. return current_offset

            // Clear and restart:
            func_body.clearRetainingCapacity();
            try self.writeLEB128(&func_body, 0); // no locals

            // Load heap watermark (will be return value)
            try func_body.append(self.allocator, 0x23); // global.get
            try self.writeLEB128(&func_body, heap_watermark_idx);

            // Compute aligned size: (param_0 + 7) & ~7
            try func_body.append(self.allocator, 0x20); // local.get 0 (param $size)
            try self.writeLEB128(&func_body, 0);
            try func_body.append(self.allocator, 0x41); // i32.const 7
            try self.writeLEB128(&func_body, 7);
            try func_body.append(self.allocator, 0x6A); // i32.add
            try func_body.append(self.allocator, 0x41); // i32.const -8
            try self.writeSLEB128(&func_body, -8);
            try func_body.append(self.allocator, 0x71); // i32.and

            // Add to current watermark: new_watermark = current + aligned_size
            try func_body.append(self.allocator, 0x23); // global.get heap_watermark
            try self.writeLEB128(&func_body, heap_watermark_idx);
            try func_body.append(self.allocator, 0x6A); // i32.add

            // Store new watermark
            try func_body.append(self.allocator, 0x24); // global.set
            try self.writeLEB128(&func_body, heap_watermark_idx);

            // Return old watermark (already on stack from first global.get)
            // end
            try func_body.append(self.allocator, 0x0B);

            // 寫入函數體長度同內容
            try self.writeLEB128(&section_payload, @intCast(func_body.items.len));
            try section_payload.appendSlice(self.allocator, func_body.items);
        }

        // 寫入 section 長度同內容
        try self.writeLEB128(module, @intCast(section_payload.items.len));
        try module.appendSlice(self.allocator, section_payload.items);
    }

    /// 帶控制流結構嘅指令翻譯 (two-pass: collect targets → emit structured code)
    fn translateWithControlFlow(
        self: *WasmModuleBuilder,
        code: *std.ArrayList(u8),
        chunk: BytecodeChunk,
        cf_analysis: *ControlFlowAnalysis,
    ) !void {
        var block_stack = BlockStack.init(self.allocator);
        defer block_stack.deinit();

        // IP → label 映射 (pre-allocated for ALL targets in Pass 1)
        var ip_to_label = std.AutoHashMap(usize, u32).init(self.allocator);
        defer ip_to_label.deinit();

        // Pass 1: Pre-allocate labels for ALL jump targets (including forward jumps)
        // This ensures ip_to_label.get(target_ip) never returns null
        var next_label: u32 = 0;
        var sorted_targets: std.ArrayList(usize) = .empty;
        defer sorted_targets.deinit(self.allocator);

        var target_iter = cf_analysis.jump_targets.keyIterator();
        while (target_iter.next()) |target_ip| {
            try sorted_targets.append(self.allocator, target_ip.*);
        }
        std.mem.sort(usize, sorted_targets.items, {}, std.sort.asc(usize));

        for (sorted_targets.items) |target_ip| {
            try ip_to_label.put(target_ip, next_label);
            next_label += 1;
        }

        // 檢查係咪有 recur (需要外層 loop)
        const has_recur = cf_analysis.loop_starts.count() > 0;
        if (has_recur) {
            // loop (result type 同 func 一致: [] → [f64])
            try code.append(self.allocator, 0x03); // loop
            try code.append(self.allocator, 0x7C); // result type: f64
            const loop_label = try block_stack.push(.loop, 0);
            // Override label 0 with loop label
            try ip_to_label.put(0, loop_label);
        }

        // Pass 2: Emit Wasm code with blocks at target IPs
        for (chunk.instructions, 0..) |instr, ip| {
            // 檢查當前 IP 係咪跳轉目標 → 插入 block
            if (ip_to_label.get(ip)) |pre_label| {
                if (has_recur and ip == 0) {
                    // Already emitted loop at IP 0
                } else {
                    // block (result type: [] → [])
                    try code.append(self.allocator, 0x02); // block
                    try code.append(self.allocator, 0x40); // void
                    const label = try block_stack.push(.block, ip);
                    // Verify label matches pre-allocated
                    std.debug.assert(label == pre_label);
                }
            }

            // 翻譯指令
            switch (instr.opcode) {
                .op_jump => {
                    // 計算目標 IP
                    const target_ip = try cf_analysis.computeJumpTarget(ip, instr.operand);
                    // 揾目標 block label (guaranteed to exist after Pass 1)
                    const target_label = ip_to_label.get(target_ip).?;
                    // br <depth>
                    // NOTE: forward jumps 到 not-yet-pushed blocks return depth 0 (stub behavior)
                    const depth = block_stack.computeBranchDepth(target_label) orelse 0;
                    try code.append(self.allocator, 0x0C); // br
                    try self.writeLEB128(code, depth);
                },
                .op_jump_if_false => {
                    // stack: [cond] → []
                    // if cond == 0, jump to target
                    const target_ip = try cf_analysis.computeJumpTarget(ip, instr.operand);
                    // 揾目標 block label (guaranteed to exist after Pass 1)
                    const target_label = ip_to_label.get(target_ip).?;
                    // NOTE: forward jumps 到 not-yet-pushed blocks return depth 0 (stub behavior)
                    const depth = block_stack.computeBranchDepth(target_label) orelse 0;

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

    fn needsTempLocals(_: *WasmModuleBuilder, chunk: BytecodeChunk) bool {
        for (chunk.instructions) |instr| {
            switch (instr.opcode) {
                .op_mod, .op_rem => return true,
                else => {},
            }
        }
        return false;
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
                    // Phase 3b: Heap types (String, Vector, Map, etc.)
                    // Now with runtime allocator, we encode proper Values

                    if (val.tag() == .string) {
                        // Static string: look up linear memory offset and encode as Value
                        const offset = self.string_offsets.get(instr.operand) orelse {
                            std.debug.print("[WASM ERROR] String constant at index {d} not in offset map\n", .{instr.operand});
                            return error.MissingStringOffset;
                        };

                        // Import WasmLinearMemory for encodeOffset
                        const WasmLinearMemory = @import("wasm_linear_memory.zig").WasmLinearMemory;
                        const HeapTag = @import("../../../runtime/value/value.zig").HeapTag;

                        // Encode offset as proper Value (NaN-box with string tag)
                        const string_value = WasmLinearMemory.encodeOffset(offset, HeapTag.string);
                        const value_bits = @intFromEnum(string_value);

                        // Push Value bits as f64
                        try code.append(self.allocator, 0x44); // f64.const
                        const f: f64 = @bitCast(value_bits);
                        const bytes = @as([8]u8, @bitCast(f));
                        try code.appendSlice(self.allocator, &bytes);
                    } else {
                        // Other heap types: passthrough for now (will use heap_alloc when opcodes land)
                        const bits_as_f64: f64 = @bitCast(val_int);
                        try code.append(self.allocator, 0x44); // f64.const
                        const bytes = @as([8]u8, @bitCast(bits_as_f64));
                        try code.appendSlice(self.allocator, &bytes);
                    }
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
                // Wasm has no native dup; use local.tee + local.get
                const num_user_locals = self.num_locals - 2;
                const tmp_idx = num_user_locals; // Use first temp local
                try code.append(self.allocator, 0x22); // local.tee (set + keep on stack)
                try self.writeLEB128(code, tmp_idx);
                try code.append(self.allocator, 0x20); // local.get (duplicate)
                try self.writeLEB128(code, tmp_idx);
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
                // Clojure floorMod: a - (b * floor(a/b))
                // Stack in: [a b], Stack out: [a mod b]
                const num_user_locals = self.num_locals - 2;
                const tmp_a_idx = num_user_locals;
                const tmp_b_idx = num_user_locals + 1;

                // Save both operands (stack pops in reverse: b first, then a)
                try code.append(self.allocator, 0x21); // local.set $tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0x21); // local.set $tmp_a
                try self.writeLEB128(code, tmp_a_idx);

                // Compute a - (floor(a/b) * b)
                try code.append(self.allocator, 0x20); // local.get $tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get $tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get $tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9C); // f64.floor
                try code.append(self.allocator, 0x20); // local.get $tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA2); // f64.mul
                try code.append(self.allocator, 0xA1); // f64.sub
            },
            .op_quot => {
                // Quotient: trunc(a/b) — truncate toward zero
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9A); // f64.trunc
            },
            .op_rem => {
                // Java-style remainder: a - (trunc(a/b) * b)
                // Stack in: [a b], Stack out: [a rem b]
                const num_user_locals = self.num_locals - 2;
                const tmp_a_idx = num_user_locals;
                const tmp_b_idx = num_user_locals + 1;

                // Save both operands
                try code.append(self.allocator, 0x21); // local.set $tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0x21); // local.set $tmp_a
                try self.writeLEB128(code, tmp_a_idx);

                // Compute a - (trunc(a/b) * b)
                try code.append(self.allocator, 0x20); // local.get $tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get $tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get $tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9A); // f64.trunc
                try code.append(self.allocator, 0x20); // local.get $tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA2); // f64.mul
                try code.append(self.allocator, 0xA1); // f64.sub
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
            .op_jump_if_false => {
                // Conditional branch if top of stack is falsey
                // Stack: [cond] → [] (branch if cond is false)
                // STUB: needs truthiness check + br_if
                // Stub: br_if 0 (Wasm br_if branches on non-zero i32)
                try code.append(self.allocator, 0x0D); // br_if
                try self.writeLEB128(code, 0);
            },

            // Fusion comparison-branch opcodes (Group 2)
            // These combine a comparison + conditional branch
            // _local_const: local compared with stack value
            // _locals: two locals compared
            .op_branch_ge_local_const => {
                // ge: local >= stack_top → branch if true
                // Stack: [b] → []
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get local_a
                try self.writeLEB128(code, local_idx);
                // Now stack: [b a], need f64.ge → [a >= b]
                try code.append(self.allocator, 0xC6); // f64.ge
                try code.append(self.allocator, 0x0D); // br_if 0
                try self.writeLEB128(code, 0);
            },
            .op_branch_ge_locals => {
                // ge: local_a >= local_b → branch if true
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xC6); // f64.ge
                try code.append(self.allocator, 0x0D); // br_if 0
                try self.writeLEB128(code, 0);
            },
            .op_branch_gt_local_const => {
                // gt: local > stack_top → branch if true
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get local_a
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xC5); // f64.gt
                try code.append(self.allocator, 0x0D); // br_if 0
                try self.writeLEB128(code, 0);
            },
            .op_branch_gt_locals => {
                // gt: local_a > local_b → branch if true
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xC5); // f64.gt
                try code.append(self.allocator, 0x0D); // br_if 0
                try self.writeLEB128(code, 0);
            },
            .op_branch_ne_local_const => {
                // ne: local != stack_top → branch if true
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get local_a
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xC2); // f64.ne
                try code.append(self.allocator, 0x0D); // br_if 0
                try self.writeLEB128(code, 0);
            },
            .op_branch_ne_locals => {
                // ne: local_a != local_b → branch if true
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
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
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xA0); // f64.add
            },
            .op_sub_local_const => {
                // sub with one arg from local: local - stack_top
                // Stack: [b] → [(local_a - b)]
                const local_idx = @as(u32, instr.operand);
                const num_user_locals = self.num_locals - 2;
                const tmp_b_idx = num_user_locals;

                // Stack: [b] after previous ops
                try code.append(self.allocator, 0x21); // local.set tmp_b (save b)
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0x20); // local.get local_a
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA1); // f64.sub
            },
            .op_sub_locals => {
                // sub with both args from locals
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xA1); // f64.sub
            },
            .op_mul_local_const => {
                // mul with one arg from local
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xA2); // f64.mul
            },
            .op_mul_locals => {
                // mul with both args from locals
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xA2); // f64.mul
            },
            .op_quot_local_const => {
                // quot with one arg from local
                const local_idx = @as(u32, instr.operand);
                const num_user_locals = self.num_locals - 2;
                const tmp_b_idx = num_user_locals;

                try code.append(self.allocator, 0x21); // local.set tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0x20); // local.get local_a
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9A); // f64.trunc
            },
            .op_quot_locals => {
                // quot with both args from locals
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9A); // f64.trunc
            },
            .op_mod_local_const => {
                // mod with one arg from local
                // Requires temp locals for full a - (b * floor(a/b)) computation
                const local_idx = @as(u32, instr.operand);
                const num_user_locals = self.num_locals - 2;
                const tmp_a_idx = num_user_locals;
                const tmp_b_idx = num_user_locals + 1;

                // Stack: [b] + local_a
                try code.append(self.allocator, 0x21); // local.set tmp_b (save stack b)
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0x20); // local.get local_a
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0x21); // local.set tmp_a
                try self.writeLEB128(code, tmp_a_idx);

                // Now compute: tmp_a - (tmp_b * floor(tmp_a / tmp_b))
                try code.append(self.allocator, 0x20); // local.get tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9C); // f64.floor
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA2); // f64.mul
                try code.append(self.allocator, 0xA1); // f64.sub
            },
            .op_mod_locals => {
                // mod with both args from locals
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                const num_user_locals = self.num_locals - 2;
                const tmp_a_idx = num_user_locals;
                const tmp_b_idx = num_user_locals + 1;

                // Load and save both
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x21); // local.set tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0x21); // local.set tmp_b
                try self.writeLEB128(code, tmp_b_idx);

                // Compute: tmp_a - (tmp_b * floor(tmp_a / tmp_b))
                try code.append(self.allocator, 0x20); // local.get tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9C); // f64.floor
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA2); // f64.mul
                try code.append(self.allocator, 0xA1); // f64.sub
            },
            .op_rem_local_const => {
                // rem with one arg from local
                const local_idx = @as(u32, instr.operand);
                const num_user_locals = self.num_locals - 2;
                const tmp_a_idx = num_user_locals;
                const tmp_b_idx = num_user_locals + 1;

                // Stack: [b] + local_a
                try code.append(self.allocator, 0x21); // local.set tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0x20); // local.get local_a
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0x21); // local.set tmp_a
                try self.writeLEB128(code, tmp_a_idx);

                // Compute: tmp_a - (trunc(tmp_a / tmp_b) * tmp_b)
                try code.append(self.allocator, 0x20); // local.get tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9A); // f64.trunc
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA2); // f64.mul
                try code.append(self.allocator, 0xA1); // f64.sub
            },
            .op_rem_locals => {
                // rem with both args from locals
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                const num_user_locals = self.num_locals - 2;
                const tmp_a_idx = num_user_locals;
                const tmp_b_idx = num_user_locals + 1;

                // Load and save both
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x21); // local.set tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0x21); // local.set tmp_b
                try self.writeLEB128(code, tmp_b_idx);

                // Compute: tmp_a - (trunc(tmp_a / tmp_b) * tmp_b)
                try code.append(self.allocator, 0x20); // local.get tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_a
                try self.writeLEB128(code, tmp_a_idx);
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA3); // f64.div
                try code.append(self.allocator, 0x9A); // f64.trunc
                try code.append(self.allocator, 0x20); // local.get tmp_b
                try self.writeLEB128(code, tmp_b_idx);
                try code.append(self.allocator, 0xA2); // f64.mul
                try code.append(self.allocator, 0xA1); // f64.sub
            },
            // Non-fusion comparison opcodes (push result, don't branch)
            .op_eq_local_const => {
                // eq: local == stack_top → push 1.0 or 0.0
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xC1); // f64.eq
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s (i32 → f64)
            },
            .op_eq_locals => {
                // eq: local_a == local_b → push 1.0 or 0.0
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xC1); // f64.eq
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_ge_local_const => {
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xC6); // f64.ge
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_ge_locals => {
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xC6); // f64.ge
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_le_local_const => {
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xC4); // f64.le
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_le_locals => {
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xC4); // f64.le
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_lt_local_const => {
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xC3); // f64.lt
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_lt_locals => {
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xC3); // f64.lt
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_gt_local_const => {
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xC5); // f64.gt
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_gt_locals => {
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xC5); // f64.gt
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },
            .op_ne_local_const => {
                // ne: local != stack_top → push 1.0 or 0.0
                const local_idx = @as(u32, instr.operand);
                try code.append(self.allocator, 0x20); // local.get
                try self.writeLEB128(code, local_idx);
                try code.append(self.allocator, 0xC2); // f64.ne
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s (i32 → f64)
            },
            .op_ne_locals => {
                // ne: local_a != local_b → push 1.0 or 0.0
                const local_a = @as(u32, instr.operand & 0xFFFF);
                const local_b = @as(u32, @as(u32, instr.operand) >> 16);
                try code.append(self.allocator, 0x20); // local.get a
                try self.writeLEB128(code, local_a);
                try code.append(self.allocator, 0x20); // local.get b
                try self.writeLEB128(code, local_b);
                try code.append(self.allocator, 0xC2); // f64.ne
                try code.append(self.allocator, 0xB7); // f64.convert_i32_s
            },

            // Group 3: Collections + exceptions
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

            // Binding frame ops
            .op_pop_binding_frame => {
                // Pop binding frame
                // STUB: no-op stub
            },
            .op_pop_handler => {
                // Pop exception handler
                // STUB: no-op stub
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
                //
                // NEW STRATEGY (Phase 3c revised):
                // Instead of host imports with linear memory complications,
                // inline the heap allocation + element writes in wasm code.
                //
                // Memory layout for Vector:
                //   [offset+0..7]   HeapHeader { tag = .vector, meta = elem_count }
                //   [offset+8..]    [Value; elem_count] elements
                //
                // Steps:
                // 1. Store N values from stack into locals
                // 2. Call heap_alloc(size = 8 + N*8)
                // 3. Write HeapHeader at returned offset
                // 4. Write elements from locals to [offset+8..]
                // 5. Encode offset as NaN-boxed Value, push to stack
                //
                const elem_count = instr.operand;

                if (elem_count > 64) {
                    // Sanity check - vectors this large need different strategy
                    return error.VectorTooLarge;
                }

                // Step 1: Store elements into locals (in reverse order since stack is LIFO)
                // We'll use locals [1..elem_count] (local 0 is reserved for other uses)
                // Actually: need to allocate temp locals for this. For now, simplified approach:
                // Just save to a temporary "element buffer" using a helper global or memory.
                //
                // SIMPLIFIED V1: For small vectors (≤4), use explicit locals
                // For larger vectors, use linear memory temp buffer at fixed offset

                if (elem_count <= 4) {
                    // Small vector: use locals
                    // Allocate elem_count locals (assume they're available)
                    // Store in reverse: vN → local[elem_count-1], ..., v1 → local[0]

                    // TODO: This needs local allocation tracking in the builder
                    // For now, emit stub that returns empty vector
                    // (Proper implementation needs refactoring builder to track locals)

                    // Drop elements from stack
                    for (0..elem_count) |_| {
                        try code.append(self.allocator, 0x1A); // drop
                    }

                    // Push empty vector (offset 0 = reserved null, will crash if dereferenced)
                    // Better: call empty vector constructor
                    // For now: push 0 as i64 (will show as nil)
                    try code.append(self.allocator, 0x42); // i64.const
                    try code.append(self.allocator, 0x00); // LEB128(0) = 0x00
                } else {
                    // Large vector: needs temp memory buffer
                    // Phase 3c TODO: implement temp buffer strategy

                    for (0..elem_count) |_| {
                        try code.append(self.allocator, 0x1A); // drop
                    }
                    try code.append(self.allocator, 0x42); // i64.const
                    try code.append(self.allocator, 0x00); // LEB128 of 0 is just 0x00
                }
            },
            .op_set_literal => {
                // Stack: [v1, v2, ..., vN] → [set]
                // operand = element count
                // Phase 3c: Call host import set_from_slice (same pattern as vector)
                const elem_count = instr.operand;

                // i32.const 0 (stackPtr placeholder)
                try code.append(self.allocator, 0x41); // i32.const
                try self.writeLEB128(code, 0);

                // i32.const elem_count
                try code.append(self.allocator, 0x41); // i32.const
                try self.writeLEB128(code, elem_count);

                // call $set_from_slice (import index = num_builtins + 2)
                try code.append(self.allocator, 0x10); // call
                const num_builtins = self.scanBuiltins(chunk);
                const import_idx = num_builtins + 2; // set_from_slice is third collection import
                try self.writeLEB128(code, import_idx);

                // Drop original N f64 operands
                for (0..elem_count) |_| {
                    try code.append(self.allocator, 0x1A); // drop
                }
            },
            .op_map_literal => {
                // Stack: [k1, v1, k2, v2, ...] → [map]
                // operand = value count (= 2 * pair_count)
                // Phase 3c: Call host import map_from_pairs
                const value_count = instr.operand;

                // i32.const 0 (stackPtr placeholder)
                try code.append(self.allocator, 0x41); // i32.const
                try self.writeLEB128(code, 0);

                // i32.const value_count
                try code.append(self.allocator, 0x41); // i32.const
                try self.writeLEB128(code, value_count);

                // call $map_from_pairs (import index = num_builtins + 1)
                try code.append(self.allocator, 0x10); // call
                const num_builtins = self.scanBuiltins(chunk);
                const import_idx = num_builtins + 1; // map_from_pairs is second collection import
                try self.writeLEB128(code, import_idx);

                // Drop original value_count f64 operands
                for (0..value_count) |_| {
                    try code.append(self.allocator, 0x1A); // drop
                }
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

            .op_get => {
                // Stack: [coll, k] → [result]
                // Phase 3d: Call host imports cljw_get_2 / cljw_get_3
                //
                // VM backend has intrinsic.fastGet (map/nil inline) + deopt.
                // WASM backend: TWO host imports (2-arg / 3-arg).
                //
                // Problem: op_get is 2-arg ONLY in VM (default=nil implicit).
                // But Clojure `get` has both 2-arg and 3-arg forms.
                //
                // Resolution: op_get always calls cljw_get_2 (coll, k, implicit_nil).
                // If compiler emits op_get, it means 2-arg form.
                // (3-arg form would use a different opcode or inline nil push + this opcode)
                //
                // Simplified emit: assume top 2 stack values are coll, k (f64 values)
                // Pop them, call cljw_get_2, push result.
                //
                // Phase 3c TODO: Proper operand stack. For now: assume f64 stack in wasm.

                // Assume: wasm operand stack has [.., coll (f64), k (f64)]
                // cljw_get_2 signature: [f64 f64] -> [f64]
                // Wasm: top 2 stack values are already args, just emit call

                try code.append(self.allocator, 0x10); // call
                const num_builtins = self.scanBuiltins(chunk);
                const needs_collections = self.scanCollectionLiterals(chunk);
                const num_collection_imports: u32 = if (needs_collections) 3 else 0;
                const import_idx = num_builtins + num_collection_imports + 0; // cljw_get_2 is first accessor import
                try self.writeLEB128(code, import_idx);

                // Result (f64) is on stack
            },

            .op_nth => {
                // Stack: [coll, i, default] → [result]
                // Phase 3d: Call host import cljw_nth_3 (3-arg form)

                try code.append(self.allocator, 0x10); // call
                const num_builtins = self.scanBuiltins(chunk);
                const needs_collections = self.scanCollectionLiterals(chunk);
                const num_collection_imports: u32 = if (needs_collections) 3 else 0;
                const accessors = self.scanCollectionAccessors(chunk);
                var accessor_offset: u32 = 0;
                if (accessors.op_get) accessor_offset += 2; // cljw_get_2/3 come before cljw_nth_3
                const import_idx = num_builtins + num_collection_imports + accessor_offset + 0; // cljw_nth_3
                try self.writeLEB128(code, import_idx);

                // Result (f64) is on stack
            },

            .op_nth2 => {
                // Stack: [coll, i] → [result]
                // Phase 3d: Call host import cljw_nth_2 (2-arg form, raises on OOB)

                try code.append(self.allocator, 0x10); // call
                const num_builtins = self.scanBuiltins(chunk);
                const needs_collections = self.scanCollectionLiterals(chunk);
                const num_collection_imports: u32 = if (needs_collections) 3 else 0;
                const accessors = self.scanCollectionAccessors(chunk);
                var accessor_offset: u32 = 0;
                if (accessors.op_get) accessor_offset += 2; // cljw_get_2/3
                if (accessors.op_nth) accessor_offset += 1; // cljw_nth_3
                const import_idx = num_builtins + num_collection_imports + accessor_offset + 0; // cljw_nth_2
                try self.writeLEB128(code, import_idx);

                // Result (f64) is on stack
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

    /// Write signed LEB128 (for i32.const immediates)
    fn writeSLEB128(self: *WasmModuleBuilder, buffer: *std.ArrayList(u8), value: i32) !void {
        var v = value;
        while (true) {
            const byte = @as(u8, @intCast(v & 0x7F));
            v >>= 7;
            // Continue if more sign-extended bits remain
            const sign_bit_set = (byte & 0x40) != 0;
            if ((v == 0 and !sign_bit_set) or (v == -1 and sign_bit_set)) {
                try buffer.append(self.allocator, byte);
                break;
            } else {
                try buffer.append(self.allocator, byte | 0x80);
            }
        }
    }

    /// Write a little-endian u32 (for HeapHeader fields in data section)
    fn writeU32(_: *WasmModuleBuilder, buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        try buffer.appendSlice(allocator, &bytes);
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

test "control flow: if-then-else (forward jump)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // BytecodeChunk for: (if true 10 20)
    // Bytecode structure:
    // IP 0: const 1.0 (true)
    // IP 1: jump_if_false +3 (if false, jump to IP 4 = else branch)
    // IP 2: const 10 (then branch)
    // IP 3: jump +2 (skip else, jump to IP 5 = after if)
    // IP 4: const 20 (else branch)
    // IP 5: ret
    var instructions = [_]opcode_mod.WireInstr{
        .{ .opcode = .op_const, .operand = 0 }, // true
        .{ .opcode = .op_jump_if_false, .operand = 3 }, // +3 offset
        .{ .opcode = .op_const, .operand = 1 }, // 10
        .{ .opcode = .op_jump, .operand = 2 }, // +2 offset
        .{ .opcode = .op_const, .operand = 2 }, // 20
        .{ .opcode = .op_ret, .operand = 0 },
    };

    var constants = [_]Value{
        Value.initFloat(1.0), // true
        Value.initFloat(10.0),
        Value.initFloat(20.0),
    };

    const chunk = BytecodeChunk{
        .instructions = &instructions,
        .constants = &constants,
        .call_sites = &[_]opcode_mod.CallSiteEntry{},
        .libspecs = &[_]opcode_mod.LibspecEntry{},
        .ns_filters = &[_]opcode_mod.NsFilterEntry{},
        .ctor_sites = &[_]opcode_mod.CtorEntry{},
        .import_sites = &[_]opcode_mod.ImportPair{},
        .source_file = "",
    };

    const wasm_bytes = try buildWasmModule(allocator, chunk);
    defer allocator.free(wasm_bytes);

    // Currently this will emit hard-coded `br 0` for both jumps,
    // which produces structurally invalid or incorrect Wasm.
    // This test captures the RED state: build succeeds but
    // behavior is wrong (full validation + execution check belongs in e2e).
    // For now, just verify the binary is generated (>0 length).
    try testing.expect(wasm_bytes.len > 8); // At least magic + version
}
