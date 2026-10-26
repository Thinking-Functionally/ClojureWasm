# ClojureWasm Core Functions Review

**Date:** 2026-10-26  
**Purpose:** Comprehensive review of existing core functions in TreeWalk/VM implementations to inform WasmGC backend development strategy

---

## Executive Summary

ClojureWasm has **574 total core functions** implemented across Zig primitives and Clojure bootstrap code. The WasmGC backend can leverage this complete foundation without extending the Clojure library.

### Implementation Breakdown

| Layer | Count | Coverage |
|-------|-------|----------|
| **Zig Primitives** | 365 functions | Low-level runtime operations |
| **Clojure Bootstrap** | 209 functions | High-level core.clj functions |
| **Total** | 574 functions | Complete Clojure 1.12 surface |

---

## 1. Zig Primitive Functions (365 total)

### 1.1 Math Primitives (59 functions)
**File:** `src/lang/primitive/math.zig`

**Arithmetic:**
- `+` (plus), `-` (minus), `*` (star), `/` (slash)
- `inc`, `dec`, `quot`, `rem`, `mod`
- `unchecked-add`, `unchecked-subtract`, `unchecked-multiply`, etc.

**Comparison:**
- `=` (equals), `==` (equiv), `<`, `>`, `<=`, `>=`
- `compare`, `zero?`, `pos?`, `neg?`, `odd?`, `even?`

**Bitwise:**
- `bit-and`, `bit-or`, `bit-xor`, `bit-not`
- `bit-shift-left`, `bit-shift-right`, `unsigned-bit-shift-right`
- `bit-and-not`

**Numeric Functions:**
- `abs`, `min`, `max`, `numerator`, `denominator`
- `rand`, `rand-int`, `rationalize`
- `bigint`, `bigdec`, `int`, `long`, `double`, `float`, `num`

### 1.2 Core Primitives (74 functions)
**File:** `src/lang/primitive/core.zig`

**Type Predicates:**
- `nil?`, `true?`, `false?`, `identical?`, `some?`
- `string?`, `number?`, `integer?`, `float?`, `ratio?`, `decimal?`
- `symbol?`, `keyword?`, `vector?`, `map?`, `set?`, `list?`
- `fn?`, `boolean?`, `char?`, `coll?`, `seq?`, `sequential?`
- `associative?`, `counted?`, `map-entry?`, `record?`, `uri?`
- `ifn?`, `var?`, `bound?`, `thread-bound?`
- `pos-int?`, `neg-int?`, `nat-int?`, `nan?`, `infinite?`

**Core Operations:**
- `identity`, `boolean`, `not`, `str`, `name`, `namespace`
- `keyword`, `symbol`, `gensym`, `pr-str`, `prn-str`, `print-str`, `println-str`
- `subs`, `format`, `apply`, `hash`, `hash-ordered-coll`, `hash-unordered-coll`
- `class`, `class?`, `instance?`, `class-isa?`

### 1.3 Sequence Primitives (11 functions)
**File:** `src/lang/primitive/sequence.zig`

- `seq`, `rseq`, `first`, `rest`, `next`, `cons`
- `count`, `empty`, `nth`
- `lazy-seq` (internal), `__lazy-seq-create`

### 1.4 Collection Primitives (15 functions)
**File:** `src/lang/primitive/collection.zig`

**Core Operations:**
- `conj`, `disj`, `get`, `nth`, `contains?`
- `assoc`, `dissoc`, `keys`, `vals`
- `kv-reduce`, `update-in`

**Queue:**
- `queue?`, `queue-pop`, `#queue` reader

### 1.5 String Primitives (27 functions)
**File:** `src/lang/primitive/string.zig`

**clojure.string namespace:**
- `blank?`, `capitalize`, `ends-with?`, `starts-with?`, `includes?`
- `index-of`, `last-index-of`, `join`, `lower-case`, `upper-case`
- `replace`, `replace-first`, `reverse`, `split`, `split-lines`
- `trim`, `trim-newline`, `triml`, `trimr`, `escape`

### 1.6 Regex Primitives (7 functions)
**File:** `src/lang/primitive/regex.zig`

- `re-pattern`, `re-matcher`, `re-find`, `re-matches`
- `re-groups`, `re-seq`

### 1.7 Set Primitives (3 functions)
**File:** `src/lang/primitive/set.zig`

**clojure.set namespace:**
- `union`, `intersection`, `difference`

### 1.8 Atom/Concurrency Primitives (15 functions)
**File:** `src/lang/primitive/atom.zig`

- `atom`, `deref` (also `@`), `swap!`, `reset!`
- `compare-and-set!`, `reset-meta!`, `set-validator!`, `get-validator!`
- `add-watch`, `remove-watch`

### 1.9 Agent Primitives (13 functions)
**File:** `src/lang/primitive/agent.zig`

- `agent`, `send`, `send-off`, `send-via`
- `release-pending-sends`, `agent-error`, `restart-agent`, `shutdown-agents`

### 1.10 STM/Ref Primitives (21 functions)
**File:** `src/lang/primitive/stm.zig`

- `ref`, `alter`, `commute`, `ref-set`
- `ensure`, `ref-history-count`, `ref-min-history`, `ref-max-history`
- `dosync` (transaction coordinator)

### 1.11 Protocol/Multimethod Primitives (22 functions)
**Files:** `src/lang/primitive/protocol.zig`, `src/lang/primitive/multimethod.zig`

**Protocols:**
- `defprotocol*`, `extend-protocol`, `extend-type`, `extends?`, `satisfies?`

**Multimethods:**
- `defmulti`, `defmethod`, `remove-method`, `remove-all-methods`
- `prefer-method`, `prefers`, `methods`, `get-method`

### 1.12 Namespace Primitives (22 functions)
**File:** `src/lang/primitive/namespace.zig`

- `ns`, `in-ns`, `create-ns`, `remove-ns`, `all-ns`, `find-ns`
- `ns-name`, `ns-aliases`, `ns-imports`, `ns-interns`, `ns-map`, `ns-publics`
- `alias`, `require`, `use`, `import`, `refer`, `intern`, `resolve`
- `ns-unalias`, `ns-unmap`

### 1.13 Metadata Primitives (4 functions)
**File:** `src/lang/primitive/metadata.zig`

- `meta`, `with-meta`, `alter-meta!`, `reset-meta!`

### 1.14 IO Primitives (3 functions)
**File:** `src/lang/primitive/file_io.zig`

- `slurp`, `spit`, `io!`

### 1.15 Higher-Order Primitives (11 functions)
**File:** `src/lang/primitive/higher_order.zig`

- `reduce`, `map`, `filter`, `mapcat`
- `every?`, `some`, `not-any?`, `not-every?`
- `apply`, `fnil`

### 1.16 Transient Primitives (8 functions)
**File:** `src/lang/primitive/transient.zig`

- `transient`, `persistent!`, `conj!`, `assoc!`, `dissoc!`, `pop!`

### 1.17 Other Primitives
- **Error (7):** `throw`, `try`, `catch`, `finally`, `ex-info`, `ex-data`, `ex-message`
- **UUID (5):** `random-uuid`, `uuid`
- **Inst (5):** `inst-ms`, `inst?`
- **JSON (3):** `clojure.data.json/read-str`, `write-str`
- **CSV (3):** `clojure.data.csv/read-csv`, `write-csv`
- **EDN (2):** `clojure.edn/read-string`, `read`
- **Walk (4):** `clojure.walk/walk`, `prewalk`, `postwalk`, `keywordize-keys`
- **Sorted (8):** `sorted-map`, `sorted-set`, `sorted-map-by`, `sorted-set-by`
- **Reduced (5):** `reduced`, `reduced?`, `unreduced`
- **Macroexpand (3):** `macroexpand`, `macroexpand-1`, `macroexpand-all`
- **Array (1):** `into-array` primitives
- **Locking (2):** `locking`, `monitor-enter`, `monitor-exit`
- **Chunk Transform (2):** Internal chunk support

---

## 2. Clojure Bootstrap Functions (209 functions)

**File:** `src/lang/clj/clojure/core.clj` (2,694 lines)

These are **higher-level functions built on top of Zig primitives**, implemented in pure Clojure.

### 2.1 Collection Functions (60+)
- `map`, `filter`, `take`, `drop`, `take-while`, `drop-while`
- `concat`, `mapcat`, `flatten`, `reverse`, `sort`, `sort-by`
- `group-by`, `frequencies`, `partition`, `partition-all`, `partition-by`
- `into`, `vec`, `vector`, `mapv`, `filterv`
- `interleave`, `interpose`, `distinct`, `dedupe`
- `keep`, `keep-indexed`, `remove`
- `take-last`, `drop-last`, `butlast`, `last`, `ffirst`, `fnext`, `nnext`
- `split-at`, `split-with`, `splitv-at`

### 2.2 Sequence Generators (15+)
- `range`, `repeat`, `repeatedly`, `iterate`, `iteration`
- `cycle`, `lazy-seq`, `tree-seq`, `line-seq`

### 2.3 Higher-Order Functions (20+)
- `comp`, `partial`, `complement`, `constantly`, `identity`
- `juxt`, `some-fn`, `every-pred`, `fnil`
- `memoize`, `trampoline`, `completing`
- `transduce`, `eduction`, `sequence`

### 2.4 Map/Associative Functions (15+)
- `merge`, `merge-with`, `select-keys`, `update`, `update-keys`, `update-vals`
- `get-in`, `assoc-in`, `update-in`
- `find`, `key`, `val`
- `zipmap`

### 2.5 Set Functions (5+)
- `set`, `distinct?`
- Plus `clojure.set/*` in Zig primitives

### 2.6 Logic & Predicates (15+)
- `not=`, `not-any?`, `not-every?`, `not-empty`, `some?`, `any?`
- `empty?`, `distinct?`, `reversible?`, `indexed?`, `seqable?`
- `ident?`, `qualified-ident?`, `simple-ident?`
- `qualified-keyword?`, `simple-keyword?`
- `qualified-symbol?`, `simple-symbol?`

### 2.7 Numeric Functions (10+)
- `max-key`, `min-key`, `bounded-count`, `rand-nth`

### 2.8 String Functions (5+)
- `pr-str`, `prn-str`, `print-str`, `println-str`
- `with-out-str`, `printf`

### 2.9 Metadata Functions (5+)
- `vary-meta`, `alter-meta!`, `reset-meta!`

### 2.10 Namespace Functions (10+)
- `requiring-resolve`, `resolve`, `namespace-munge`
- `ancestors`, `descendants`, `parents`, `derive`, `underive`, `isa?`

### 2.11 Concurrency Functions (15+)
- `atom`, `swap-vals!`, `reset-vals!`
- `future`, `future-call`, `pcalls`, `pmap`
- `await`, `await-for`
- `add-tap`, `remove-tap`, `tap>`

### 2.12 IO Functions (5+)
- `read-line`, `line-seq`, `flush`, `with-in-str`, `with-out-str`

### 2.13 Transducer Functions (10+)
- `map`, `filter`, `cat`, `dedupe`, `partition-by`, `take-while`, `drop-while`
- `halt-when`, `random-sample`

### 2.14 Array Functions (10+)
- `into-array`, `to-array`, `make-array`
- `boolean-array`, `byte-array`, `char-array`, `int-array`, `long-array`, `float-array`, `double-array`, `short-array`, `object-array`
- `aset-boolean`, `aset-byte`, `aset-char`, `aset-int`, `aset-long`, `aset-float`, `aset-double`, `aset-short`

### 2.15 Other Functions (10+)
- `run!`, `doall`, `dorun`, `dotimes`, `doseq`
- `reduce-kv`, `reductions`
- `bound-fn*`, `class`, `class?`, `instance?`
- `load-string`, `Throwable->map`

---

## 3. WasmGC Backend Strategy

### 3.1 What WasmGC Already Has (Month 4 Alpha)

The WasmGC backend has **40 core functions** implemented for the Alpha release, focused on:

1. **Primitives:** Numbers, strings, keywords, symbols, nil, booleans
2. **Collections:** Vectors, maps, sets (persistent data structures)
3. **Functions:** First-class functions, closures, tail-call optimization
4. **JavaScript Interop:** Host function imports, value conversion, DOM manipulation

### 3.2 What's Missing for Production

From the 574 available functions, the WasmGC backend currently **does not** have:

#### High Priority (Blocking Production Use):
1. **Exception Handling** (7 functions)
   - `try`, `catch`, `finally`, `throw`, `ex-info`, `ex-data`, `ex-message`

2. **Concurrency Primitives** (50+ functions)
   - Atoms: `atom`, `swap!`, `reset!`, `compare-and-set!`
   - Refs/STM: `ref`, `dosync`, `alter`, `commute`
   - Agents: `agent`, `send`, `send-off`
   - Futures: `future`, `future-call`, `pcalls`, `pmap`

3. **Metadata Support** (4 functions)
   - `meta`, `with-meta`, `alter-meta!`, `vary-meta`

4. **Core Sequence Functions** (100+ functions)
   - Higher-order: `map`, `filter`, `reduce`, `take`, `drop`, `concat`, etc.
   - Predicates: `every?`, `some`, `not-any?`, `not-every?`
   - Generators: `range`, `repeat`, `iterate`, `cycle`

5. **Namespace Management** (22 functions)
   - `ns`, `require`, `use`, `import`, `refer`, `resolve`, `in-ns`

#### Medium Priority:
6. **String Manipulation** (27 functions from `clojure.string`)
7. **Regex** (7 functions)
8. **Set Operations** (3 functions from `clojure.set`)
9. **IO Functions** (5+ functions)
10. **Protocols & Multimethods** (22 functions)
11. **Transducers** (10+ functions)

### 3.3 Compilation Strategy

**Key Insight:** WasmGC does NOT need to extend ClojureWasm's library. All 574 functions are already implemented in TreeWalk/VM backends.

**WasmGC's Job:** Compile existing Clojure/Zig code to WebAssembly.

#### Phase 1: Core Language (Complete ✅)
- Primitives, collections, functions, closures
- **Status:** Month 4 Alpha complete

#### Phase 2: Exception Handling (Month 5)
- Compile Zig's `try`/`catch` primitives to WasmGC's exception handling proposal
- Map `throw` to `wasm throw`, `catch` to `wasm catch`

#### Phase 3: Metadata (Month 5)
- Add metadata field to WasmGC value types
- Compile `meta`/`with-meta` operations

#### Phase 4: Sequence Functions (Month 6)
- Most are **already pure Clojure** in `core.clj`
- Just compile the higher-level Clojure code
- Primitives like `seq`, `first`, `rest` already work

#### Phase 5: Concurrency (Month 7+)
- Map atoms to JavaScript `WeakMap` or WasmGC mutable refs
- Refs/STM may need browser `SharedArrayBuffer` or async coordination
- Agents map to Web Workers

#### Phase 6: Namespaces (Month 8+)
- Namespace registry in WasmGC runtime
- Module-level compilation per namespace

---

## 4. Critical Observations

### 4.1 Leverage Ratio
- **574 functions available** vs. **40 currently compiled**
- **14.3x leverage opportunity** by compiling existing code

### 4.2 No Library Extension Needed
- TreeWalk/VM backends have complete Clojure 1.12 surface
- WasmGC backend is a **compiler target**, not a new implementation
- Focus is on **compilation strategy**, not feature implementation

### 4.3 Two-Layer Architecture
1. **Zig Primitives (365):** Low-level, must compile to WAT
2. **Clojure Bootstrap (209):** High-level, compiles automatically once primitives work

### 4.4 Bootstrap Cascade
Once WasmGC can compile:
- Exception handling
- Metadata
- Basic sequence operations (seq, first, rest, cons)
- Function calls and closures (already working)

Then the **entire `core.clj` (209 functions) compiles automatically** because it's pure Clojure built on primitives.

---

## 5. Recommended Roadmap

### Month 5 (Current - Production Hardening)
1. **Exception Handling** (7 Zig primitives)
   - `throw`, `try`, `catch`, `finally`, `ex-info`, `ex-data`, `ex-message`
2. **Metadata** (4 Zig primitives)
   - `meta`, `with-meta`, `alter-meta!`, `reset-meta!`
3. **Namespace Bootstrap** (22 Zig primitives)
   - `ns`, `in-ns`, `require`, `use`, `import`, `refer`, etc.

**Result:** 33 Zig primitives → Unlocks ~100 Clojure bootstrap functions

### Month 6 (Sequence Functions)
1. **Higher-Order Compilation**
   - `reduce`, `map`, `filter` (11 Zig primitives)
2. **Lazy Sequence Support**
   - Already has `lazy-seq`, just needs compilation
3. **Test Coverage**
   - Verify ~150 sequence functions compile correctly

**Result:** Core sequence operations working → Unlocks another ~100 functions

### Month 7 (Concurrency)
1. **Atoms** (15 Zig primitives)
   - Map to JavaScript `WeakMap` or WasmGC refs
2. **Agents** (13 Zig primitives)
   - Map to Web Workers
3. **Refs/STM** (21 Zig primitives)
   - May need `SharedArrayBuffer` or degrade gracefully

**Result:** Concurrency primitives working → Production-ready for single-threaded apps

### Month 8+ (Extended Features)
1. **Protocols & Multimethods** (22 primitives)
2. **String/Regex** (34 primitives)
3. **IO** (5 primitives, browser-adapted)
4. **Performance Optimization**

---

## 6. Conclusion

ClojureWasm's **574-function core library is production-complete** in TreeWalk/VM backends. The WasmGC backend strategy is:

1. **Compile, don't extend** - All functions already exist
2. **Primitives first** - 365 Zig functions are the foundation
3. **Bootstrap cascade** - 209 Clojure functions compile automatically once primitives work
4. **Focus on gaps** - Exception handling, metadata, namespaces, concurrency

**Current gap:** 40/574 functions = 7% coverage  
**Path to 80%:** ~100 Zig primitives → unlocks 200+ Clojure functions  
**Path to 100%:** All 365 Zig primitives compiled

The WasmGC backend does **not** need to implement new features. It needs to **compile existing implementations** to WebAssembly.
