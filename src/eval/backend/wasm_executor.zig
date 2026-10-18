// SPDX-License-Identifier: EPL-2.0
//! Wasm Executor: 用 zwasm API 載入同執行生成嘅 Wasm 模組
//!
//! Tier 3: zwasm 整合層
//! 提供 BytecodeChunk → Wasm → zwasm execution → Value 嘅完整流程。

const std = @import("std");
const opcode_mod = @import("vm/opcode.zig");
const Value = @import("../../runtime/value/value.zig").Value;
const wasm_module_builder = @import("wasm_module_builder.zig");

const BytecodeChunk = opcode_mod.BytecodeChunk;

// Compile-time check: zwasm is only available with -Dwasm flag
const build_options = @import("build_options");
const has_wasm = build_options.wasm;

// Import zwasm only when available (compile-time conditional)
const wasm_engine = if (has_wasm) @import("../../runtime/cljw/wasm/engine.zig") else struct {
    pub const Loaded = void;
    pub const Value = void;
};

pub const ExecuteError = error{
    WasmModuleBuildFailed,
    WasmLoadFailed,
    WasmExecutionFailed,
    ResultConversionFailed,
    ZwasmNotAvailable,
} || std.mem.Allocator.Error;

/// Wasm 執行器
pub const WasmExecutor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !WasmExecutor {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WasmExecutor) void {
        _ = self;
    }

    /// 由 BytecodeChunk 生成 Wasm 字節碼，載入到 zwasm，執行，返回 Value
    pub fn execute(
        self: *WasmExecutor,
        chunk: BytecodeChunk,
    ) ExecuteError!Value {
        if (!has_wasm) {
            return ExecuteError.ZwasmNotAvailable;
        }

        // Step 1: 生成 Wasm 模組字節碼
        const wasm_bytes = wasm_module_builder.buildWasmModule(self.allocator, chunk) catch {
            return ExecuteError.WasmModuleBuildFailed;
        };
        defer self.allocator.free(wasm_bytes);

        // Step 2: 載入到 zwasm Engine
        var loaded = wasm_engine.load(self.allocator, wasm_bytes, .{}) catch {
            return ExecuteError.WasmLoadFailed;
        };
        defer {
            loaded.deinit();
            self.allocator.destroy(loaded);
        }

        // Step 3: 執行 "main" 函數
        var results: [1]wasm_engine.Value = undefined;
        loaded.invoke("main", &[_]wasm_engine.Value{}, &results) catch {
            return ExecuteError.WasmExecutionFailed;
        };

        // Step 4: zwasm 結果轉換為 cljw Value
        // zwasm Value.f64 is u64 (bit pattern), need @bitCast to f64
        const result_u64 = results[0].f64;
        const result_f64: f64 = @bitCast(result_u64);
        return Value.initInteger(@intFromFloat(result_f64));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "WasmExecutor: init and deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var executor = try WasmExecutor.init(allocator);
    defer executor.deinit();

    // Executor 初始化成功
    try testing.expect(true);
}

test "WasmExecutor: simple constant" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var executor = try WasmExecutor.init(allocator);
    defer executor.deinit();

    // 構造簡單嘅 BytecodeChunk: [(const 42), (ret)]
    const instructions = try allocator.alloc(opcode_mod.WireInstr, 2);
    defer allocator.free(instructions);
    instructions[0] = .{ .opcode = .op_const, .operand = 0 };
    instructions[1] = .{ .opcode = .op_ret, .operand = 0 };

    const constants = try allocator.alloc(Value, 1);
    defer allocator.free(constants);
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

    // Execute with zwasm integration (Tier 3 complete)
    const result = try executor.execute(chunk);

    // Tier 3: zwasm returns Value.initInteger(42)
    const i = result.asInteger();
    try testing.expectEqual(@as(i48, 42), i);
}
