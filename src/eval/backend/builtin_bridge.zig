// SPDX-License-Identifier: EPL-2.0
//! Builtin function bridge for IR Backend
//!
//! Provides WASM import table for runtime builtin functions.
//! When IR Backend generates WASM that calls builtins like "+", "cons",
//! this module provides the bridge to cljw's Zig implementations.
//!
//! Architecture:
//! 1. WASM module imports: (import "env" "builtin_add" (func ...))
//! 2. Bridge function: wraps cljw primitive, marshals Values
//! 3. zwasm host function registration

const std = @import("std");
const Value = @import("../../runtime/value/value.zig").Value;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Env = @import("../../runtime/env.zig").Env;
const value_marshal = @import("value_marshal.zig");
const build_options = @import("build_options");

const zwasm_available = @hasDecl(build_options, "wasm");

pub const BuiltinError = error{
    UnsupportedBuiltin,
    MarshalError,
    RuntimeError,
};

/// Builtin function descriptor
pub const BuiltinDescriptor = struct {
    name: []const u8,
    wasm_name: []const u8,
    arity: u32,

    /// Example builtins
    pub const ADD = BuiltinDescriptor{
        .name = "+",
        .wasm_name = "builtin_add",
        .arity = 2,
    };

    pub const SUB = BuiltinDescriptor{
        .name = "-",
        .wasm_name = "builtin_sub",
        .arity = 2,
    };

    pub const MUL = BuiltinDescriptor{
        .name = "*",
        .wasm_name = "builtin_mul",
        .arity = 2,
    };

    pub const DIV = BuiltinDescriptor{
        .name = "/",
        .wasm_name = "builtin_div",
        .arity = 2,
    };
};

/// All registered builtins
pub const BUILTINS = [_]BuiltinDescriptor{
    BuiltinDescriptor.ADD,
    BuiltinDescriptor.SUB,
    BuiltinDescriptor.MUL,
    BuiltinDescriptor.DIV,
};

/// Bridge context passed to host functions
pub const BridgeContext = struct {
    rt: *Runtime,
    env: *Env,
    allocator: std.mem.Allocator,
};

/// Generate WASM import declarations for builtins
/// Returns EDN string to inject into WASM module
pub fn generateImports(allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, ";; Builtin function imports\n");

    for (BUILTINS) |builtin| {
        const import_decl = try std.fmt.allocPrint(
            allocator,
            "(import \"env\" \"{s}\" (func ${s} ",
            .{ builtin.wasm_name, builtin.wasm_name }
        );
        try buf.appendSlice(allocator, import_decl);
        allocator.free(import_decl);

        // Parameters
        try buf.appendSlice(allocator, "(param");
        var i: u32 = 0;
        while (i < builtin.arity) : (i += 1) {
            try buf.appendSlice(allocator, " f64");
        }
        try buf.appendSlice(allocator, ") (result f64)))\n");
    }

    return buf.toOwnedSlice(allocator);
}

/// Host function: + (add)
fn hostAdd(args: []const f64) f64 {
    if (args.len != 2) return std.math.nan(f64);
    return args[0] + args[1];
}

/// Host function: - (subtract)
fn hostSub(args: []const f64) f64 {
    if (args.len != 2) return std.math.nan(f64);
    return args[0] - args[1];
}

/// Host function: * (multiply)
fn hostMul(args: []const f64) f64 {
    if (args.len != 2) return std.math.nan(f64);
    return args[0] * args[1];
}

/// Host function: / (divide)
fn hostDiv(args: []const f64) f64 {
    if (args.len != 2) return std.math.nan(f64);
    if (args[1] == 0.0) return std.math.nan(f64);
    return args[0] / args[1];
}

/// Register all builtin host functions with zwasm
/// This would be called before loading a WASM module
pub fn registerHostFunctions(context: *BridgeContext) !void {
    _ = context;

    // TODO: Register with zwasm engine
    // For MVP, builtins are compiled inline in WASM
    // Full implementation would use zwasm's host function API:
    //   engine.registerHostFunc("env", "builtin_add", hostAdd);
    //   engine.registerHostFunc("env", "builtin_sub", hostSub);
    //   etc.
}

/// Look up builtin by name
pub fn findBuiltin(name: []const u8) ?BuiltinDescriptor {
    for (BUILTINS) |builtin| {
        if (std.mem.eql(u8, builtin.name, name)) {
            return builtin;
        }
    }
    return null;
}

// Tests
const testing = std.testing;

test "findBuiltin: find +" {
    const builtin = findBuiltin("+");
    try testing.expect(builtin != null);
    try testing.expectEqualStrings("builtin_add", builtin.?.wasm_name);
    try testing.expectEqual(@as(u32, 2), builtin.?.arity);
}

test "hostAdd: 1 + 2 = 3" {
    const args = [_]f64{ 1.0, 2.0 };
    const result = hostAdd(&args);
    try testing.expectEqual(@as(f64, 3.0), result);
}

test "hostSub: 5 - 3 = 2" {
    const args = [_]f64{ 5.0, 3.0 };
    const result = hostSub(&args);
    try testing.expectEqual(@as(f64, 2.0), result);
}

test "hostMul: 4 * 3 = 12" {
    const args = [_]f64{ 4.0, 3.0 };
    const result = hostMul(&args);
    try testing.expectEqual(@as(f64, 12.0), result);
}

test "hostDiv: 10 / 2 = 5" {
    const args = [_]f64{ 10.0, 2.0 };
    const result = hostDiv(&args);
    try testing.expectEqual(@as(f64, 5.0), result);
}

test "generateImports: contains all builtins" {
    const imports = try generateImports(testing.allocator);
    defer testing.allocator.free(imports);

    try testing.expect(std.mem.indexOf(u8, imports, "builtin_add") != null);
    try testing.expect(std.mem.indexOf(u8, imports, "builtin_sub") != null);
    try testing.expect(std.mem.indexOf(u8, imports, "builtin_mul") != null);
    try testing.expect(std.mem.indexOf(u8, imports, "builtin_div") != null);
}
