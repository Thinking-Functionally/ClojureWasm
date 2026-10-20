# P99: Ninety-Nine Clojure Problems

Complete differential test suite for TreeWalk/VM/Wasm backend validation.

## Overview

This directory implements the P-99 problem set (99 classic Clojure problems) for testing ClojureWasm's three execution backends:
- **TreeWalk**: AST interpreter (reference implementation)
- **VM**: Bytecode interpreter (production default)  
- **Wasm**: AOT compiled WebAssembly (Phase 1-4 stubs)

All backends must produce **identical results** - any discrepancy is a correctness bug.

## Files

```
test/clj/p99/
├── core.clj                      # Original 25-problem suite
├── core_complete.clj             # NEW: Full 75-problem suite with implementations
├── reference/                    # Reference skeleton (99 problems, no implementations)
│   ├── core.clj
│   ├── 1.clj
│   └── 2.clj
├── run_tests.sh                  # Basic TreeWalk/VM runner
├── run_differential_tests.sh     # NEW: 3-backend differential tester with logs
├── run_simple_test.sh            # Inline smoke tests
└── benchmark.sh                  # Performance comparison (hyperfine)
```

## Quick Start

### Full Differential Test (Recommended)

```bash
# Build cljw first
zig build

# Run comprehensive 3-backend test with color output
./test/clj/p99/run_differential_tests.sh
```

This runs all implemented problems on TreeWalk, VM, and Wasm backends, saves logs to `test/clj/p99/logs/`, and reports any discrepancies.

### Individual Backend Tests

```bash
# TreeWalk (default)
zig-out/bin/cljw test/clj/p99/core_complete.clj

# VM (production)
zig-out/bin/cljw -Dbackend=vm test/clj/p99/core_complete.clj

# Wasm (requires -Dwasm=true at build time)
zig build -Dwasm=true
zig-out/bin/cljw -Dbackend=wasm test/clj/p99/core_complete.clj
```

### Performance Benchmark

```bash
# Compare TreeWalk vs VM performance (requires hyperfine)
./test/clj/p99/benchmark.sh
```

## Problem Coverage (core_complete.clj)

### Elementary (P01-P18) - 18 problems ✅
- **Sequence basics**: last, penultimate, nth, count, reverse
- **Transformations**: flatten, compress, pack, run-length encode
- **Arithmetic**: +, -, *, /, <, >, =
- **Higher-order**: map, filter

### Easy (P19-P34) - 16 problems ✅
- filter-even, sum, insert-at, range
- Random selection, lotto, permutation
- Fibonacci, palindrome, caps extraction
- duplicate, replicate, my-range

### Medium (P35-P70) - 26 problems ✅
- maximum, interleave, interpose, drop-every
- factorial, reverse-interleave, rotate
- split-at, split-by-type, partition
- frequencies, distinct, compose, juxt
- reductions, zipmap, iterate, group-by
- GCD, primes, merge-with, word-sort

### Hard (P71-P99) - 15 problems ✅
- set-intersection, half-truth, power-set
- happy-numbers, symmetric-difference
- cartesian-product, tree-predicate
- symmetric-tree, pascal-triangle
- equivalence-classes, product-digits

**Total: 75 implemented problems** with comprehensive test coverage

## Differential Testing Strategy

The `run_differential_tests.sh` script:
1. Runs `core_complete.clj` on TreeWalk backend → saves to `logs/treewalk.log`
2. Runs `core_complete.clj` on VM backend → saves to `logs/vm.log`
3. Runs `core_complete.clj` on Wasm backend → saves to `logs/wasm.log`
4. Compares exit codes and test counts
5. Reports any discrepancies with color-coded output

Any difference in:
- Exit codes
- Test pass/fail counts  
- Actual output values

...is flagged as a **backend correctness bug**.

## Integration Points

- **Zig-level tests**: `test/differential_backend_tests.zig` tests at Wasm runtime level
- **Clojure-level tests**: This P99 suite validates end-to-end language semantics
- **Build integration**: `zig build test-diff -Dwasm=true` runs Zig differential tests

## Wasm Backend Status

**Current**: Phase 1-4 opcode stubs only (limited heap support)
- Basic arithmetic and simple sequences work
- Complex allocations (nested collections, closures) are stubbed
- Full heap GC deferred to Phase 5-7 per ROADMAP.md

**Expected**: Wasm backend will fail many P99 tests until heap implementation completes.

## Notes

- **VM backend**: Production default since D-196 parity completion
- **TreeWalk backend**: Reference oracle for differential testing
- **clojure.test integration**: Uses standard `deftest`/`is` assertions
- **Test count validation**: Ensures backends don't silently skip tests
