const std = @import("std");
const testing = std.testing;
const compiler = @import("wasmgc").compiler;
const types = @import("wasmgc").types;

/// E2E test: Clojure → WAT → wasm-tools validate → wasmtime run
///
/// Test flow:
/// 1. Compile Clojure AST to WAT
/// 2. Write WAT to temp file
/// 3. Validate with `wasm-tools validate`
/// 4. Convert to binary with `wasm-tools parse`
/// 5. Execute with `wasmtime run` (when runtime complete)

const ASTNode = struct {
    pub const Literal = struct {
        value: union(enum) {
            nil,
            boolean: bool,
            long: i64,
            double: f64,
            string: []const u8,
        },
    };

    pub const IfExpr = struct {
        test_expr: *ASTNode,
        then_expr: *ASTNode,
        else_expr: ?*ASTNode,
    };

    pub const LetExpr = struct {
        bindings: []Binding,
        body: []ASTNode,

        pub const Binding = struct {
            name: []const u8,
            init: *ASTNode,
        };
    };

    pub const DoExpr = struct {
        exprs: []ASTNode,
    };

    pub const FnCall = struct {
        func: *ASTNode,
        args: []ASTNode,
    };

    pub const VarRef = struct {
        name: []const u8,
    };

    literal: Literal,
    if_expr: IfExpr,
    let_expr: LetExpr,
    do_expr: DoExpr,
    fn_call: FnCall,
    var_ref: VarRef,
};

/// Helper to run shell command and capture output
fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    return result;
}

/// Test: (if true 42 99) → WAT → validate
test "e2e: if expression compilation and validation" {
    const allocator = testing.allocator;

    // Build AST: (if true 42 99)
    var test_node = ASTNode{ .literal = .{ .value = .{ .boolean = true } } };
    var then_node = ASTNode{ .literal = .{ .value = .{ .long = 42 } } };
    var else_node = ASTNode{ .literal = .{ .value = .{ .long = 99 } } };

    const if_expr = ASTNode{
        .if_expr = .{
            .test_expr = &test_node,
            .then_expr = &then_node,
            .else_expr = &else_node,
        },
    };

    // Compile to WAT
    const forms = [_]ASTNode{if_expr};
    const wat = try compiler.compileModule(allocator, &forms);
    defer allocator.free(wat);

    // Write to temp file
    const tmp_wat = "/tmp/test_if.wat";
    const file = try std.fs.createFileAbsolute(tmp_wat, .{});
    defer file.close();
    try file.writeAll(wat);

    // Validate with wasm-tools
    const validate_result = try runCommand(allocator, &.{ "wasm-tools", "validate", tmp_wat });
    defer {
        allocator.free(validate_result.stdout);
        allocator.free(validate_result.stderr);
    }

    try testing.expectEqual(@as(u8, 0), validate_result.term.Exited);

    // Parse to binary
    const tmp_wasm = "/tmp/test_if.wasm";
    const parse_result = try runCommand(allocator, &.{ "wasm-tools", "parse", tmp_wat, "-o", tmp_wasm });
    defer {
        allocator.free(parse_result.stdout);
        allocator.free(parse_result.stderr);
    }

    try testing.expectEqual(@as(u8, 0), parse_result.term.Exited);

    // Cleanup
    try std.fs.deleteFileAbsolute(tmp_wat);
    try std.fs.deleteFileAbsolute(tmp_wasm);
}

// Basic let-expression e2e test
test "e2e: let expression compilation and validation" {
    const allocator = testing.allocator;

    // Build AST: (let [x 10] x)
    var init_node = ASTNode{ .literal = .{ .value = .{ .long = 10 } } };
    var body_node = ASTNode{ .var_ref = .{ .name = "x" } };

    const binding = ASTNode.LetExpr.Binding{
        .name = "x",
        .init = // <<CONTINUATION_MARKER_E2E>>init_node,
    };

    const let_expr = ASTNode{
        .let_expr = .{
            .bindings = @constCast(// <<CONTINUATION_MARKER_E2E>>[_]ASTNode.LetExpr.Binding{binding}),
            .body = @constCast(// <<CONTINUATION_MARKER_E2E>>[_]ASTNode{body_node}),
        },
    };

    // Compile to WAT
    const forms = [_]ASTNode{let_expr};
    const wat = try compiler.compileModule(allocator, // <<CONTINUATION_MARKER_E2E>>forms);
    defer allocator.free(wat);

    // Write and validate
    const tmp_wat = "/tmp/test_let.wat";
    const file = try std.fs.createFileAbsolute(tmp_wat, .{});
    defer file.close();
    try file.writeAll(wat);

    const validate_result = try runCommand(allocator, // <<CONTINUATION_MARKER_E2E>>.{ "wasm-tools", "validate", tmp_wat });
    defer {
        allocator.free(validate_result.stdout);
        allocator.free(validate_result.stderr);
    }

    try testing.expectEqual(@as(u8, 0), validate_result.term.Exited);

    // Cleanup
    try std.fs.deleteFileAbsolute(tmp_wat);
}

// Basic do-expression e2e test
test "e2e: do expression compilation and validation" {
    const allocator = testing.allocator;

    // Build AST: (do 1 2 3)
    const expr1 = ASTNode{ .literal = .{ .value = .{ .long = 1 } } };
    const expr2 = ASTNode{ .literal = .{ .value = .{ .long = 2 } } };
    const expr3 = ASTNode{ .literal = .{ .value = .{ .long = 3 } } };

    const do_expr = ASTNode{
        .do_expr = .{
            .exprs = @constCast(// <<CONTINUATION_MARKER_E2E>>[_]ASTNode{ expr1, expr2, expr3 }),
        },
    };

    // Compile to WAT
    const forms = [_]ASTNode{do_expr};
    const wat = try compiler.compileModule(allocator, // <<CONTINUATION_MARKER_E2E>>forms);
    defer allocator.free(wat);

    // Write and validate
    const tmp_wat = "/tmp/test_do.wat";
    const file = try std.fs.createFileAbsolute(tmp_wat, .{});
    defer file.close();
    try file.writeAll(wat);

    const validate_result = try runCommand(allocator, // <<CONTINUATION_MARKER_E2E>>.{ "wasm-tools", "validate", tmp_wat });
    defer {
        allocator.free(validate_result.stdout);
        allocator.free(validate_result.stderr);
    }

    try testing.expectEqual(@as(u8, 0), validate_result.term.Exited);

    // Cleanup
    try std.fs.deleteFileAbsolute(tmp_wat);
}
