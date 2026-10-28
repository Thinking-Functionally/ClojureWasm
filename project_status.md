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
- `e2e_phase14_eval` fails in the full gate on the VM as well as the other
  backends. Not verified against a clean `main` (building `main` in `/tmp` was
  denied); believed pre-existing since the branch does not touch stdin echo.
  To check: on a `main` checkout run `zig build -Dwasm && bash test/e2e/phase14_eval.sh`.
- `accepted_divergences` and `compat_members` gate steps fail on this machine
  only because `yq` is not installed.

## Gate and differential coverage

`test/clj/` (see its README) is a self-contained `clojure.test` suite run on all
three backends by `test/clj/run.sh`, which requires byte-identical results; with
`--jvm` the same source also runs on JVM Clojure as the oracle. Current suites
(assertions): tier_a 13, features 18 (needs `eval`), regression 10, p99_lists 102
(L-99 P01-P28), p99_arithmetic 44 (P31-P41), fourclojure 112 (problems 1-41);
all agree on tree_walk, vm, wasmgc and JVM Clojure. Remaining to build: L-99
P46-P99 (logic, trees, graphs, puzzles; heavy ones tagged slow) and 4clojure
42-98. Gate steps: `test_clj_tier_a`, `test_clj_suites`.

Full `test/run_all.sh` (this machine, 23 min): 436 passed, 4 failed. The four are
the two `yq` steps, `e2e_phase14_eval` (above), and `e2e_reach`, which was an
orphaned vacuous script (`wasmgc_simple_arithmetic.sh`) that has since been
replaced by `test/e2e/wasmgc_backend_smoke.sh` (29 output assertions, registered)
and now passes. The gate was not re-run end to end after that last fix.

`test/run_all.sh` runs: `zig_build_test_wasmgc` (same test binary,
`CLJW_BACKEND=wasmgc`), `corpus_regression_tree_walk`, `corpus_regression_wasmgc`,
`backend_diff_three_way` (118 cases in `test/diff/backends/`, one process per
backend; 2 accepted pre-existing TreeWalk/VM divergences in
`known_divergences.txt`), `e2e_wasmgc_backend_smoke` and `e2e_wasmgc` (sandboxed
harness with the allow-list `test/wasmgc_known_failures.txt`).
`cljw --compare` runs all three backends in-process (heap values and errors
report MISMATCH there by design; use `check_backend_diff.sh` for semantics).

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
