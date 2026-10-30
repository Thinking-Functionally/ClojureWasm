# test/clj — Clojure test suites

Self-contained `clojure.test` suites, run on every backend from one binary and
required to agree. Entry point: `bash test/clj/run.sh` (see its header for all
options).

```
test/clj/
  run.sh                 runner: one cljw process per suite per backend
  run_tier_a.sh          compatibility wrapper (gate step test_clj_tier_a)
  support/
    suites.txt           manifest: suite, files/namespaces, min assertions, capabilities
    cljtest/runner.clj   shared reporter (prints CLJTEST-SUMMARY, sets the exit code)
  skip_taxonomy.yaml     Tier A skip rows (ADR-0046)
  tier_a/                cw_ported.clj — semantic ports of upstream Clojure tests
  features/              eval_test.clj — needs the `eval` capability
  regression/            one file per fixed bug (min_max_key_test.clj)
  p99/                   L-99 ("Ninety-Nine Lisp Problems") in Clojure, src/ + test/
  fourclojure/           the 4clojure problems, solutions + enabled tests
  depth/                 recursion-depth contract: deep recursion works, runaway
                         recursion is a catchable StackOverflowError, recovery
```

`p99/reference/` holds the original Common Lisp solutions (MIT, upstream LICENSE
kept) and the 4clojure starter skeleton. They are reference material only; the
suites use their own Clojure code.

## Running

```sh
bash test/clj/run.sh                    # all suites, binary's default backend
bash test/clj/run.sh --all-backends     # tree_walk, vm, wasmgc: must agree
bash test/clj/run.sh --suite tier_a --backend wasmgc
bash test/clj/run.sh --include-slow     # also suites marked slow
bash test/clj/run.sh --all-backends --jvm   # also run each suite on JVM Clojure (`clj`)
CLJ_TEST_CAPS="threads fs" bash test/clj/run.sh   # no `eval`: features is SKIPped
```

`--jvm` is the oracle: the p99 and fourclojure suites are plain portable Clojure,
so the very same source and tests run on JVM Clojure and the assertion counts
must match. A test's expected value counts as validated only once JVM Clojure
agrees. (Requires `clj`; not part of the gate.)

## Contract (what makes a suite portable to other platforms)

- A suite is a set of `deftest`s. It prints nothing itself; `cljtest.runner`
  prints one `CLJTEST-SUMMARY {:suite … :test N :pass N :fail N :error N}` line
  and exits non-zero on any failure, error, or when no test ran.
- `suites.txt` records a minimum assertion count per suite, so a suite cannot
  shrink or silently stop running.
- A suite declares the capabilities it needs (`eval`, `threads`, `fs`, `net`,
  `java`). A platform without one skips the suite with a recorded reason.
- Tests must be deterministic (no clock, randomness, or hash-order dependence in
  expected values). Timing is never asserted.
- Expected values for new suites are validated against JVM Clojure (`clj`).

## Adding a regression test
Put the file in `regression/`, add a line to `support/suites.txt` (or extend the
existing suite's file list), and keep the file free of `run-tests` calls.

## Slow workloads

The default gate includes every implemented L-99 problem, with bounded inputs.
`--include-slow` additionally runs the large totient/Goldbach cases and the
larger regular-graph and knight-tour cases. Their separate manifest entries
retain minimum assertion counts; they are not silently dropped.

Use a ReleaseSafe binary for the full slow run. The 6x6/8x8 knight tours
currently exceed WasmGC's native-stack budget in Debug even though they passed
in ReleaseSafe. Skipping the slow suite in the default gate is not proof of
Debug equivalence for those inputs.
