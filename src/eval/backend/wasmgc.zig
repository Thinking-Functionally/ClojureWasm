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
    /// Phase: Incremental TDD - implementing features one by one
    pub fn compile(self: *Compiler, node: anytype) ![]const u8 {
        _ = self;
        _ = node;
        return error.NotImplemented;
    }
};
