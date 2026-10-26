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
const Runtime = @import("../../runtime/runtime.zig").Runtime;
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
    pub fn compile(self: *Compiler, node: anytype) ![]const u8 {
        // Convert Runtime's Node to WasmGC's ASTNode
        const ast_node = try self.convertNode(node);

        // Wrap in array for compileModule (expects []ASTNode)
        var forms = [_]ASTNode{ast_node};

        // Call the real compiler
        return try wasmgc_compiler.compileModule(self.arena, forms[0..]);
    }

    /// Convert Runtime's Node to WasmGC's ASTNode representation.
    fn convertNode(self: *Compiler, node: anytype) error{OutOfMemory}!ASTNode {
        const NodeType = @TypeOf(node);

        // Dereference if it's a pointer
        const actual_node = if (@typeInfo(NodeType) == .pointer) node.* else node;

        return switch (actual_node) {
            .constant => |c| ASTNode{
                .literal = .{ .value = try self.convertValue(c.value) }
            },

            .var_ref => |v| ASTNode{
                .var_ref = .{ .name = v.var_ptr.name }
            },

            .local_ref => |l| ASTNode{
                .var_ref = .{ .name = l.name }
            },

            .if_node => |i| blk: {
                const test_expr = try self.arena.create(ASTNode);
                test_expr.* = try self.convertNode(i.cond);

                const then_expr = try self.arena.create(ASTNode);
                then_expr.* = try self.convertNode(i.then_branch);

                const else_expr = if (i.else_branch) |e| blk2: {
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
                var bindings = std.ArrayList(wasmgc_compiler.Binding).empty;
                for (l.bindings) |binding_node| {
                    const init_ast = try self.arena.create(ASTNode);
                    init_ast.* = try self.convertNode(binding_node.value_expr);
                    try bindings.append(self.arena, .{
                        .name = binding_node.name,
                        .init = init_ast,
                    });
                }

                // body is a single *const Node, not array
                const body_ast = try self.arena.create(ASTNode);
                body_ast.* = try self.convertNode(l.body);
                var body_array = [_]ASTNode{body_ast.*};

                break :blk ASTNode{
                    .let_expr = .{
                        .bindings = try bindings.toOwnedSlice(self.arena),
                        .body = &body_array,
                    }
                };
            },

            .do_node => |d| blk: {
                var exprs = std.ArrayList(ASTNode).empty;
                for (d.forms) |expr| {
                    try exprs.append(self.arena, try self.convertNode(expr));
                }
                break :blk ASTNode{
                    .do_expr = .{ .exprs = try exprs.toOwnedSlice(self.arena) }
                };
            },

            .fn_node => |f| blk: {
                // Convert parameter names
                var params = std.ArrayList([]const u8).empty;
                for (f.methods[0].params) |param| {
                    try params.append(self.arena, param);
                }

                // body is a single *const Node
                const body_ast = try self.arena.create(ASTNode);
                body_ast.* = try self.convertNode(f.methods[0].body);
                var body_array = [_]ASTNode{body_ast.*};

                break :blk ASTNode{
                    .fn_expr = .{
                        .params = try params.toOwnedSlice(self.arena),
                        .body = &body_array,
                    }
                };
            },

            .def_node => |d| blk: {
                const init_ast = try self.arena.create(ASTNode);
                init_ast.* = try self.convertNode(d.value_expr);

                break :blk ASTNode{
                    .def = .{
                        .name = d.name,
                        .init = init_ast,
                    }
                };
            },

            .call_node => |c| blk: {
                const func = try self.arena.create(ASTNode);
                func.* = try self.convertNode(c.callee);

                var args = std.ArrayList(ASTNode).empty;
                for (c.args) |arg| {
                    try args.append(self.arena, try self.convertNode(arg));
                }

                break :blk ASTNode{
                    .fn_call = .{
                        .func = func,
                        .args = try args.toOwnedSlice(self.arena),
                    }
                };
            },

            .loop_node => |l| blk: {
                var bindings = std.ArrayList(wasmgc_compiler.Binding).empty;
                for (l.bindings) |binding_node| {
                    const init_ast = try self.arena.create(ASTNode);
                    init_ast.* = try self.convertNode(binding_node.value_expr);
                    try bindings.append(self.arena, .{
                        .name = binding_node.name,
                        .init = init_ast,
                    });
                }

                // body is a single *const Node
                const body_ast = try self.arena.create(ASTNode);
                body_ast.* = try self.convertNode(l.body);
                var body_array = [_]ASTNode{body_ast.*};

                break :blk ASTNode{
                    .loop_expr = .{
                        .bindings = try bindings.toOwnedSlice(self.arena),
                        .body = &body_array,
                    }
                };
            },

            .recur_node => |r| blk: {
                var args = std.ArrayList(ASTNode).empty;
                for (r.args) |arg| {
                    try args.append(self.arena, try self.convertNode(arg));
                }

                break :blk ASTNode{
                    .recur = .{ .args = try args.toOwnedSlice(self.arena) }
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
    fn convertValue(self: *Compiler, val: @import("../../runtime/value/value.zig").Value) !Value {
        _ = self;
        const v = @import("../../runtime/value/value.zig");
        const String = @import("../../runtime/collection/string.zig").String;

        return if (val == v.Value.nil_val)
            .nil
        else if (val == v.Value.true_val)
            Value{ .boolean = true }
        else if (val == v.Value.false_val)
            Value{ .boolean = false }
        else if (val.isInt())
            Value{ .long = @intCast(val.asInteger()) }
        else if (val.isFloat())
            Value{ .double = val.asFloat() }
        else if (val.isString()) blk: {
            const str_ptr = val.decodePtr(*const String);
            break :blk Value{ .string = str_ptr.bytes() };
        }
        else
            .nil; // Default for unsupported types
    }
};

/// Execute compiled WAT code and return the result (Option A).
/// Flow: WAT → wasm-tools → WASM binary → zwasm → execute → Value
/// Based on zwasm v2 embedding API (docs/examples/zig_host/hello.zig)
pub fn executeWat(rt: *Runtime, env: anytype, arena: std.mem.Allocator, wat_code: []const u8) !@import("../../runtime/value/value.zig").Value {
    _ = env;
    _ = rt;
    const ValueType = @import("../../runtime/value/value.zig").Value;
    const zwasm = @import("zwasm");

    // Step 1: Write WAT to temp file using standard Zig API
    const tmp_wat = "/tmp/cljw_wasmgc.wat";
    {
        const file = try std.Io.Dir.cwd().createFile(rt.io, tmp_wat, .{});
        defer file.close(rt.io);
        var buf: [4096]u8 = undefined;
        var fw = file.writer(rt.io, &buf);
        try fw.interface.writeAll(wat_code);
        try fw.flush();
    }

    // Step 2: Convert WAT → WASM with wasm-tools (shell command)
    const tmp_wasm = "/tmp/cljw_wasmgc.wasm";
    const result = try std.process.Child.run(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "wasm-tools", "parse", tmp_wat, "-o", tmp_wasm },
    });
    defer arena.free(result.stdout);
    defer arena.free(result.stderr);
    if (result.term.Exited != 0) return error.WasmConversionFailed;

    // Step 3: Read WASM binary
    const file = try std.Io.Dir.cwd().openFile(rt.io, tmp_wasm, .{});
    defer file.close(rt.io);
    const wasm_bytes = try file.readToEnd(rt.io, arena, 10 * 1024 * 1024);
    defer arena.free(wasm_bytes);

    // Step 4: Execute with zwasm (v2 API from docs/examples/zig_host/hello.zig)
    var eng = try zwasm.Engine.init(arena, .{});
    defer eng.deinit();
    var mod = try eng.compile(wasm_bytes);
    defer mod.deinit();
    var inst = try mod.instantiate(.{});
    defer inst.deinit();

    // Step 5: Call "main" function and convert result to Value
    const MainFn = fn () i64;
    const main_fn = inst.typedFunc(MainFn, "main");
    const result_i64 = try main_fn.call(.{});

    // Convert i64 → ClojureWasm Value
    return ValueType.makeInteger(@intCast(result_i64));
}

