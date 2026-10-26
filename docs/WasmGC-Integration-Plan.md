# WasmGC Backend Integration Implementation Plan

**Goal**: Make WasmGC backend pass the same 1,242 test suite as TreeWalk and VM backends

**Current Status**: 
- WasmGC backend: 6,069 LOC implemented (Month 4 Alpha complete)
- Test coverage: 45 unit tests (WAT generation only)
- Main test suite: 0/1,242 tests running against WasmGC
- Blocker: Module boundary issues in build system

---

## Problem Statement

### Current Architecture Gap

**What Works**:
✅ WasmGC compiles Clojure AST → WAT text  
✅ Unit tests verify WAT syntax generation  
✅ 40 functions manually tested in browser  

**What's Missing**:
❌ No execution of compiled WASM in test suite  
❌ No integration with main ClojureWasm test harness  
❌ No proof that WasmGC produces same results as TreeWalk/VM  
❌ No CLI command to evaluate Clojure via WasmGC backend  

### The Core Issue

The 1,242-test suite works like this:

```
Test Case → ClojureWasm CLI → evalForm() → Backend Selection
                                             ├─ TreeWalk ✅
                                             ├─ VM ✅
                                             └─ WasmGC ❌ (missing execution)
```

**WasmGC path is incomplete**:
```zig
// src/eval/driver.zig
pub fn evalForm(rt: *Runtime, ast: *Node) !Value {
    return switch (build_options.backend) {
        .tree_walk => TreeWalk.eval(rt, ast),     // ✅ Works
        .vm => VM.eval(rt, ast),                   // ✅ Works
        .wasmgc => WasmGC.eval(rt, ast),          // ❌ Doesn't exist!
    };
}
```

---

## Implementation Options

### Option A: Embed WebAssembly Runtime (Recommended for Testing) ⭐

**Strategy**: Embed `wasmtime` in ClojureWasm binary to execute compiled WASM

**Pros**:
- ✅ Can run full 1,242-test suite against WasmGC
- ✅ Proves WasmGC produces correct results
- ✅ Automated CI/CD testing
- ✅ Cross-backend differential testing

**Cons**:
- ❌ Adds wasmtime dependency (~10MB binary size)
- ❌ Two-phase execution (compile → load → run)
- ❌ Slower than native VM backend

**Implementation Steps**:

#### Phase 1: Add Wasmtime Dependency (Week 1)

1. **Add `wasmtime-c-api` to `build.zig.zon`**
   ```zig
   .dependencies = .{
       .zwasm = .{ ... },  // Existing FFI
       .wasmtime = .{      // NEW: Execution runtime
           .url = "https://github.com/bytecodealliance/wasmtime/releases/download/v15.0.0/wasmtime-v15.0.0-x86_64-macos-c-api.tar.xz",
           .hash = "...",
       },
   },
   ```

2. **Create `src/eval/backend/wasmgc/executor.zig`**
   ```zig
   //! WebAssembly execution runtime (wasmtime wrapper)
   const std = @import("std");
   const wasmtime = @cImport(@cInclude("wasmtime.h"));
   const Value = @import("../../runtime/value/value.zig").Value;
   
   pub const Executor = struct {
       engine: *wasmtime.Engine,
       store: *wasmtime.Store,
       
       pub fn init(allocator: std.mem.Allocator) !Executor {
           const engine = wasmtime.wasm_engine_new() orelse return error.EngineInitFailed;
           const store = wasmtime.wasm_store_new(engine) orelse return error.StoreInitFailed;
           return .{ .engine = engine, .store = store };
       }
       
       pub fn executeWat(self: *Executor, wat: []const u8) !Value {
           // Compile WAT → WASM binary
           var wasm_bytes = try self.wat2wasm(wat);
           defer self.allocator.free(wasm_bytes);
           
           // Load module
           var module = try self.loadModule(wasm_bytes);
           defer module.deinit();
           
           // Call exported main function
           var result = try module.callExport("main");
           
           // Convert WASM result → ClojureWasm Value
           return try self.wasmToValue(result);
       }
   };
   ```

#### Phase 2: Integrate with `evalForm()` (Week 2)

3. **Modify `src/eval/driver.zig`**
   ```zig
   const WasmGC = @import("backend/wasmgc.zig");
   const WasmExecutor = @import("backend/wasmgc/executor.zig").Executor;
   
   var wasmgc_executor: ?WasmExecutor = null;
   
   pub fn evalForm(rt: *Runtime, ast: *Node) !Value {
       return switch (build_options.backend) {
           .tree_walk => TreeWalk.eval(rt, ast),
           .vm => VM.eval(rt, ast),
           .wasmgc => blk: {
               // Lazy init executor
               if (wasmgc_executor == null) {
                   wasmgc_executor = try WasmExecutor.init(rt.arena);
               }
               
               // Compile AST → WAT
               var compiler = WasmGC.Compiler.init(rt.arena, rt);
               const wat = try compiler.compile(ast);
               
               // Execute WAT → Value
               break :blk try wasmgc_executor.?.executeWat(wat);
           },
       };
   }
   ```

4. **Fix module boundary issues**
   - Make `Node` type accessible to wasmgc.zig
   - Add AST module to build.zig imports
   - Resolve circular dependencies

#### Phase 3: Value Marshalling (Week 3)

5. **Implement WASM ↔ Clojure Value conversion**
   ```zig
   // executor.zig
   fn wasmToValue(self: *Executor, wasm_val: wasmtime.Val) !Value {
       return switch (wasm_val.kind) {
           .i64 => Value.encodeInt(wasm_val.of.i64),
           .f64 => Value.encodeDouble(wasm_val.of.f64),
           .ref => {
               // Decode WasmGC struct tag
               const tag = try self.readStructField(wasm_val.of.ref, 0);
               return switch (tag) {
                   0 => Value.nil_val,
                   1 => Value.encodeBool(...),
                   4 => try self.decodeString(...),
                   // ... more types
               };
           },
       };
   }
   
   fn valueToWasm(self: *Executor, val: Value) !wasmtime.Val {
       // Inverse conversion
   }
   ```

6. **Handle host function imports**
   ```zig
   // Provide Clojure runtime functions as WASM imports
   fn setupImports(self: *Executor) !void {
       try self.linkHostFunction("clojure.core", "conj", conjImpl);
       try self.linkHostFunction("clojure.core", "assoc", assocImpl);
       // ... 40+ core functions
   }
   ```

#### Phase 4: Test Suite Integration (Week 4)

7. **Run main test suite with WasmGC**
   ```bash
   # Should now pass 1,242 tests
   zig build test -Dbackend=wasmgc
   ```

8. **Add differential testing**
   ```zig
   // test/differential_test.zig
   test "cross-backend equivalence" {
       const test_cases = @embedFile("test_corpus.clj");
       
       for (test_cases) |case| {
           const tw_result = evalWithTreeWalk(case);
           const vm_result = evalWithVM(case);
           const wg_result = evalWithWasmGC(case);  // NEW
           
           try testing.expect(tw_result.eql(vm_result));
           try testing.expect(vm_result.eql(wg_result));  // Verify WasmGC matches
       }
   }
   ```

---

### Option B: External WASM Runtime (Current State)

**Strategy**: WasmGC only generates WAT files; user runs them externally

**Pros**:
- ✅ No runtime dependency
- ✅ Works with any WASM engine (wasmtime, browser, Node.js)
- ✅ Simpler architecture

**Cons**:
- ❌ Cannot run automated tests
- ❌ No proof of correctness
- ❌ Manual verification only

**Current CLI Flow**:
```bash
# 1. Compile Clojure → WAT
cljw --backend=wasmgc --emit-wat app.clj > app.wat

# 2. Convert WAT → WASM (external tool)
wasm-tools parse app.wat -o app.wasm

# 3. Run WASM (external runtime)
wasmtime app.wasm
# OR: <script src="app.wasm"></script> in browser
```

**This is the current Month 4 Alpha state** - it works for manual browser demos but cannot be automated.

---

### Option C: Hybrid Approach (Recommended Long-Term) ⭐⭐

**Strategy**: Option A for testing + Option B for production

1. **Development builds** (`-Dwasm-executor`): Embed wasmtime for testing
2. **Release builds** (default): Pure compiler, no runtime

```zig
// build.zig
const wasm_executor = b.option(bool, "wasm-executor", "Embed wasmtime for WasmGC testing") orelse false;

if (wasm_executor) {
    exe_mod.addImport("wasmtime", wasmtime_mod);
}
build_options.addOption(bool, "wasm_executor", wasm_executor);
```

```zig
// driver.zig
pub fn evalForm(rt: *Runtime, ast: *Node) !Value {
    return switch (build_options.backend) {
        .wasmgc => blk: {
            const wat = try compileToWat(rt, ast);
            
            if (build_options.wasm_executor) {
                // Testing path: execute inline
                break :blk try executeWat(wat);
            } else {
                // Production path: write WAT file
                try std.fs.cwd().writeFile("output.wat", wat);
                std.log.info("Compiled to output.wat", .{});
                return Value.nil_val;
            }
        },
    };
}
```

---

## Detailed Task Breakdown

### Phase 1: Wasmtime Integration (2 weeks)

**Tasks**:
- [ ] Research wasmtime C API
- [ ] Add wasmtime-c-api to build.zig.zon
- [ ] Create executor.zig wrapper
- [ ] Test basic WAT execution
- [ ] Implement wat2wasm compilation
- [ ] Implement module loading

**Deliverable**: Can execute simple WAT string and get i64 result

**Test**:
```zig
test "execute simple WAT" {
    var executor = try Executor.init(testing.allocator);
    defer executor.deinit();
    
    const wat = "(module (func (export \"main\") (result i64) (i64.const 42)))";
    const result = try executor.executeWat(wat);
    
    try testing.expectEqual(@as(i64, 42), result.asInt());
}
```

### Phase 2: Value Marshalling (2 weeks)

**Tasks**:
- [ ] Implement WASM ref → ClojureWasm Value decoder
- [ ] Handle all primitive types (nil, bool, int, double)
- [ ] Handle string decoding (WasmGC array → UTF-8)
- [ ] Handle collection types (vector, map, set)
- [ ] Implement ClojureWasm Value → WASM ref encoder
- [ ] Test round-trip conversions

**Deliverable**: Can convert between WASM and ClojureWasm representations

**Test**:
```zig
test "value marshalling round-trip" {
    const original = Value.encodeInt(42);
    const wasm_val = try valueToWasm(original);
    const decoded = try wasmToValue(wasm_val);
    try testing.expect(original.eql(decoded));
}
```

### Phase 3: Host Function Imports (2 weeks)

**Tasks**:
- [ ] Design host import ABI
- [ ] Implement `clojure.core/conj` host import
- [ ] Implement `clojure.core/assoc` host import
- [ ] Implement arithmetic operators (+, -, *, /)
- [ ] Implement comparison operators (<, >, =)
- [ ] Implement collection accessors (first, rest, nth)
- [ ] Test each host function individually

**Deliverable**: WasmGC modules can call ClojureWasm runtime functions

**Test**:
```zig
test "host function: conj" {
    const wat = 
        \\(module
        \\  (import "clojure.core" "conj" 
        \\    (func $conj (param (ref $Value)) (param (ref $Value)) (result (ref $Value))))
        \\  (func (export "main") (result (ref $Value))
        \\    (call $conj 
        \\      (call $vector-empty)
        \\      (call $int-new (i64.const 42)))))
        ;
    const result = try executor.executeWat(wat);
    try testing.expectEqual(1, result.asVector().count());
}
```

### Phase 4: Integration with evalForm() (1 week)

**Tasks**:
- [ ] Fix module boundary issues in build.zig
- [ ] Make Node type accessible to wasmgc.zig
- [ ] Wire WasmGC backend into evalForm()
- [ ] Add backend selection flag to CLI
- [ ] Test simple expressions

**Deliverable**: Can run `zig build run -Dbackend=wasmgc -- -e "(+ 1 2)"`

### Phase 5: Test Suite Migration (2 weeks)

**Tasks**:
- [ ] Run full test suite with WasmGC backend
- [ ] Debug failures
- [ ] Fix missing runtime functions
- [ ] Add test output comparison (TreeWalk vs VM vs WasmGC)
- [ ] Achieve zero-divergence on 1,242 tests

**Deliverable**: All 1,242 tests pass with WasmGC backend

---

## Success Criteria

### Milestone 1: Basic Execution ✅
- [ ] Can compile simple WAT and execute it
- [ ] Can decode i64/f64 results
- [ ] Can call one host function (e.g., `+`)

### Milestone 2: Value System ✅
- [ ] All primitive types work (nil, bool, int, double, string)
- [ ] Collections work (vector, map, set)
- [ ] Round-trip conversion preserves data

### Milestone 3: Runtime Functions ✅
- [ ] 40 core functions work as host imports
- [ ] Arithmetic works (+, -, *, /)
- [ ] Collections work (conj, assoc, get)
- [ ] Control flow works (if, do, let)

### Milestone 4: Full Integration ✅
- [ ] WasmGC backend in evalForm() switch
- [ ] CLI flag `-Dbackend=wasmgc` works
- [ ] REPL can use WasmGC backend

### Milestone 5: Test Parity ✅ **FINAL GOAL**
- [ ] **1,242/1,242 tests pass with WasmGC backend**
- [ ] Zero divergence from TreeWalk and VM
- [ ] Differential testing verifies equivalence
- [ ] CI/CD runs all three backends

---

## Timeline Estimate

| Phase | Duration | Outcome |
|-------|----------|---------|
| **Phase 1**: Wasmtime Integration | 2 weeks | Basic WAT execution |
| **Phase 2**: Value Marshalling | 2 weeks | Data conversion working |
| **Phase 3**: Host Imports | 2 weeks | Runtime functions callable |
| **Phase 4**: evalForm() Integration | 1 week | CLI works with WasmGC |
| **Phase 5**: Test Migration | 2 weeks | **1,242 tests passing** |
| **Buffer** | 1 week | Bug fixes, polish |
| **Total** | **10 weeks** (~2.5 months) |

**Start**: 2026-10-26 (Month 5 Week 1)  
**Target Completion**: 2027-01-03 (Month 7 Week 2)

---

## Risk Mitigation

### Risk 1: Wasmtime C API Complexity
**Mitigation**: Start with minimal wrapper, expand incrementally

### Risk 2: Value Marshalling Performance
**Mitigation**: Profile and optimize hot paths; consider zero-copy strategies

### Risk 3: Host Import ABI Mismatch
**Mitigation**: Design ABI carefully; add comprehensive tests for each function

### Risk 4: Test Suite Divergence
**Mitigation**: Run differential tests continuously; fix divergences as they appear

### Risk 5: Binary Size Bloat
**Mitigation**: Make wasmtime optional (`-Dwasm-executor` flag); release builds exclude it

---

## Alternative: Skip Testing Integration

**If automated testing is not a priority**, the current Month 4 Alpha state is sufficient:

✅ WasmGC generates correct WAT  
✅ Manual browser testing works  
✅ 40 functions verified manually  
❌ Cannot prove correctness programmatically  
❌ Cannot run CI/CD tests  
❌ Relies on manual QA  

**This path means:**
- Continue manual testing in browsers
- Skip automated test suite
- Accept higher risk of regressions
- Focus on feature development over quality assurance

**Recommendation**: **Do NOT skip testing integration.** The 1,242-test suite is ClojureWasm's quality guarantee. Without it, WasmGC backend cannot be trusted for production use.

---

## Next Steps (Immediate Actions)

1. **Decide on approach**: Option A (embedded runtime) vs Option B (external only) vs Option C (hybrid)
2. **Verify current module boundary issues**: Fix wasmgc.zig import errors
3. **Set up wasmtime dependency**: Add to build.zig.zon
4. **Create executor.zig stub**: Minimal wrapper for basic WAT execution
5. **Write first integration test**: Simple expression end-to-end

**Recommendation**: Start with Option C (hybrid) - embedded runtime for development/testing, external for production. This gives best of both worlds.
