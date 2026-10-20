#!/usr/bin/env bash
# Benchmark P99 performance: TreeWalk vs VM backends

set -euo pipefail

# Find project root and set paths accordingly
if [[ -f zig-out/bin/cljw ]]; then
  # Running from project root
  CLJW="${CLJW:-zig-out/bin/cljw}"
  TEST_FILE="test/clj/p99/core.clj"
  RESULTS="test/clj/p99/benchmark_results.md"
elif [[ -f ../../../zig-out/bin/cljw ]]; then
  # Running from test/clj/p99/
  CLJW="${CLJW:-../../../zig-out/bin/cljw}"
  TEST_FILE="core.clj"
  RESULTS="benchmark_results.md"
else
  # Fallback
  CLJW="${CLJW:-zig-out/bin/cljw}"
  TEST_FILE="test/clj/p99/core.clj"
  RESULTS="test/clj/p99/benchmark_results.md"
fi

if ! command -v hyperfine &> /dev/null; then
  echo "❌ hyperfine not found. Install: brew install hyperfine"
  exit 1
fi

if [[ ! -f "$CLJW" ]]; then
  echo "❌ cljw not found at $CLJW"
  exit 1
fi

echo "=== P99 Performance Benchmark ==="
echo "Comparing TreeWalk vs VM backends"
echo

hyperfine \
  --warmup 3 \
  --runs 10 \
  --export-markdown "$RESULTS" \
  --command-name "TreeWalk" "$CLJW $TEST_FILE" \
  --command-name "VM" "$CLJW -Dbackend=vm $TEST_FILE"

echo
echo "📊 Results saved to $RESULTS"
cat "$RESULTS"
