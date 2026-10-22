// SPDX-License-Identifier: EPL-2.0
//! WasmGC literal compilation tests.
//!
//! Verifies that basic Clojure literals (nil, boolean, long, double, string)
//! compile correctly to WAT format.
//!
//! Phase: Month 1 Week 3-4 — basic literal compilation

const std = @import("std");
const testing = std.testing;
const wasmgc = @import("wasmgc");
const value_types = @import("value_types");
const Runtime = @import("Runtime");

test "TypeTag enum values match specification" {
    try testing.expectEqual(@as(i32, 0), @intFromEnum(value_types.TypeTag.nil));
    try testing.expectEqual(@as(i32, 1), @intFromEnum(value_types.TypeTag.boolean));
    try testing.expectEqual(@as(i32, 2), @intFromEnum(value_types.TypeTag.long));
    try testing.expectEqual(@as(i32, 3), @intFromEnum(value_types.TypeTag.double));
    try testing.expectEqual(@as(i32, 4), @intFromEnum(value_types.TypeTag.string));
    try testing.expectEqual(@as(i32, 5), @intFromEnum(value_types.TypeTag.symbol));
    try testing.expectEqual(@as(i32, 6), @intFromEnum(value_types.TypeTag.keyword));
    try testing.expectEqual(@as(i32, 7), @intFromEnum(value_types.TypeTag.list));
    try testing.expectEqual(@as(i32, 8), @intFromEnum(value_types.TypeTag.vector));
    try testing.expectEqual(@as(i32, 9), @intFromEnum(value_types.TypeTag.map));
    try testing.expectEqual(@as(i32, 10), @intFromEnum(value_types.TypeTag.set));
}

test "WatTypeGen emits core $Value type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var gen = value_types.WatTypeGen.init(arena.allocator());
    const wat = try gen.emitValueType();

    // Verify WAT output contains expected structure
    try testing.expect(std.mem.indexOf(u8, wat, "(type $Value (struct") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(field $tag i32)") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(field $data (ref null $ValueData))") != null);
}

test "WatTypeGen emits $String type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var gen = value_types.WatTypeGen.init(arena.allocator());
    const wat = try gen.emitStringType();

    try testing.expect(std.mem.indexOf(u8, wat, "(type $String (struct") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(field $bytes (array (mut i8)))") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(field $hash i32)") != null);
}

test "WatTypeGen emits $Symbol type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var gen = value_types.WatTypeGen.init(arena.allocator());
    const wat = try gen.emitSymbolType();

    try testing.expect(std.mem.indexOf(u8, wat, "(type $Symbol (struct") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(field $ns (ref null $String))") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(field $name (ref $String))") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(field $hash i32)") != null);
}

test "WatTypeGen emits $Keyword type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var gen = value_types.WatTypeGen.init(arena.allocator());
    const wat = try gen.emitKeywordType();

    try testing.expect(std.mem.indexOf(u8, wat, "(type $Keyword (struct") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(field $ns (ref null $String))") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(field $name (ref $String))") != null);
}

test "WatTypeGen emitAllTypes contains all core types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var gen = value_types.WatTypeGen.init(arena.allocator());
    const wat = try gen.emitAllTypes();

    // Verify all type definitions present
    try testing.expect(std.mem.indexOf(u8, wat, "$Value") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "$String") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "$Symbol") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "$Keyword") != null);
}
