# ClojureWasm Handover (2026-10-20)

**Current Status**: Phase 3 complete - AOT compilation + host imports framework

## Recent Work (Session 2026-10-20)

### 1. D-581: zwasm v2.5.0 Host Imports Discovery ✅

**Major breakthrough**: Discovered zwasm v2.5.0 already has ALL necessary APIs
for implementing D-579/D-580 host imports. Previous assumption that v2.5.0
lacked memory accessor APIs was INCORRECT.

**APIs confirmed present in v2.5.0**:
- `Linker.defineFunc()` - Register host functions with comptime signature
- `Caller.memory()` - Access guest linear memory from host functions
- `Memory.read/write/slice()` - Typed linear memory access
- `wasm_memory_data()` - Standard wasm.h C API

**Implementation**: `src/eval/backend/wasm/wasm_host_imports.zig`
- D-579 functions: `vector_from_slice`, `map_from_pairs`, `set_from_slice`
- D-580 functions: `cljw_get_2/3`, `cljw_nth_2/3`
- Registration: `registerHostImports(&linker)` helper

### 2. Two-Runtime Strategy

**Local zwasm execution** (this session):
- Native Zig host imports using Caller.memory()
- Preserves F-001 (zwasm v2.5.0 FINAL pin)
- Framework complete, needs Runtime integration for actual collection construction

**Cloudflare Workers** (complete from previous session):
- JS runtime implementation in `workers/cljw_runtime.js`
- Fully working, tested with `(+ 1 2)` example
- Handles NaN-boxing + JS-side heap tracking

## Current State

### Completed ✅
1. AOT compilation pipeline (bytecode → Wasm module)
2. Cloudflare Workers deployment + runtime
3. D-579/D-580 host import framework (both Zig + JS)
4. Control flow translation (jumps, branches)
5. Collection heap builder (inline approach for standalone modules)

### Next Steps
1. **Integrate Runtime context into host imports** - Pass Runtime* to access collection APIs
2. **Update wasm_executor.zig** - Setup Linker + register host imports before instantiation
3. **P99 test suite** - 99 Clojure problems for backend validation
4. **Differential testing** - Compare TreeWalk/VM/Wasm backends

## Key Files

**AOT Pipeline**:
- `src/eval/backend/wasm/wasm_module_builder.zig` - Bytecode → Wasm translation
- `src/eval/backend/wasm/wasm_executor.zig` - zwasm execution wrapper
- `src/eval/backend/wasm/wasm_host_imports.zig` - D-579/D-580 host functions

**Workers Deployment**:
- `workers/cljw_runtime.js` - JS host imports implementation
- `workers/worker.js` - Cloudflare Worker entry point
- `workers/README.md` - Complete deployment documentation (Cantonese)

**Project Structure**:
- `.dev/decisions/D-581_*` - Host imports discovery ADR
- `.dev/ROADMAP.md` - Overall project roadmap
- `CLAUDE.md` - Project instructions + constraints

## Known Issues

1. **Host import TODO markers** - Functions read memory correctly but return nil
   - Need Runtime* context to call collection construction APIs
   - Framework is correct, just needs final integration

2. **Build error fixed** - Added `VectorTooLarge` to BuildError set

## F-001 Status: PRESERVED ✅

zwasm v2.5.0 remains FINAL pin. No upgrade needed - all APIs present.
