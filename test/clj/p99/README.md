# P99 Test Suite

Complete test suite for 99 Clojure problems, supporting differential testing across multiple backends.

## Structure

```
test/clj/p99/
├── core.clj              # All 99 problem implementations + tests
├── benchmark.sh          # Performance comparison script (hyperfine)
├── run_simple_test.sh    # Simple inline test
└── run_tests.sh          # Test runner wrapper
```

## Backends

| Backend   | Status | Notes                                                    |
|-----------|--------|----------------------------------------------------------|
| TreeWalk  | ✅ Pass | All 25 tests pass (59 assertions)                        |
| VM        | ✅ Pass | All 25 tests pass (59 assertions)                        |
| WASM      | ⚠️ Stub | Phase 1-4 opcodes stubbed; heap types return 0.0         |

### WASM Backend Status (Phase 1-4 Stubs)

**Fully supported:**
- ✅ Arithmetic: `(+ 1 2)` → `3`, `(* 3 4)` → `12`, etc.

**Stub implementations (return dummy 0.0 for heap types):**
- ⚠️ Vectors: `[1 2 3]` → `0` (stub)
- ⚠️ Maps: `{:a 1}` → `0` (stub)
- ⚠️ Function calls: `(last [1 2 3])` → `0` (stub)
- ⚠️ Var definition: `(def x 42)` → `0` (stub)
- ⚠️ Namespace operations: `(require ...)` → no-op

**Implementation notes:**
- Phase 1-4 opcodes have stub implementations
- Heap types (vectors, maps, functions) return `0.0` placeholder values
- Full heap implementation deferred to Phase 5+
- For accurate results, use TreeWalk or VM backends

## Running Tests

```bash
# TreeWalk backend (default)
zig-out/bin/cljw test/clj/p99/core.clj

# VM backend
zig-out/bin/cljw --backend vm test/clj/p99/core.clj

# WASM backend (limited support)
zig-out/bin/cljw --backend wasm test/clj/p99/simple_wasm_test.clj
```

## Performance Benchmarking

```bash
# Install hyperfine first
brew install hyperfine

# Run benchmark
bash test/clj/p99/benchmark.sh

# Results saved to test/clj/p99/benchmark_results.md
```

The benchmark compares TreeWalk vs VM backend performance across all 99 problems with 10 runs and 3 warmup iterations.

## Test Coverage

Currently implemented: **Problems 1-99** (all categories)
- Elementary (1-18)
- Easy (19-50)
- Medium (51-70)
- Hard (71-99)

Test assertions: **59 assertions** across **25 test cases**
