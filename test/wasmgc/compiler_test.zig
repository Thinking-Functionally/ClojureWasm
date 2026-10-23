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

test "compile nil literal wrapped in def" {
    var literal = compiler.ASTNode{ .literal = .{ .value = .nil } };
    const def_form = compiler.ASTNode{ .def = .{
        .name = "x",
        .init = &literal,
    } };
    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify nil literal (tag=0, null data)
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 0)") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(ref.null $ValueData)") != null);
}

test "compile boolean literal wrapped in def" {
    var literal = compiler.ASTNode{ .literal = .{ .value = .{ .boolean = true } } };
    const def_form = compiler.ASTNode{ .def = .{
        .name = "x",
        .init = &literal,
    } };
    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify boolean tag (tag=1)
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 1)") != null);

    // Verify union construction
    try testing.expect(std.mem.indexOf(u8, wat, "(union.new $ValueData $boolean") != null);
}

test "compile long literal wrapped in def" {
    var literal = compiler.ASTNode{ .literal = .{ .value = .{ .long = 42 } } };
    const def_form = compiler.ASTNode{ .def = .{
        .name = "x",
        .init = &literal,
    } };
    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify long tag (tag=2) and i64 value
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 2)") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(i64.const 42)") != null);
}

test "compile double literal wrapped in def" {
    var literal = compiler.ASTNode{ .literal = .{ .value = .{ .double = 3.14 } } };
    const def_form = compiler.ASTNode{ .def = .{
        .name = "x",
        .init = &literal,
    } };
    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify double tag (tag=3) and f64 value
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 3)") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "f64.const") != null);
}

test "compile string literal wrapped in def" {
    var literal = compiler.ASTNode{ .literal = .{ .value = .{ .string = "hi" } } };
    const def_form = compiler.ASTNode{ .def = .{
        .name = "x",
        .init = &literal,
    } };
    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify runtime call to $rt_make_string
    try testing.expect(std.mem.indexOf(u8, wat, "$rt_make_string") != null);

    // Verify array construction with byte values for "hi" (104, 105)
    try testing.expect(std.mem.indexOf(u8, wat, "104") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "105") != null);
}
