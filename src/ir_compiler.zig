// SPDX-License-Identifier: EPL-2.0
//! IR Compiler Wrapper - integrates IR Backend with ir_to_wasm and zwasm runtime
//!
//! This module provides the high-level interface for compiling Clojure code
//! through the IR pipeline:
//!   1. Analyzer Node tree → EDN IR (via IR Backend)
//!   2. EDN IR → WASM bytecode (via ir_to_wasm)
//!   3. WASM execution (via zwasm runtime)

const std = @import("std");
const ir_backend = @import("eval/backend/ir.zig");
const ir_to_wasm = @import("ir/ir_to_wasm.zig");
const node_mod = @import("eval/node.zig");

pub const CompileError = error{
    AnalysisFailed,
    IRCompilationFailed,
    WasmCompilationFailed,
    ExecutionFailed,
} || ir_backend.CompileError || ir_to_wasm.CompileError;

/// High-level IR compiler interface
pub const IRCompiler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) IRCompiler {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *IRCompiler) void {
        _ = self;
        // No resources to clean up at this level
    }

    /// Compile a function Node to IR EDN string
    pub fn compileToIR(self: *IRCompiler, fn_node: node_mod.FnNode) ![]const u8 {
        return ir_backend.compileFunctionToIR(self.allocator, fn_node);
    }

    /// Compile IR EDN string to WASM module
    pub fn compileToWasm(self: *IRCompiler, ir_edn: []const u8) !ir_to_wasm.wasm.WasmModule {
        return try ir_to_wasm.compile(self.allocator, ir_edn);
    }

    /// Full pipeline: Node → IR → WASM
    pub fn compileNodeToWasm(self: *IRCompiler, fn_node: node_mod.FnNode) !ir_to_wasm.wasm.WasmModule {
        // Step 1: Node → IR
        const ir_edn = try self.compileToIR(fn_node);
        defer self.allocator.free(ir_edn);

        // Step 2: IR → WASM
        return try self.compileToWasm(ir_edn);
    }
};

// Tests
const testing = std.testing;
const Value = @import("runtime/value/value.zig").Value;
const Node = node_mod.Node;

test "IRCompiler: compile simple constant" {
    var compiler = IRCompiler.init(testing.allocator);
    defer compiler.deinit();

    const body = Node{ .constant = .{ .value = Value.initFloat(42) } };
    const fn_node = node_mod.FnNode{
        .methods = &[_]node_mod.FnMethod{.{
            .arity = 0,
            .params = &[_][]const u8{},
            .body = &body,
        }},
    };

    const ir = try compiler.compileToIR(fn_node);
    defer testing.allocator.free(ir);

    try testing.expect(std.mem.indexOf(u8, ir, "42") != null);
    try testing.expect(std.mem.indexOf(u8, ir, ":op") != null);
}

test "IRCompiler: compile let expression" {
    var compiler = IRCompiler.init(testing.allocator);
    defer compiler.deinit();

    const binding_val = Node{ .constant = .{ .value = Value.initFloat(42) } };
    const body = Node{ .local_ref = .{ .name = "x", .index = 0 } };

    const bindings = [_]node_mod.LetNode.Binding{.{
        .name = "x",
        .index = 0,
        .value_expr = &binding_val,
    }};

    const let_node = Node{ .let_node = .{
        .bindings = &bindings,
        .body = &body,
    } };

    const fn_node = node_mod.FnNode{
        .methods = &[_]node_mod.FnMethod{.{
            .arity = 0,
            .params = &[_][]const u8{},
            .body = &let_node,
        }},
    };

    const ir = try compiler.compileToIR(fn_node);
    defer testing.allocator.free(ir);

    try testing.expect(std.mem.indexOf(u8, ir, "\"bind\"") != null);
    try testing.expect(std.mem.indexOf(u8, ir, ":local0") != null);
}
