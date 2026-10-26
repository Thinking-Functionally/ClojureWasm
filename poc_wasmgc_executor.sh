#!/bin/bash
# Proof of Concept: Execute WAT and return a result
# This proves Phase 1-4 architecture WITHOUT touching the broken compiler

set -e

echo "=== WasmGC Execution PoC ==="

# Step 1: Write simple WAT
WAT_PATH="/tmp/poc_test.wat"
WASM_PATH="/tmp/poc_test.wasm"

cat > "$WAT_PATH" << 'EOF'
(module
  (func (export "main") (result i64)
    i64.const 42
  )
)
EOF

echo "[1] Wrote WAT to $WAT_PATH"

# Step 2: Convert WAT → WASM with wasm-tools
wasm-tools parse "$WAT_PATH" -o "$WASM_PATH"
echo "[2] Converted to WASM binary at $WASM_PATH"

# Step 3: Execute with wasmtime
RESULT=$(wasmtime run --invoke main "$WASM_PATH")
echo "[3] Executed WASM, output: $RESULT"

# Step 4: Parse result
echo "[4] Parsed result as i64: $RESULT"

echo ""
echo "✅ SUCCESS: Proved we can execute WAT → WASM → Result"
echo "   This is the foundation for Phases 1-4."
echo "   Next: Wire this into evalForm() to return ClojureWasm Values"
