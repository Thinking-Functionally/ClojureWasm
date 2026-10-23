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

    var fn_expr = compiler.ASTNode{ .fn_expr = .{
        .params = &params,
        .body = &body,
    } };

    const def_form = compiler.ASTNode{ .def = .{
        .name = "identity",
        .init = &fn_expr,
    } };

    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify function type in output
    try testing.expect(std.mem.indexOf(u8, wat, "(type $Function") != null);

    // Verify function definition
    try testing.expect(std.mem.indexOf(u8, wat, "(func $lambda") != null);

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

    var fn_expr = compiler.ASTNode{ .fn_expr = .{
        .params = &params,
        .body = &body,
    } };

    const def_form = compiler.ASTNode{ .def = .{
        .name = "const_fn",
        .init = &fn_expr,
    } };

    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify arity=2
    try testing.expect(std.mem.indexOf(u8, wat, "(i32.const 2)") != null);

    // Verify both parameters
    try testing.expect(std.mem.indexOf(u8, wat, "$arg0") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "$arg1") != null);
}

test "compile closure - captured variable" {
    // (let [y 42] (fn* [x] y))
    var y_val = compiler.ASTNode{ .literal = .{ .value = .{ .long = 42 } } };
    const binding = compiler.Binding{ .name = "y", .init = &y_val };
    const bindings = [_]compiler.Binding{binding};

    const param_x = "x";
    const params = [_][]const u8{param_x};
    const y_ref = compiler.ASTNode{ .var_ref = .{ .name = "y" } };
    const fn_body = [_]compiler.ASTNode{y_ref};

    var fn_expr = compiler.ASTNode{ .fn_expr = .{
        .params = &params,
        .body = &fn_body,
    } };

    var let_body = [_]compiler.ASTNode{fn_expr};
    var let_expr = compiler.ASTNode{ .let_expr = .{
        .bindings = &bindings,
        .body = &let_body,
    } };

    const def_form = compiler.ASTNode{ .def = .{
        .name = "make_closure",
        .init = &let_expr,
    } };

    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify captures array is built
    try testing.expect(std.mem.indexOf(u8, wat, "$captures") != null);

    // Verify closure struct includes captures
    try testing.expect(std.mem.indexOf(u8, wat, "(array (ref $Value))") != null);
}

// ============================================================================
// loop*/recur Tests
// ============================================================================

test "compile loop* - simple loop" {
    // (loop* [x 10] x)
    var x_val = compiler.ASTNode{ .literal = .{ .value = .{ .long = 10 } } };
    const binding = compiler.Binding{ .name = "x", .init = &x_val };
    const bindings = [_]compiler.Binding{binding};

    const x_ref = compiler.ASTNode{ .var_ref = .{ .name = "x" } };
    const body = [_]compiler.ASTNode{x_ref};

    var loop_expr = compiler.ASTNode{ .loop_expr = .{
        .bindings = &bindings,
        .body = &body,
    } };

    const def_form = compiler.ASTNode{ .def = .{
        .name = "simple_loop",
        .init = &loop_expr,
    } };

    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify loop block
    try testing.expect(std.mem.indexOf(u8, wat, "(block $loop") != null or
                       std.mem.indexOf(u8, wat, "(loop $loop") != null);
}

test "compile recur - tail recursion" {
    // (loop* [x 10] (if (> x 0) (recur (- x 1)) x))
    // Simplified: (loop* [x 10] (recur x))
    var x_val = compiler.ASTNode{ .literal = .{ .value = .{ .long = 10 } } };
    const binding = compiler.Binding{ .name = "x", .init = &x_val };
    const bindings = [_]compiler.Binding{binding};

    const recur_x = compiler.ASTNode{ .var_ref = .{ .name = "x" } };
    var recur_args = [_]compiler.ASTNode{recur_x};
    const recur_expr = compiler.ASTNode{ .recur = .{ .args = &recur_args } };

    const body = [_]compiler.ASTNode{recur_expr};

    var loop_expr = compiler.ASTNode{ .loop_expr = .{
        .bindings = &bindings,
        .body = &body,
    } };

    const def_form = compiler.ASTNode{ .def = .{
        .name = "tail_recur",
        .init = &loop_expr,
    } };

    var forms = [_]compiler.ASTNode{def_form};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify branch instruction for recur
    try testing.expect(std.mem.indexOf(u8, wat, "br $loop") != null or
                       std.mem.indexOf(u8, wat, "br_if") != null);
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
        .params = &params,
        .body = &body,
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

    var add_defn = compiler.ASTNode{ .defn = .{
        .name = "add",
        .params = &params,
        .body = &add_body,
    } };

    const y_ref = compiler.ASTNode{ .var_ref = .{ .name = "y" } };
    const mul_body = [_]compiler.ASTNode{y_ref};

    const mul_defn = compiler.ASTNode{ .defn = .{
        .name = "mul",
        .params = &params,
        .body = &mul_body,
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
    var def_x = compiler.ASTNode{ .def = .{
        .name = "x",
        .init = &x_val,
    } };

    var empty_params = [_][]const u8{};
    const x_ref = compiler.ASTNode{ .var_ref = .{ .name = "x" } };
    const body = [_]compiler.ASTNode{x_ref};

    var get_x_defn = compiler.ASTNode{ .defn = .{
        .name = "get_x",
        .params = &empty_params,
        .body = &body,
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
        .params = &params,
        .body = &body,
    } };

    var forms = [_]compiler.ASTNode{fib_defn};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify function exists
    try testing.expect(std.mem.indexOf(u8, wat, "(func $fib") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "(param $arg0") != null);
}

test "compile factorial stub with loop*" {
    // (defn fact [n] (loop* [acc 1 i n] acc))
    const param_n = "n";
    const params = [_][]const u8{param_n};

    var acc_val = compiler.ASTNode{ .literal = .{ .value = .{ .long = 1 } } };
    var acc_binding = compiler.Binding{ .name = "acc", .init = &acc_val };

    const n_ref = compiler.ASTNode{ .var_ref = .{ .name = "n" } };
    var i_binding = compiler.Binding{ .name = "i", .init = &n_ref };

    const bindings = [_]compiler.Binding{ acc_binding, i_binding };

    var acc_ref = compiler.ASTNode{ .var_ref = .{ .name = "acc" } };
    const loop_body = [_]compiler.ASTNode{acc_ref};

    var loop_expr = compiler.ASTNode{ .loop_expr = .{
        .bindings = &bindings,
        .body = &loop_body,
    } };

    const fn_body = [_]compiler.ASTNode{loop_expr};

    var fact_defn = compiler.ASTNode{ .defn = .{
        .name = "fact",
        .params = &params,
        .body = &fn_body,
    } };

    var forms = [_]compiler.ASTNode{fact_defn};
    const wat = try compiler.compileModule(testing.allocator, @constCast(forms[0..]));
    defer testing.allocator.free(wat);

    // Verify function with loop
    try testing.expect(std.mem.indexOf(u8, wat, "(func $fact") != null);
    try testing.expect(std.mem.indexOf(u8, wat, "loop") != null);
}
