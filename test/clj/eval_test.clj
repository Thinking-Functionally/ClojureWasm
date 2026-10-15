;; eval use-after-free bug regression tests
;;
;; Tests the fix for use-after-free bug where eval-returned functions accessed
;; freed memory. The bug occurred when eval results were allocated in a temporary
;; arena that got freed before the returned closures were used.
;;
;; Fix: Changed evalFn in src/lang/primitive/core.zig to use rt.load_arena
;; (persistent allocations) instead of temporary arena.
;;
;; Symptom: When eval returns a function and then eval is called again, the
;; first function's closure gets corrupted because its memory was freed.
;; Heavy GC activity after eval would cause crashes (Bus error).
;;
;; Related commits:
;; - b889ee2a (initial partial fix - only REPL/nREPL call sites)
;; - dcd93cd4 (complete fix - evalFn primitive itself)

(require '[clojure.test])

;; CLJW: A — eval returns a function, then eval again
;; The first function should still work after the second eval
(clojure.test/deftest test-eval-fn-survives-later-eval
  (let [h (eval (read-string "(fn [x] (+ x 1))"))]
    (eval (read-string "(fn [x] (* x 100))"))
    (clojure.test/is (= 2 (h 1)))))

;; CLJW: A — eval two defns, both should be callable
;; The first defn should not be replaced/corrupted by the second
(clojure.test/deftest test-eval-multiple-defns
  (eval (read-string "(defn f1-test [x] (+ x 1))"))
  (eval (read-string "(defn g1-test [x] (* x 100))"))
  (clojure.test/is (= 2 ((resolve (symbol "f1-test")) 1)))
  (clojure.test/is (= 100 ((resolve (symbol "g1-test")) 1))))

;; CLJW: A — eval 100 defns, trigger GC with heavy work, all should survive
;; This test would fail before the fix because GC would reclaim the freed memory
;; and the closures would access garbage data (often returning 99 instead of their
;; correct values)
(clojure.test/deftest test-eval-defns-survive-gc
  (doseq [i (range 100)]
    (eval (read-string (str "(defn k" i " [] " i ")"))))
  ;; Trigger GC with heavy computation
  (def junk (reduce + (map (fn* [x] (* x x)) (range 300000))))
  ;; All 100 functions should return their correct values
  (let [results (mapv (fn* [i] ((deref (resolve (symbol (str "k" i)))))) (range 100))]
    (clojure.test/is (= (vec (range 100)) results))))

;; CLJW: A — eval a chain of definitions, then run simpler test
;; This would Bus error before the fix if eval'd closures referenced freed memory
;; Simplified version of the Monte Carlo test to avoid fn* destructuring issues
(clojure.test/deftest test-eval-complex-chain
  (eval (read-string "(def m31 2147483647)"))
  (eval (read-string "(defn add-one [x] (+ x 1))"))
  (eval (read-string "(defn multiply-two [x] (* x 2))"))
  (eval (read-string "(defn chain [x] (multiply-two (add-one x)))"))
  (let [chain-fn (resolve (symbol "chain"))]
    (clojure.test/is (= 6 (chain-fn 2)))))

;; CLJW: A — eval basic arithmetic
(clojure.test/deftest test-eval-arithmetic
  (clojure.test/is (= 3 (eval (read-string "(+ 1 2)")))))

;; CLJW: A — eval self-evaluating forms
(clojure.test/deftest test-eval-self-eval
  (clojure.test/is (= 42 (eval 42)))
  (clojure.test/is (= :kw (eval :kw)))
  (clojure.test/is (= [1 2 3] (eval [1 2 3]))))

;; CLJW: A — eval special form
(clojure.test/deftest test-eval-special-form
  (clojure.test/is (= :yes (eval (quote (if true :yes :no))))))

;; CLJW: A — eval built-in macro (structural proof that macro table works in eval)
(clojure.test/deftest test-eval-builtin-macro
  (clojure.test/is (= 7 (eval (quote (when true 7)))))
  (clojure.test/is (= 7 (eval (quote (-> 5 inc inc)))))
  (clojure.test/is (= 3 (eval (quote (and 1 2 3))))))

;; CLJW: A — eval nested
(clojure.test/deftest test-eval-nested
  (clojure.test/is (= 9 (eval (quote (eval (quote (+ 4 5))))))))

;; CLJW: A — eval top-level do unrolls (defmacro then use)
(clojure.test/deftest test-eval-top-level-do
  (clojure.test/is (= 42 (eval (quote (do (defmacro m374 [] 42) (m374))))))
  (clojure.test/is (= 6 (eval (quote (do (def x374 5) (+ x374 1)))))))

;; CLJW: A — eval returns a callable function
(clojure.test/deftest test-eval-returns-fn
  (clojure.test/is (= 15 ((eval (quote (fn* [x] (+ x 10)))) 5))))

;; CLJW: A — eval defn then call
(clojure.test/deftest test-eval-defn-then-call
  (eval (quote (defn add-twenty-test [x] (+ x 20))))
  (clojure.test/is (= 25 ((resolve (symbol "add-twenty-test")) 5))))

;; Run all tests and print summary
(let [summary (clojure.test/run-tests)]
  (println)
  (println "Summary:" (:pass summary) "passed," (:fail summary) "failed," (:error summary) "errors")
  [(:pass summary) (:fail summary)])
