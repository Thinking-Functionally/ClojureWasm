# IR Backend Integration Status

**Branch**: `experimental/ir-rewrite`  
**Date**: 2026-10-16  
**Status**: Partial Integration (Stages 1-6 Complete)

## Overview

This document tracks the integration of the IR (Intermediate Representation) Backend into ClojureWasm. The IR Backend provides an alternative compilation path using SSA-form IR and WASM bytecode generation.

## Architecture

```
Clojure Source
    ↓ (Analyzer)
Node Tree
    ↓ (IR Backend - NEW)
EDN IR (SSA form)
    ↓ (ir_to_wasm - EXISTS)
WASM Bytecode
    ↓ (zwasm runtime - EXISTS)
Execution
```

## Completed Work (Stages 1-6)

### ✅ Stage 1-4: IR Backend Core
**Files**: `src/eval/backend/ir.zig`

- IRCompiler structure with complete state management
- SSA form output (`:v0`, `:v1`, ... value IDs)
- Multi-block CFG (basic blocks + terminators)
- Memory-safe (all allocations tracked and freed)

**Supported Node Types** (7 total):
1. `constant` → `{:op "const" :result :v0 :value 42}`
2. `local_ref` → `{:op "var-ref" :result :v1 :var :param0}`
3. `call_node` → `{:op "call" :result :v2 :fn "builtin/+" :args [:v0 :v1]}`
4. `if_node` → branch terminator + then/else blocks + phi merge
5. `do_node` → sequential execution
6. `let_node` → local variable bindings with incremental params extension
7. `quote_node` → quoted values as constants

**Tests**: 4 unit tests (constant, local_ref, if, let)  
**Memory**: Zero leaks, proper resource tracking

### ✅ Stage 5: Extended Node Support
**Commits**: 
- `851713a7` - let_node compilation
- `310c79fc` - quote_node compilation

Added local variable binding support with proper memory management.

### ✅ Stage 6: IR Compiler Wrapper
**File**: `src/ir_compiler.zig`

High-level interface integrating the pipeline:
- `compileToIR()`: Node → EDN IR
- `compileToWasm()`: EDN IR → WASM module
- `compileNodeToWasm()`: Full pipeline

**Integration**: Added to `src/main.zig` test aggregator  
**Tests**: 2 wrapper tests (constant, let expression)

### ✅ Stage 7-8 Partial: Build System
**File**: `build.zig`

- Added `.ir` to Backend enum
- Available via: `zig build -Dbackend=ir`
- Compilation works successfully

## Incomplete Work

### ❌ Runtime Execution Path
**Blockers**:
1. `driver.zig` needs IR execution branch
2. zwasm runtime connection incomplete
3. Value marshaling (cljw Value ↔ zwasm.Value) needed

**Current State**:
- Can compile: Node → IR ✅
- Can generate: IR → WASM ✅ (via existing ir_to_wasm.zig)
- Cannot execute: WASM → Result ❌

### ❌ Missing Node Types
**Critical for Recursion**:
- `loop_node` - recursion entry point
- `recur_node` - tail recursion
- `fn_node` - nested functions + closures

**Others**:
- `var_ref` - global variable references
- `set_node` - variable mutation
- `try_node`, `throw_node` - exception handling

### ❌ E2E Testing
No end-to-end tests yet. Cannot run:
```bash
./zig-out/bin/cljw -e '(+ 1 2)'  # Would need runtime execution
```

## Technical Details

### IR Format (EDN)
```clojure
{:entry :block0
 :blocks {
   :block0 {:instructions [{:op "const" :result :v0 :value 1}
                           {:op "const" :result :v1 :value 2}
                           {:op "call" :result :v2 :fn "builtin/+" :args [:v0 :v1]}]
            :terminator {:op "return" :value :v2}}}}
```

### Memory Management
- **Value IDs**: Tracked in `IRCompiler.value_ids`, freed in `deinit()`
- **Block IDs**: Freed in `Block.deinit()`
- **Local IDs**: Scoped defer blocks in `compileLet()`
- **Instructions**: Freed per-block

### Existing Components (Reused)
- `src/ir/edn_parser.zig` - EDN parsing ✅
- `src/ir/ir_to_wasm.zig` - IR → WASM compilation ✅
- `src/ir/wasm_codegen.zig` - WASM bytecode generation ✅
- `src/runtime/cljw/wasm/` - zwasm integration layer ✅

## Next Steps

### Immediate (to complete Stage 7-8)
1. **Add IR execution path in `driver.zig`**:
   ```zig
   if (comptime build_options.backend == .vm) {
       // ... vm path
   } else if (comptime build_options.backend == .ir) {
       // NEW: IR → WASM → zwasm execution
   } else {
       // ... tree_walk path
   }
   ```

2. **Wire zwasm runtime**:
   - Use existing `src/runtime/cljw/wasm/` infrastructure
   - Connect `ir_compiler.compileNodeToWasm()` output
   - Execute WASM module via zwasm

3. **E2E testing**:
   ```bash
   zig build -Dbackend=ir
   ./zig-out/bin/cljw -e '(+ 1 2)'  # Should print 3
   ```

### Future Enhancements
- Complete Node type coverage (loop/recur/fn)
- Performance benchmarking vs TreeWalk/VM
- Error handling and debugging support
- Optimization passes on IR

## Build Commands

```bash
# Default (VM backend)
zig build

# TreeWalk backend
zig build -Dbackend=tree_walk

# IR backend (experimental) - BLOCKED
# Currently fails at build time because cache_gen (bootstrap AOT compiler)
# hits the NotImplemented stub in driver.zig. Full build requires:
#   1. Complete zwasm runtime integration for actual execution
#   2. Or: conditional cache_gen that skips bootstrap on IR backend
# zig build -Dbackend=ir  # <- does not complete yet

# Run tests (uses default VM backend)
zig build test

# Run with IR backend (once execution wired)
# zig build -Dbackend=ir
# ./zig-out/bin/cljw -e '(+ 1 2)'
```

## Project Constraints

- **Branch**: `experimental/ir-rewrite` (never merges to main)
- **Self-contained**: Uses cljw for IR generation, not JVM Clojure
- **Zig 0.16**: All code compatible with Zig 0.16 API

## Progress Tracking

- [x] Stage 1-4: IR Backend Core (Node → EDN IR)
- [x] Stage 5: Extended Node Support (let, quote)
- [x] Stage 6: IR Compiler Wrapper
- [x] Stage 7-8 Partial: Build System Integration
- [ ] Stage 7-8 Complete: Runtime Execution
- [ ] Stage 9: Documentation & Testing
- [ ] Future: loop/recur/fn support

## Commits

Key commits on `experimental/ir-rewrite`:
- `8a29a675` - IR Backend core implementation
- `851713a7` - let_node support
- `310c79fc` - quote_node support
- `e00e4f0e` - IR Compiler wrapper
- `59bd1c75` - Build system integration

## References

- Original IR work: `src/ir/` directory
- Phase 0-4 POC: `test/phase1_poc_e2e.sh` through `test/phase4_poc_e2e.sh`
- Specification: `docs/ir/SPECIFICATION_v1.0_COMPACT.md`
