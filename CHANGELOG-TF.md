# Changelog - Thinking-Functionally Fork

All notable changes to this fork of ClojureWasm will be documented in this file.

This fork is maintained at: https://github.com/Thinking-Functionally/ClojureWasm

## [Unreleased]

## [v1.10.1-tf.1] - 2026-10-13

### Fixed

- **eval use-after-free bug**: Fixed critical memory safety issue where values returned from `eval` were allocated in a temporary arena that was freed before the values could be used. This caused functions returned from `eval` to be unusable and could lead to crashes.
  - Fixed in `src/runtime/repl.zig` (lines 196, 259)
  - Fixed in `src/runtime/nrepl.zig` (line 189)
  - Changed temporary arena allocations to use `rt.load_arena.allocator()` for persistent storage
  - Added regression test in `test/e2e/phase14_eval.sh`

- **min-key/max-key tie-breaking**: Fixed behavior to match JVM Clojure when multiple elements have equal keys. Now correctly returns the last element instead of the first.
  - Changed `max-key` comparison from `>` to `>=` in `src/lang/clj/clojure/core.clj`
  - Changed `min-key` comparison from `<` to `<=` in `src/lang/clj/clojure/core.clj`
  - Example: `(max-key (fn [x] 1) "a" "b" "c")` now returns `"c"` (was `"a"`)
  - Added test corpus in `test/diff/clj_corpus/tie_breaking.txt`

### Testing

- All existing tests pass
- New regression tests added for both fixes
- Verified against JVM Clojure behavior

## Notes

This fork was created from ClojureWasm v1.10.1 to provide bug fixes and improvements while the upstream project is in maintenance mode.

For the original ClojureWasm changelog, see the upstream repository at: https://github.com/clojurewasm/ClojureWasm
