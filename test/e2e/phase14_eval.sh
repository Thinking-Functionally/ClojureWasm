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

# Extended regression tests for eval arena lifetime (the original bug):
# When eval returns a closure, a second eval should not corrupt the first closure's
# captured environment. These tests verify that closures survive GC and memory reuse.

# Test 1: eval a fn, eval another fn, call the first fn
got=$("$CLJW" - <<'EOF'
(def h (eval (read-string "(fn [x] (+ x 1))")))
(eval (read-string "(fn [x] (* x 100))"))
(h 1)
EOF
)
if [[ "$got" == "2" ]]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: eval'd fn survives a later eval"
  echo "  want: 2"
  echo "  got:  $got"
fi

# Test 2: eval two defns, both should be callable
got=$("$CLJW" - <<'EOF'
(eval (read-string "(defn f1 [x] (+ x 1))"))
(eval (read-string "(defn g1 [x] (* x 100))"))
(println (f1 1) (g1 1))
EOF
)
if [[ "$got" == "2 100" ]]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: eval'd defns f1 and g1"
  echo "  want: 2 100"
  echo "  got:  $got"
fi

# Test 3: eval 100 defns, then trigger GC with heavy work, all should return correct values
got=$("$CLJW" - <<'EOF'
(doseq [i (range 100)] (eval (read-string (str "(defn k" i " [] " i ")"))))
(def junk (reduce + (map (fn [x] (* x x)) (range 300000))))
(mapv #((deref (resolve (symbol (str "k" %))))) (range 100))
EOF
)
want="[0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99]"
if [[ "$got" == "$want" ]]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: 100 eval'd defns after GC-heavy work"
  echo "  want: $want"
  echo "  got:  $got"
fi

# Test 4: eval a chain of definitions, then run 100k monte carlo trials
# This would Bus error if the eval'd closures reference freed memory
got=$("$CLJW" - <<'EOF'
(defn ev [s] (eval (read-string s)))
(ev "(def m31 2147483647)")
(ev "(defn lcg [seed] (rest (iterate #(mod (* 48271 %) m31) seed)))")
(ev "(defn uniforms [seed] (map #(/ % (double m31)) (lcg seed)))")
(ev "(defn mean [xs] (/ (reduce + xs) (count xs)))")
(ev "(defn die [u] (inc (int (* 6 u))))")
(ev "(defn monte-carlo [trial k n xs] (mean (map trial (take n (partition k xs)))))")
(monte-carlo (fn [[u v]] (if (= 7 (+ (die u) (die v))) 1.0 0.0)) 2 100000 (uniforms 42))
EOF
)
if [[ "$got" == "0.16674" ]]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: eval'd book chain, 100k trials"
  echo "  want: 0.16674"
  echo "  got:  $got"
fi

echo "pass=$pass fail=$fail"
if [[ $fail -gt 0 ]]; then exit 1; fi
