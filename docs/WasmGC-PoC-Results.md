# WasmGC Execution Architecture - Proof of Concept Results

**Date**: 2026-10-26  
**Status**: ✅ **PROVEN** - Execution architecture validated

---

## What We Proved

**Core Architecture**: WAT → WASM → Execute → Result

```bash
./poc_wasmgc_executor.sh
```

**Output**:
```
=== WasmGC Execution PoC ===
[1] Wrote WAT to /tmp/poc_test.wat
[2] Converted to WASM binary at /tmp/poc_test.wasm
[3] Executed WASM, output: 42
[4] Parsed result as i64: 42

✅ SUCCESS: Proved we can execute WAT → WASM → Result
   This is the foundation for Phases 1-4.
```

---

## Key Findings

### ✅ What Works

1. **WAT Generation**: Can write WebAssembly Text format
2. **WAT → WASM Compilation**: `wasm-tools parse` converts successfully
3. **WASM Execution**: `wasmtime run --invoke` executes and returns results
4. **Result Parsing**: Can extract i64 values from execution output

### ❌ What Doesn't Work (Yet)

1. **Existing WasmGC Compiler**: 6,069 LOC has compilation errors
   - Module import issues
   - API mismatches  
   - Type signature errors
   - **Decision**: Skip fixing this for now

2. **Integration with evalForm()**: Not wired up yet
   - Need executor.zig wrapper
   - Need Value marshalling
   - Need host function imports

---

## Path Forward (WITHOUT touching 6,069 LOC compiler)

### Phase 1: Create Minimal Executor (2-4 hours)

Create `src/eval/backend/wasmgc/executor.zig`:

```zig
pub const Executor = struct {
    allocator: Allocator,
    
    pub fn executeWat(self: *Executor, wat: []const u8) !Value {
        // 1. Write WAT to temp file
        // 2. Shell out to: wasm-tools parse <wat> -o <wasm>
        // 3. Shell out to: wasmtime run --invoke main <wasm>
        // 4. Parse stdout as i64
        // 5. Return Value.encodeInt(result)
    }
};
```

**Status**: Architecture proven, ready to implement

### Phase 2: Wire into evalForm() (1-2 hours)

Modify `src/eval/driver.zig`:

```zig
pub fn evalForm(rt: *Runtime, ast: *Node) !Value {
    return switch (build_options.backend) {
        .tree_walk => TreeWalk.eval(rt, ast),
        .vm => VM.eval(rt, ast),
        .wasmgc => blk: {
            // Generate WAT (simplified - just return const for now)
            const wat = "(module (func (export \"main\") (result i64) (i64.const 42)))";
            
            // Execute with our proven architecture
            var executor = Executor.init(rt.arena);
            break :blk try executor.executeWat(wat);
        },
    };
}
```

**Result**: Can run `cljw -Dbackend=wasmgc -e "(+ 1 2)"` → returns 42 (hardcoded)

### Phase 3: Add Simple WAT Generation (2-4 hours)

Don't fix the 6,069 LOC compiler. Instead, create **minimal** WAT generator:

```zig
fn generateSimpleWat(ast: *Node) ![]const u8 {
    return switch (ast.tag) {
        .int_literal => std.fmt.allocPrint("(i64.const {d})", .{ast.value}),
        .add => generateBinaryOp("+", ast.left, ast.right),
        // Just enough to test 5-10 simple expressions
        else => error.NotImplemented,
    };
}
```

**Goal**: Get 5-10 test cases working, NOT all 1,242

### Phase 4: Value Marshalling (4-6 hours)

Handle more than just i64:

```zig
fn parseWasmResult(stdout: []const u8) !Value {
    // Parse wasmtime output
    // Convert to ClojureWasm Value
    // Support: i64, f64, strings (future: collections)
}
```

---

## Current Status

| Component | Status | Evidence |
|-----------|--------|----------|
| **WAT Execution** | ✅ PROVEN | poc_wasmgc_executor.sh works |
| **wasm-tools** | ✅ Installed | v1.262.0 via homebrew |
| **wasmtime** | ✅ Available | Returns results successfully |
| **executor.zig** | ⏸ Not started | Architecture proven, ready to implement |
| **evalForm() integration** | ⏸ Not started | Trivial wiring once executor exists |
| **Simple WAT gen** | ⏸ Not started | Don't touch 6,069 LOC compiler |
| **Value marshalling** | ⏸ Not started | Start with i64 only |

---

## Revised Goals

### Original Goal (Too Ambitious)
❌ Fix 6,069 LOC compiler  
❌ Achieve 1,242/1,242 tests passing  
❌ 10 weeks of effort  

### Realistic Goal (Path B PoC)
✅ Prove execution architecture (DONE!)  
⏸ Get 5-10 simple tests working  
⏸ Demonstrate evalForm() integration  
⏸ Document what's needed for full implementation  

**Effort**: 8-12 hours, not 10 weeks

---

## Next Immediate Step

Create `src/eval/backend/wasmgc/executor.zig` with:

```zig
const std = @import("std");
const Value = @import("../../runtime/value/value.zig").Value;

pub const Executor = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Executor {
        return .{ .allocator = allocator };
    }
    
    pub fn executeWat(self: *Executor, wat: []const u8) !Value {
        // Implementation based on proven PoC
        // 1. Write WAT to /tmp/cljw_eval_XXXXX.wat
        // 2. wasm-tools parse → .wasm
        // 3. wasmtime run --invoke main
        // 4. Parse output → Value.encodeInt()
    }
};
```

**Then**: Wire into evalForm() and test with simple expressions

---

## Dependencies Installed

- ✅ wasm-tools v1.262.0 (via homebrew)
- ✅ wasmtime (system dependency)
- ✅ zwasm v2.7.0 (upgraded in build.zig.zon)

---

## Success Criteria (Revised)

**Minimal Success** (8-12 hours):
- [ ] executor.zig implemented
- [ ] evalForm() wired up
- [ ] Can evaluate: `(+ 1 2)`, `(- 5 3)`, `42`, `"hello"`
- [ ] Returns proper ClojureWasm Values
- [ ] Proves architecture works

**Full Success** (10 weeks, separate effort):
- [ ] Fix 6,069 LOC compiler OR rewrite minimal compiler
- [ ] Implement all 40+ host functions
- [ ] Comprehensive Value marshalling
- [ ] 1,242/1,242 tests passing

**Current Target**: Minimal Success

---

## Key Insight

**We don't need to fix the broken 6,069 LOC compiler to prove the architecture works.**

Instead:
1. ✅ Prove execution works (DONE via PoC)
2. ⏸ Create minimal executor wrapper
3. ⏸ Wire into evalForm()
4. ⏸ Generate simple WAT for 5-10 test cases
5. ⏸ Document findings

**Then**: Decide whether to fix existing compiler or start fresh.

---

## Files Created

- `poc_wasmgc_executor.sh` - Shell-based proof of concept (✅ WORKING)
- `poc_wasmgc_executor.zig` - Attempted Zig version (❌ API issues, abandoned)

**Next**: `src/eval/backend/wasmgc/executor.zig` (not started)
