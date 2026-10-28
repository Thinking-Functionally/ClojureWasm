(ns p99.logic-test
  (:require [clojure.test :refer [deftest is]]
            [clojure.string]
            [p99.logic :as g]))

(deftest p46-connectives
  (is (= [[true true true] [true false false] [false true false] [false false false]]
         (g/truth-table 2 g/and*)))
  (is (= [[true true true] [true false true] [false true true] [false false false]]
         (g/truth-table 2 g/or*)))
  (is (= [[true true false] [true false true] [false true true] [false false true]]
         (g/truth-table 2 g/nand*)))
  (is (= [[true true false] [true false false] [false true false] [false false true]]
         (g/truth-table 2 g/nor*)))
  (is (= [[true true false] [true false true] [false true true] [false false false]]
         (g/truth-table 2 g/xor*)))
  (is (= [[true true true] [true false false] [false true true] [false false true]]
         (g/truth-table 2 g/impl*)))
  (is (= [[true true true] [true false false] [false true false] [false false true]]
         (g/truth-table 2 g/equ*)))
  (is (= [[true true true] [true false true] [false true false] [false false false]]
         (g/table [a b] (g/and* a (g/or* a b))))))

(deftest p47-infix-style-table-macro
  (is (= [[true true true] [true false true] [false true false] [false false false]]
         (g/table [a b] (and a (or a b)))))
  (is (= [[true true true] [true false false] [false true true] [false false true]]
         (g/table [a b] (g/impl* a b)))))

(deftest p48-n-variable-tables
  (is (= [[true true true true] [true true false true] [true false true true] [true false false true]
          [false true true false] [false true false true] [false false true true] [false false false false]]
         (g/table [a b c] (g/or* a (g/xor* b c)))))
  (is (= [[true]] (g/truth-table 0 (fn [] true))))
  (is (= [[true true] [false false]] (g/truth-table 1 identity)))
  (doseq [n (range 0 6)]
    (let [rows (g/truth-table n (fn [& _] true))]
      (is (= (bit-shift-left 1 n) (count rows)))
      (is (= (bit-shift-left 1 n) (count (set rows))))
      (is (every? #(= (inc n) (count %)) rows))))
  (is (= 4 (count (filter last (g/truth-table 3 (fn [a b c] (g/equ* a (g/equ* b c)))))))))

(deftest p49-gray-code
  (is (= [""] (g/gray 0)))
  (is (= ["0" "1"] (g/gray 1)))
  (is (= ["00" "01" "11" "10"] (g/gray 2)))
  (is (= ["000" "001" "011" "010" "110" "111" "101" "100"] (g/gray 3)))
  (doseq [n (range 1 8)]
    (let [c (g/gray n)
          differ (fn [a b] (count (filter false? (map = a b))))]
      (is (= (bit-shift-left 1 n) (count c)))
      (is (= (count c) (count (set c))))
      (is (every? #(= 1 (apply differ %)) (partition 2 1 c))))))

(def ^:private lw [[\a 45] [\b 13] [\c 12] [\d 16] [\e 9] [\f 5]])

(deftest p50-huffman
  (is (= [[\a "0"] [\b "101"] [\c "100"] [\d "111"] [\e "1101"] [\f "1100"]] (g/huffman lw)))
  (let [codes (g/huffman lw)
        lens (into {} (map (fn [[s c]] [s (count c)]) codes))]
    (is (= {\a 1 \b 3 \c 3 \d 3 \e 4 \f 4} lens))
    (is (= 224 (reduce + (map (fn [[s w]] (* w (lens s))) lw))))
    (is (= 1 (reduce + (map (fn [[_ c]] (/ 1 (bit-shift-left 1 (count c)))) codes))))
    (is (not-any? (fn [[[_ a] [_ b]]] (and (not= a b) (clojure.string/starts-with? a b)))
                  (for [x codes y codes] [x y]))))
  (is (= [[:x "0"]] (g/huffman [[:x 7]])))
  (is (= [[:a "0"] [:b "1"]] (g/huffman [[:a 1] [:b 9]])))
  (is (= #{2} (set (map (comp count second) (g/huffman [[:a 1] [:b 1] [:c 1] [:d 1]]))))))
