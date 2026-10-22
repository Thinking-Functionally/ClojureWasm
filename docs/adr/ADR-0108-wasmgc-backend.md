# ADR-0108: WasmGC Backend Implementation

## Status

Accepted (2026-10-22)

## Context

ClojureWasm currently provides two backend execution strategies:

1. **TreeWalk** (`src/eval/backend/tree_walk.zig`) - Direct AST interpretation for debugging
2. **VM** (`src/eval/backend/vm/`) - Bytecode compilation for balanced performance

For deployment to web browsers and edge computing environments, we need a third backend that targets WebAssembly. Initial investigation considered Phase 1 (cross-compiling existing runtime to wasm32-wasi), but analysis revealed 4 fundamental blockers:

- **Threading architecture** (CRITICAL): Multi-threaded runtime vs single-threaded wasm32-wasi
- **Atomic operations** (CRITICAL): 64-bit atomics unsupported in wasm32
- **Platform dependencies** (HIGH): POSIX/libc APIs unavailable in WASI
- **Alignment guarantees** (MEDIUM): Different alignment assumptions

Phase 1 fix effort: 4-5 months with 30-40% success probability.

**Alternative**: Phase 4 (WasmGC backend) - build a native WebAssembly backend using the WasmGC proposal, targeting host-managed garbage collection.

## Decision

Implement **WasmGC backend** as the third backend option, positioned at Layer 1 (`src/eval/backend/wasmgc/`).

### Architecture Positioning

```
Clojure source
    ↓
Reader → Analyzer (generates AST with macro expansion)
    ↓
    ├─→ TreeWalk (tree_walk.zig) - direct AST interpretation
    ├─→ VM (vm/) - bytecode execution
    └─→ WasmGC (wasmgc/) - compile to WebAssembly ← NEW
```

**Shared infrastructure** (all backends):
- `src/runtime/` - Value type definitions, collection interfaces (reference only for WasmGC)
- `src/eval/reader.zig` - Clojure source → Forms
- `src/eval/analyzer/` - Forms → AST (with macro expansion)
- `src/eval/macro_dispatch.zig` - Macro expansion engine

**WasmGC-specific**:
- Consumes already-expanded AST from Analyzer (no macro handling in backend)
- Emits WebAssembly Text format (WAT)
- Uses WasmGC native types (struct/array/ref), not NaN-boxing
- Host-managed GC (no manual arena management)

### Value Representation

**Decision**: Tagged union representation (Option B from Phase 4 proposal)

**Rationale**:
- WasmGC struct types provide native type safety
- Host GC eliminates manual memory management complexity
- Type tag enables runtime type dispatch
- Simpler than NaN-boxing for WebAssembly's typed memory model

**Implementation**:

```wasm
;; Core Clojure Value type
(type $Value (struct
  (field $tag i32)        ;; TypeTag: 0=nil, 1=boolean, ..., 10=set
  (field $data (ref null $ValueData))
))

;; Type tag constants (see src/eval/backend/wasmgc/value_types.zig)
;; 0=nil, 1=boolean, 2=long, 3=double, 4=string, 5=symbol,
;; 6=keyword, 7=list, 8=vector, 9=map, 10=set
```

**Alternatives considered**:
- **NaN-boxing**: Rejected - wasm32 has typed memory, unaligned access penalties
- **Union types directly**: Rejected - WasmGC union proposal not yet baseline
- **External type table**: Rejected - indirection overhead, complexity

### Exception Handling

**Decision**: WasmGC native exception handling (no fallback)

**Rationale**:
- Browser support: 96.16% coverage (baseline December 2024)
  - Chrome 119+ (November 2023)
  - Firefox 131+ (October 2024)
  - Safari 18.2+ (December 2024)
- Maps cleanly to Clojure's throw/try/catch semantics
- No need for Result<T, E> wrapper types
- Simpler control flow than manual error propagation

**Trade-off**: Requires modern browser. Acceptable for community fork targeting contemporary deployment environments.

### Directory Structure

```
src/eval/backend/wasmgc/
├── compiler.zig       # AST → WAT compilation logic
├── codegen.zig        # WAT text generation utilities
├── value_types.zig    # Clojure type → WasmGC type mapping
├── runtime.zig        # WasmGC runtime support (core functions)
├── collections.zig    # Persistent data structures (Vector/Map/Set)
├── host_interop.zig   # JavaScript/Web platform integration
└── emit.zig           # WAT formatting/output
```

Entry point: `src/eval/backend/wasmgc.zig`

### Zone Dependency Compliance

WasmGC backend is **Layer 1** (`src/eval/backend/wasmgc/`).

**Allowed imports**:
```zig
// Layer 0 (runtime)
const Value = @import("../../runtime/Value.zig");
const Env = @import("../../runtime/Env.zig");
const Runtime = @import("../../runtime/Runtime.zig");

// Layer 1 (eval) - same level
const Analyzer = @import("../analyzer.zig");
const AST = @import("../ast.zig");
```

**Prohibited imports**:
- Layer 2 (`src/lang/`) - must not import
- Layer 3 (`src/app/`) - must not import

### Timeline

**4 months** (Month 1-4):

- **Month 1**: Value type design + basic literal compilation
- **Month 2**: Persistent data structures + basic evaluator
- **Month 3**: Functions/closures/recur
- **Month 4**: Host interop + testing

See: `docs/reference/Phase 4 詳細方案 — WasmGC Backend（第三後端）202610222131.md` for detailed breakdown.

## Consequences

### Positive

- **Shorter timeline**: 3-4 months vs 4-5 months for Phase 1 fixes
- **Clean architecture**: No adaptation of multi-threaded runtime
- **Modern target**: WasmGC optimization for managed languages
- **Host-managed GC**: Eliminates manual memory management (Phase 3 burden)
- **No Phase 1 blockers**: Avoids threading, atomics, platform dependency issues
- **Browser deployment**: Direct path to web/edge deployment

### Negative

- **Browser requirement**: Requires Chrome 119+, Firefox 131+, Safari 18.2+
- **New compilation path**: Separate toolchain (wasm-tools)
- **Dual value models**: WasmGC uses different representation than TreeWalk/VM
- **Initial learning curve**: Team must learn WasmGC spec and tooling

### Neutral

- **Third backend**: Increases codebase surface but follows established pattern
- **Tool dependencies**: Requires wasm-tools, wasmtime (standard Rust toolchain)
- **Testing strategy**: Needs cross-backend validation (already established for TreeWalk/VM)

## Validation

### Acceptance Criteria

**Month 1 (Current)**:
- ✅ Directory structure created at `src/eval/backend/wasmgc/`
- ✅ `value_types.zig` with TypeTag enum and WatTypeGen
- ✅ Entry point `wasmgc.zig` with Compiler stub
- ⏳ Basic literal compilation (nil, boolean, long, double, string) with tests

**Month 2**:
- Persistent data structures (Vector, Map, Set, List) in WasmGC
- Simple evaluator: `do`, `if`, `let`, function calls

**Month 3**:
- Functions (`fn*`) with closures
- `loop*` + `recur`
- Namespace + `def`

**Month 4**:
- JavaScript interop
- e2e test suite (30-50 core functions)
- Performance baseline (2-5x faster than TreeWalk)

### Correctness Testing

Cross-backend validation (per ADR-0107 two-tier gate):

```bash
# Differential testing: TreeWalk vs WasmGC
bash scripts/clj_diff_sweep.sh test/wasmgc_exprs.txt --backends tree_walk,wasmgc
```

Target: Zero divergence (except accepted divergences in `.dev/accepted_divergences.yaml`)

## References

- Phase 1 analysis: `docs/reference/phase1-blockers-analysis.md`
- Phase 4 detailed proposal: `docs/reference/Phase 4 詳細方案 — WasmGC Backend（第三後端）202610222131.md`
- WasmGC spec: https://github.com/WebAssembly/gc
- Browser compatibility: https://webassembly.org/roadmap/ (WasmGC baseline December 2024)
- ADR-0107: Two-tier gate cadence (smoke per commit, full e2e at phase boundaries)
- Zone dependency rules: `.claude/rules/zone_deps.md`

## Alternatives Considered

### Phase 1 (wasm32-wasi cross-compilation)

**Rejected**: 4 fundamental blockers, 4-5 months, 30-40% success probability.

### Phase 3 (Manual GC)

**Rejected**: Host-managed GC (WasmGC) eliminates manual mark-and-sweep complexity.

### Hybrid approach (Phase 1 + fallback to Phase 3)

**Rejected**: Maximum complexity, no clear advantage over direct WasmGC.

---

**Author**: Claude Sonnet 4.6  
**Date**: 2026-10-22  
**Phase**: Month 1 Week 1 (WasmGC spec research + value type design)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
