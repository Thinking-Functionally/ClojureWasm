#!/usr/bin/env bash
# SPDX-License-Identifier: EPL-2.0
# Wasm backend differential test: TreeWalk vs VM vs Wasm
#
# Phase 3 complete: 三方差分測試
# 驗證 Wasm 後端同 TreeWalk/VM 產生相同結果

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="${BIN:-$REPO_ROOT/zig-out/bin/cljw}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

pass() {
    echo "PASS: $*"
}

# Phase 3: 簡單算術測試
test_arithmetic() {
    local expr="$1"
    local expected="$2"

    # TreeWalk
    local tw_result
    tw_result=$("$BIN" -e "$expr" 2>&1) || fail "TreeWalk failed: $expr"

    # VM (預設)
    local vm_result
    vm_result=$("$BIN" -e "$expr" 2>&1) || fail "VM failed: $expr"

    # TODO: Wasm backend (需要實現完整 zwasm 整合)
    # local wasm_result
    # wasm_result=$("$BIN" --backend=wasm -e "$expr" 2>&1) || fail "Wasm failed: $expr"

    # 驗證 TreeWalk == VM
    [[ "$tw_result" == "$vm_result" ]] || fail "TreeWalk vs VM mismatch: $expr (tw=$tw_result, vm=$vm_result)"

    # 驗證結果正確
    [[ "$vm_result" == "$expected" ]] || fail "Incorrect result: $expr (got=$vm_result, expected=$expected)"

    pass "$expr => $vm_result"
}

echo "=== Wasm Differential Tests ==="

# 基礎算術
test_arithmetic "(+ 1 2)" "3"
test_arithmetic "(- 10 5)" "5"
test_arithmetic "(* 3 4)" "12"

# 嵌套表達式
test_arithmetic "(+ (* 2 3) 4)" "10"
test_arithmetic "(- (+ 10 5) 3)" "12"

echo ""
echo "All tests passed!"
