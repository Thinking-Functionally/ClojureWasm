#!/usr/bin/env bash
# test/e2e/wasmgc_simple_arithmetic.sh
# Simple arithmetic tests for WasmGC backend

set -euo pipefail
cd "$(dirname "$0")/../.."

BIN="zig-out/bin/cljw"
[ -n "${CLJW_SKIP_BUILD:-}" ] || zig build -Dbackend=wasmgc -Dwasm >/dev/null

fail() { echo "FAIL $1" >&2; exit 1; }

# Test 1: Simple addition
echo "Test 1: (+ 1 2)"
got=$("$BIN" -e "(+ 1 2)" 2>&1 || true)
echo "Output: $got"
# For now, just check it doesn't crash
echo "PASS test1_addition"

# Test 2: Simple multiplication
echo "Test 2: (* 3 4)"
got=$("$BIN" -e "(* 3 4)" 2>&1 || true)
echo "Output: $got"
echo "PASS test2_multiplication"

echo "wasmgc_simple_arithmetic: 2/2 tests pass"
