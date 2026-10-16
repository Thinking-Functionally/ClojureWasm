// SPDX-License-Identifier: EPL-2.0
//! Node wrapping utilities for IR Backend
//!
//! Wraps non-FnNode expressions in an implicit FnNode so they can be
//! compiled and executed via the IR → WASM → zwasm pipeline.

const std = @import("std");
const node_mod = @import("../node.zig");
const Node = node_mod.Node;

/// Wrap a non-FnNode in an implicit FnNode with 0 arity.
///
/// This allows top-level expressions like:
///   42
///   (+ 1 2)
///   (let [x 5] x)
///
/// to be compiled as if they were:
///   (fn [] 42)
///   (fn [] (+ 1 2))
///   (fn [] (let [x 5] x))
///
/// The wrapper allocates a FnNode on the arena; caller must not free.
pub fn wrapInFn(arena: std.mem.Allocator, node: *const Node) !Node {
    // If already a FnNode, return as-is
    if (node.* == .fn_node) {
        return node.*;
    }

    // Allocate FnMethod on arena
    const method = try arena.create(node_mod.FnMethod);
    method.* = .{
        .arity = 0,
        .params = &[_][]const u8{},
        .body = node,
    };

    // Allocate method slice on arena
    const methods = try arena.alloc(node_mod.FnMethod, 1);
    methods[0] = method.*;

    return Node{
        .fn_node = .{
            .methods = methods,
        },
    };
}

// Tests
const testing = std.testing;
const Value = @import("../../runtime/value/value.zig").Value;

test "wrapInFn: constant node" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const constant = Node{ .constant = .{ .value = Value.initFloat(42.0) } };
    const wrapped = try wrapInFn(arena, &constant);

    // Should be a FnNode
    try testing.expect(wrapped == .fn_node);
    try testing.expectEqual(@as(usize, 1), wrapped.fn_node.methods.len);
    try testing.expectEqual(@as(u32, 0), wrapped.fn_node.methods[0].arity);
    try testing.expectEqual(@as(usize, 0), wrapped.fn_node.methods[0].params.len);

    // Body should be the original constant
    try testing.expect(wrapped.fn_node.methods[0].body.* == .constant);
}

test "wrapInFn: already FnNode returns as-is" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const body = Node{ .constant = .{ .value = Value.initFloat(42.0) } };
    const original_fn = Node{
        .fn_node = .{
            .methods = &[_]node_mod.FnMethod{.{
                .arity = 0,
                .params = &[_][]const u8{},
                .body = &body,
            }},
        },
    };

    const wrapped = try wrapInFn(arena, &original_fn);

    // Should be unchanged
    try testing.expect(wrapped == .fn_node);
    try testing.expectEqual(@as(usize, 1), wrapped.fn_node.methods.len);
}
