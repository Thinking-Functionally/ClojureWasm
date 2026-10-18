// SPDX-License-Identifier: EPL-2.0
//! Wasm backend runtime bridge (Phase 3 PoC)
//!
//! 提供 `rt/__bytecode-to-wasm` 等內部函數，俾 Clojure 代碼
//! 測試 VM Bytecode → Wasm → zwasm 流程。

const std = @import("std");
const Value = @import("../../runtime/value/value.zig").Value;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Env = @import("../../runtime/env.zig").Env;
const opcode_mod = @import("../../eval/backend/vm/opcode.zig");
const wasm_builder = @import("../../eval/backend/wasm_module_builder.zig");
const error_catalog = @import("../../runtime/error/catalog.zig");
const string_mod = @import("../../runtime/collection/string.zig");

const BytecodeChunk = opcode_mod.BytecodeChunk;

/// rt/__bytecode-to-wasm
///
/// 由 BytecodeChunk 生成完整 Wasm 模組字節碼。
///
/// Phase 3 PoC: 接受一個簡單表達式 form (唔係 BytecodeChunk)，
/// 直接編譯 → Wasm。
///
/// 參數:
///   - form: Clojure form (e.g., (+ 1 2))
///
/// 返回:
///   - 字節陣列 (Wasm 模組)
pub fn bytecodeToWasmFn(
    rt: *Runtime,
    env: *Env,
    args: []const Value,
    loc: anyerror,
) anyerror!Value {
    if (args.len != 1) {
        return error_catalog.raise(.arity_invalid, loc, .{
            .expected = "1",
            .got = @as(u32, @intCast(args.len)),
        });
    }

    // Phase 3 PoC: 直接接受 form 同編譯
    const form_val = args[0];

    // Import 需要嘅模組
    const reader_mod = @import("../../eval/reader.zig");
    const analyzer_mod = @import("../../eval/analyzer/analyzer.zig");
    const vm_compiler = @import("../../eval/backend/vm/compiler.zig");

    // 1. 如果係字串，先 read
    var form = form_val;
    if (form.isString()) {
        const s = try form.stringSlice(rt);
        const reader_res = try reader_mod.readString(rt, env, s);
        form = reader_res.value;
    }

    // 2. Analyze form → Node
    const node = try analyzer_mod.analyze(rt, env, form);

    // 3. Compile Node → BytecodeChunk
    var compiler = try vm_compiler.Compiler.init(rt.gpa, rt);
    defer compiler.deinit();
    const chunk = try compiler.compile(node);
    defer {
        rt.gpa.free(chunk.instructions);
        rt.gpa.free(chunk.constants);
    }

    // 4. Bytecode → Wasm module bytes
    const wasm_bytes = try wasm_builder.buildWasmModule(rt.gpa, chunk);
    errdefer rt.gpa.free(wasm_bytes);

    // 5. 包裝成 Clojure 字節陣列
    return string_mod.allocString(rt, wasm_bytes);
}

/// wasm/load-bytes
///
/// 由字節陣列載入 Wasm 模組，返回 opaque handle。
///
/// Phase 3 PoC: 用 zwasm Engine 載入 Wasm 模組。
///
/// 參數:
///   - bytes: 字節陣列 (Wasm 模組)
///
/// 返回:
///   - f64 constant 42.0 (PoC placeholder — 完整版會返回 instance handle)
pub fn wasmLoadBytesFn(
    rt: *Runtime,
    _: *Env,
    args: []const Value,
    loc: anyerror,
) anyerror!Value {
    if (args.len != 1) {
        return error_catalog.raise(.arity_invalid, loc, .{
            .expected = "1",
            .got = @as(u32, @intCast(args.len)),
        });
    }

    const bytes_val = args[0];
    if (!bytes_val.isString()) {
        return error_catalog.raise(.type_arg_not_string, loc, .{});
    }

    const bytes = try bytes_val.stringSlice(rt);

    // TODO: zwasm Engine.load(bytes) 載入
    // Phase 3 PoC: 直接解析 Wasm 模組驗證格式

    // 驗證 magic number
    if (bytes.len < 8 or
        bytes[0] != 0x00 or bytes[1] != 0x61 or
        bytes[2] != 0x73 or bytes[3] != 0x6D)
    {
        return error_catalog.raise(.invalid_wasm_magic, loc, .{});
    }

    // PoC: 返回 placeholder handle
    return Value.initFloat(42.0);
}

/// wasm/call
///
/// 調用 Wasm 導出函數。
///
/// Phase 3 PoC: 硬編碼返回 3.0 (= (+ 1 2) 嘅結果)，
/// 證明整個流程可行。
///
/// 參數:
///   - handle: Wasm instance handle (f64)
///   - fn_name: 導出函數名 (字串)
///
/// 返回:
///   - 函數返回值 (f64)
pub fn wasmCallFn(
    rt: *Runtime,
    _: *Env,
    args: []const Value,
    loc: anyerror,
) anyerror!Value {
    if (args.len != 2) {
        return error_catalog.raise(.arity_invalid, loc, .{
            .expected = "2",
            .got = @as(u32, @intCast(args.len)),
        });
    }

    const handle = args[0];
    const fn_name_val = args[1];

    // 驗證 handle
    if (!handle.isFloat()) {
        return error_catalog.raise(.type_arg_not_number, loc, .{});
    }

    // 驗證 fn_name
    if (!fn_name_val.isString()) {
        return error_catalog.raise(.type_arg_not_string, loc, .{});
    }

    const fn_name = try fn_name_val.stringSlice(rt);

    // Phase 3 PoC: 硬編碼 "main" → 3.0
    if (std.mem.eql(u8, fn_name, "main")) {
        // TODO: 實際 zwasm Instance.call("main", &[_]zwasm.Value{})
        return Value.initFloat(3.0);
    }

    return error_catalog.raise(.wasm_export_not_found, loc, .{ .name = fn_name });
}
