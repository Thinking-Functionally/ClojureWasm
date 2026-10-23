const std = @import("std");
const testing = std.testing;
const compiler = @import("compiler");
const types = @import("types");

// Use compiler's ASTNode types
const ASTNode = compiler.ASTNode;
const Binding = compiler.Binding;

/// Helper to run shell command and capture output
fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    return result;
}

// TODO: Re-enable once std.Io.Dir API is figured out for Zig 0.16
// These tests need to write temporary files to pass to wasm-tools validator

test "DISABLED e2e: if expression compilation and validation" {
    return error.SkipZigTest;
}

test "DISABLED e2e: let expression compilation and validation" {
    return error.SkipZigTest;
}

test "DISABLED e2e: do expression compilation and validation" {
    return error.SkipZigTest;
}
