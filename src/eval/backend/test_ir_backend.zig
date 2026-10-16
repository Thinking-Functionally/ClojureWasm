// SPDX-License-Identifier: EPL-2.0
//! Test IR Backend execution through driver.zig
//!
//! These tests verify that the IR backend can compile and execute
//! simple expressions via the zwasm runtime.

const std = @import("std");
const testing = std.testing;
const node_mod = @import("../node.zig");
const Node = node_mod.Node;
const Value = @import("../../runtime/value/value.zig").Value;
const driver = @import("../driver.zig");
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Env = @import("../../runtime/env.zig").Env;
const build_options = @import("build_options");

test "IR backend: compile simple constant" {
    // This test only runs if backend is IR
    if (comptime build_options.backend != .ir) {
        return error.SkipZigTest;
    }

    var rt = try Runtime.init(testing.allocator);
    defer rt.deinit();

    var env = try Env.init(&rt);
    defer env.deinit();

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Create a simple FnNode that returns constant 42.0
    const body = Node{ .constant = .{ .value = Value.initFloat(42.0) } };
    const fn_node = Node{
        .fn_node = .{
            .methods = &[_]node_mod.FnMethod{.{
                .arity = 0,
                .params = &[_][]const u8{},
                .body = &body,
            }},
        },
    };

    var locals: [driver.MAX_LOCALS]Value = [_]Value{.nil_val} ** driver.MAX_LOCALS;

    // This will compile Node → IR → WASM → execute
    const result = driver.evalForm(&rt, &env, &locals, arena, &fn_node) catch |err| {
        if (err == error.NotImplemented) {
            // IR backend without -Dwasm flag
            return error.SkipZigTest;
        }
        return err;
    };

    // Verify result is 42.0
    try testing.expectEqual(@as(f64, 42.0), result.asFloat());
}

test "IR backend: compile simple arithmetic" {
    // This test only runs if backend is IR and -Dwasm is enabled
    if (comptime build_options.backend != .ir) {
        return error.SkipZigTest;
    }
    if (comptime !@hasDecl(build_options, "wasm")) {
        return error.SkipZigTest;
    }

    var rt = try Runtime.init(testing.allocator);
    defer rt.deinit();

    var env = try Env.init(&rt);
    defer env.deinit();

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Create FnNode: (+ 1.0 2.0)
    const arg1 = Node{ .constant = .{ .value = Value.initFloat(1.0) } };
    const arg2 = Node{ .constant = .{ .value = Value.initFloat(2.0) } };
    const args = [_]*const Node{ &arg1, &arg2 };

    const call = Node{
        .call_node = .{
            .fn_expr = &Node{ .constant = .{ .value = Value.nil_val } }, // placeholder
            .args = &args,
        },
    };

    const fn_node = Node{
        .fn_node = .{
            .methods = &[_]node_mod.FnMethod{.{
                .arity = 0,
                .params = &[_][]const u8{},
                .body = &call,
            }},
        },
    };

    var locals: [driver.MAX_LOCALS]Value = [_]Value{.nil_val} ** driver.MAX_LOCALS;

    const result = try driver.evalForm(&rt, &env, &locals, arena, &fn_node);

    // Verify result is 3.0
    try testing.expectEqual(@as(f64, 3.0), result.asFloat());
}
