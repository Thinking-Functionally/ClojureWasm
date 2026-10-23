// SPDX-License-Identifier: EPL-2.0
//! WAT output verification tests for WasmGC compiler
//!
//! These tests verify that the compiler generates correct WAT for:
//! - Literal values (nil, boolean, long, double, string)
//! - Runtime function calls (hash computation, equality)
//! - Special forms (if, do, let)
//! - Function definitions and calls

const std = @import("std");
const testing = std.testing;
const compiler = @import("compiler");
const runtime = @import("runtime");
const types = @import("types");

test "compile nil literal via compileModule" {
    const forms = [_]compiler.ASTNode{
        .{ .literal = .{ .value = .nil } },
    };
    const wat = try compiler.compileModule(testing.allocator, &forms);
    defer testing.allocator.free(wat);

    // Verify module structure
    try testing.expect(std.mem.indexOf(u8, wat, "(module") != null);

    // Verify nil literal (tag=0, null data)
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 0)") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(ref.null $ValueData)") != null);
}

test "compile boolean literals via compileModule" {
    const forms = [_]compiler.ASTNode{
        .{ .literal = .{ .value = .{ .boolean = true } } },
        .{ .literal = .{ .value = .{ .boolean = false } } },
    };
    const wat = try compiler.compileModule(testing.allocator, &forms);
    defer testing.allocator.free(wat);

    // Verify boolean tag (tag=1)
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 1)") != null);

    // Verify union construction
    try testing.expect(std.mem.indexOf(u8, wat, "(union.new $ValueData $boolean") != null);
}

test "compile long literal via compileModule" {
    const forms = [_]compiler.ASTNode{
        .{ .literal = .{ .value = .{ .long = 42 } } },
    };
    const wat = try compiler.compileModule(testing.allocator, &forms);
    defer testing.allocator.free(wat);

    // Verify long tag (tag=2) and i64 value
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 2)") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(i64.const 42)") != null);
}

test "compile double literal via compileModule" {
    const forms = [_]compiler.ASTNode{
        .{ .literal = .{ .value = .{ .double = 3.14 } } },
    };
    const wat = try compiler.compileModule(testing.allocator, &forms);
    defer testing.allocator.free(wat);

    // Verify double tag (tag=3) and f64 value
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 3)") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "f64.const") != null);
}

test "compile string literal via compileModule" {
    const forms = [_]compiler.ASTNode{
        .{ .literal = .{ .value = .{ .string = "hi" } } },
    };
    const wat = try compiler.compileModule(testing.allocator, &forms);
    defer testing.allocator.free(wat);

    // Verify runtime call to $rt_make_string
    try testing.expect(std.mem.indexOf(u8, wat, "$rt_make_string") != null);

    // Verify array construction with byte values for "hi" (104, 105)
    try testing.expect(std.mem.indexOf(u8, wat, "104") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "105") != null);
}

test "runtime - emit string hash function" {
    var gen = runtime.RuntimeGen.init(testing.allocator);
    defer gen.deinit();

    const wat = try gen.emitStringHash();

    // Verify function signature
    try testing.expect(std.mem.indexOf(u8, wat, "(func $rt_string_hash") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(param $s (ref $String))") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(result i32)") != null);

    // Verify FNV-1a constants
    try testing.expect(std.mem.indexOf(u8, wat, "0x811c9dc5") != null); // FNV offset basis
    try testing.expect(std.mem.indexOf(u8, wat, "0x01000193") != null); // FNV prime
}

test "runtime - emit string equals function" {
    var gen = runtime.RuntimeGen.init(testing.allocator);
    defer gen.deinit();

    const wat = try gen.emitStringEquals();

    // Verify function signature
    try testing.expect(std.mem.indexOf(u8, wat, "(func $rt_string_equals") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(param $a (ref $String))") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(param $b (ref $String))") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(result i32)") != null);

    // Verify hash-first optimization
    try testing.expect(std.mem.indexOf(u8, wat, "Fast path: different hashes") != null);

    // Verify byte-by-byte comparison (no TODO)
    try testing.expect(std.mem.indexOf(u8, wat, "TODO") == null);
    try testing.expect(std.mem.indexOf(u8, wat, "array.get_u") != null);
}

test "runtime - emit symbol equals function" {
    var gen = runtime.RuntimeGen.init(testing.allocator);
    defer gen.deinit();

    const wat = try gen.emitSymbolEquals();

    // Verify function signature
    try testing.expect(std.mem.indexOf(u8, wat, "(func $rt_symbol_equals") != null);

    // Verify full ns + name comparison (no TODO)
    try testing.expect(std.mem.indexOf(u8, wat, "TODO") == null);
    try testing.expect(std.mem.indexOf(u8, wat, "Full ns + name string comparison") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "struct.get $Symbol $ns") != null);
}

test "runtime - emit keyword equals function" {
    var gen = runtime.RuntimeGen.init(testing.allocator);
    defer gen.deinit();

    const wat = try gen.emitKeywordEquals();

    // Verify function signature
    try testing.expect(std.mem.indexOf(u8, wat, "(func $rt_keyword_equals") != null);

    // Verify full ns + name comparison (no TODO)
    try testing.expect(std.mem.indexOf(u8, wat, "TODO") == null);
    try testing.expect(std.mem.indexOf(u8, wat, "Full ns + name string comparison") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "struct.get $Keyword $ns") != null);
}

test "types - ValueTag to WAT conversion" {
    try testing.expectEqualStrings("0", types.ValueTag.nil.toWAT());
    try testing.expectEqualStrings("1", types.ValueTag.boolean.toWAT());
    try testing.expectEqualStrings("2", types.ValueTag.long.toWAT());
    try testing.expectEqualStrings("3", types.ValueTag.double.toWAT());
    try testing.expectEqualStrings("4", types.ValueTag.string.toWAT());
}
