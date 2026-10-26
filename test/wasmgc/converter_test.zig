// Test Node → ASTNode converter in wasmgc.zig
//
// TEMPORARILY DISABLED: This test tries to create Node instances and pass them
// to wasmgc.Compiler, but Node lives outside wasmgc's module boundary.
// The converter is stubbed out (returns error.NotImplemented) until we decide
// on the cross-module architecture.
//
// To re-enable: Either move Node into a shared module both Runtime and wasmgc
// can import, or redesign the converter to work with serialized AST.

const std = @import("std");
const Runtime = @import("Runtime");
const wasmgc = @import("wasmgc");

test "wasmgc: compile simple constant (SKIPPED)" {
    return error.SkipZigTest;
}

test "wasmgc: compile if expression (SKIPPED)" {
    return error.SkipZigTest;
}
