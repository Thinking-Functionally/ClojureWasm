# WasmGC backend — status

Branch: `feature/wasmgc-simple`. Numbers below were measured, not estimated.

## What it is

One `cljw` binary contains three evaluation backends: `tree_walk`, `vm`,
`wasmgc`. Pick one per run, no rebuild:

```
cljw --backend=wasmgc -e '(+ 1 2)'     # or: --backend wasmgc
CLJW_BACKEND=wasmgc cljw -e '(+ 1 2)'  # env var, for harnesses/CI
```

Precedence: `--backend` flag, then `CLJW_BACKEND`, then the build default
(`-Dbackend`, default `vm`). `cljw --version` names the effective backend.
`-Dwasm` only gates the polyglot Wasm-FFI namespace; WasmGC does not need it.

## Pipeline

`src/eval/backend/wasmgc.zig` is the entry point (like `tree_walk.zig`,
`vm.zig`); `driver.evalForm` calls `evalNode` per top-level form.

```
Clojure -> Reader/Analyzer -> Node (25 kinds, all compiled)
        -> WAT text -> wasm-tools parse -> WASM binary -> zwasm instance -> Value
```

- Values inside WASM are i32 handles into a host table (fixed buffer, published
  to the GC as a root frame while WASM runs; loop back-edges reclaim handles).
- Clojure `fn` bodies are exported WASM functions stamped onto ordinary
  `Function` objects via `FunctionMethod.native`, so `fn?`, metadata, protocols
  and callbacks from `map`/`reduce` work unchanged.
- `try/catch/finally`, `binding`, `def`, literals, interop and calls use host
  imports (module `h`). `clojure.core` and other library functions are reached
  through those imports (VM bytecode / Zig builtins) for user programs.
- Threads: one zwasm instance per thread (instances are not re-entrant across
  threads). zwasm caps an instance at 256 wasm frames, so activations continue
  on a fresh instance every 100 levels.
- Memory: forms that define no function free everything on return; function-
  defining forms keep only the `.wasm` bytes and are LRU-evicted/revived
  (64 live instances per thread).
- `wasm-tools` must be on `PATH`.

## Results (single build, backend chosen at runtime)

| Check | tree_walk | vm | wasmgc |
|---|---|---|---|
| `zig build test` (main unit suite) | n/a | 1250/1250 | 1250/1250 |
| `test/e2e/*.sh` scripts | 398/403 | 398/403 | 395/403 |
| golden corpus replay (4347 cases) | 4347/4347 | 4347/4347 | 4347/4347 |

- Unit suite wall time / peak RSS: vm 3 min / 3 GB; wasmgc 11 min / 10 GB
  (loads `clojure.core` from source through the WasmGC compiler).
- e2e: 5 scripts fail on every backend under the harness (`phase14_eval`,
  `phase16_wasm_run_output_cap`, `phase4_cli`, `phase4_exit`,
  `phase4_exit_codes`). 3 more fail only on wasmgc because they run `zig build`
  themselves and so replace the binary under test (`entrypoint_eval_parity`,
  `phase14_cljw_build`, `phase8_compare_cli`).

Reproduce: `BACKEND=wasmgc bash test/wasmgc_baseline.sh` (also `vm`,
`tree_walk`; optional script-name substring). Results in
`/tmp/<backend>_baseline/summary.tsv`. Unit suite:
`CLJW_BACKEND=wasmgc zig build test -Dwasm`. Corpus:
`CLJW_BACKEND=wasmgc bash scripts/check_corpus_regression.sh`.

## Known gaps

- Recursion depth: ~36 KB native stack per Clojure call level (zwasm
  interpreter), so about 170 levels under the 6 MiB budget versus thousands on
  the VM. `phase15_watch_recursion.sh` and `phase16_gc_torture.sh` use smaller
  depths for wasmgc, as they already do for tree_walk.
- `clojure.core` is not natively WasmGC for user programs (host imports);
  the backend is not standalone.
- Slower and larger than the VM (see unit-suite figures above).
- Per-form `wasm-tools` subprocess (needs `wasm-tools` on `PATH`).
- `e2e_phase14_eval` (3 of 21 cases) fails on every backend. Verified
  pre-existing: passes on clean `main`, fails at `dcd93cd4` (see below). Not a
  WasmGC regression, and not fixed here.
- `accepted_divergences` and `compat_members` gate steps fail on this machine
  only because `yq` is not installed.

## Gate and differential coverage

`test/clj/` (see its README) is a self-contained `clojure.test` suite run on all
three backends by `test/clj/run.sh`, which requires byte-identical results; with
`--jvm` the same source also runs on JVM Clojure as the oracle. Current suites
(assertions): tier_a 13, features 18 (needs `eval`), regression 10, p99_lists 102
(L-99 P01-P28), p99_arithmetic 43 (P31-P41), p99_logic 65 (P46-P50), p99_trees 154
(P54-P69), p99_multitrees 32 (P70-P73), p99_graphs 66 (P80-P89), p99_puzzles 62
(P90-P99), fourclojure 302 (problems 1-98 except 72 and 87, which the skeleton omits);
The latest default Debug run passed all 11 suites on tree_walk, vm and wasmgc
in 460 seconds, skipping two explicit slow suites: p99_arithmetic_slow (6
assertions) and p99_puzzles_slow (20 assertions). The latter includes 6x6/8x8
knight tours that exceed the WasmGC native-stack budget in Debug; moving them
out of the default gate does not fix that backend limitation.

Before the latest arithmetic split, all suites including the puzzle slow suite
passed on the three ReleaseSafe backends and JVM Clojure in about 31 seconds.
After the arithmetic split, a rebuilt ReleaseSafe binary passed all 13 suites
(slow ones included) on tree_walk, vm, wasmgc and JVM Clojure in 34 seconds:
`CLJW_BIN=<release-binary> bash test/clj/run.sh --all-backends --jvm --include-slow`.
The suite found two real bugs: `empty` raised on ranges and every lazy seq (now `()`
like JVM, with a differential case), and wasmgc died with `OutOfFuel` after zwasm's
default 1e9 instructions (now unmetered; the Clojure eval budget still bounds runaway
code). Gate steps: `test_clj_tier_a`, `test_clj_suites`.

Full `test/run_all.sh` at `c5f7742b` (this machine, 22.5 min): **439 passed, 3
failed**, all three failures outside the WasmGC work:
- `accepted_divergences` and `compat_members`: `yq` is not installed here.
- `e2e_phase14_eval` (3 of 21 cases): verified pre-existing. It passes 15/15 on
  clean `main`, and fails identically at `dcd93cd4` (the fork's own 2023-10-13
  "use rt.load_arena" commit that added those 3 cases), before any WasmGC code
  existed. The eval'd-function-survives-GC cases return empty output on the
  tree-walk build; the underlying eval use-after-free fix looks incomplete.
  Not touched here.

`zig_build_test_wasmgc` (271 s), `corpus_regression_wasmgc`, `backend_diff_three_way`,
`e2e_wasmgc` (allow-list) and `test_clj_suites` all pass.

`test/run_all.sh` runs: `zig_build_test_wasmgc` (same test binary,
`CLJW_BACKEND=wasmgc`), `corpus_regression_tree_walk`, `corpus_regression_wasmgc`,
`backend_diff_three_way` (118 cases in `test/diff/backends/`, one process per
backend; 2 accepted pre-existing TreeWalk/VM divergences in
`known_divergences.txt`), `e2e_wasmgc_backend_smoke` and `e2e_wasmgc` (sandboxed
harness with the allow-list `test/wasmgc_known_failures.txt`).
`cljw --compare` runs all three backends in-process (heap values and errors
report MISMATCH there by design; use `check_backend_diff.sh` for semantics).

## Recursion depth (measured 2026-10-29/30, ReleaseSafe, one machine)

Direct recursion `(defn f [n] (if (zero? n) 0 (inc (f (dec n)))))`, maximum
depth before `StackOverflowError`:

| Platform | Depth |
|---|---|
| JVM Clojure (Java 25) | ~214,000 (through `map`: ~2.8k cold, ~7.7k warm) |
| ClojureScript on Node/V8 | ~9,700 (through `map`: ~1,100) |
| Raw wasm in V8, small frame | ~10,400 (frame with 14 extra locals: ~4,800; 30: ~3,000) |
| Wasm calling back through a JS import | ~900 |
| cljw TreeWalk | 225 before, **59,200** now (through `map`: 2,000 before, 16,000 now) |
| cljw WasmGC | 168 before, **15,200** now (bound by zwasm's interpreter loop, see below) |
| cljw VM | 2,000 before, **16,000** now (through `map`: 8,000) |

All three backends now clear ClojureScript's ~9,700. Where the depth comes from:

- **Stack budget** (`src/runtime/stack_guard.zig`): each thread's budget is
  derived from its real stack. The program runs on a 512 MiB thread, workers get
  128 MiB, anything else keeps 6 MiB. `CLJW_STACK_MB` (16..4096) overrides the
  main stack. A runaway recursion fills the stack before the catchable overflow
  (TreeWalk ~524 MB, WasmGC ~770 MB at 512 MiB), so lower it for small
  containers: at 128 MiB TreeWalk still reaches 14,800 and peaks at ~140 MB.
- **TreeWalk frames**: a call cost ~27 KB of native stack because `evalCall`
  carried worst-case argument buffers (8.7 KB, twice per call) and
  `callMethodImpl` a 256-slot locals array. Both are now sized to the call
  (non-inlined comptime variants), ~9 KB per call. Per-function frame sizes can
  be re-measured with `zig build -Doptimize=ReleaseSafe -Dprofile=true` and
  `otool -tV` (look for `sub sp, sp, #N`).
- **VM**: `FRAMES_MAX` 2,048 -> 16,384 and the operand/locals arenas now span
  the whole `u16` index range, with an explicit headroom check so running out is
  a catchable overflow rather than an index panic. The arena is ~4.5 MB, so it
  is no longer a `threadlocal` array (that committed it for every thread): it is
  mapped lazily per thread and unmapped by a pthread-key destructor at thread
  exit. Result: idle RSS 13 -> 11 MB, 200 concurrent futures 106 -> 40 MB, a
  15,000-deep recursion peaks at 14 MB. Going past ~16k frames needs
  `EvalFrame.sp` and the VM's operand indexes widened from `u16` (touches the
  GC, TreeWalk and WasmGC).
- **WasmGC** is bound by zwasm's interpreter loop (`dispatch.run`, a ~21 KB
  frame per wasm re-entry), not by cljw. Only direct wasm-to-wasm calls remove
  it; that is part of the standalone compiler. zwasm v2.8.1 was built and
  measured (2026-10-30, local source, not adopted): direct recursion 15,200 ->
  16,800 and through `map` 12,000 -> 13,200, about +10%, with the same
  `max_frame_stack = 256` cap and native-stack recursion per call. Not worth a
  dependency bump, so the pin stays at v2.7.0.

Implications for the standalone compiler: a browser engine gives roughly
10k wasm calls for a small frame and fewer for realistic ones, so
ClojureScript-level depth is the ceiling there unless the design uses an
explicit heap-allocated call stack. A design that re-enters wasm through host
imports (like the current hybrid) gets only ~900. Direct wasm-to-wasm calls are
required, and frames must stay small.

## Direction (decided in discussion, not yet implemented)

Deployment targets: browser, Cloudflare Workers, standalone server (WASI).
Requirement: a compiler for **full Clojure** to deployable `.wasm`, not a demo.

What the current backend is: a native-hosted execution mode (WASM calls back into
Zig host functions inside a native `cljw`, run by zwasm, with `wasm-tools`
spawned per form). It cannot be deployed to any of the three targets. It stays
valuable as the conformance/differential vehicle and as the compiler front end.

Agreed architecture: compile to **standalone Wasm 3.0** (GC, exceptions via
`try_table`, tail calls via `return_call`) so the engines do the work: values are
WasmGC references, no interpreter and no VM in the artifact, no host process.
Macros expand at build time; no runtime `eval`/`load-string` in the AOT artifact
(same property as ClojureScript). The library layer is written in Clojure on a
small set of compiler intrinsics (ClojureScript approach), ported from the Zig
implementation (which matches JVM hash/iteration order that the golden corpus
depends on), with a small hand-written WAT/intrinsic kernel.

Measured size of the Zig layer to replace (lines): primitives 13,540 (~1,115
builtins), collections 7,560, `java.*` emulation 11,134, regex 4,177, numerics
3,216, printer+reader 3,096; ~43k total. The ~9.6k lines of Clojure in
`src/lang/clj` (`core.clj`, spec, pprint, zip, ...) compile as-is once the Zig
layer exists.

Proposed tiers: T0 kernel (arrays, long/double, strings, hashing, interning,
exceptions); T1 seqs + core collections; T2 protocols/multimethods/records/
atoms/transducers; T3 strings/printer/reader/clojure.string; T4 bignum/ratio/
bigdecimal and regex; T5 `java.*` per-platform subset; T6 single-threaded
`future`/`agent` semantics. Network/files/threads are per-platform capability
tiers, not parity items. Success metric per program: number of host imports it
still needs (zero = deployable).

Proposed first deliverables (all kept in the repo, no throwaway spikes):
1. Inventory of the ~1,115 builtins (tier, corpus/core usage, portability).
2. ADR: value representation (i31 vs boxed i64 for longs, string layout, closure
   layout), calling convention, function table, exceptions, string encoding,
   platform capability model.
3. Engine-conformance fixtures (hand-written `.wat`, one per Wasm 3.0 feature the
   compiler emits) run on zwasm, wasmtime, V8/Node, Chrome and Workers by a script
   in the gate. (Workers' WasmGC support is undocumented; this settles it.)
4. A walking skeleton in the production compiler (constants, locals, if, let,
   fn/closures, loop/recur, try, in-module calls), differential-tested vs the VM.

Facts to re-verify before relying on them (taken from web search, not checked
against primary sources): Cloudflare Workers disallows runtime compilation of
WASM from bytes (modules must be pre-compiled static imports) and is
single-threaded; its size limit was reported as 64 MiB total; WasmGC shipped in
Chrome 119, Firefox 120, Safari 18.2; wasmtime/WasmEdge/Wasmer report GC support.
Also unchecked: licensing compatibility if any `cljs.core` source is reused
(this repo's header is EPL-2.0).

Findings from a probe: building cljw for `wasm32-wasi` currently fails first in
`zwasm` (its native JIT supports only aarch64/x86_64); on this branch zwasm is
linked unconditionally (`main` links it only with `-Dwasm`). Remaining errors
after that are unknown.

Open questions for the maintainer (unanswered when work paused):
- Is `java.*` parity required, or a documented per-platform subset?
- Full numeric tower from the first release, or longs/doubles first?
- Must the artifact use real WasmGC values (this plan assumes yes)?
- Server runtime(s) to support (wasmtime, WasmEdge, Wasmer, Node/Deno)?
- Threads in the wasm build: synchronous `future`/`agent`/`pmap`, or concurrent?
- How strict is the Cloudflare Workers size/startup budget?
- Where to start: builtin inventory + ADR first, or close out this branch and open
  the PR first (PR template at `.github/pull_request_template.md` must be used)?
