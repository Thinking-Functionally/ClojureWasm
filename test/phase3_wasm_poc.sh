#!/usr/bin/env bash
# SPDX-License-Identifier: EPL-2.0
# Phase 3 Wasm PoC: 最小可行測試
#
# 測試目標:
#   1. Wasm 模組建造器可以生成有效 Wasm 字節碼
#   2. Wasm 模組格式正確 (magic number + sections)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Phase 3 Wasm PoC: Wasm module builder test"

# Build
echo "Building cljw..."
zig build -Dwasm >/dev/null 2>&1 || {
  echo "FAIL: zig build failed"
  exit 1
}

# Run unit tests for wasm_module_builder
echo "Running wasm_module_builder unit test..."
zig build test >/dev/null 2>&1 || {
  echo "FAIL: unit tests failed"
  exit 1
}

echo "✓ Phase 3 Wasm PoC: Wasm module builder tests passed"
echo ""
echo "Next steps:"
echo "  1. Tier 1: Control flow (op_jump, op_jump_if_false, op_recur)"
echo "  2. Tier 2: Function calls (op_call with function table)"
echo "  3. Tier 3: Integration with zwasm API"
echo "  4. Tier 4: Three-way differential oracle (TreeWalk/VM/Wasm)"
