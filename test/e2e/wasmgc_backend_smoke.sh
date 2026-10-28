#!/usr/bin/env bash
# test/e2e/wasmgc_backend_smoke.sh — the WasmGC backend (`--backend=wasmgc`)
# evaluates real programs and produces the exact values the other backends do.
# Every assertion compares output, so this cannot pass vacuously (it replaces an
# earlier script that only echoed PASS). Covers: literals, arithmetic through
# host imports, closures, loop/recur, try/catch/finally, binding, collections,
# callbacks from core fns into WASM-compiled fns, and error exit codes.
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN="zig-out/bin/cljw"
[ -n "${CLJW_SKIP_BUILD:-}" ] || zig build -Dwasm -Doptimize="${CLJW_OPT:-ReleaseSafe}" >/dev/null
fail() { echo "FAIL $1" >&2; exit 1; }
assert_eq() { local n="$1" g="$2" w="$3"; [[ "$g" == "$w" ]] || fail "$n: got '$g' want '$w'"; echo "PASS $n -> $w"; }
wg() { "$BIN" --backend=wasmgc -e "$1" 2>&1; }

assert_eq 'int_literal'   "$(wg '42')" '42'
assert_eq 'bool_literal'  "$(wg 'true')" 'true'
assert_eq 'nil_literal'   "$(wg 'nil')" 'nil'
assert_eq 'add'           "$(wg '(+ 1 2)')" '3'
assert_eq 'mul'           "$(wg '(* 3 7)')" '21'
assert_eq 'double'        "$(wg '(* 1.5 2)')" '3.0'
assert_eq 'vector_map'    "$(wg '[1 2 {:a 1}]')" '[1 2 {:a 1}]'
assert_eq 'let'           "$(wg '(let [x 5] (* x x))')" '25'
assert_eq 'if'            "$(wg '(if nil :a :b)')" ':b'
assert_eq 'fn_call'       "$(wg '((fn [x] (* x x)) 7)')" '49'
assert_eq 'closure'       "$(wg '(let [k 10] ((fn [x] (+ x k)) 5))')" '15'
assert_eq 'self_recursion' "$(wg '((fn f [n] (if (< n 2) 1 (* n (f (dec n))))) 10)')" '3628800'
assert_eq 'loop_recur'    "$(wg '(loop [i 0 s 0] (if (< i 1000) (recur (inc i) (+ s i)) s))')" '499500'
assert_eq 'fn_tail_recur' "$(wg '((fn [n acc] (if (zero? n) acc (recur (dec n) (+ acc n)))) 100000 0)')" '5000050000'
assert_eq 'multi_arity'   "$(wg '((fn ([a] a) ([a b] (+ a b))) 1 2)')" '3'
assert_eq 'variadic'      "$(wg '((fn [a & r] [a r]) 1 2 3)')" '[1 (2 3)]'
assert_eq 'callback_map'  "$(wg '(map (fn [x] (inc x)) [1 2 3])')" '(2 3 4)'
assert_eq 'callback_reduce' "$(wg '(reduce (fn [a b] (+ a b)) 0 (range 1000))')" '499500'
assert_eq 'try_catch'     "$(wg '(try (throw (ex-info "x" {:a 1})) (catch Exception e (ex-data e)))')" '{:a 1}'
assert_eq 'try_internal'  "$(wg '(try (/ 1 0) (catch ArithmeticException e :div))')" ':div'
assert_eq 'finally_order' "$(wg '(let [l (atom [])] (try (try (throw (Exception. "e")) (finally (swap! l conj :f))) (catch Exception e (swap! l conj :c))) @l)')" '[:f :c]'
assert_eq 'binding'       "$(wg '(do (def ^:dynamic *v* 1) [*v* (binding [*v* 2] *v*) *v*])')" '[1 2 1]'
assert_eq 'letfn'         "$(wg '(letfn [(ev? [n] (if (zero? n) true (od? (dec n)))) (od? [n] (if (zero? n) false (ev? (dec n))))] (ev? 10))')" 'true'
assert_eq 'future'        "$(wg '(let [x 5] @(future (+ x 1)))')" '6'
assert_eq 'interop'       "$(wg '(.toUpperCase "abc")')" '"ABC"'
assert_eq 'def_then_call' "$(wg '(do (defn sq [x] (* x x)) (sq 12))')" '144'

# An uncaught error exits non-zero and names the error (not a crash).
set +e
out="$("$BIN" --backend=wasmgc -e '(throw (ex-info "boom" {}))' 2>&1)"; rc=$?
set -e
[[ "$rc" == 1 ]] || fail "uncaught_exit_code: got $rc want 1"
[[ "$out" == *boom* ]] || fail "uncaught_message: '$out' lacks 'boom'"
echo "PASS uncaught_error -> exit 1 + message"

# Same answers as the other backends on a mixed program.
prog='(let [f (fn [x] (* x 2))] (vec (map f (filter odd? (range 10)))))'
want="$("$BIN" --backend=vm -e "$prog" 2>&1)"
assert_eq 'matches_vm'        "$(wg "$prog")" "$want"
assert_eq 'matches_tree_walk' "$("$BIN" --backend=tree_walk -e "$prog" 2>&1)" "$want"
