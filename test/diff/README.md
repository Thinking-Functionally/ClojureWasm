# test/diff — Differential test layer (TreeWalk vs VM)

> Layer 3 of the test taxonomy per ADR-0021. Implementation
> contract per ADR-0022.

## Files (after Phase 4 task 4.10 lands)

- `runner.zig` — `zig build test`-discoverable runner, embeds
  `cases.yaml`, dispatches each case to TreeWalk and VM, compares
  the resulting Value bit-for-bit.
- `cases.yaml` — case list. Each entry has `name`, `src`,
  `expected` (informational), `skip_reason` (`null` = enabled,
  string = skip with reason).
- `fixtures/` — per-case Clojure source files when inline `src`
  is unwieldy (referenced from cases.yaml by
  `fixture: path/to/file.clj`).

At Phase 4 entry, only this README exists. The Zig runner and
YAML case file land with task 4.10.

## When to add a case

Any time a TreeWalk and VM divergence is plausible. Examples:

- Closure capture across scopes.
- Tail-call (`recur`) in different positions.
- Exception unwind through nested forms.
- Macro expansion that touches both backends.
- Phase 5+: collection ops (vector / map / set).
- Phase 7+: protocol dispatch under both backends.

A case **does not** belong here if Layer 1 (inline unit) already
covers it — Layer 3 is for cases that exercise the backend
boundary specifically.

## Phase 17 extension

When JIT lands (Phase 17), `runner.zig` switches to
`Evaluator.compareThree(...)` and asserts TreeWalk == VM == JIT.
`cases.yaml` is unchanged.

## Three-way backend differential (`backends/`)

`scripts/check_backend_diff.sh` runs every case in `test/diff/backends/*.txt`
(cases separated by `;;---`) as `(do <case>)` in a separate `cljw` process per
backend (`--backend=tree_walk|vm|wasmgc`) and requires identical stdout, exit
code and error header (first two stderr lines; traces differ per backend).
Separate processes avoid the in-process `--compare` limits (shared `Env`, heap
values compared by address). Accepted divergences go in
`backends/known_divergences.txt` as `file:case-number`.

`cljw --compare -e '<expr>'` is the in-process oracle; it now runs all three
backends and prints one line per backend on `MISMATCH`.

Gate steps (`test/run_all.sh`): `zig_build_test_wasmgc`,
`corpus_regression_tree_walk`, `corpus_regression_wasmgc`,
`backend_diff_three_way`, `e2e_wasmgc`.
