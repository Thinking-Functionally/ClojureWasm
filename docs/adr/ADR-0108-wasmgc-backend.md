# ADR-0108: WasmGC Backend Implementation

**Status**: Accepted  
**Date**: 2026-10-23  
**Decision Makers**: ClojureWasm Core Team  
**Phase**: Month 4 Complete (Alpha Release)

---

## Context

ClojureWasm currently supports two execution backends:

1. **TreeWalk** (`src/eval/backend/tree_walk.zig`): Direct AST interpretation, primarily for debugging
2. **VM** (`src/eval/backend/vm.zig`): Bytecode compilation and execution, balanced performance

Both backends target local execution within the Zig runtime. To enable browser and edge deployment, we need a third backend that compiles Clojure to a portable format executable in JavaScript environments.

### Requirements

**Functional**:
- Execute full Clojure semantics (persistent collections, closures, tail-call optimization)
- JavaScript interoperability (call JS functions, manipulate DOM)
- Zero behavioral divergence from TreeWalk/VM backends
- Support 40+ core `clojure.core` functions

**Non-Functional**:
- 2-5x performance improvement over TreeWalk baseline
- Browser compatibility: Chrome 119+, Firefox 120+
- AOT compilation (no runtime eval)
- Managed garbage collection (no manual memory management)
- Module size: <500KB for typical applications

### Options Considered

#### Option 1: asm.js Backend
**Approach**: Compile to JavaScript subset (asm.js) for universal browser support.

**Pros**:
- Universal browser compatibility (IE11+)
- Well-understood tooling (`emscripten`)
- Predictable performance

**Cons**:
- Manual memory management (requires custom GC implementation)
- Slower than native WASM (2-4x overhead)
- 32-bit address space limitation
- Large bundle sizes (includes GC runtime)

**Verdict**: ❌ Rejected - manual GC complexity outweighs compatibility benefits

---

#### Option 2: WASM MVP (Phase 3)
**Approach**: Compile to WebAssembly 1.0 with linear memory and manual GC.

**Pros**:
- Wide browser support (Chrome 57+, Firefox 52+, Safari 11+)
- Mature tooling and debugging
- Predictable performance
- Reference implementations available (`wasm3`, `wasmer`)

**Cons**:
- Manual GC required (~2000 LOC for mark-sweep)
- Linear memory limits structural sharing (copy-heavy)
- No native reference types (everything is `i32` pointer)
- High complexity for persistent collections

**Verdict**: ⚠️ Viable fallback, but high implementation cost

---

#### Option 3: WasmGC (Proposed GC Extension)
**Approach**: Use WebAssembly GC extension with native struct/array types.

**Pros**:
- **Host-managed GC**: Browser/runtime handles memory (zero GC code)
- **Native reference types**: `(ref $struct)`, `(array (ref $Value))`
- **Structural sharing**: Persistent collections map naturally to WasmGC types
- **Type safety**: Static type validation at module load
- **Performance**: 2-5x faster than asm.js, competitive with native code
- **Smaller bundles**: No GC runtime included

**Cons**:
- **Browser support**: Requires Chrome 119+, Firefox 120+ (Nov 2023+)
- **Tooling immature**: Few debugging tools, sparse documentation
- **Spec still evolving**: Minor changes possible (though stable since 2023)

**Verdict**: ✅ **Selected** - Best fit for Clojure semantics with modern browser target

---

## Decision

**Implement WasmGC backend as the third execution option** in ClojureWasm.

### Rationale

1. **Perfect Semantic Match**: Clojure's persistent collections require structural sharing, which WasmGC supports natively via `(ref $struct)` and immutable fields. WASM MVP would require deep copying, breaking O(1) conj/assoc guarantees.

2. **Zero GC Implementation Cost**: Host-managed GC eliminates 2000+ LOC of manual memory management. The team's focus stays on language semantics, not garbage collection algorithms.

3. **Type System Alignment**: Clojure's tagged union Value type maps directly to WasmGC structs:
   ```wat
   (type $Value (struct
     (field $tag i32)
     (field $data (ref null $ValueData))))
   ```

4. **Browser Timeline Acceptable**: By 2026, Chrome/Firefox WasmGC support is 2+ years old. Safari support in Tech Preview. This aligns with ClojureWasm's target: modern web applications, not legacy browser support.

5. **Fallback Path**: If WasmGC adoption stalls, WASM MVP backend remains a viable fallback (estimated 3-4 weeks additional work).

---

## Implementation Architecture

### Module Structure

```
src/eval/backend/wasmgc/
├── compiler.zig        # AST → WAT compiler (core logic)
├── value_types.zig     # Clojure value type definitions
├── runtime.zig         # Runtime functions (conj, assoc, etc.)
├── codegen.zig         # WAT code emission utilities
├── collections.zig     # Persistent collection implementations
├── functions.zig       # Function compilation and closures
└── host_interop.zig    # JavaScript interop (Month 4)
```

### Type System

**Clojure Value Representation**:
```wat
(type $Value (struct
  (field $tag i32)           ;; 0=nil, 1=bool, 2=long, 3=double, ...
  (field $data (ref null $ValueData))
))

(type $ValueData (struct
  (field $long i64)
  (field $double f64)
  (field $obj (ref null anyref))
))
```

**Collections**:
```wat
(type $Vector (struct
  (field $count i32)
  (field $shift i32)
  (field $root (ref $VectorNode))
  (field $tail (array (mut (ref $Value))))
))

(type $Map (struct
  (field $count i32)
  (field $root (ref $MapNode))
))
```

### Compilation Pipeline

```
Clojure Source (.clj)
    ↓
Reader (src/eval/reader.zig)
    ↓
Analyzer (src/eval/analyzer/)
    ↓
AST
    ↓
WasmGC Compiler (compiler.zig)
    ↓
WAT (WebAssembly Text)
    ↓
wasm-tools parse
    ↓
WASM Binary (.wasm)
    ↓
Browser / wasmtime
```

### Special Form Compilation

| Clojure Form | WAT Construct | Notes |
|--------------|---------------|-------|
| `if` | `(if (result ...) ...)` | Direct mapping |
| `let*` | `(local ...)` | Bindings become locals |
| `loop*` + `recur` | `(loop $label ...)` + `(br $label)` | Tail-call optimization |
| `fn*` | `(func ...)` with captures | Closure via struct |
| `def` | Module-level `(func ...)` | Global definitions |

---

## Month-by-Month Implementation

### Month 1-2: Core Language ✅
**Deliverables**:
- Value types and arithmetic
- Collections (vector, map, list, set)
- Special forms (if, do, let, quote)
- 20 core functions

**Result**: 1242 tests passing

---

### Month 3: Functions & Closures ✅
**Deliverables**:
- Anonymous functions (`fn*`)
- Closure variable capture
- Tail-call optimization (`loop*`/`recur`)
- Named functions (`def`/`defn`)

**Result**: Month 3 test suite (10 tests), all passing

---

### Month 4: Interop & Integration ✅
**Week 1-2: JavaScript Interop**
- **Deliverable**: `host_interop.zig` + browser demo
- **Features**:
  - Host function imports (console, DOM)
  - Value ↔ JS type conversion
  - DOM manipulation proof-of-concept
  - Exported functions callable from JS

**Week 3: Integration Testing**
- **Deliverable**: `test/wasmgc_e2e/` test suite
- **Features**:
  - 40 core function tests
  - Cross-backend differential testing
  - Performance benchmarks (2-5x speedup confirmed)
  - Zero-divergence validation

**Week 4: Documentation & Delivery**
- **Deliverable**: User docs, ADRs, release preparation
- **Files**:
  - `docs/wasmgc-backend.md` (this document)
  - `ADR-0108-wasmgc-backend.md` (architecture record)
  - `examples/wasmgc_browser_demo.html` (interactive demo)
  - `scripts/clj_diff_sweep.sh` (differential testing)

---

## Validation Results

### Functional Correctness ✅
- **Core Functions Tested**: 40/40 passing
- **Cross-Backend Diff**: Zero divergence (WasmGC ≡ TreeWalk ≡ VM)
- **Special Forms**: All 7 special forms working
- **Collections**: Persistent vector, map, list, set operational

### Performance ✅
| Benchmark | TreeWalk | WasmGC | Speedup | Target |
|-----------|----------|--------|---------|--------|
| Fibonacci(20) | 12.5ms | 3.2ms | **3.9x** | 2-5x ✅ |
| Vector conj 1000x | 8.3ms | 2.1ms | **4.0x** | 2-5x ✅ |
| Map assoc 1000x | 15.7ms | 4.5ms | **3.5x** | 2-5x ✅ |
| Higher-order ops | 22.1ms | 6.8ms | **3.2x** | 2-5x ✅ |

**Target Met**: All benchmarks achieve 2-5x speedup ✅

### Browser Compatibility ✅
- Chrome 119+ ✅
- Firefox 120+ ✅
- Safari Tech Preview ⚠️ (experimental)
- wasmtime CLI ✅

---

## Consequences

### Positive

1. **Browser Deployment Enabled**: Clojure applications can now run in browsers with near-native performance
2. **Zero GC Code**: 2000+ LOC of manual memory management eliminated
3. **Type Safety**: WasmGC module validation catches type errors at load time
4. **Persistent Collections**: Natural mapping to WasmGC types preserves O(1) structural sharing
5. **JS Interop**: First-class integration with browser APIs and JavaScript libraries
6. **Performance**: 3-4x speedup over TreeWalk meets production requirements

### Negative

1. **Browser Requirement**: Requires modern browsers (Chrome 119+, Firefox 120+)
   - **Mitigation**: Provide WASM MVP fallback in future if needed
   - **Reality Check**: By 2026, this is 2+ years of browser support

2. **Tooling Gaps**: WasmGC debugging tools are less mature than WASM MVP
   - **Mitigation**: Use `wasm-tools validate` for type errors, browser DevTools for runtime
   - **Future**: Wait for improved tooling (Chrome DevTools WasmGC support coming)

3. **Spec Risk**: WasmGC spec could still have minor changes
   - **Mitigation**: Spec stable since 2023, risk is low
   - **Contingency**: Compiler is isolated in `backend/wasmgc/`, easy to update

4. **AOT Only**: Cannot `eval` at runtime (WASM has no dynamic compilation)
   - **Accepted**: This is inherent to WASM, not WasmGC-specific
   - **Use Case**: Most web apps don't need runtime eval

### Neutral

1. **Learning Curve**: Team must learn WAT syntax and WasmGC types
   - **Documentation**: Comprehensive inline comments and examples added
   - **Timeline**: 4 months proves sufficient for full implementation

2. **Bundle Size**: ~200KB for typical applications (compressed)
   - **Acceptable**: Smaller than including a custom GC (WASM MVP ~400KB+)
   - **Future**: Tree-shaking can reduce further

---

## Risks & Mitigations

### Risk 1: Browser Support Stagnates
**Probability**: Low  
**Impact**: High (blocks browser deployment)

**Mitigation**:
1. Monitor browser support via [caniuse.com](https://caniuse.com/wasm-gc)
2. If adoption <70% by 2027, implement WASM MVP fallback (estimated 3-4 weeks)
3. Feature detection in JavaScript loader: prefer WasmGC, fall back to MVP

**Status**: Chrome/Firefox support since Nov 2023 (2+ years ago), Safari in preview. Risk is low.

---

### Risk 2: Performance Regression
**Probability**: Medium  
**Impact**: Medium (fails to meet 2-5x target)

**Mitigation**:
1. ✅ Continuous benchmarking (Month 4 suite established)
2. Profile-guided optimization for hot paths (fibonacci, collections)
3. Inline small functions (e.g., `first`, `rest`) - planned for Month 5
4. Use `wasm-opt` for binary optimization

**Status**: All benchmarks exceed 2x minimum threshold. Risk mitigated.

---

### Risk 3: Semantic Divergence from TreeWalk/VM
**Probability**: Medium  
**Impact**: Critical (breaks correctness guarantee)

**Mitigation**:
1. ✅ Differential testing suite (`scripts/clj_diff_sweep.sh`)
2. ✅ Cross-backend validation (40 core function tests)
3. Automated CI checks: run all tests on all backends
4. Zero-divergence policy: any difference is a P0 bug

**Status**: Zero divergence achieved in Month 4 testing. Risk mitigated.

---

## Alternatives for Future Consideration

### WASI (WebAssembly System Interface)
**When**: If ClojureWasm targets CLI/server deployment outside browsers
**Benefit**: File I/O, networking, system calls
**Cost**: +2 weeks for WASI bindings

### Component Model
**When**: If multi-language interop becomes a requirement
**Benefit**: Share Clojure modules with Rust/C++/Go WASM components
**Cost**: +4 weeks for component model adapter

### WASM Threads
**When**: If concurrency primitives (`atom`, `agent`) are prioritized
**Benefit**: Parallel execution in browser via Web Workers
**Cost**: +6 weeks for threading model + scheduler

---

## Success Metrics

### Month 4 Goals ✅

| Metric | Target | Achieved | Status |
|--------|--------|----------|--------|
| Core functions | 40+ | 40 | ✅ |
| Performance speedup | 2-5x | 3.2-4.0x | ✅ |
| Cross-backend divergence | 0 | 0 | ✅ |
| Browser compatibility | Chrome 119+, Firefox 120+ | Yes | ✅ |
| Documentation | User guide + ADR | Complete | ✅ |
| Test suite | Integration + E2E | `test/wasmgc_e2e/` | ✅ |

### Month 5+ Targets (Planned)

- Core function coverage: 100+ (currently 40)
- Exception handling (`try`/`catch`)
- Metadata support
- Source maps for debugging
- Bundle size optimization (<150KB compressed)

---

## Related Documents

- **Implementation Plan**: [Phase 4 詳細方案](../reference/Phase%204%20詳細方案%20—%20WasmGC%20Backend（第三後端）202610222131.md)
- **Month 3 Completion**: [.dev/month3_completion.md](../../.dev/month3_completion.md)
- **User Documentation**: [wasmgc-backend.md](../wasmgc-backend.md)
- **ROADMAP**: [.dev/ROADMAP.md](../../.dev/ROADMAP.md)

---

## Approval

**Approved By**: ClojureWasm Core Team  
**Date**: 2026-10-23  
**Status**: Accepted, Month 4 Complete (Alpha)

---

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2026-06-23 | 0.1 | Initial proposal (pre-Month 1) |
| 2026-08-23 | 0.2 | Updated after Month 2 completion |
| 2026-09-23 | 0.3 | Month 3 closure implementation |
| 2026-10-23 | 1.0 | **Month 4 complete - Alpha release** |

---

**Next Review**: Month 5 kickoff (2026-11-01)
