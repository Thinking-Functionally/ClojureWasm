// SPDX-License-Identifier: EPL-2.0
//! Unit tests for IR codegen

const std = @import("std");
const testing = std.testing;
const codegen = @import("codegen.zig");
const node_mod = @import("../eval/node.zig");

const FnNode = node_mod.FnNode;
const FnMethod = node_mod.FnMethod;
const CompileContext = codegen.CompileContext;

test "compileFnNode: simple top-level function (no closure)" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Construct FnNode: (fn [x] x)
    const param_names = &[_][]const u8{"x"};

    // Create dummy body node
    const dummy_body_node = node_mod.Node{ .constant = .{ .value = .nil_val } };

    const method = FnMethod{
        .arity = 1,
        .has_rest = false,
        .params = param_names,
        .body = &dummy_body_node,
    };

    const fn_node = FnNode{
        .methods = &[_]FnMethod{method},
        .variadic = null,
        .slot_base = 0, // Top-level, no closure
        .name = "identity",
        .defining_ns = "user",
    };

    var ctx = CompileContext.init(allocator);
    const functions = try codegen.compileFnNode(&ctx, fn_node);
    defer {
        for (functions) |*func| func.deinit(allocator);
        allocator.free(functions);
    }

    try testing.expectEqual(@as(usize, 1), functions.len);
    const func = functions[0];

    try testing.expectEqual(@as(usize, 0), func.captures.len); // No closure
    try testing.expectEqual(@as(usize, 1), func.params.len);
    try testing.expectEqualStrings("x", func.params[0]);
    try testing.expect(func.arity == .fixed);
    try testing.expectEqual(@as(u16, 1), func.arity.fixed);
}

test "compileFnNode: simple closure (let [x 1] (fn [] x))" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create dummy body node
    const dummy_body_node = node_mod.Node{ .constant = .{ .value = .nil_val } };

    // Construct FnNode: (fn [] x) where x is in slot 0
    const method = FnMethod{
        .arity = 0,
        .has_rest = false,
        .params = &[_][]const u8{},
        .body = &dummy_body_node,
    };

    const fn_node = FnNode{
        .methods = &[_]FnMethod{method},
        .variadic = null,
        .slot_base = 1, // Captures slot 0 (x)
        .name = null,
        .defining_ns = "user",
    };

    var ctx = CompileContext.init(allocator);
    const functions = try codegen.compileFnNode(&ctx, fn_node);
    defer {
        for (functions) |*func| func.deinit(allocator);
        allocator.free(functions);
    }

    try testing.expectEqual(@as(usize, 1), functions.len);
    const func = functions[0];

    try testing.expectEqual(@as(usize, 1), func.captures.len); // Captures slot 0
    try testing.expectEqual(@as(usize, 0), func.params.len); // No parameters
}

test "compileFnNode: multi-arity function" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create dummy body node
    const dummy_body_node = node_mod.Node{ .constant = .{ .value = .nil_val } };

    // Construct FnNode: (fn ([x] x) ([x y] (+ x y)))
    const param1 = &[_][]const u8{"x"};
    const param2 = &[_][]const u8{ "x", "y" };

    const method1 = FnMethod{
        .arity = 1,
        .has_rest = false,
        .params = param1,
        .body = &dummy_body_node,
    };

    const method2 = FnMethod{
        .arity = 2,
        .has_rest = false,
        .params = param2,
        .body = &dummy_body_node,
    };

    const fn_node = FnNode{
        .methods = &[_]FnMethod{ method1, method2 },
        .variadic = null,
        .slot_base = 0,
        .name = "add",
        .defining_ns = "user",
    };

    var ctx = CompileContext.init(allocator);
    const functions = try codegen.compileFnNode(&ctx, fn_node);
    defer {
        for (functions) |*func| func.deinit(allocator);
        allocator.free(functions);
    }

    try testing.expectEqual(@as(usize, 2), functions.len); // Two arities

    // Check first arity
    const func1 = functions[0];
    try testing.expectEqual(@as(usize, 1), func1.params.len);
    try testing.expectEqual(@as(u16, 1), func1.arity.fixed);

    // Check second arity
    const func2 = functions[1];
    try testing.expectEqual(@as(usize, 2), func2.params.len);
    try testing.expectEqual(@as(u16, 2), func2.arity.fixed);
}

test "compileFnNode: nested closure" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create dummy body node
    const dummy_body_node = node_mod.Node{ .constant = .{ .value = .nil_val } };

    // Construct FnNode: nested (fn [y] ...) with slot_base=1 (captures x)
    const param_names = &[_][]const u8{"y"};

    const method = FnMethod{
        .arity = 1,
        .has_rest = false,
        .params = param_names,
        .body = &dummy_body_node,
    };

    const fn_node = FnNode{
        .methods = &[_]FnMethod{method},
        .variadic = null,
        .slot_base = 1, // Captures slot 0 (x from outer)
        .name = null,
        .defining_ns = "user",
    };

    var ctx = CompileContext.init(allocator);
    const functions = try codegen.compileFnNode(&ctx, fn_node);
    defer {
        for (functions) |*func| func.deinit(allocator);
        allocator.free(functions);
    }

    try testing.expectEqual(@as(usize, 1), functions.len);
    const func = functions[0];

    // Captures 1 slot (x), has 1 param (y)
    try testing.expectEqual(@as(usize, 1), func.captures.len);
    try testing.expectEqual(@as(usize, 1), func.params.len);
    try testing.expectEqualStrings("y", func.params[0]);
}

// ============================================================================
// Control Flow Node Tests (loop/recur/try/throw)
// ============================================================================

test "compileLoopNode: simple loop with binding" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create body node
    const body_node = node_mod.Node{ .constant = .{ .value = .nil_val } };

    // Create initial value node
    const init_node = node_mod.Node{ .constant = .{ .value = .{ .int = 0 } } };

    // Create binding
    const binding = node_mod.LetNode.Binding{
        .name = "i",
        .index = 0,
        .value_expr = &init_node,
    };
    const bindings = &[_]node_mod.LetNode.Binding{binding};

    const loop_node = node_mod.LoopNode{
        .bindings = bindings,
        .body = &body_node,
    };

    var ctx = CompileContext.init(allocator);
    const result = try codegen.compileLoopNode(&ctx, loop_node);

    // Verify we got a result value ID
    try testing.expect(result == .val);
}

test "compileRecurNode: recur with arguments" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create argument nodes
    const arg1 = node_mod.Node{ .constant = .{ .value = .{ .int = 1 } } };
    const arg2 = node_mod.Node{ .constant = .{ .value = .{ .int = 2 } } };
    const args = &[_]node_mod.Node{ arg1, arg2 };

    const recur_node = node_mod.RecurNode{
        .args = args,
    };

    var ctx = CompileContext.init(allocator);
    const result = try codegen.compileRecurNode(&ctx, recur_node);

    // Verify we got a result value ID
    try testing.expect(result == .val);
}
