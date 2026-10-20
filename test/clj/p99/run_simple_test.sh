#!/usr/bin/env bash
# Simple inline test for basic P99 problems

set -euo pipefail

# Find project root (up to 3 levels)
if [[ -f zig-out/bin/cljw ]]; then
  CLJW="${CLJW:-zig-out/bin/cljw}"
elif [[ -f ../../../zig-out/bin/cljw ]]; then
  CLJW="${CLJW:-../../../zig-out/bin/cljw}"
else
  CLJW="${CLJW:-zig-out/bin/cljw}"
fi

if [[ ! -f "$CLJW" ]]; then
  echo "❌ cljw not found at $CLJW"
  exit 1
fi

echo "=== P99 Simple Inline Tests ==="

echo "P01: Last element"
result=$("$CLJW" -e "(last [1 2 3 4])")
[[ "$result" == "4" ]] && echo "✅ Pass" || echo "❌ Fail: got $result"

echo "P04: Count"
result=$("$CLJW" -e "(count [1 2 3 4 5])")
[[ "$result" == "5" ]] && echo "✅ Pass" || echo "❌ Fail: got $result"

echo "P05: Reverse"
result=$("$CLJW" -e "(reverse [1 2 3 4])")
[[ "$result" == "[4 3 2 1]" ]] && echo "✅ Pass" || echo "❌ Fail: got $result"

echo "P11: Addition"
result=$("$CLJW" -e "(+ 10 5)")
[[ "$result" == "15" ]] && echo "✅ Pass" || echo "❌ Fail: got $result"

echo "P13: Multiplication"
result=$("$CLJW" -e "(* 10 5)")
[[ "$result" == "50" ]] && echo "✅ Pass" || echo "❌ Fail: got $result"

echo
echo "✅ Simple tests complete"
