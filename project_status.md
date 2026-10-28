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
- Not done: a CI gate run on a clean checkout of the full `test/run_all.sh`
  (the new steps were each run individually), and replacing the per-form
  `wasm-tools` subprocess with direct binary emission.

## Gate and differential coverage

`test/run_all.sh` now also runs: `zig_build_test_wasmgc` (same test binary,
`CLJW_BACKEND=wasmgc`), `corpus_regression_tree_walk`, `corpus_regression_wasmgc`,
`backend_diff_three_way` (73 cases in `test/diff/backends/`, one process per
backend; see `test/diff/README.md`) and `e2e_wasmgc` (sandboxed harness with the
allow-list `test/wasmgc_known_failures.txt`). `cljw --compare` runs all three
backends in-process.
