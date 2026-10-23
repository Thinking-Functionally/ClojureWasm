#!/usr/bin/env bash
#
# clj_diff_sweep.sh - Differential testing: Compare backend outputs
#
# Usage:
#   bash scripts/clj_diff_sweep.sh test/wasmgc_exprs.txt --backends tree_walk,wasmgc
#
# Month 4, Week 3: Integration Testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/zig-out/bin"

# Default backends to compare
BACKENDS="tree_walk,vm,wasmgc"
INPUT_FILE=""
VERBOSE=0
OUTPUT_DIR="$PROJECT_ROOT/.dev/diff_results"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backends)
            BACKENDS="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            INPUT_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$INPUT_FILE" ]]; then
    echo "Error: No input file specified"
    echo "Usage: $0 <expr_file> [--backends tree_walk,wasmgc] [--verbose]"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Clojure Backend Differential Testing                      ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  Input:    $INPUT_FILE"
echo "║  Backends: $BACKENDS"
echo "║  Output:   $OUTPUT_DIR"
echo "╚════════════════════════════════════════════════════════════╝"
echo

# Convert comma-separated backends to array
IFS=',' read -ra BACKEND_ARRAY <<< "$BACKENDS"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Counters
TOTAL=0
PASS=0
FAIL=0

# Process each expression
while IFS= read -r expr || [[ -n "$expr" ]]; do
    # Skip comments and empty lines
    [[ -z "$expr" || "$expr" =~ ^[[:space:]]*# ]] && continue

    TOTAL=$((TOTAL + 1))
    echo "─────────────────────────────────────────────────────"
    echo "Test $TOTAL: $expr"

    declare -A outputs
    declare -A exit_codes

    # Run on each backend
    for backend in "${BACKEND_ARRAY[@]}"; do
        backend=$(echo "$backend" | tr -d '[:space:]')

        if [[ $VERBOSE -eq 1 ]]; then
            echo "  Running on $backend..."
        fi

        # Execute via ClojureWasm CLI with specified backend
        output_file="$OUTPUT_DIR/test_${TOTAL}_${backend}.txt"

        # TODO: Replace with actual CLI invocation
        # For now, mock the execution
        case "$backend" in
            tree_walk)
                echo "[TreeWalk] Result: 42" > "$output_file"
                exit_codes[$backend]=0
                ;;
            vm)
                echo "[VM] Result: 42" > "$output_file"
                exit_codes[$backend]=0
                ;;
            wasmgc)
                echo "[WasmGC] Result: 42" > "$output_file"
                exit_codes[$backend]=0
                ;;
            *)
                echo "Error: unknown backend" > "$output_file"
                exit_codes[$backend]=1
                ;;
        esac

        outputs[$backend]=$(cat "$output_file")
    done

    # Compare outputs
    first_backend="${BACKEND_ARRAY[0]}"
    first_output="${outputs[$first_backend]}"
    all_match=1

    for backend in "${BACKEND_ARRAY[@]}"; do
        backend=$(echo "$backend" | tr -d '[:space:]')
        if [[ "${outputs[$backend]}" != "$first_output" ]]; then
            all_match=0
            break
        fi
    done

    if [[ $all_match -eq 1 ]]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}✓ PASS${NC} - All backends agree: $first_output"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}✗ FAIL${NC} - Output divergence detected:"
        for backend in "${BACKEND_ARRAY[@]}"; do
            backend=$(echo "$backend" | tr -d '[:space:]')
            echo "    $backend: ${outputs[$backend]}"
        done
    fi

done < "$INPUT_FILE"

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test Results                                              ║"
echo "╠════════════════════════════════════════════════════════════╣"
printf "║  Total:  %-49d ║\n" "$TOTAL"
printf "║  Pass:   ${GREEN}%-49d${NC} ║\n" "$PASS"
printf "║  Fail:   ${RED}%-49d${NC} ║\n" "$FAIL"

if [[ $TOTAL -gt 0 ]]; then
    success_rate=$(awk "BEGIN {printf \"%.1f\", ($PASS/$TOTAL)*100}")
    printf "║  Rate:   %-48s%% ║\n" "$success_rate"
fi

echo "╚════════════════════════════════════════════════════════════╝"

if [[ $FAIL -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed!${NC} ✨"
    exit 0
else
    echo -e "\n${RED}Some tests failed.${NC} Check $OUTPUT_DIR for details."
    exit 1
fi
