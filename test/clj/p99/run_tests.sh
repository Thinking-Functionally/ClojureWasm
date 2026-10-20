#!/usr/bin/env bash
# Run P99 test suite across all backends

set -euo pipefail

# Find project root (up to 3 levels)
if [[ -f zig-out/bin/cljw ]]; then
  CLJW="${CLJW:-zig-out/bin/cljw}"
  TEST_FILE="test/clj/p99/core.clj"
elif [[ -f ../../../zig-out/bin/cljw ]]; then
  CLJW="${CLJW:-../../../zig-out/bin/cljw}"
  TEST_FILE="core.clj"
else
  CLJW="${CLJW:-zig-out/bin/cljw}"
  TEST_FILE="test/clj/p99/core.clj"
fi

if [[ ! -f "$CLJW" ]]; then
  echo "❌ cljw not found at $CLJW"
  echo "Run: zig build"
  exit 1
fi

echo "=== P99 Test Suite Runner ==="
echo

echo "📝 TreeWalk Backend"
"$CLJW" "$TEST_FILE"
echo

echo "🚀 VM Backend"
"$CLJW" --backend=vm "$TEST_FILE"
echo

echo "✅ All backends complete"
