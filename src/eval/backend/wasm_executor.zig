// SPDX-License-Identifier: EPL-2.0
//! Wasm Executor: 用 zwasm API 載入同執行生成嘅 Wasm 模組
//!
//! Tier 3: zwasm 整合層
//! 提供 BytecodeChunk → Wasm → zwasm execution → Value 嘅完整流程。

const std = @import("std");
const opcode_mod = @import("vm/opcode.zig");
const Value = @import("../../runtime/value/value.zig").Value;
const wasm_module_builder = @import("wasm_module_builder.zig");

// TODO: Import zwasm API
// const zwasm = @import("zwasm");

const BytecodeChunk = opcode_mod.BytecodeChunk;

pub const ExecuteError = error{
    WasmModuleBuildFailed,
    WasmLoadFailed,
    WasmExecutionFailed,
    ResultConversionFailed,
} || std.mem.Allocator.Error;

/// Wasm 執行器
pub const WasmExecutor = struct {
    allocator: std.mem.Allocator,
    // zwasm_engine: zwasm.Engine,  // TODO: zwasm v2.5.0 Engine

    pub fn init(allocator: std.mem.Allocator) !WasmExecutor {
        return .{
            .allocator = allocator,
            // .zwasm_engine = try zwasm.Engine.init(allocator),  // TODO
        };
    }

    pub fn deinit(self: *WasmExecutor) void {
        // self.zwasm_engine.deinit();  // TODO
        _ = self;
    }

    /// 由 BytecodeChunk 生成 Wasm 字節碼，載入到 zwasm，執行，返回 Value
    pub fn execute(
        self: *WasmExecutor,
        chunk: BytecodeChunk,
    ) ExecuteError!Value {
        // Step 1: 生成 Wasm 模組字節碼
        const wasm_bytes = wasm_module_builder.buildWasmModule(self.allocator, chunk) catch {
            return ExecuteError.WasmModuleBuildFailed;
        };
        defer self.allocator.free(wasm_bytes);

        // Step 2: 載入到 zwasm Engine
        // TODO: 用 zwasm.Module.parse + zwasm.Instance.create
        // const module = try zwasm.Module.parse(&self.zwasm_engine, wasm_bytes);
        // defer module.deinit();

        // Step 3: 執行 "main" 函數
        // TODO: instance.call("main", &[_]zwasm.Value{})
        // const result = try instance.call("main", &[_]zwasm.Value{});

        // Step 4: zwasm 結果轉換為 cljw Value
        // TODO: zwasm.Value (f64) → cljw Value.initFloat
        // return Value.initFloat(result.asF64());

        // Placeholder: 暫時返回 nil
        return Value.nil();
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

test "WasmExecutor: simple constant (placeholder)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var executor = try WasmExecutor.init(allocator);
    defer executor.deinit();

    // 構造簡單嘅 BytecodeChunk: [(const 42), (ret)]
    const instructions = try allocator.alloc(opcode_mod.Instruction, 2);
    defer allocator.free(instructions);
    instructions[0] = .{ .op = .op_const, .operand = 0, .loc = null };
    instructions[1] = .{ .op = .op_ret, .operand = 0, .loc = null };

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
        .source_file = null,
    };

    // Execute (暫時返回 nil，因為 zwasm 整合未完成)
    const result = try executor.execute(chunk);

    // Placeholder: 預期返回 nil
    try testing.expect(result.isNil());
}
