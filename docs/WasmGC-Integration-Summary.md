# WasmGC Backend Integration - Executive Summary

**Date**: 2026-10-26  
**Status**: Month 5 Week 1 - Planning Phase  
**Question**: Can WasmGC backend run the main 1,242-test suite?

---

## TL;DR

**Short Answer**: **No, but it can be done.**

The WasmGC backend is **feature-complete** (6,069 LOC, Month 4 Alpha) but **architecturally isolated**. It generates WAT text but cannot execute it, so it cannot run the main test suite that TreeWalk and VM backends pass.

**To fix this**: Embed a WebAssembly runtime (wasmtime) to execute compiled WAT during tests. Estimated effort: **10 weeks**.

---

## Current State Analysis

### What WasmGC Backend Can Do ✅

1. **Compile Clojure → WAT**
   ```
   Clojure code → Reader → Analyzer → AST → WasmGC Compiler → WAT text
   ```

2. **Generate correct WAT for 40+ functions**
   - Primitives (nil, bool, int, double, string)
   - Collections (vector, map, set)
   - Control flow (if, do, let, loop/recur)
   - Functions and closures
   - JavaScript interop

3. **Manual browser testing works**
   ```bash
   cljw --emit-wat app.clj > app.wat
   wasm-tools parse app.wat -o app.wasm
   # Load in browser → verified working
   ```

### What WasmGC Backend Cannot Do ❌

1. **Cannot execute compiled WASM**
   - No embedded WebAssembly runtime
   - No way to call `executeWat(wat_string) → Value`

2. **Cannot run automated tests**
   - Main test suite uses `evalForm(ast) → Value`
   - WasmGC path is incomplete:
     ```zig
     pub fn evalForm(rt: *Runtime, ast: *Node) !Value {
         return switch (build_options.backend) {
             .tree_walk => TreeWalk.eval(rt, ast),     // ✅ Returns Value
             .vm => VM.eval(rt, ast),                   // ✅ Returns Value  
             .wasmgc => WasmGC.compile(rt, ast),       // ❌ Returns []const u8 (WAT text)
         };
     }
     ```

3. **Cannot prove correctness**
   - No differential testing vs TreeWalk/VM
   - Manual testing only
   - High risk of silent bugs

---

## The Architecture Gap

### How TreeWalk/VM Work

```
Test Suite → evalForm() → TreeWalk.eval() → Value
                       └→ VM.eval()       → Value
                                              ↓
                                         Assert expected
```

**Both backends execute code inline and return results.**

### How WasmGC Currently Works

```
Test Suite → evalForm() → WasmGC.compile() → WAT text string
                                               ↓
                                          (no execution)
                                               ↓
                                          ??? (return what?)
```

**WasmGC generates code but doesn't run it.**

### What's Missing

```
WasmGC.compile() → WAT text → ??? → Value
                               ↑
                    THIS PART MISSING
                    (WebAssembly runtime)
```

---

## Proposed Solution: Embed Wasmtime

### Architecture

```
Test Suite → evalForm() → WasmGC.compile() → WAT text
                              ↓
                         Wasmtime Runtime (NEW)
                              ↓
                         Execute WASM → WASM result
                              ↓
                         Value Marshalling (NEW)
                              ↓
                         ClojureWasm Value
                              ↓
                         Assert expected ✅
```

### Key Components

1. **Wasmtime C API Integration**
   - Add `wasmtime-c-api` dependency to build.zig
   - Create `executor.zig` wrapper
   - Compile WAT → WASM binary → Execute → Result

2. **Value Marshalling Layer**
   - Convert WASM results → ClojureWasm Values
   - Convert ClojureWasm Values → WASM inputs
   - Handle all types (primitives, collections, functions)

3. **Host Function Imports**
   - Export 40+ Clojure runtime functions to WASM
   - Implement `clojure.core/conj`, `assoc`, `get`, etc. as host functions
   - WasmGC modules call these instead of embedding logic

4. **evalForm() Integration**
   - Wire WasmGC execution path
   - Make it behave like TreeWalk/VM
   - Return proper Values

---

## Implementation Plan

### Phase 1: Wasmtime Integration (2 weeks)
- Add dependency
- Create executor.zig
- Test basic WAT execution

### Phase 2: Value Marshalling (2 weeks)
- WASM ref ↔ ClojureWasm Value conversion
- Handle all types
- Test round-trips

### Phase 3: Host Imports (2 weeks)
- Export 40+ core functions
- Test each individually
- Verify ABI compatibility

### Phase 4: evalForm() Integration (1 week)
- Wire into driver.zig
- Add CLI flag support
- Test simple expressions

### Phase 5: Test Migration (2 weeks)
- Run full 1,242-test suite
- Fix failures
- Achieve zero divergence

### Buffer (1 week)
- Polish, documentation
- Performance tuning

**Total: 10 weeks** (Month 5-7)

---

## Alternative: Skip Testing

**If automated testing is not required**, the current Alpha state is sufficient:

✅ Generates correct WAT  
✅ Works in browsers  
✅ 40 functions manually verified  
❌ No automated quality assurance  
❌ No CI/CD  
❌ Higher regression risk  

**Recommendation**: **DO NOT skip testing.** The 1,242-test suite is ClojureWasm's quality contract. Without it, WasmGC cannot be trusted for production.

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Wasmtime complexity | High | Start minimal, expand incrementally |
| Value marshalling bugs | High | Comprehensive round-trip tests |
| Performance overhead | Medium | Profile and optimize; consider zero-copy |
| Binary size bloat | Low | Make wasmtime optional (`-Dwasm-executor` flag) |
| ABI mismatches | High | Design carefully; test each host function |

---

## Decision Required

**Choose one path**:

### Path A: Full Integration (Recommended) ⭐
- Embed wasmtime for testing
- Run 1,242-test suite
- Prove correctness
- 10 weeks effort

### Path B: Manual Testing Only
- Keep current Alpha state
- Browser-only verification
- No automated tests
- 0 weeks effort (done)

### Path C: Hybrid (Best of Both) ⭐⭐
- Embed wasmtime for development/testing (`-Dwasm-executor` flag)
- Pure compiler for production (no runtime)
- Best quality + deployment story
- 10 weeks effort + better architecture

---

## Recommendation

**Choose Path C (Hybrid)**:

1. **Short-term**: Fix module boundary issues, verify current implementation
2. **Medium-term**: Integrate wasmtime for testing (10 weeks)
3. **Long-term**: Production deployments use pure compiler

This gives:
- ✅ Automated quality assurance
- ✅ CI/CD support
- ✅ Clean production artifacts (no runtime dependency)
- ✅ Proof of correctness
- ✅ Future-proof architecture

---

## Next Immediate Steps

1. ✅ **Document the gap** (this file)
2. ⏳ **Fix module boundary issues** (current blocker)
3. ⏳ **Verify test results** (check current failures)
4. ⏸ **Decide on path** (user decision)
5. ⏸ **Start wasmtime integration** (if Path C chosen)

---

## Questions for Stakeholder

1. **Is automated testing a requirement?**
   - Yes → Proceed with Path C
   - No → Stay with current Alpha (Path B)

2. **What is the production deployment target?**
   - Browsers only → Path B sufficient
   - Mixed (browsers + CI + REPL) → Path C required

3. **What is the risk tolerance?**
   - Low (need proof of correctness) → Path C
   - High (trust manual testing) → Path B

4. **What is the timeline constraint?**
   - <2 months → Path B (use current Alpha)
   - 2-3 months available → Path C (full integration)

---

## Success Metrics

### If Path C Chosen:

- [ ] Wasmtime integrated and working
- [ ] Value marshalling tests pass (100%)
- [ ] 40 host functions exported
- [ ] evalForm() returns proper Values
- [ ] **1,242/1,242 tests pass with WasmGC backend**
- [ ] Zero divergence from TreeWalk and VM
- [ ] CI/CD runs all three backends
- [ ] Production builds exclude wasmtime (binary size <5MB)

### If Path B Chosen:

- [x] WAT generation works
- [x] Browser demos work
- [x] 40 functions manually tested
- [ ] Document limitations clearly
- [ ] Accept manual QA process

---

## References

- **Full Plan**: [WasmGC-Integration-Plan.md](WasmGC-Integration-Plan.md)
- **Current Status**: [project_status.md](../memory/project_status.md)
- **Original Spec**: [Phase 4 詳細方案.md](reference/Phase 4 詳細方案 — WasmGC Backend（第三後端）202610222131.md)
- **User Docs**: [wasmgc-backend.md](wasmgc-backend.md)
