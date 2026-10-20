# D-581: zwasm v2.5.0 Host Imports Discovery

**Status**: Accepted  
**Date**: 2026-10-20  
**Supersedes**: Previous assumption that zwasm v2.5.0 lacked host import capabilities

## Context

D-579/D-580 define collection literal and accessor host imports for ClojureWasm.
Initial investigation assumed zwasm v2.5.0 (F-001 FINAL pin) lacked the necessary
APIs to implement these host imports in native Zig code.

## Discovery

After examining zwasm v2.5.0 source code, discovered that ALL necessary APIs exist:

1. **Linker.defineFunc()** - Register host functions with comptime signature derivation
2. **Caller** - Host function execution context (passed as first parameter)
3. **Caller.memory()** - Access guest linear memory from host code
4. **Memory.read/write/slice()** - Typed linear memory access
5. **wasm_memory_data()** - Standard wasm.h C API (always present)

## Decision

Implement D-579/D-580 host imports in Zig using zwasm v2.5.0 APIs:

### Host Function Signature Pattern
```zig
fn hostFunc(caller: *zwasm.Caller, param1: i32, param2: i64) i64 {
    const mem = caller.memory() orelse return nan_box_nil();
    const data = mem.read(i64, @intCast(param1)) catch return nan_box_nil();
    // ... process data ...
    return result;
}
```

### Implementation Files
- `src/eval/backend/wasm/wasm_host_imports.zig` - Host function implementations
- `src/eval/backend/wasm/wasm_executor.zig` - Linker setup + registration
- Registration via `registerHostImports(&linker)` before instantiation

## Implications

✅ **Preserves F-001**: No zwasm upgrade needed, v2.5.0 FINAL pin intact  
✅ **Proper architecture**: Centralized host imports, smaller wasm modules  
✅ **Local execution**: Native Zig implementation for local zwasm execution  
✅ **Workers deployment**: Existing JS implementation (workers/cljw_runtime.js) unchanged  

## Two-Runtime Strategy

1. **Local zwasm** - Native Zig host imports (this decision)
2. **Cloudflare Workers** - JS runtime implementation (already complete)

Both paths support the same D-579/D-580 contract.

## Next Steps

1. ✅ Implement host functions with Caller.memory() access
2. [ ] Update wasm_executor.zig to setup Linker + register imports
3. [ ] Update wasm_module_builder.zig to emit import declarations
4. [ ] Test with P99 suite
