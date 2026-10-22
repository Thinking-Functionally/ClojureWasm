# Phase 1 Blockers Analysis

## Executive Summary

Phase 1 (cross-compilation to wasm32-wasi) revealed **4 fundamental architectural incompatibilities** that make simple cross-compilation non-viable. Total: 124 compilation errors.

**Recommendation: Skip Phase 1, move directly to Phase 4 (WasmGC).**

---

## Blocker Categories

### 1. Threading Architecture (CRITICAL - Architectural)

**Error:**
```
error: Cannot spawn thread when building in single-threaded mode
```

**Impact:** 
- ClojureWasm's concurrency model assumes multi-threading throughout
- Affects: `src/runtime/thread.zig`, `src/runtime/java/lang/Thread.zig`
- wasm32-wasi is **fundamentally single-threaded** by design

**Severity:** 🔴 CRITICAL - Requires architectural redesign

**Fix Effort:** 
- High (3-4 weeks minimum)
- Requires:
  - Add conditional compilation for single-threaded mode
  - Implement cooperative scheduling or remove threading
  - Refactor all thread-dependent features
  - May break JVM compatibility guarantees

**Trade-offs:**
- Undermines native multi-threaded performance
- Complicates codebase with dual execution models
- May not fully support concurrent Clojure semantics

---

### 2. Atomic Operations (CRITICAL - Data Structure)

**Error:**
```
error: expected 32-bit integer type or smaller; found 64-bit integer type
```

**Impact:**
- ClojureWasm uses 64-bit `Value` type with atomic operations
- wasm32 only supports 32-bit atomics
- Affects: 8+ files including core concurrency primitives
  - `src/runtime/agent.zig` (2 sites)
  - `src/runtime/atom.zig` (6 sites)
  - `src/runtime/concurrency/safepoint.zig`
  - `src/runtime/concurrency/lock_tx.zig`
  - `src/runtime/stm/ref.zig`

**Severity:** 🔴 CRITICAL - Core data structure incompatibility

**Fix Effort:**
- Very High (4-6 weeks minimum)
- Options:
  1. Split Value into two 32-bit atomics (complex, error-prone)
  2. Use mutex-based synchronization (performance penalty)
  3. Redesign Value representation for wasm32 (breaks NaN-boxing)

**Trade-offs:**
- Any fix significantly impacts performance
- May break Value layout assumptions throughout codebase
- Complicates concurrent data structure semantics

---

### 3. Platform Dependencies (HIGH - API Surface)

**Errors:**
```
error: dependency on libc must be explicitly specified
error: unsupported OS
```

**Impact:**
- Terminal control: `tcgetattr`, `tcsetattr`
- Scheduling: `sched_yield`
- Various POSIX APIs not available in WASI
- Zig std library explicitly rejects WASI for some functions

**Severity:** 🟡 HIGH - Requires API abstraction

**Fix Effort:**
- Medium (2-3 weeks)
- Requires:
  - Abstract platform-specific functionality
  - Implement WASI-compatible alternatives
  - Remove or stub out unsupported features (REPL readline, etc.)

**Trade-offs:**
- Loss of interactive REPL features in wasm build
- May need to disable some platform-specific functionality
- Increases code complexity with conditional compilation

---

### 4. Alignment Guarantees (MEDIUM - Platform Assumptions)

**Error:**
```
error: reached unreachable code
```

**Impact:**
- Compile-time assertions failing: `@alignOf(T) >= 8`
- Affects: `JavaArray`, `String`, `BigDecimal`, `BigInt`, `TypeDescriptorRef`
- wasm32 may have different alignment guarantees than 64-bit platforms

**Severity:** 🟢 MEDIUM - Needs investigation

**Fix Effort:**
- Low-Medium (1 week)
- Requires:
  - Verify actual wasm32 alignment guarantees
  - Adjust assertions or add padding if needed
  - May need to use explicit alignment attributes

**Trade-offs:**
- Minimal if adjustments are small
- Could increase memory usage slightly if padding needed

---

## Phase 1 Viability Assessment

### Effort Required
- **Minimum:** 10-14 weeks (2.5-3.5 months)
- **Realistic:** 16-20 weeks (4-5 months) accounting for testing and integration

### Risk Factors
1. **Architectural mismatch:** Single-threaded vs multi-threaded is fundamental
2. **Performance regression:** Fixes may significantly impact native performance
3. **Maintenance burden:** Dual execution models increase complexity
4. **Incomplete solution:** May not achieve full Clojure concurrency semantics

### Success Probability
- **Low (30-40%)** - Too many fundamental incompatibilities

---

## Recommendation: Skip to Phase 4

### Why Phase 4 is Better

**Phase 4 (WasmGC Backend):**
- **Shorter timeline:** 3-4 months (vs 4-5 months for Phase 1 fixes)
- **Clean slate:** No need to adapt multi-threaded architecture
- **Better performance:** WasmGC is optimized for managed languages
- **Simpler value model:** Use WasmGC reference types directly
- **Modern target:** Targets browsers with WasmGC support (Chrome 119+, Firefox 120+)
- **No legacy constraints:** Don't inherit native runtime's assumptions

### Phase 4 Advantages Over Fixed Phase 1
1. **No threading issues:** WasmGC runtime can be single-threaded from start
2. **No atomic issues:** Use WasmGC's native struct types, not 64-bit NaN-boxing
3. **No platform dependencies:** Pure wasm, no POSIX/libc assumptions
4. **Host-managed GC:** No need to implement manual mark-and-sweep (Phase 3's burden)
5. **Better tool support:** Growing ecosystem (wasm-tools, wit-bindgen)

---

## Community Fork Strategy

For this **community-maintained fork** (not upstream ClojureWasm):

### Recommended Path
1. ~~Phase 1~~ **SKIP** - Cross-compilation blockers too severe
2. ~~Phase 2~~ **SKIP** - Was just Phase 1 validation
3. ~~Phase 3~~ **SKIP** - Manual GC unnecessary with WasmGC
4. **Phase 4** - Direct implementation of WasmGC backend ✅

### Why This Makes Sense
- Community fork can target modern environments only
- No need to support legacy wasm runtimes
- Can assume WasmGC availability (standardized 2023)
- Faster time-to-working-prototype
- Cleaner implementation without native runtime baggage

---

## Next Steps (If Proceeding with Phase 4)

### Phase 4 Foundation Work
1. **Research WasmGC:**
   - Study spec: https://github.com/WebAssembly/gc
   - Review examples: wasm-tools, binaryen
   - Understand struct/array/ref types

2. **Design value representation:**
   - Map Clojure types to WasmGC types
   - Design persistent data structures in WasmGC
   - Plan interop with host (JS/web)

3. **Prototype core runtime:**
   - Implement basic value types
   - Build simple evaluator
   - Test in browser environment

4. **Incremental implementation:**
   - Bootstrap minimal core.clj
   - Add data structures (vector, map, set)
   - Implement special forms
   - Add host interop

### Estimated Timeline (Phase 4)
- Month 1: Research + value representation design
- Month 2: Core runtime + basic evaluator
- Month 3: Data structures + special forms
- Month 4: Host interop + testing

---

## Conclusion

**Phase 1 is not viable** due to fundamental architectural incompatibilities:
- Multi-threading vs single-threaded (architectural)
- 64-bit atomics vs 32-bit limit (data structure)
- Platform dependencies (API surface)
- Alignment assumptions (platform)

**Recommendation:** Skip directly to **Phase 4 (WasmGC)**, which:
- Takes less time (3-4 months vs 4-5 months)
- Avoids all Phase 1 blockers
- Provides cleaner architecture
- Better aligns with community fork goals

**Decision needed:** Confirm Phase 4 approach before starting implementation.
