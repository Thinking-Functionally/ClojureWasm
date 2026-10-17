;; min-key/max-key tie-breaking behavior tests
;;
;; Tests the fix for tie-breaking in min-key/max-key: when multiple elements
;; have the same key value, the LAST one should be returned (not the first).
;; This matches JVM Clojure behavior.
;;
;; Fix: Changed from `(if (> (f b) (f a)) b a)` to `(if (>= (f b) (f a)) b a)`
;; in src/lang/clj/clojure/core.clj
;;
;; Related commits:
;; - 7c967d1a (initial broken implementation)
;; - be5424b0 (fix with >= and <=)
;; - f74ecd50 (cherry-picked to fix/eval-uaf)

(require '[clojure.test])

;; CLJW: A — min-key tie-breaking with vector as key function
;; When two elements have the same minimum key, return the LAST one
(clojure.test/deftest test-min-key-tie-vector
  (clojure.test/is (= 2 (apply min-key [-2 -1 -2 0] (range 4)))))

;; CLJW: A — max-key tie-breaking with vector as key function
;; When two elements have the same maximum key, return the LAST one
(clojure.test/deftest test-max-key-tie-vector
  (clojure.test/is (= 2 (apply max-key [1 3 3 0] (range 4)))))

;; CLJW: A — min-key tie-breaking with 2-arity
(clojure.test/deftest test-min-key-tie-2-arity
  (clojure.test/is (= 1 (min-key [5 5] 0 1))))

;; CLJW: A — max-key tie-breaking with 2-arity
(clojure.test/deftest test-max-key-tie-2-arity
  (clojure.test/is (= 1 (max-key [5 5] 0 1))))

;; CLJW: A — min-key with constant key function
;; All elements have the same key, should return the LAST one
(clojure.test/deftest test-min-key-const-key
  (clojure.test/is (= "c" (min-key (fn* [_] 1) "a" "b" "c"))))

;; CLJW: A — max-key with constant key function
;; All elements have the same key, should return the LAST one
(clojure.test/deftest test-max-key-const-key
  (clojure.test/is (= "c" (max-key (fn* [_] 1) "a" "b" "c"))))

;; CLJW: A — min-key without tie
(clojure.test/deftest test-min-key-no-tie
  (clojure.test/is (= "a" (min-key count "aaa" "a" "aa"))))

;; CLJW: A — max-key without tie
(clojure.test/deftest test-max-key-no-tie
  (clojure.test/is (= [1 2 3] (max-key count [1] [1 2 3] [1 2]))))

;; CLJW: A — min-key with single argument
(clojure.test/deftest test-min-key-single-arg
  (clojure.test/is (= [1] (min-key count [1]))))

;; CLJW: A — Book example: circular race track starting point
;; From "The Joy of Clojure" - find the best starting point for a circular race
(clojure.test/deftest test-min-key-book-example
  (let [cum (vec (reductions + (map - [1 3 2 4] [3 2 3 2])))]
    (clojure.test/is (= 3 (mod (inc (apply min-key cum (range (count cum)))) (count cum))))))

;; Run all tests and print summary
(let [summary (clojure.test/run-tests)]
  (println)
  (println "Summary:" (:pass summary) "passed," (:fail summary) "failed," (:error summary) "errors")
  [(:pass summary) (:fail summary)])
