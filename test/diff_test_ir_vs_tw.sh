#!/usr/bin/env bash
# SPDX-License-Identifier: EPL-2.0
# Differential test: IR Backend vs TreeWalk evaluation
#
# Phase 1 scope: verify that expressions compile to IR without errors.
# Future phases will compare IR evaluation results against TreeWalk.

set -uo pipefail

BIN_CLJW="${BIN_CLJW:-./zig-out/bin/cljw}"
BIN_IR="${BIN_IR:-./zig-out/bin/cljw-ir}"

fail_count=0
pass_count=0

test_expr() {
    local expr="$1"
    local desc="$2"

    echo "Testing: $desc"
    echo "  Expression: $expr"

    # TreeWalk: evaluate (expect a Value result)
    local tw_out
    local tw_exit
    tw_out=$("$BIN_CLJW" -e "$expr" 2>&1) || tw_exit=$?
    if [ -n "${tw_exit:-}" ]; then
        echo "  TreeWalk: FAILED with exit code $tw_exit"
        echo "  TreeWalk output: $tw_out"
        ((fail_count++))
        return 0
    fi
    echo "  TreeWalk: $tw_out"

    # IR: compile (expect :val/N result)
    local ir_out
    local ir_exit
    ir_out=$("$BIN_IR" -e "$expr" 2>&1 | grep -v '^;;') || ir_exit=$?
    if [ -n "${ir_exit:-}" ]; then
        echo "  IR: FAILED with exit code $ir_exit"
        echo "  IR output: $ir_out"
        ((fail_count++))
        return 0
    fi
    echo "  IR:       $ir_out"

    # Phase 1: verify IR compiled successfully (starts with :val/ or :local/ or :param/)
    if [[ "$ir_out" =~ ^:(val|local|param)/ ]]; then
        echo "  ✓ PASS"
        ((pass_count++))
    else
        echo "  ✗ FAIL: IR output does not start with :val/, :local/, or :param/"
        ((fail_count++))
    fi
    echo
}

# Test cases

# Basic arithmetic
test_expr "(+ 1 2)" "addition"
test_expr "(- 10 3)" "subtraction"
test_expr "(* 4 5)" "multiplication"
test_expr "(/ 20 4)" "division"

# Let bindings
test_expr "(let [x 10] x)" "let binding"
test_expr "(let [x 1 y 2] (+ x y))" "multiple bindings"

# Conditionals
test_expr "(if true 1 2)" "if true"
test_expr "(if false 1 2)" "if false"
test_expr "(if nil 1 2)" "if nil"

# Nested expressions
test_expr "(+ (* 2 3) (- 10 5))" "nested arithmetic"
test_expr "(let [x (+ 1 2)] (* x 3))" "let with nested expr"

# Constants
test_expr "42" "integer constant"
test_expr "\"hello\"" "string constant"
test_expr ":keyword" "keyword constant"
test_expr "true" "boolean true"
test_expr "false" "boolean false"
test_expr "nil" "nil constant"

# Summary
echo "=========================================="
echo "Differential test summary:"
echo "  Pass: $pass_count"
echo "  Fail: $fail_count"
echo "=========================================="

if [ "$fail_count" -gt 0 ]; then
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
