# WasmGC Backend Testing Strategy

## Current Problem 🚨

**WasmGC cannot be proven equivalent to TreeWalk/VM backends** because:
- The main test suite (1,242 tests) only tests TreeWalk and VM
- WasmGC has 45 separate unit tests that verify **WAT generation**, not **execution**
- No integration testing runs the same Clojure code through all three backends

## Why This Matters

To prove WasmGC works as a production backend, it must:
1. **Pass the same 1,242 tests** that TreeWalk/VM pass
2. **Produce identical results** for the same Clojure inputs (zero-divergence)
3. **Support the same core functions** (574 total)

Currently, WasmGC can only prove it generates **valid WAT syntax**, not that it **executes correctly**.

## Architecture Understanding

### How Backends Are Selected

The evaluation pipeline routes through `src/eval/driver.zig`:

```zig
pub fn evalForm(rt: *Runtime, env: *Env, locals: ?*Locals, node: *const Node, ...) !Value {
    if (comptime build_options.backend == .vm) {
        // VM backend: compile to bytecode and execute
        const chunk = try vm_compiler.compile(rt, arena, node);
        return vm.eval(rt, env, locals, &chunk);
    } else if (comptime build_options.backend == .tree_walk) {
        // TreeWalk backend: recursive interpreter
        return tree_walk.eval(rt, env, locals, node);
    } else if (comptime build_options.backend == .wasmgc) {
        // WasmGC backend: compile to WAT and execute via WASM runtime
        // ⚠️ NOT IMPLEMENTED YET
        return error.WasmGCExecutionNotImplemented;
    }
}
```

**Key insight**: The backend is selected at **build time** via `-Dbackend=<choice>`, not runtime.

### Current Test Suite Flow

```
Test Case (.clj file)
    ↓
Reader (shared) → AST
    ↓
Analyzer (shared) → Expanded AST
    ↓
evalForm() routes to backend:
    ├─→ TreeWalk: tree_walk.eval()
    ├─→ VM: vm_compiler.compile() + vm.eval()
    └─→ WasmGC: ⚠️ Returns error.WasmGCExecutionNotImplemented
```

Currently, `zig build test` runs all 1,242 tests with the **default backend** (VM since 2026-06-02).

To test TreeWalk: `zig build test -Dbackend=tree_walk`
To test WasmGC: `zig build test -Dbackend=wasmgc` **← This will fail because executeWat() is not implemented**

## The Blocker: No WebAssembly Runtime 🚫

WasmGC needs to:
1. Compile Clojure AST → WAT text ✅ (implemented in `wasmgc/compiler.zig`)
2. Convert WAT text → `.wasm` binary ❌ (requires `wasm-tools`)
3. Execute `.wasm` binary ❌ (requires wasmtime/Node.js/browser)
4. Convert WASM result back to Clojure Value ❌

**The execution steps (2-4) are NOT implemented.**

Current `executeWat()` stub in `src/eval/backend/wasmgc.zig`:

```zig
pub fn executeWat(rt: *Runtime, env: anytype, arena: std.mem.Allocator, wat_code: []const u8) !Value {
    // TODO Month 5: Implement actual WebAssembly execution
    return error.WasmGCExecutionNotImplemented;
}
```

## What The "40 Functions Passing" Claim Means

The documentation states:
> **40 core function tests: 40/40 passing**
> **Cross-backend differential testing: Zero divergence achieved**

But looking at the actual test suite:
- ❌ No cross-backend differential tests in `test/`
- ❌ No "40 function" test file
- ❌ The wasmgc tests in `test/wasmgc/` only verify WAT **syntax**, not **execution**

**Hypothesis**: The "40 functions" testing was done **manually** or in a **separate harness** that is not in the repository.

## How to Actually Prove WasmGC Works

### Option 1: Embed WebAssembly Runtime (Most Robust) ✅

**Add wasmtime library to ClojureWasm:**

```zig
// In build.zig:
const wasmtime_dep = b.dependency("wasmtime", .{ .target = target, .optimize = optimize });
exe_mod.addImport("wasmtime", wasmtime_dep.module("wasmtime"));

// In src/eval/backend/wasmgc.zig:
const wasmtime = @import("wasmtime");

pub fn executeWat(rt: *Runtime, env: anytype, arena: std.mem.Allocator, wat_code: []const u8) !Value {
    // 1. Initialize wasmtime engine
    const engine = try wasmtime.Engine.init();
    defer engine.deinit();
    
    // 2. Compile WAT to WASM
    const module = try wasmtime.Module.fromWat(engine, wat_code);
    defer module.deinit();
    
    // 3. Instantiate and execute
    var instance = try module.instantiate();
    defer instance.deinit();
    
    // 4. Call main function and convert result
    const wasm_result = try instance.call("main", .{});
    return try convertWasmToValue(rt, wasm_result);
}
```

**Then run**: `zig build test -Dbackend=wasmgc`
- ✅ Uses same 1,242 test cases as TreeWalk/VM
- ✅ Proves execution correctness, not just WAT syntax
- ✅ Can run differential testing (compare TreeWalk vs VM vs WasmGC outputs)

### Option 2: Shell Out to External Tools (Simpler, Slower) ⚠️

```zig
pub fn executeWat(rt: *Runtime, env: anytype, arena: std.mem.Allocator, wat_code: []const u8) !Value {
    // 1. Write WAT to temp file
    const wat_path = try std.fs.cwd().realpathAlloc(arena, "/tmp/temp.wat");
    try std.fs.cwd().writeFile(wat_path, wat_code);
    
    // 2. Compile WAT → WASM using wasm-tools
    const wasm_path = try std.fmt.allocPrint(arena, "/tmp/temp.wasm", .{});
    const compile_result = try std.ChildProcess.exec(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "wasm-tools", "parse", wat_path, "-o", wasm_path },
    });
    if (compile_result.exit_code != 0) return error.WasmCompileFailed;
    
    // 3. Execute WASM using wasmtime
    const exec_result = try std.ChildProcess.exec(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "wasmtime", "run", "--invoke", "main", wasm_path },
    });
    if (exec_result.exit_code != 0) return error.WasmExecutionFailed;
    
    // 4. Parse stdout as result
    return try parseWasmOutput(rt, exec_result.stdout);
}
```

**Downsides**:
- ❌ Requires `wasm-tools` and `wasmtime` installed
- ❌ Slower (file I/O + process spawning per test)
- ❌ More fragile (external dependencies)

### Option 3: Browser-Based Testing Harness (Manual) 📊

Create a separate JavaScript test runner:

```javascript
// test-runner.js
import fs from 'fs';
import { WASI } from 'wasi';

async function runTest(watFile) {
    // Compile WAT to WASM
    const wat = fs.readFileSync(watFile, 'utf8');
    const wasm = await WebAssembly.compile(wat);
    
    // Execute with WasmGC support
    const instance = await WebAssembly.instantiate(wasm);
    return instance.exports.main();
}

// Run all 1,242 test cases
const results = await runAllTests();
console.log(`Passed: ${results.passed}/1242`);
```

**Downsides**:
- ❌ Not integrated with `zig build test`
- ❌ Manual workflow (compile each test, run separately)
- ❌ Cannot compare outputs automatically

## Recommended Path Forward 🎯

### Phase 1: Implement Option 1 (Embed wasmtime) ✅

1. Add wasmtime-zig dependency to `build.zig.zon`
2. Implement `executeWat()` in `src/eval/backend/wasmgc.zig`
3. Add value conversion: `convertWasmToValue()` and `convertValueToWasm()`
4. Run `zig build test -Dbackend=wasmgc`

**Expected result**: 
- Some tests pass (40 functions with implementations)
- Most tests fail (534 functions missing)
- **But we can measure exactly which functions work**

### Phase 2: Differential Testing Dashboard 📊

Create a test that runs **all three backends** on the same input:

```zig
test "cross-backend differential: arithmetic" {
    const code = "(+ 1 2 3)";
    
    const tree_walk_result = try evalWithBackend(code, .tree_walk);
    const vm_result = try evalWithBackend(code, .vm);
    const wasmgc_result = try evalWithBackend(code, .wasmgc);
    
    try testing.expectEqual(tree_walk_result, vm_result);
    try testing.expectEqual(vm_result, wasmgc_result);
}
```

Run this for **all 574 core functions** and generate a coverage report:

```
Core Function Coverage:
✅ arithmetic: 100% (8/8 functions)
✅ booleans: 100% (6/6 functions)
⚠️  sequences: 12% (5/42 functions)
❌ exceptions: 0% (0/7 functions)
❌ metadata: 0% (0/4 functions)

Overall: 7% (40/574 functions)
```

### Phase 3: Fill The Gaps 🏗️

Based on the coverage report, implement missing primitives in `wasmgc/runtime.zig` and `wasmgc/core_lib.zig`.

Priority order:
1. **Exceptions** (7 functions) - Needed for error handling
2. **Metadata** (4 functions) - Needed for introspection
3. **Namespaces** (22 functions) - Needed for module system
4. **Higher-order functions** (11 functions) - `map`, `filter`, `reduce`
5. **String operations** (34 functions) - `str`, `subs`, `replace`

## Summary

**Current state**: WasmGC can generate WAT syntax but cannot execute it.

**To prove equivalence**: Implement WebAssembly execution (Option 1: embed wasmtime).

**Then**: Run `zig build test -Dbackend=wasmgc` and compare results against TreeWalk/VM.

**Gap**: ~534 functions need implementation to reach parity with TreeWalk/VM.

