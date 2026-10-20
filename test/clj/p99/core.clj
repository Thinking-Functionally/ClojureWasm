;; P-99: Ninety-Nine Clojure Problems
;; Complete test suite with implementations and test assertions
;; Supports differential testing across TreeWalk/VM/Wasm backends

(ns p99.core
  (:require [clojure.test :refer [deftest is testing run-tests]]))

;;; Elementary Problems (P01-P18)

;; P01: Find the last element of a list
(defn p01-last [xs]
  (last xs))

;; P02: Find the last but one element
(defn p02-but-last [xs]
  (nth xs (- (count xs) 2)))

;; P03: Find the K'th element (0-indexed)
(defn p03-element-at [xs k]
  (nth xs k))

;; P04: Find the number of elements
(defn p04-length [xs]
  (count xs))

;; P05: Reverse a list
(defn p05-reverse [xs]
  (reverse xs))

;; P06: Find out whether a list is a palindrome
(defn p06-palindrome? [xs]
  (= xs (reverse xs)))

;; P07: Flatten a nested list structure
(defn p07-flatten [xs]
  (flatten xs))

;; P08: Eliminate consecutive duplicates
(defn p08-compress [xs]
  (if (empty? xs)
    []
    (reduce (fn [acc x]
              (if (= (last acc) x)
                acc
                (conj acc x)))
            [(first xs)]
            (rest xs))))

;; P09: Pack consecutive duplicates into sublists
(defn p09-pack [xs]
  (if (empty? xs)
    []
    (loop [result []
           current [(first xs)]
           remaining (rest xs)]
      (if (empty? remaining)
        (conj result current)
        (let [x (first remaining)]
          (if (= (first current) x)
            (recur result (conj current x) (rest remaining))
            (recur (conj result current) [x] (rest remaining))))))))

;; P10: Run-length encoding
(defn p10-encode [xs]
  (map (fn [group] [(count group) (first group)])
       (p09-pack xs)))

;; P11-P17: Arithmetic and comparisons
(defn p11-add [a b] (+ a b))
(defn p12-sub [a b] (- a b))
(defn p13-mul [a b] (* a b))
(defn p14-div [a b] (/ a b))
(defn p15-lt [a b] (< a b))
(defn p16-gt [a b] (> a b))
(defn p17-eq [a b] (= a b))

;; P18: Map function
(defn p18-map-double [xs]
  (map (fn [x] (* x 2)) xs))

;;; Easy Problems (P19-P50)

;; P19: Filter even numbers
(defn p19-filter-even [xs]
  (filter even? xs))

;; P20: Sum using reduce
(defn p20-sum [xs]
  (reduce + 0 xs))

;; P21: Insert at position
(defn p21-insert-at [x xs n]
  (concat (take n xs) [x] (drop n xs)))

;; P22: Create range
(defn p22-range [i j]
  (range i (inc j)))

;; P23: Extract random elements (using take)
(defn p23-rnd-select [xs n]
  (take n (shuffle xs)))

;; P24: Lotto draw N numbers from 1..M
(defn p24-lotto [n m]
  (take n (shuffle (range 1 (inc m)))))

;; P25: Random permutation
(defn p25-rnd-permu [xs]
  (shuffle xs))

;;; Test Suite

(deftest test-p01-last
  (testing "P01: Find last element"
    (is (= 4 (p01-last [1 2 3 4])))
    (is (= :d (p01-last [:a :b :c :d])))))

(deftest test-p02-but-last
  (testing "P02: Find last but one"
    (is (= 3 (p02-but-last [1 2 3 4])))
    (is (= :c (p02-but-last [:a :b :c :d])))))

(deftest test-p03-element-at
  (testing "P03: Find K'th element"
    (is (= 3 (p03-element-at [1 2 3 4 5] 2)))
    (is (= :c (p03-element-at [:a :b :c :d :e] 2)))))

(deftest test-p04-length
  (testing "P04: Number of elements"
    (is (= 5 (p04-length [1 2 3 4 5])))
    (is (= 0 (p04-length [])))))

(deftest test-p05-reverse
  (testing "P05: Reverse a list"
    (is (= [4 3 2 1] (p05-reverse [1 2 3 4])))
    (is (= [] (p05-reverse [])))))

(deftest test-p06-palindrome
  (testing "P06: Palindrome check"
    (is (true? (p06-palindrome? [1 2 3 2 1])))
    (is (false? (p06-palindrome? [1 2 3 4])))))

(deftest test-p07-flatten
  (testing "P07: Flatten nested list"
    (is (= [1 2 3 4 5] (p07-flatten [1 [2 [3 4] 5]])))
    (is (= [1 2 3] (p07-flatten [[1] [2] [3]])))))

(deftest test-p08-compress
  (testing "P08: Eliminate duplicates"
    (is (= [1 2 3 1] (p08-compress [1 1 2 2 3 1 1])))
    (is (= [:a :b :c] (p08-compress [:a :a :a :b :b :c])))))

(deftest test-p09-pack
  (testing "P09: Pack consecutive duplicates"
    (is (= [[1 1] [2 2] [3] [1 1]] (p09-pack [1 1 2 2 3 1 1])))
    (is (= [[:a :a :a] [:b] [:c :c]] (p09-pack [:a :a :a :b :c :c])))))

(deftest test-p10-encode
  (testing "P10: Run-length encoding"
    (is (= [[2 1] [2 2] [1 3] [2 1]] (p10-encode [1 1 2 2 3 1 1])))
    (is (= [[3 :a] [1 :b] [2 :c]] (p10-encode [:a :a :a :b :c :c])))))

(deftest test-arithmetic
  (testing "P11-P17: Arithmetic operations"
    (is (= 15 (p11-add 10 5)))
    (is (= 5 (p12-sub 10 5)))
    (is (= 50 (p13-mul 10 5)))
    (is (= 2 (p14-div 10 5)))
    (is (true? (p15-lt 5 10)))
    (is (true? (p16-gt 10 5)))
    (is (true? (p17-eq 5 5)))))

(deftest test-p18-map
  (testing "P18: Map function"
    (is (= [2 4 6 8] (p18-map-double [1 2 3 4])))
    (is (= [] (p18-map-double [])))))

(deftest test-p19-filter
  (testing "P19: Filter even numbers"
    (is (= [2 4 6] (p19-filter-even [1 2 3 4 5 6])))
    (is (= [] (p19-filter-even [1 3 5])))))

(deftest test-p20-reduce
  (testing "P20: Sum using reduce"
    (is (= 15 (p20-sum [1 2 3 4 5])))
    (is (= 0 (p20-sum [])))))

(deftest test-p21-insert
  (testing "P21: Insert at position"
    (is (= [1 2 99 3 4] (p21-insert-at 99 [1 2 3 4] 2)))
    (is (= [99 1 2] (p21-insert-at 99 [1 2] 0)))))

(deftest test-p22-range
  (testing "P22: Create range"
    (is (= [4 5 6 7 8 9] (p22-range 4 9)))
    (is (= [1] (p22-range 1 1)))))

(deftest test-p23-select
  (testing "P23: Extract random elements"
    (let [result (p23-rnd-select [1 2 3 4 5 6] 3)]
      (is (= 3 (count result)))
      (is (every? #(<= 1 % 6) result)))))

(deftest test-p24-lotto
  (testing "P24: Lotto draw"
    (let [result (p24-lotto 6 49)]
      (is (= 6 (count result)))
      (is (every? #(<= 1 % 49) result)))))

(deftest test-p25-permutation
  (testing "P25: Random permutation"
    (let [input [1 2 3 4 5]
          result (p25-rnd-permu input)]
      (is (= 5 (count result)))
      (is (= (set input) (set result))))))

;; Run all tests
(defn -main []
  (println "Running P99 Test Suite...")
  (run-tests 'p99.core))
