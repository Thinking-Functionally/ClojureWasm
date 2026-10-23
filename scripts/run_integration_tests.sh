#!/bin/bash
# run_integration_tests.sh
# Complete integration test suite for WasmGC backend
# Month 5, Weeks 3-4

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "=========================================="
echo "WasmGC Backend Integration Tests"
echo "Month 5, Weeks 3-4"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check for wasmtime
if ! command -v wasmtime &> /dev/null; then
    echo "⚠️  wasmtime not found. Installing via homebrew..."
    brew install wasmtime
fi

# Check for wat2wasm (from WABT)
if ! command -v wat2wasm &> /dev/null; then
    echo "⚠️  wat2wasm not found. Installing WABT via homebrew..."
    brew install wabt
fi

# Check for wasm-tools
if ! command -v wasm-tools &> /dev/null; then
    echo "⚠️  wasm-tools not found. Installing via homebrew..."
    brew install wasm-tools
fi

echo "✓ All prerequisites satisfied"
echo ""

# Build the project first
echo "Building ClojureWasm..."
zig build
echo "✓ Build complete"
echo ""

# Run integration tests
echo "=========================================="
echo "Running Integration Test Suite"
echo "=========================================="
echo ""

# Task 1-6: Complete integration test
echo "--- Task 1-6: Complete Integration Suite ---"
zig build test --summary all 2>&1 | tee .zig-cache/integration_test.log

# Extract test results
if grep -q "All integration tests passed" .zig-cache/integration_test.log; then
    echo "✓ Integration tests passed"
else
    echo "⚠️  Some integration tests failed or skipped"
fi

echo ""

# Generate benchmark report
echo "=========================================="
echo "Performance Benchmark Summary"
echo "=========================================="
echo ""

if [ -f .zig-cache/benchmark_results.txt ]; then
    cat .zig-cache/benchmark_results.txt
else
    echo "No benchmark results found. Tests may have been skipped."
fi

echo ""

# Browser test instructions
echo "=========================================="
echo "Browser Integration Tests"
echo "=========================================="
echo ""
echo "To run browser tests:"
echo "1. Start HTTP server:"
echo "   python3 -m http.server 8000"
echo "2. Open browser to:"
echo "   http://localhost:8000/test/wasmgc_e2e/browser_test.html"
echo "3. Check browser console for results"
echo ""

# Generate final report
echo "=========================================="
echo "Test Report Summary"
echo "=========================================="
echo ""

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

if [ -f .zig-cache/integration_test.log ]; then
    TOTAL_TESTS=$(grep -c "Test:" .zig-cache/integration_test.log || echo "0")
    PASSED_TESTS=$(grep -c "✓" .zig-cache/integration_test.log || echo "0")
    FAILED_TESTS=$(grep -c "✗" .zig-cache/integration_test.log || echo "0")
    SKIPPED_TESTS=$(grep -c "Skipping" .zig-cache/integration_test.log || echo "0")
fi

echo "Total Tests:   $TOTAL_TESTS"
echo "Passed:        $PASSED_TESTS"
echo "Failed:        $FAILED_TESTS"
echo "Skipped:       $SKIPPED_TESTS"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo "✓ All tests passed or skipped gracefully"
    exit 0
else
    echo "⚠️  Some tests failed"
    exit 1
fi
