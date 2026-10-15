# ClojureWasm IR (Intermediate Representation)

**Status**: 🚧 Experimental Design Phase  
**Version**: 0.1.0-draft  
**Branch**: `experimental/ir-rewrite`

## What is This?

This directory contains the design specification for ClojureWasm's Intermediate Representation (IR) — a stable layer between Clojure source code and WASM bytecode generation.

## Documents

| Document | Purpose | Status |
|----------|---------|--------|
| [SPECIFICATION.md](./SPECIFICATION.md) | Complete IR format specification | ✅ Draft complete |
| [DESIGN_RATIONALE.md](./DESIGN_RATIONALE.md) | Design decisions and trade-offs | ✅ Draft complete |
| [EXAMPLES.md](./EXAMPLES.md) | Clojure → IR examples | ✅ Draft complete |

## Quick Overview

### Current Architecture (Before IR)

```
Clojure Source → AST → Direct WASM Generation (Zig)
```

**Problem**: Tight coupling, hard to optimize, single backend only.

### Proposed Architecture (With IR)

```
Clojure Source → AST → IR (EDN) → Optimizations → WASM Generation
                 ↓                                  ↓
            (Clojure)                             (Zig)
```

**Benefits**: Separation of concerns, optimization layer, multiple backends, better testability.

## Key Design Decisions

1. **Format**: EDN (Extensible Data Notation)
   - Clojure-native, rich types, human-readable
   - Trade-off: Less universal than JSON, but better for Clojure ecosystem

2. **Structure**: SSA-inspired with basic blocks
   - Each value defined once
   - Explicit control flow
   - Standard compiler IR pattern

3. **Frontend/Backend Split**: 
   - **Frontend (Clojure)**: Parse, analyze, generate IR
   - **Backend (Zig)**: Read IR, optimize, generate WASM

4. **Explicit Control Flow**: Basic blocks with terminators
   - Clear for optimization
   - Maps well to WASM

## Example

### Clojure Source
```clojure
(defn add [x y]
  (+ x y))
```

### IR (EDN)
```edn
{:id :fn/user-add-1
 :name "add"
 :namespace "user"
 :arity {:fixed 2}
 :params [:param/x :param/y]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:id :block/entry
   :instructions [{:op :var-ref :result :val/1 :var :param/x}
                  {:op :var-ref :result :val/2 :var :param/y}
                  {:op :call :result :val/3 :fn :builtin/add :args [:val/1 :val/2]}]
   :terminator {:op :return :value :val/3}}}}
```

## Current Status

### ✅ Completed

- [x] IR format specification
- [x] Design rationale document
- [x] Comprehensive examples
- [x] EDN format choice justified
- [x] SSA-inspired structure defined

### 🚧 In Progress

- [ ] Proof-of-concept Clojure→IR compiler
- [ ] Proof-of-concept IR→WASM backend

### 📋 Planned (Phase 1)

- [ ] Simple frontend (Clojure)
  - [ ] Parse basic expressions
  - [ ] Generate IR for simple functions
  - [ ] Handle local bindings
  - [ ] Handle conditionals
- [ ] Simple backend (Zig)
  - [ ] Parse EDN IR
  - [ ] Validate IR structure
  - [ ] Generate WASM for basic operations
  - [ ] Test with examples
- [ ] Integration
  - [ ] End-to-end test: Clojure → IR → WASM
  - [ ] Compare with current compiler output

### 🔮 Future (Phase 2+)

- [ ] Full Clojure semantics
- [ ] Optimization passes
- [ ] Incremental compilation
- [ ] Multiple backends (JVM, native)
- [ ] Debugging tools (IR inspector, visualizer)

## Getting Started (When Ready)

### Prerequisites

- Clojure (for frontend)
- Zig 0.16.0 (for backend)
- EDN parser for Zig (to be integrated)

### Build IR from Clojure

```bash
# Not yet implemented - planned:
cljw compile --emit-ir source.clj -o output.ir.edn
```

### Compile IR to WASM

```bash
# Not yet implemented - planned:
cljw ir-compile output.ir.edn -o output.wasm
```

## Architecture Diagram

```
┌─────────────────┐
│  Clojure Code   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Clojure Parser  │  ← tools.analyzer or custom
│  & Analyzer     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  AST (Clojure)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  IR Generator   │  ← Clojure (new)
│   (Clojure)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   IR (EDN)      │  ◀─ The Boundary
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   IR Parser     │  ← Zig (new, needs EDN parser)
│     (Zig)       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  IR Validator   │  ← Zig (new)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Optimizations  │  ← Zig (optional, future)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ WASM Generator  │  ← Zig (adapt existing)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  WASM Binary    │
└─────────────────┘
```

## Contributing

This is an experimental design phase. Feedback welcome on:

1. **IR format**: Is the structure clear? Missing operations?
2. **EDN choice**: Right decision? Alternative suggestions?
3. **Examples**: Are they comprehensive? Missing use cases?
4. **Implementation strategy**: Better approach to Phase 1?

## References

### External

- [LLVM IR](https://llvm.org/docs/LangRef.html) - Inspiration for SSA form
- [Cranelift](https://github.com/bytecodealliance/wasmtime/tree/main/cranelift) - WASM-focused IR
- [ClojureScript Compiler](https://clojurescript.org/about/compiler-internals) - Clojure analysis
- [GraalVM Truffle](https://www.graalvm.org/latest/graalvm-as-a-platform/language-implementation-framework/) - AST interpreter framework

### Internal

- [BRANCHING_STRATEGY.md](../BRANCHING_STRATEGY.md) - How experimental branches work
- [PHASE_0_COMPLETE.md](../PHASE_0_COMPLETE.md) - v1.10.1-tf.2 release notes
- Main ClojureWasm docs in `/docs`

## Timeline

- **2026-10-15**: IR specification drafted
- **Next**: Implement proof-of-concept
- **Goal**: Validate design before full implementation

## Questions?

See [DESIGN_RATIONALE.md](./DESIGN_RATIONALE.md) for detailed explanations of design choices, or check the [Appendix: Open Questions](./DESIGN_RATIONALE.md#appendix-open-questions) section.

---

**Note**: This is experimental work on the `experimental/ir-rewrite` branch. The stable release (v1.10.1-tf.2) on the `stable` branch uses the current direct-compilation architecture.
