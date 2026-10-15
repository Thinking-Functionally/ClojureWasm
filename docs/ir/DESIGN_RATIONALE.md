# ClojureWasm IR Design Rationale

**Version**: 0.1.0-draft  
**Last Updated**: 2026-10-15

## Executive Summary

This document explains the design decisions behind the ClojureWasm IR (Intermediate Representation). The IR serves as a bridge between Clojure semantics and WASM code generation, enabling better optimization, multiple backends, and clearer separation of concerns.

## The Problem: Current Architecture

### Current State (Before IR)

```
Clojure Source → AST → Direct WASM Generation
```

**Challenges**:

1. **Tight Coupling**: Clojure semantics are tightly coupled with WASM generation
2. **Hard to Optimize**: No stable structure for optimization passes
3. **Single Backend**: Changing target (JVM, native) requires rewriting entire backend
4. **Testing Difficulty**: Hard to test compilation stages independently
5. **Zig Implementation**: Complex Clojure semantics in Zig are hard to maintain

### Proposed Architecture (With IR)

```
Clojure Source → AST → IR → Optimizations → WASM Generation
                 ↓                           ↓
            (Clojure)                      (Zig)
```

**Benefits**:

1. **Separation**: Frontend (Clojure analysis) and backend (code generation) are independent
2. **Optimization Layer**: Stable IR allows multiple optimization passes
3. **Multiple Backends**: Same IR can target WASM, JVM, native, etc.
4. **Testability**: Each stage can be tested independently
5. **Better Tools**: IR can be inspected, visualized, and debugged

## Key Design Decisions

### Decision 1: EDN vs JSON

**Choice**: EDN (Extensible Data Notation)

**Alternatives Considered**:
1. JSON - Universal, but limited types
2. Protocol Buffers - Efficient, but binary and complex
3. S-expressions - Lisp-native, but less structured

**Rationale**:

| Criterion | EDN | JSON | Protobuf | S-expr |
|-----------|-----|------|----------|--------|
| Clojure-native | ✅ | ❌ | ❌ | ⚠️ |
| Rich types | ✅ | ❌ | ✅ | ❌ |
| Human-readable | ✅ | ✅ | ❌ | ✅ |
| Metadata support | ✅ | ❌ | ❌ | ⚠️ |
| Tooling | ✅ | ✅ | ⚠️ | ⚠️ |
| Zig parser exists | ✅* | ✅ | ⚠️ | ❌ |

*EDN parsers exist for C/C++, can be wrapped in Zig

**Trade-offs**:
- ❌ Less universal than JSON
- ❌ Slightly more complex to parse
- ✅ Native Clojure experience
- ✅ Richer type system
- ✅ Better debugging

**Conclusion**: For a Clojure-to-WASM compiler, Clojure-native format wins.

### Decision 2: SSA Form

**Choice**: SSA-inspired IR (each value defined once)

**Alternatives Considered**:
1. Tree-based IR (like AST)
2. Stack-based IR (like JVM bytecode)
3. Full SSA with phi nodes

**Rationale**:

SSA (Static Single Assignment) properties:
- Each variable is assigned exactly once
- Makes dataflow analysis easier
- Enables aggressive optimizations

**Our Approach**: SSA-inspired, not pure SSA
- Use unique IDs for all values (`:val/NNN`)
- Include phi nodes for control flow merges
- But allow some flexibility for Clojure semantics

**Example**:

```clojure
;; Source
(let [x 1
      y 2]
  (+ x y))

;; SSA-style IR
{:op :const :result :val/1 :value 1}
{:op :const :result :val/2 :value 2}
{:op :call :result :val/3 :fn :builtin/add :args [:val/1 :val/2]}
{:op :return :value :val/3}
```

Each value (`:val/1`, `:val/2`, `:val/3`) is defined exactly once.

### Decision 3: Basic Block Structure

**Choice**: Explicit basic blocks with terminators

**Alternatives Considered**:
1. Flat instruction stream
2. Nested expression tree
3. Continuation-passing style

**Rationale**:

Basic blocks provide:
- Clear control flow structure
- Natural fit for optimizations (dead code elimination, constant folding)
- Easy mapping to WASM blocks
- Standard compiler IR pattern (LLVM, Cranelift use this)

**Structure**:
```edn
{:id :block/entry
 :instructions [...]
 :terminator {:op :return ...}}
```

Each block:
- Has a unique ID
- Contains a sequence of instructions
- Ends with exactly one terminator (return/branch/jump)

### Decision 4: Clojure Frontend

**Choice**: Implement IR generation in Clojure

**Alternatives Considered**:
1. Keep everything in Zig
2. Mixed approach (some in Clojure, some in Zig)

**Rationale**:

**Advantages of Clojure Frontend**:
- ✅ Clojure is better at manipulating Clojure code
- ✅ Access to full Clojure macro system
- ✅ Easier to maintain Clojure semantics
- ✅ Can use existing Clojure analysis tools
- ✅ EDN generation is trivial in Clojure

**Zig Backend Advantages**:
- ✅ Zig is better at WASM generation
- ✅ No GC overhead during code generation
- ✅ Can use zwasm library directly
- ✅ Better integration with existing runtime

**Architecture**:
```
┌──────────────┐
│ Clojure Code │
└──────┬───────┘
       │
┌──────▼──────────────┐
│ Clojure Compiler    │  ← Implemented in Clojure
│ (Parser + Analyzer) │
└──────┬──────────────┘
       │
┌──────▼──────┐
│  IR (EDN)   │  ← The boundary
└──────┬──────┘
       │
┌──────▼──────────────┐
│ Zig Code Generator  │  ← Implemented in Zig
│ (IR → WASM)         │
└──────┬──────────────┘
       │
┌──────▼──────┐
│ WASM Binary │
└─────────────┘
```

### Decision 5: Flat vs Nested Structure

**Choice**: Flat structure with references

**Example**:

❌ **Nested (Deep Tree)**:
```edn
{:op :call
 :fn {:op :var-ref :var "add"}
 :args [{:op :const :value 1}
        {:op :const :value 2}]}
```

✅ **Flat (Our Choice)**:
```edn
[{:op :const :result :val/1 :value 1}
 {:op :const :result :val/2 :value 2}
 {:op :call :result :val/3 :fn :builtin/add :args [:val/1 :val/2]}]
```

**Rationale**:
- Easier to traverse and analyze
- Natural for optimization passes
- Better matches SSA form
- Simpler serialization

### Decision 6: Explicit vs Implicit Control Flow

**Choice**: Explicit control flow with blocks and jumps

**Example**:

❌ **Implicit**:
```edn
{:op :if
 :condition {...}
 :then {...}
 :else {...}}
```

✅ **Explicit**:
```edn
{:op :branch
 :condition :val/3
 :true-target :block/then
 :false-target :block/else}
```

**Rationale**:
- Makes control flow analysis trivial
- Easy to add optimization passes
- Clear mapping to WASM control flow
- Standard in modern compiler IRs

## Architecture Boundaries

### Frontend Responsibilities (Clojure)

1. **Parsing**: Clojure code → AST
2. **Macro Expansion**: Expand all macros
3. **Analysis**: 
   - Symbol resolution
   - Lexical scoping
   - Type inference (optional)
4. **IR Generation**: AST → IR (EDN)
5. **Validation**: Check IR is well-formed

**Output**: Valid IR (EDN file or data structure)

### Backend Responsibilities (Zig)

1. **IR Loading**: Parse EDN → Internal representation
2. **Validation**: Verify IR is valid
3. **Optimization**: 
   - Constant folding
   - Dead code elimination
   - Inlining
4. **Code Generation**: IR → WASM
5. **Linking**: Combine modules, resolve references

**Output**: WASM binary

### The Boundary (IR)

The IR is the **contract** between frontend and backend:
- Frontend promises: valid, well-formed IR
- Backend promises: correct WASM for valid IR

**Stability**: Once v1.0, IR format is stable (semantic versioning).

## Optimization Opportunities

### Frontend Optimizations (Clojure)

- Macro expansion and constant folding
- Dead code elimination at AST level
- Inlining of simple functions
- Type propagation

### IR-Level Optimizations

- Constant propagation
- Common subexpression elimination
- Dead code elimination
- Tail call optimization

### Backend Optimizations (Zig)

- Register allocation
- Instruction selection
- Peephole optimization
- WASM-specific optimizations

## Incremental Compilation

The IR enables incremental compilation:

```
user.clj → user.ir.edn ───┐
                            ├→ Combined IR → WASM
clojure/core.clj → core.ir.edn ┘
```

**Benefits**:
- Compile changed files only
- Cache IR for unchanged code
- Faster development cycle
- Easier parallel compilation

## Debugging and Tooling

### IR Inspector

```bash
# View IR for a function
cljw compile --emit-ir user.clj
cat user.ir.edn | jq '.modules[0].functions[] | select(.name == "add")'
```

### IR Visualizer

```bash
# Generate control flow graph
cljw ir-viz user.ir.edn --output cfg.dot
dot -Tpng cfg.dot -o cfg.png
```

### IR Validator

```bash
# Validate IR is well-formed
cljw ir-validate user.ir.edn
```

## Migration Path

### Phase 1: Proof of Concept (Current)

- ✅ Design IR specification
- ⏳ Implement simple Clojure → IR compiler
- ⏳ Implement simple IR → WASM backend
- ⏳ Test with basic examples

### Phase 2: Parity

- Port existing functionality to IR-based architecture
- Maintain dual implementation (old + new)
- Compare outputs for equivalence

### Phase 3: Optimization

- Add optimization passes
- Benchmark performance
- Enable by default if faster

### Phase 4: Full Migration

- Remove old direct-compilation path
- IR becomes the only compilation path
- Focus on IR-level improvements

## Trade-offs and Limitations

### Added Complexity

**Cost**: Extra compilation stage (AST → IR → WASM)

**Benefit**: Better structure, easier to maintain long-term

### Performance Overhead

**Cost**: IR serialization/deserialization

**Mitigation**: 
- In-memory IR (skip serialization during compilation)
- Cache compiled IR
- Binary IR format (future optimization)

### Learning Curve

**Cost**: Developers need to understand IR

**Mitigation**:
- Comprehensive documentation
- Good error messages
- IR visualization tools

## Comparison with Other Approaches

### ClojureScript

ClojureScript compiles to JavaScript:
- No formal IR (direct AST → JS)
- Heavy reliance on Google Closure Compiler for optimization
- Good model for macro expansion and analysis

**Lesson**: Leverage existing Clojure analysis, but add IR layer.

### GraalVM Truffle

GraalVM uses Truffle framework:
- AST-based with specialization
- JIT compilation at runtime
- Very sophisticated but heavyweight

**Lesson**: We want simpler, AOT-focused approach.

### LLVM

LLVM has very sophisticated IR:
- SSA form with phi nodes
- Rich type system
- Extensive optimization passes

**Lesson**: Take SSA concepts, but keep it simpler for our needs.

### Cranelift

Cranelift (Rust → WASM compiler):
- Clear IR specification
- Designed for WASM from the start
- Good performance

**Lesson**: Clear IR spec and WASM-awareness are valuable.

## Future Directions

### Multiple Targets

With IR in place, we can target:
- ✅ WASM (primary)
- 🔮 JVM bytecode (for better JVM interop)
- 🔮 Native code (via LLVM)
- 🔮 JavaScript (via ClojureScript-like approach)

### Advanced Optimizations

- Profile-guided optimization
- Escape analysis for allocation elimination
- Advanced inlining heuristics
- SIMD vectorization

### Tooling Ecosystem

- IR-based debugger
- Performance profiler using IR annotations
- Static analysis tools
- Educational tools (visualize compilation)

## Conclusion

The IR layer is a significant architectural improvement that:

1. **Separates concerns** between Clojure semantics and code generation
2. **Enables optimization** through a stable intermediate form
3. **Supports multiple backends** with shared frontend
4. **Improves testability** of compilation stages
5. **Makes the compiler more maintainable** long-term

The EDN format choice aligns with Clojure's philosophy while providing rich types and metadata. The SSA-inspired structure enables standard compiler optimizations. The Clojure frontend / Zig backend split plays to each language's strengths.

While there is upfront cost in building this infrastructure, the long-term benefits for correctness, performance, and maintainability justify the investment.

## References

- [Engineering a Compiler (Cooper & Torczon)](https://www.elsevier.com/books/engineering-a-compiler/cooper/978-0-12-088478-0)
- [Modern Compiler Implementation (Appel)](https://www.cs.princeton.edu/~appel/modern/)
- [LLVM: A Compilation Framework for Lifelong Program Analysis](https://llvm.org/pubs/2004-01-30-CGO-LLVM.pdf)
- [Cranelift Code Generator](https://github.com/bytecodealliance/wasmtime/tree/main/cranelift)
- [ClojureScript: Lisp's Revenge (David Nolen)](https://www.youtube.com/watch?v=MTawgp3SKy8)

## Appendix: Open Questions

### Q1: How to handle macros?

**Answer**: Macros are expanded in the Clojure frontend before IR generation. The IR only sees the expanded form.

### Q2: What about ClojureScript interop?

**Answer**: Out of scope for v1. Future consideration for shared tooling.

### Q3: Can we reuse ClojureScript's analyzer?

**Answer**: Potentially yes. Worth investigating in Phase 1.

### Q4: Performance compared to direct compilation?

**Answer**: Unknown until benchmarking. Expect slight overhead initially, but better optimization potential long-term.

### Q5: How to handle dynamic features (eval, load)?

**Answer**: IR represents compile-time structure. Dynamic features require runtime compiler or interpretation. Future work.
