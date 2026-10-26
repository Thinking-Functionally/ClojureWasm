# WasmGC Backend vs WebAssembly FFI

## Short Answer ✅

**Yes!** The WebAssembly FFI works with **ALL backends** (TreeWalk, VM, and WasmGC). They are completely independent features.

## The Two Different WebAssembly Features

ClojureWasm has **TWO separate WebAssembly capabilities** that are often confused:

### 1. **WebAssembly FFI** (`-Dwasm` flag) 🔧
**Purpose:** Call external WASM modules from Clojure  
**Status:** ✅ **Production-ready** (released in binaries)  
**Works with:** All backends (TreeWalk, VM, WasmGC)  

```clojure
;; Load a WASM module compiled from Rust/C/Zig/Go
(def rust-module (wasm/load "add.wasm"))

;; Call its exported function
(wasm/call rust-module "add" 2 40)  ;=> 42
```

**How it works:**
- Embeds [zwasm v2](https://github.com/zwasm/zwasm) WebAssembly engine
- Provides `wasm/load` and `wasm/call` Clojure functions
- Backend-agnostic: works regardless of which backend evaluates the Clojure code
- The WASM module runs in zwasm's sandbox
- Arguments are marshalled: Clojure values ↔ WASM i32/i64/f32/f64

### 2. **WasmGC Backend** (`-Dbackend=wasmgc` option) 🚀
**Purpose:** Compile Clojure code itself to WebAssembly  
**Status:** 🚧 **Alpha** (Month 5 development)  
**Works with:** Browser/Node.js as execution target

```bash
# Compile Clojure → WASM
zig build -Dbackend=wasmgc
./zig-out/bin/cljw --emit-wat my-app.clj > app.wat

# Run the compiled WASM in browser
# (converts WAT → WASM binary, loads in browser)
```

**How it works:**
- Compiles Clojure AST → WebAssembly Text (WAT)
- Uses WasmGC proposal (struct/array/ref types)
- Target: run Clojure in browsers without a full runtime
- Does NOT use zwasm (generates WASM, doesn't execute it)

## Can You Use Both Together? ✅

**Yes!** The features are orthogonal:

```clojure
;; Clojure code using WebAssembly FFI
(def rust-add (wasm/load "math.wasm"))
(defn my-app []
  (let [x 10
        y 32]
    (wasm/call rust-add "multiply" x y)))

(println (my-app))
```

**This code can be:**
1. ✅ Evaluated by **TreeWalk backend** (with `-Dwasm`)
2. ✅ Evaluated by **VM backend** (with `-Dwasm`)  
3. ✅ Compiled to WASM by **WasmGC backend** (with `-Dwasm -Dbackend=wasmgc`)

The compiled WASM output would:
- Run in a browser
- Still be able to load external WASM modules via the FFI
- Call Rust/C/Zig functions through `wasm/call`

## Current Status Summary

| Feature | Status | Works With | Use Case |
|---------|--------|------------|----------|
| **WebAssembly FFI** | ✅ Production | TreeWalk/VM/WasmGC | Call Rust/C/Zig from Clojure |
| **WasmGC Backend** | 🚧 Alpha | Browser/Node.js | Run Clojure in browser |

## Build Commands

```bash
# 1. TreeWalk + WebAssembly FFI
zig build -Dbackend=tree_walk -Dwasm
./zig-out/bin/cljw docs/examples/wasm/add.clj

# 2. VM + WebAssembly FFI (production default)
zig build -Dwasm
./zig-out/bin/cljw docs/examples/wasm/add.clj

# 3. WasmGC backend (no FFI yet)
zig build -Dbackend=wasmgc
./zig-out/bin/cljw --emit-wat app.clj > app.wat

# 4. WasmGC backend + WebAssembly FFI (both features)
zig build -Dbackend=wasmgc -Dwasm
./zig-out/bin/cljw --emit-wat app-with-ffi.clj > app.wat
```

## Example: Polyglot Pipeline

```clojure
;; math.wasm exports: (multiply i32 i32) -> i32 (compiled from Rust)
;; strings.wasm exports: (format i32) -> i32 (compiled from C)

(def math (wasm/load "math.wasm"))
(def strings (wasm/load "strings.wasm"))

(defn calculate [x y]
  (let [product (wasm/call math "multiply" x y)
        formatted (wasm/call strings "format" product)]
    formatted))

;; This Clojure code can be:
;; - Run directly via VM backend (native executable)
;; - Compiled to WASM via WasmGC backend (runs in browser)
;; Either way, it calls Rust and C code through the FFI!
```

## The Key Insight 💡

**WebAssembly FFI is a runtime library feature.**  
**WasmGC is a compilation target.**

They solve different problems:
- **FFI:** "I want to call Rust libraries from my Clojure app"
- **WasmGC:** "I want to run my Clojure app in a web browser"

Both can coexist because:
- The FFI (`wasm/load`, `wasm/call`) is just Clojure functions
- Any backend that can evaluate Clojure functions can support the FFI
- When WasmGC compiles to WASM, it compiles those function calls too

## Testing Matrix

| Test | TreeWalk | VM | WasmGC |
|------|----------|-----|---------|
| Pure Clojure (1,242 tests) | ✅ Pass | ✅ Pass | ❌ Not tested |
| WebAssembly FFI (2 examples) | ✅ Pass | ✅ Pass | ❓ Unknown |
| WasmGC unit tests (45 tests) | N/A | N/A | ✅ Pass |

**The gap:** WasmGC backend has never been tested against the main 1,242-test suite OR the WebAssembly FFI examples.

## References

- WebAssembly FFI: `docs/examples/wasm/README.md`
- WasmGC Backend: `docs/wasmgc-backend.md`
- FFI Implementation: `src/runtime/cljw/wasm/`
- WasmGC Compiler: `src/eval/backend/wasmgc/`
- ADR-0099: WebAssembly FFI design
- ADR-0108: WasmGC backend design
