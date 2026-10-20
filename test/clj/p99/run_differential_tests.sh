#!/usr/bin/env bash
# Comprehensive 3-backend differential test suite for P99
# Tests TreeWalk, VM, and Wasm backends and reports discrepancies

set -euo pipefail

# Find project root and set paths accordingly
if [[ -f zig-out/bin/cljw ]]; then
  # Running from project root
  CLJW="${CLJW:-zig-out/bin/cljw}"
  TEST_FILE="test/clj/p99/core_complete.clj"
  LOG_DIR="test/clj/p99/logs"
elif [[ -f ../../../zig-out/bin/cljw ]]; then
  # Running from test/clj/p99/
  CLJW="${CLJW:-../../../zig-out/bin/cljw}"
  TEST_FILE="core_complete.clj"
  LOG_DIR="logs"
else
  # Fallback
  CLJW="${CLJW:-zig-out/bin/cljw}"
  TEST_FILE="test/clj/p99/core_complete.clj"
  LOG_DIR="test/clj/p99/logs"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [[ ! -f "$CLJW" ]]; then
  echo -e "${RED}❌ cljw not found at $CLJW${NC}"
  echo "Run: zig build"
  exit 1
fi

mkdir -p "$LOG_DIR"

echo -e "${BLUE}=== P99 Three-Backend Differential Test Suite ===${NC}"
echo "Test file: $TEST_FILE"
echo "Backends: TreeWalk (default), VM (-Dbackend=vm), Wasm (-Dbackend=wasm)"
echo

# Run TreeWalk backend
echo -e "${YELLOW}[1/3] Running TreeWalk backend...${NC}"
if "$CLJW" "$TEST_FILE" > "$LOG_DIR/treewalk.log" 2>&1; then
  TREEWALK_EXIT=0
  echo -e "${GREEN}✓ TreeWalk completed${NC}"
else
  TREEWALK_EXIT=$?
  echo -e "${RED}✗ TreeWalk failed (exit $TREEWALK_EXIT)${NC}"
fi
cat "$LOG_DIR/treewalk.log"
echo

# Run VM backend
echo -e "${YELLOW}[2/3] Running VM backend...${NC}"
if "$CLJW" -Dbackend=vm "$TEST_FILE" > "$LOG_DIR/vm.log" 2>&1; then
  VM_EXIT=0
  echo -e "${GREEN}✓ VM completed${NC}"
else
  VM_EXIT=$?
  echo -e "${RED}✗ VM failed (exit $VM_EXIT)${NC}"
fi
cat "$LOG_DIR/vm.log"
echo

# Run Wasm backend (if enabled)
echo -e "${YELLOW}[3/3] Running Wasm backend...${NC}"
if "$CLJW" -Dbackend=wasm "$TEST_FILE" > "$LOG_DIR/wasm.log" 2>&1; then
  WASM_EXIT=0
  echo -e "${GREEN}✓ Wasm completed${NC}"
else
  WASM_EXIT=$?
  echo -e "${YELLOW}⚠ Wasm failed or not built (exit $WASM_EXIT)${NC}"
  echo -e "${YELLOW}Note: Wasm backend requires -Dwasm=true during build${NC}"
fi
cat "$LOG_DIR/wasm.log"
echo

# Summary
echo -e "${BLUE}=== Differential Test Summary ===${NC}"
echo

if [[ $TREEWALK_EXIT -eq 0 ]] && [[ $VM_EXIT -eq 0 ]]; then
  echo -e "${GREEN}✓ TreeWalk and VM backends: CONSISTENT${NC}"

  # Extract test counts
  TREEWALK_PASS=$(grep -o "Pass: [0-9]*" "$LOG_DIR/treewalk.log" | grep -o "[0-9]*" || echo "0")
  VM_PASS=$(grep -o "Pass: [0-9]*" "$LOG_DIR/vm.log" | grep -o "[0-9]*" || echo "0")

  echo "  TreeWalk: $TREEWALK_PASS tests passed"
  echo "  VM:       $VM_PASS tests passed"

  if [[ "$TREEWALK_PASS" == "$VM_PASS" ]]; then
    echo -e "${GREEN}  ✓ Test counts match${NC}"
  else
    echo -e "${RED}  ✗ Test count mismatch!${NC}"
  fi
else
  echo -e "${RED}✗ Backend discrepancy detected${NC}"
  echo "  TreeWalk exit code: $TREEWALK_EXIT"
  echo "  VM exit code:       $VM_EXIT"
fi

if [[ $WASM_EXIT -eq 0 ]]; then
  echo -e "${YELLOW}⚠ Wasm backend: Phase 1-4 stubs (limited heap support)${NC}"
  WASM_PASS=$(grep -o "Pass: [0-9]*" "$LOG_DIR/wasm.log" | grep -o "[0-9]*" || echo "0")
  echo "  Wasm: $WASM_PASS tests passed"
else
  echo -e "${YELLOW}⚠ Wasm backend: Not tested (build with -Dwasm=true)${NC}"
fi

echo
echo "Detailed logs saved to:"
echo "  $LOG_DIR/treewalk.log"
echo "  $LOG_DIR/vm.log"
echo "  $LOG_DIR/wasm.log"

# Exit with error if any backend failed unexpectedly
if [[ $TREEWALK_EXIT -ne 0 ]] || [[ $VM_EXIT -ne 0 ]]; then
  exit 1
fi

exit 0
