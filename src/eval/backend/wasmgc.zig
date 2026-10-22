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
const Env = @import("Env");
const Value = @import("Value");
const AST = @import("AST");
const Node = AST.Node;

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
    /// Phase: Month 1 Week 3-4 (basic expressions only)
    pub fn compile(self: *Compiler, node: *const Node) ![]const u8 {
        _ = self;
        _ = node;
        return error.NotImplemented;
    }
};

/// Entry point: Compile Clojure source to .wasm module.
///
/// Usage:
///   cljw wasmgc -i core.clj -o core.wasm
///
/// Pipeline:
///   1. Reader parses source → Forms
///   2. Analyzer expands macros + analyzes → AST
///   3. WasmGC Compiler generates → WAT text
///   4. wasm-tools (external) converts WAT → .wasm binary
///
/// Spec: This function orchestrates steps 1-3; step 4 is external tooling.
pub fn compileToWasm(
    arena: std.mem.Allocator,
    rt: *Runtime,
    source: []const u8,
    output_path: []const u8,
) !void {
    _ = arena;
    _ = rt;
    _ = source;
    _ = output_path;
    return error.NotImplemented;
}
