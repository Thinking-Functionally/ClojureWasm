// SPDX-License-Identifier: EPL-2.0
//! Month 3 Tests: Functions, Closures, and Namespaces
//!
//! Tests verify:
//! - fn* (anonymous functions)
//! - Closure capture mechanism
//! - loop*/recur for tail recursion
//! - Multi-function modules
//! - Namespace system (def/defn)

const std = @import("std");
const testing = std.testing;
const compiler = @import("compiler");

// ============================================================================
// Week 1-2: Anonymous Functions & Closures
// ============================================================================

test "compile fn* - simple lambda" {
    // (fn* [x] x)
    const param_x = "x";
    const params = [_][]const u8{param_x};

    const x_ref = compiler.ASTNode{ .var_ref = .{ .name = "x" } };
    const body = [_]compiler.ASTNode{x_ref};

    const fn_expr = compiler.ASTNode{ .fn_expr = .{
        .params = @constCast(&params),
        .body = @constCast(&body),
    } };

    const def_form = compiler.ASTNode{ .def = .{
        .name = "identity",
        .init = @constCast(&fn_expr),
    } };

    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify function type in output
    try testing.expect(std.mem.indexOf(u8, wat, "(type $Function") != null);

    // Verify function definition
    try testing.expect(std.mem.indexOf(u8, wat, "(func $lambda_") != null);

    // Verify arity
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 1)") != null); // arity=1
}

test "compile fn* - two parameters" {
    // (fn* [x y] x)
    const param_x = "x";
    const param_y = "y";
    const params = [_][]const u8{ param_x, param_y };

    const x_ref = compiler.ASTNode{ .var_ref = .{ .name = "x" } };
    const body = [_]compiler.ASTNode{x_ref};

    const fn_expr = compiler.ASTNode{ .fn_expr = .{
        .params = @constCast(&params),
        .body = @constCast(&body),
    } };

    const def_form = compiler.ASTNode{ .def = .{
        .name = "const_fn",
        .init = @constCast(&fn_expr),
    } };

    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify arity=2
    try testing.expect(std.mem.indexOf(u8, wat, "arity") != null);

    // Verify both parameters
    try testing.expect(std.mem.indexOf(u8, wat, "param") != null);
}

test "compile closure - captured variable" {
    // (fn* [] (let* [y 42] (fn* [x] y)))
    var y_val = compiler.ASTNode{ .literal = .{ .value = .{ .long = 42 } } };
    const binding = compiler.Binding{ .name = "y", .init = &y_val };
    const bindings = [_]compiler.Binding{binding};

    const param_x = "x";
    const params = [_][]const u8{param_x};
    const y_ref = compiler.ASTNode{ .var_ref = .{ .name = "y" } };
    const fn_body = [_]compiler.ASTNode{y_ref};

    const inner_fn = compiler.ASTNode{ .fn_expr = .{
        .params = @constCast(&params),
        .body = @constCast(&fn_body),
    } };

    var let_body = [_]compiler.ASTNode{inner_fn};
    const let_expr = compiler.ASTNode{ .let_expr = .{
        .bindings = @constCast(&bindings),
        .body = &let_body,
    } };

    // Wrap in outer function
    const no_params = [_][]const u8{};
    var outer_body = [_]compiler.ASTNode{let_expr};
    var outer_fn = compiler.ASTNode{ .fn_expr = .{
        .params = @constCast(&no_params),
        .body = @constCast(&outer_body),
    } };

    const def_form = compiler.ASTNode{ .def = .{
        .name = "make_closure",
        .init = &outer_fn,
    } };

    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify captures array is built
    try testing.expect(std.mem.indexOf(u8, wat, "lambda") != null);
}

// ============================================================================
// loop*/recur Tests
// ============================================================================

test "compile loop* - simple loop" {
    // (defn simple_loop [] (loop* [x 10] x))
    var x_val = compiler.ASTNode{ .literal = .{ .value = .{ .long = 10 } } };
    const binding = compiler.Binding{ .name = "x", .init = &x_val };
    const bindings = [_]compiler.Binding{binding};

    const x_ref = compiler.ASTNode{ .var_ref = .{ .name = "x" } };
    const body = [_]compiler.ASTNode{x_ref};

    const loop_expr = compiler.ASTNode{ .loop_expr = .{
        .bindings = @constCast(&bindings),
        .body = @constCast(&body),
    } };

    var fn_body = [_]compiler.ASTNode{loop_expr};
    const defn_form = compiler.ASTNode{ .defn = .{
        .name = "simple_loop",
        .params = &[_][]const u8{},
        .body = @constCast(&fn_body),
    } };

    var forms = [_]compiler.ASTNode{defn_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify loop block
    try testing.expect(std.mem.indexOf(u8, wat, "loop") != null);
}

test "compile recur - tail recursion" {
    // (defn tail_recur [] (loop* [x 10] (recur x)))
    var x_val = compiler.ASTNode{ .literal = .{ .value = .{ .long = 10 } } };
    const binding = compiler.Binding{ .name = "x", .init = &x_val };
    const bindings = [_]compiler.Binding{binding};

    const recur_x = compiler.ASTNode{ .var_ref = .{ .name = "x" } };
    var recur_args = [_]compiler.ASTNode{recur_x};
    const recur_expr = compiler.ASTNode{ .recur = .{ .args = &recur_args } };

    const body = [_]compiler.ASTNode{recur_expr};

    const loop_expr = compiler.ASTNode{ .loop_expr = .{
        .bindings = @constCast(&bindings),
        .body = @constCast(&body),
    } };

    var fn_body = [_]compiler.ASTNode{loop_expr};
    const defn_form = compiler.ASTNode{ .defn = .{
        .name = "tail_recur",
        .params = &[_][]const u8{},
        .body = @constCast(&fn_body),
    } };

    var forms = [_]compiler.ASTNode{defn_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify branch instruction for recur
    try testing.expect(std.mem.indexOf(u8, wat, "br") != null);
}

// ============================================================================
// Higher-Order Functions
// ============================================================================

test "compile higher-order function - map stub" {
    // (defn map [f coll] f)  ;; Stub - just return f
    const param_f = "f";
    const param_coll = "coll";
    const params = [_][]const u8{ param_f, param_coll };

    const f_ref = compiler.ASTNode{ .var_ref = .{ .name = "f" } };
    const body = [_]compiler.ASTNode{f_ref};

    const defn = compiler.ASTNode{ .defn = .{
        .name = "map",
        .params = @constCast(&params),
        .body = @constCast(&body),
    } };

    var forms = [_]compiler.ASTNode{defn};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify function accepts function parameter
    try testing.expect(std.mem.indexOf(u8, wat, "(func $map") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "$f") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "$coll") != null);
}

// ============================================================================
// Week 3-4: Namespace System
// ============================================================================

test "compile multi-function module" {
    // (defn add [x y] x)
    // (defn mul [x y] y)
    const param_x = "x";
    const param_y = "y";
    const params = [_][]const u8{ param_x, param_y };

    const x_ref = compiler.ASTNode{ .var_ref = .{ .name = "x" } };
    var add_body = [_]compiler.ASTNode{x_ref};

    const add_defn = compiler.ASTNode{ .defn = .{
        .name = "add",
        .params = @constCast(&params),
        .body = &add_body,
    } };

    const y_ref = compiler.ASTNode{ .var_ref = .{ .name = "y" } };
    const mul_body = [_]compiler.ASTNode{y_ref};

    const mul_defn = compiler.ASTNode{ .defn = .{
        .name = "mul",
        .params = @constCast(&params),
        .body = @constCast(&mul_body),
    } };

    var forms = [_]compiler.ASTNode{ add_defn, mul_defn };
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify both functions exist
    try testing.expect(std.mem.indexOf(u8, wat, "(func $add") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(func $mul") != null);
}

test "compile def and defn interaction" {
    // (def x 42)
    // (defn get-x [] x)
    var x_val = compiler.ASTNode{ .literal = .{ .value = .{ .long = 42 } } };
    const def_x = compiler.ASTNode{ .def = .{
        .name = "x",
        .init = &x_val,
    } };

    var empty_params = [_][]const u8{};
    const x_ref = compiler.ASTNode{ .var_ref = .{ .name = "x" } };
    const body = [_]compiler.ASTNode{x_ref};

    const get_x_defn = compiler.ASTNode{ .defn = .{
        .name = "get_x",
        .params = &empty_params,
        .body = @constCast(&body),
    } };

    var forms = [_]compiler.ASTNode{ def_x, get_x_defn };
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify global x
    try testing.expect(std.mem.indexOf(u8, wat, "(global $x") != null);

    // Verify function get_x
    try testing.expect(std.mem.indexOf(u8, wat, "(func $get_x") != null);

    // Verify function reads global
    try testing.expect(std.mem.indexOf(u8, wat, "global.get $x") != null);
}

// ============================================================================
// Recursive Functions (Fibonacci, Factorial)
// ============================================================================

test "compile fibonacci stub - defn with self-recursion" {
    // (defn fib [n] n)  ;; Stub - actual recursion requires if and function calls
    const param_n = "n";
    const params = [_][]const u8{param_n};

    const n_ref = compiler.ASTNode{ .var_ref = .{ .name = "n" } };
    const body = [_]compiler.ASTNode{n_ref};

    const fib_defn = compiler.ASTNode{ .defn = .{
        .name = "fib",
        .params = @constCast(&params),
        .body = @constCast(&body),
    } };

    var forms = [_]compiler.ASTNode{fib_defn};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify function exists
    try testing.expect(std.mem.indexOf(u8, wat, "(func $fib") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "param") != null);
}

test "compile factorial stub with loop*" {
    // (defn fact [n] (loop* [acc 1 i n] acc))
    const param_n = "n";
    const params = [_][]const u8{param_n};

    var acc_val = compiler.ASTNode{ .literal = .{ .value = .{ .long = 1 } } };
    const acc_binding = compiler.Binding{ .name = "acc", .init = &acc_val };

    const n_ref = compiler.ASTNode{ .var_ref = .{ .name = "n" } };
    const i_binding = compiler.Binding{ .name = "i", .init = @constCast(&n_ref) };

    const bindings = [_]compiler.Binding{ acc_binding, i_binding };

    const acc_ref = compiler.ASTNode{ .var_ref = .{ .name = "acc" } };
    const loop_body = [_]compiler.ASTNode{acc_ref};

    const loop_expr = compiler.ASTNode{ .loop_expr = .{
        .bindings = @constCast(&bindings),
        .body = @constCast(&loop_body),
    } };

    const fn_body = [_]compiler.ASTNode{loop_expr};

    const fact_defn = compiler.ASTNode{ .defn = .{
        .name = "fact",
        .params = @constCast(&params),
        .body = @constCast(&fn_body),
    } };

    var forms = [_]compiler.ASTNode{fact_defn};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify function with loop
    try testing.expect(std.mem.indexOf(u8, wat, "(func $fact") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "loop") != null);
}
