//! WasmGC backend — Layer 1 entry point.
//!
//! The WasmGC backend is ClojureWasm's **third backend option** alongside
//! TreeWalk and VM. It compiles Clojure AST (from Analyzer) into WebAssembly
//! Text format (WAT), targeting host-managed GC (WasmGC proposal).
//!
//! Architecture positioning:
//!   - Layer 1 (eval backend) — shares Reader + Analyzer with TreeWalk/VM
//!   - Consumes already-expanded AST (macro expansion done in Analyzer)
//!   - Emits WAT text format → wasm-tools converts to .wasm binary
//!   - Uses WasmGC native types (struct/array/ref), not NaN-boxing
//!
//! Directory structure:
//!   src/eval/backend/wasmgc/
//!   ├── compiler.zig       — AST → WAT compilation logic
//!   ├── codegen.zig        — WAT text generation utilities
//!   ├── value_types.zig    — Clojure type → WasmGC type mapping
//!   ├── runtime.zig        — WasmGC runtime support (core functions)
//!   ├── collections.zig    — Persistent data structures (Vector/Map/Set)
//!   ├── host_interop.zig   — JavaScript/Web platform integration
//!   └── emit.zig           — WAT formatting/output
//!
//! Current phase: Month 1 Week 1 — Value type design + simple literal compilation
//!
//! Spec reference: https://github.com/WebAssembly/gc
//! ADR: (to be written in docs/adr/)

const std = @import("std");
const Runtime = @import("Runtime");
const wasmgc_compiler = @import("wasmgc/compiler.zig");
const ASTNode = wasmgc_compiler.ASTNode;
const Value = wasmgc_compiler.Value;

/// Compiler instance for WasmGC backend.
pub const Compiler = struct {
    arena: std.mem.Allocator,
    rt: *Runtime,

    /// Initialize compiler for a compilation session.
    pub fn init(arena: std.mem.Allocator, rt: *Runtime) Compiler {
        return .{
            .arena = arena,
            .rt = rt,
        };
    }

    /// Compile AST node to WAT string.
    /// Spec: Takes already-expanded AST from Analyzer and emits WAT text.
    /// Phase: Wires Runtime's Node through converter to wasmgc/compiler.zig
    pub fn compile(self: *Compiler, node: anytype) ![]const u8 {
        // Convert Runtime Node to WasmGC ASTNode
        const ast_node = try self.convertNode(node);

        // Compile single expression as module
        const forms = [_]ASTNode{ast_node};
        return wasmgc_compiler.compileModule(self.arena, &forms);
    }

    /// Convert Runtime's Node to WasmGC's ASTNode representation.
    fn convertNode(self: *Compiler, node: anytype) error{OutOfMemory}!ASTNode {
        const NodeType = @TypeOf(node.*);

        // Handle anytype - could be *Node or *const Node
        if (@typeInfo(NodeType) != .Union) {
            @compileError("Expected Node union type");
        }

        return switch (node.*) {
            .constant => |c| ASTNode{
                .literal = .{ .value = try self.convertValue(c.value) }
            },

            .var_ref => |v| ASTNode{
                .var_ref = .{ .name = v.name }
            },

            .local_ref => |l| ASTNode{
                .var_ref = .{ .name = l.name }
            },

            .if_node => |i| blk: {
                const test_expr = try self.arena.create(ASTNode);
                test_expr.* = try self.convertNode(i.test_node);

                const then_expr = try self.arena.create(ASTNode);
                then_expr.* = try self.convertNode(i.then_node);

                const else_expr = if (i.else_node) |e| blk2: {
                    const else_ptr = try self.arena.create(ASTNode);
                    else_ptr.* = try self.convertNode(e);
                    break :blk2 else_ptr;
                } else null;

                break :blk ASTNode{
                    .if_expr = .{
                        .test_expr = test_expr,
                        .then_expr = then_expr,
                        .else_expr = else_expr,
                    }
                };
            },

            .let_node => |l| blk: {
                var bindings = std.ArrayList(wasmgc_compiler.Binding).init(self.arena);
                for (l.bindings) |binding_node| {
                    const init = try self.arena.create(ASTNode);
                    init.* = try self.convertNode(binding_node.binding_node.init_node);
                    try bindings.append(.{
                        .name = binding_node.binding_node.name,
                        .init = init,
                    });
                }

                var body = std.ArrayList(ASTNode).init(self.arena);
                for (l.body) |body_node| {
                    try body.append(try self.convertNode(body_node));
                }

                break :blk ASTNode{
                    .let_expr = .{
                        .bindings = try bindings.toOwnedSlice(),
                        .body = try body.toOwnedSlice(),
                    }
                };
            },

            .do_node => |d| blk: {
                var exprs = std.ArrayList(ASTNode).init(self.arena);
                for (d.body) |expr| {
                    try exprs.append(try self.convertNode(expr));
                }
                break :blk ASTNode{
                    .do_expr = .{ .exprs = try exprs.toOwnedSlice() }
                };
            },

            .fn_node => |f| blk: {
                // Convert parameter names
                var params = std.ArrayList([]const u8).init(self.arena);
                for (f.params) |param| {
                    try params.append(param);
                }

                // Convert body
                var body = std.ArrayList(ASTNode).init(self.arena);
                for (f.body) |node_ptr| {
                    try body.append(try self.convertNode(node_ptr));
                }

                break :blk ASTNode{
                    .fn_expr = .{
                        .params = try params.toOwnedSlice(),
                        .body = try body.toOwnedSlice(),
                    }
                };
            },

            .def_node => |d| blk: {
                const init = try self.arena.create(ASTNode);
                init.* = try self.convertNode(d.init_node);

                break :blk ASTNode{
                    .def = .{
                        .name = d.name,
                        .init = init,
                    }
                };
            },

            .call_node => |c| blk: {
                const func = try self.arena.create(ASTNode);
                func.* = try self.convertNode(c.fn_node);

                var args = std.ArrayList(ASTNode).init(self.arena);
                for (c.arg_nodes) |arg| {
                    try args.append(try self.convertNode(arg));
                }

                break :blk ASTNode{
                    .fn_call = .{
                        .func = func,
                        .args = try args.toOwnedSlice(),
                    }
                };
            },

            .loop_node => |l| blk: {
                var bindings = std.ArrayList(wasmgc_compiler.Binding).init(self.arena);
                for (l.bindings) |binding_node| {
                    const init = try self.arena.create(ASTNode);
                    init.* = try self.convertNode(binding_node.binding_node.init_node);
                    try bindings.append(.{
                        .name = binding_node.binding_node.name,
                        .init = init,
                    });
                }

                var body = std.ArrayList(ASTNode).init(self.arena);
                for (l.body) |body_node| {
                    try body.append(try self.convertNode(body_node));
                }

                break :blk ASTNode{
                    .loop_expr = .{
                        .bindings = try bindings.toOwnedSlice(),
                        .body = try body.toOwnedSlice(),
                    }
                };
            },

            .recur_node => |r| blk: {
                var args = std.ArrayList(ASTNode).init(self.arena);
                for (r.arg_nodes) |arg| {
                    try args.append(try self.convertNode(arg));
                }

                break :blk ASTNode{
                    .recur = .{ .args = try args.toOwnedSlice() }
                };
            },

            // Unsupported nodes - return error or stub
            else => {
                // For now, return a nil literal for unsupported node types
                return ASTNode{
                    .literal = .{ .value = .nil }
                };
            },
        };
    }

    /// Convert Runtime's Value to WasmGC's Value representation.
    fn convertValue(self: *Compiler, val: @import("Runtime").Value) !Value {
        _ = self;
        const v = @import("Runtime").value;

        return if (val.isNil())
            .nil
        else if (val.isTrue() or val.isFalse())
            Value{ .boolean = val.isTrue() }
        else if (v.isLong(val))
            Value{ .long = v.asLong(val) }
        else if (v.isDouble(val))
            Value{ .double = v.asDouble(val) }
        else if (v.isString(val))
            Value{ .string = v.asString(val).str }
        else
            .nil; // Default for unsupported types
    }
};
