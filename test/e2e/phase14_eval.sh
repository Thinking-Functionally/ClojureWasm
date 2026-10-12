#!/usr/bin/env bash
# e2e: clojure.core/eval (D-162 / ADR-0058)
# Proves eval reaches BOTH the runtime evaluator AND the built-in macro
# table (when / -> / and expand inside eval'd forms).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLJW="$ROOT/zig-out/bin/cljw"

pass=0
fail=0

check() {
  local desc="$1" expr="$2" want="$3"
  local got
  got="$("$CLJW" -e "$expr" 2>&1)" || true
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $desc"
    echo "  expr: $expr"
    echo "  want: $want"
    echo "  got:  $got"
  fi
}

# Motivating case: read-string then eval.
check "eval read-string arithmetic" '(eval (read-string "(+ 1 2)"))' '3'
# Self-evaluating literals round-trip through valueToForm.
check "eval self-eval int"     '(eval 42)' '42'
check "eval self-eval keyword" '(eval :kw)' ':kw'
check "eval self-eval vector"  '(eval [1 2 3])' '[1 2 3]'
# Constructed list with a quoted symbol head.
check "eval constructed list" '(eval (list (symbol "+") 1 2 3))' '6'
# Special form inside eval.
check "eval special form if" '(eval (quote (if true :yes :no)))' ':yes'
# THE structural proof: built-in Zig macros must expand inside eval
# (this is why eval needs the macro_table, not just env).
check "eval built-in macro when" '(eval (quote (when true 7)))' '7'
check "eval built-in macro ->"   '(eval (quote (-> 5 inc inc)))' '7'
check "eval built-in macro and"  '(eval (quote (and 1 2 3)))' '3'
# Nested eval.
check "eval nested" '(eval (quote (eval (quote (+ 4 5)))))' '9'

# D-374: a top-level `(do …)` is unrolled — each child is analyzed+evaluated in
# sequence, so an effect in an earlier child is visible to a later child's
# ANALYSIS (clj parity). Without unrolling, `(m)` is analyzed before `defmacro m`
# runs → "macro Var not callable".
check "top-level do: defmacro then use" '(do (defmacro m374 [] 42) (m374))' '42'
check "top-level do: def then use"      '(do (def x374 5) (+ x374 1))' '6'
check "top-level do: value is last child" '(do 1 2 3)' '3'
check "top-level do: nested do unrolls"  '(do (do (def y374 9)) (inc y374))' '10'
# eval of a top-level (do …) unrolls too (eval treats its arg as a top-level form).
check "eval top-level do unrolls" '(eval (quote (do (defmacro n374 [] 7) (n374))))' '7'

# Regression test for eval use-after-free bug: eval returns a function,
# that function is called later. The function's bytecode and captured values
# must live in rt.load_arena (persistent), not in a temporary arena that gets
# freed when eval returns.
check "eval returns callable fn" '((eval (quote (fn [x] (+ x 10)))) 5)' '15'
check "eval defn then call" '(do (eval (quote (defn add-twenty [x] (+ x 20)))) (add-twenty 5))' '25'

echo "pass=$pass fail=$fail"
if [[ $fail -gt 0 ]]; then exit 1; fi
