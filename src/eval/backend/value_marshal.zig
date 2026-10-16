// SPDX-License-Identifier: EPL-2.0
//! Value marshaling between cljw and zwasm
//!
//! Converts cljw runtime Values to/from zwasm WASM Values for
//! IR Backend execution via zwasm runtime.
//!
//! Current support:
//! - f64 (numbers)
//!
//! Planned support:
//! - i64 (encoded pointers for strings, collections, etc.)
//! - Complex types via pointer encoding

const std = @import("std");
const Value = @import("../../runtime/value/value.zig").Value;
const build_options = @import("build_options");

// Only available when -Dwasm flag is set
const zwasm_available = @hasDecl(build_options, "wasm");
const ZwasmValue = if (zwasm_available)
    @import("../../runtime/cljw/wasm/engine.zig").Value
else
    void;

pub const MarshalError = error{
    UnsupportedType,
    OutOfMemory,
};

/// Convert cljw Value to zwasm Value
pub fn toZwasm(value: Value) MarshalError!ZwasmValue {
    if (!zwasm_available) {
        return error.UnsupportedType;
    }

    // For now, only support f64
    if (value.isNumber()) {
        return ZwasmValue{ .f64 = value.asFloat() };
    }

    // TODO: Support other types
    // - nil → f64 NaN (special encoding)
    // - bool → i32 (0/1)
    // - string → i64 (pointer)
    // - collections → i64 (pointer)

    return error.UnsupportedType;
}

/// Convert zwasm Value to cljw Value
pub fn fromZwasm(zwasm_value: ZwasmValue) MarshalError!Value {
    if (!zwasm_available) {
        return error.UnsupportedType;
    }

    // For now, only support f64
    return Value.initFloat(zwasm_value.f64);

    // TODO: Support other types
    // - Check for NaN patterns (nil, booleans)
    // - Decode i64 pointers to heap objects
}

/// Marshal array of cljw Values to zwasm Values
pub fn toZwasmArray(
    allocator: std.mem.Allocator,
    values: []const Value,
) MarshalError![]ZwasmValue {
    if (!zwasm_available) {
        return error.UnsupportedType;
    }

    var result = try allocator.alloc(ZwasmValue, values.len);
    errdefer allocator.free(result);

    for (values, 0..) |value, i| {
        result[i] = try toZwasm(value);
    }

    return result;
}

/// Marshal array of zwasm Values to cljw Values
pub fn fromZwasmArray(
    allocator: std.mem.Allocator,
    zwasm_values: []const ZwasmValue,
) MarshalError![]Value {
    if (!zwasm_available) {
        return error.UnsupportedType;
    }

    var result = try allocator.alloc(Value, zwasm_values.len);
    errdefer allocator.free(result);

    for (zwasm_values, 0..) |zwasm_value, i| {
        result[i] = try fromZwasm(zwasm_value);
    }

    return result;
}

// Tests
const testing = std.testing;

test "toZwasm: f64 number" {
    if (!zwasm_available) {
        return error.SkipZigTest;
    }

    const value = Value.initFloat(42.5);
    const zwasm_value = try toZwasm(value);

    try testing.expectEqual(@as(f64, 42.5), zwasm_value.f64);
}

test "fromZwasm: f64 number" {
    if (!zwasm_available) {
        return error.SkipZigTest;
    }

    const zwasm_value = ZwasmValue{ .f64 = 42.5 };
    const value = try fromZwasm(zwasm_value);

    try testing.expectEqual(@as(f64, 42.5), value.asFloat());
}

test "toZwasmArray: multiple values" {
    if (!zwasm_available) {
        return error.SkipZigTest;
    }

    const values = [_]Value{
        Value.initFloat(1.0),
        Value.initFloat(2.0),
        Value.initFloat(3.0),
    };

    const zwasm_values = try toZwasmArray(testing.allocator, &values);
    defer testing.allocator.free(zwasm_values);

    try testing.expectEqual(@as(usize, 3), zwasm_values.len);
    try testing.expectEqual(@as(f64, 1.0), zwasm_values[0].f64);
    try testing.expectEqual(@as(f64, 2.0), zwasm_values[1].f64);
    try testing.expectEqual(@as(f64, 3.0), zwasm_values[2].f64);
}
