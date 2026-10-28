(ns fourclojure.core-test
  "4clojure problems 1-41, enabled. Derived from ../reference/core_test.clj.
  Problems 4, 6 and 36 have multi-form blanks in the original; their solutions
  are the vector of forms and the tests apply them explicitly."
  (:require [clojure.test :refer [deftest is]]
            [clojure.set]
            [fourclojure.core :refer :all]))

;; problem 1
(deftest can-nothing-but-the-truth
  (is (= nothing-but-the-truth-solution true)))

;; problem 2
(deftest can-simple-math
  (is (= (- 10 (* 2 3)) simple-math-solution)))

;; problem 3
(deftest can-intro-to-strings
  (is (= intro-to-strings-solution (.toUpperCase "hello world"))))

;; problem 4 (original blank is three forms: :a :b :c)
(deftest can-intro-to-lists
  (is (= (apply list intro-to-lists-solution) '(:a :b :c)))
  (is (= (list :a :b :c) (apply list intro-to-lists-solution))))

;; problem 5
(deftest can-lists-conj
  (is (= lists-conj-solution (conj '(2 3 4) 1)))
  (is (= lists-conj-solution (conj '(3 4) 2 1))))

;; problem 6 (original blank is three forms)
(deftest can-intro-to-vectors
  (is (= intro-to-vectors-solution (list :a :b :c) (vec '(:a :b :c)) (vector :a :b :c))))

;; problem 7
(deftest can-vectors-conj
  (is (= vectors-conj-solution (conj [1 2 3] 4)))
  (is (= vectors-conj-solution (conj [1 2] 3 4))))

;; problem 8
(deftest can-intro-to-sets
  (is (= intro-to-sets-solution (set '(:a :a :b :c :c :c :c :d :d))))
  (is (= intro-to-sets-solution (clojure.set/union #{:a :b :c} #{:b :c :d}))))

;; problem 9
(deftest can-sets-conj
  (is (= #{1 2 3 4} (conj #{1 4 3} sets-conj-solution))))

;; problem 10
(deftest can-intro-to-maps
  (is (= intro-to-maps-solution ((hash-map :a 10, :b 20, :c 30) :b)))
  (is (= intro-to-maps-solution (:b {:a 10, :b 20, :c 30}))))

;; problem 11
(deftest can-maps-conj
  (is (= {:a 1, :b 2, :c 3} (conj {:a 1} maps-conj-solution [:c 3]))))

;; problem 12
(deftest can-intro-to-sequences
  (is (= intro-to-sequences-solution (first '(3 2 1))))
  (is (= intro-to-sequences-solution (second [2 3 4])))
  (is (= intro-to-sequences-solution (last (list 1 2 3)))))

;; problem 13
(deftest can-sequences-rest
  (is (= sequences-rest-solution (rest [10 20 30 40]))))

;; problem 14
(deftest can-intro-to-functions
  (is (= intro-to-functions-solution ((fn add-five [x] (+ x 5)) 3)))
  (is (= intro-to-functions-solution ((fn [x] (+ x 5)) 3)))
  (is (= intro-to-functions-solution (#(+ % 5) 3)))
  (is (= intro-to-functions-solution ((partial + 5) 3))))

;; problem 15
(deftest can-double-down
  (is (= (double-down-solution 2) 4))
  (is (= (double-down-solution 3) 6))
  (is (= (double-down-solution 11) 22))
  (is (= (double-down-solution 7) 14)))

;; problem 16
(deftest can-hello-world
  (is (= (hello-world-solution "Dave") "Hello, Dave!"))
  (is (= (hello-world-solution "Jenn") "Hello, Jenn!"))
  (is (= (hello-world-solution "Rhea") "Hello, Rhea!")))

;; problem 17
(deftest can-sequences-map
  (is (= sequences-map-solution (map #(+ % 5) '(1 2 3)))))

;; problem 18
(deftest can-sequences-filter
  (is (= sequences-filter-solution (filter #(> % 5) '(3 4 5 6 7)))))

;; problem 19
(deftest can-last-element
  (is (= (last-element-solution [1 2 3 4 5]) 5))
  (is (= (last-element-solution '(5 4 3)) 3))
  (is (= (last-element-solution ["b" "c" "d"]) "d")))

;; problem 20
(deftest can-penultimate-element
  (is (= (penultimate-element-solution (list 1 2 3 4 5)) 4))
  (is (= (penultimate-element-solution ["a" "b" "c"]) "b"))
  (is (= (penultimate-element-solution [[1 2] [3 4]]) [1 2])))

;; problem 21
(deftest can-nth-element
  (is (= (nth-element-solution '(4 5 6 7) 2) 6))
  (is (= (nth-element-solution [:a :b :c] 0) :a))
  (is (= (nth-element-solution [1 2 3 4] 1) 2))
  (is (= (nth-element-solution '([1 2] [3 4] [5 6]) 2) [5 6])))

;; problem 22
(deftest can-count-a-sequence
  (is (= (count-a-sequence-solution '(1 2 3 3 1)) 5))
  (is (= (count-a-sequence-solution "Hello World") 11))
  (is (= (count-a-sequence-solution [[1 2] [3 4] [5 6]]) 3))
  (is (= (count-a-sequence-solution '(13)) 1))
  (is (= (count-a-sequence-solution '(:a :b :c)) 3)))

;; problem 23
(deftest can-reverse-a-sequence
  (is (= (reverse-a-sequence-solution [1 2 3 4 5]) [5 4 3 2 1]))
  (is (= (reverse-a-sequence-solution (sorted-set 5 7 2 7)) '(7 5 2)))
  (is (= (reverse-a-sequence-solution [[1 2][3 4][5 6]]) [[5 6][3 4][1 2]])))

;; problem 24
(deftest can-sum-it-all-up
  (is (= (sum-it-all-up-solution [1 2 3]) 6))
  (is (= (sum-it-all-up-solution (list 0 -2 5 5)) 8))
  (is (= (sum-it-all-up-solution #{4 2 1}) 7))
  (is (= (sum-it-all-up-solution '(0 0 -1)) -1))
  (is (= (sum-it-all-up-solution '(1 10 3)) 14)))

;; problem 25
(deftest can-find-the-odd-numbers
  (is (= (find-the-odd-numbers-solution #{1 2 3 4 5}) '(1 3 5)))
  (is (= (find-the-odd-numbers-solution [4 2 1 6]) '(1)))
  (is (= (find-the-odd-numbers-solution [2 2 4 6]) '()))
  (is (= (find-the-odd-numbers-solution [1 1 1 3]) '(1 1 1 3))))

;; problem 26
(deftest can-fibonacci-sequence
  (is (= (fibonacci-sequence-solution 3) '(1 1 2)))
  (is (= (fibonacci-sequence-solution 6) '(1 1 2 3 5 8)))
  (is (= (fibonacci-sequence-solution 8) '(1 1 2 3 5 8 13 21))))

;; problem 27
(deftest can-palindrome-detector
  (is (false? (palindrome-detector-solution '(1 2 3 4 5))))
  (is (true? (palindrome-detector-solution "racecar")))
  (is (true? (palindrome-detector-solution [:foo :bar :foo])))
  (is (true? (palindrome-detector-solution '(1 1 3 3 1 1))))
  (is (false? (palindrome-detector-solution '(:a :b :c)))))

;; problem 28
(deftest can-flatten-a-sequence
  (is (= (flatten-a-sequence-solution '((1 2) 3 [4 [5 6]])) '(1 2 3 4 5 6)))
  (is (= (flatten-a-sequence-solution ["a" ["b"] "c"]) '("a" "b" "c")))
  (is (= (flatten-a-sequence-solution '((((:a))))) '(:a))))

;; problem 29
(deftest can-get-the-caps
  (is (= (get-the-caps-solution "HeLlO, WoRlD!") "HLOWRD"))
  (is (empty? (get-the-caps-solution "nothing")))
  (is (= (get-the-caps-solution "$#A(*&987Zf") "AZ")))

;; problem 30
(deftest can-compress-a-sequence
  (is (= (apply str (compress-a-sequence-solution "Leeeeeerrroyyy")) "Leroy"))
  (is (= (compress-a-sequence-solution [1 1 2 3 3 2 2 3]) '(1 2 3 2 3)))
  (is (= (compress-a-sequence-solution [[1 2] [1 2] [3 4] [1 2]]) '([1 2] [3 4] [1 2]))))

;; problem 31
(deftest can-pack-a-sequence
  (is (= (pack-a-sequence-solution [1 1 2 1 1 1 3 3]) '((1 1) (2) (1 1 1) (3 3))))
  (is (= (pack-a-sequence-solution [:a :a :b :b :c]) '((:a :a) (:b :b) (:c))))
  (is (= (pack-a-sequence-solution [[1 2] [1 2] [3 4]]) '(([1 2] [1 2]) ([3 4])))))

;; problem 32
(deftest can-duplicate-a-sequence
  (is (= (duplicate-a-sequence-solution [1 2 3]) '(1 1 2 2 3 3)))
  (is (= (duplicate-a-sequence-solution [:a :a :b :b]) '(:a :a :a :a :b :b :b :b)))
  (is (= (duplicate-a-sequence-solution [[1 2] [3 4]]) '([1 2] [1 2] [3 4] [3 4]))))

;; problem 33
(deftest can-replicate-a-sequence
  (is (= (replicate-a-sequence-solution [1 2 3] 2) '(1 1 2 2 3 3)))
  (is (= (replicate-a-sequence-solution [:a :b] 4) '(:a :a :a :a :b :b :b :b)))
  (is (= (replicate-a-sequence-solution [4 5 6] 1) '(4 5 6)))
  (is (= (replicate-a-sequence-solution [[1 2] [3 4]] 2) '([1 2] [1 2] [3 4] [3 4])))
  (is (= (replicate-a-sequence-solution [44 33] 2) [44 44 33 33])))

;; problem 34
(deftest can-implement-range
  (is (= (implement-range-solution 1 4) '(1 2 3)))
  (is (= (implement-range-solution -2 2) '(-2 -1 0 1)))
  (is (= (implement-range-solution 5 8) '(5 6 7))))

;; problem 35
(deftest can-local-bindings
  (is (= local-bindings-solution (let [x 5] (+ 2 x))))
  (is (= local-bindings-solution (let [x 3, y 10] (- y x))))
  (is (= local-bindings-solution (let [x 21] (let [y 3] (/ x y))))))

;; problem 36 (the blank is a binding vector; `let` needs a literal vector, so the
;; test checks the vector and then repeats the original bodies with it inlined)
(deftest can-let-it-be
  (is (= let-it-be-solution '[x 7 y 3 z 1]))
  (is (= 10 (let [x 7 y 3 z 1] (+ x y))))
  (is (= 4 (let [x 7 y 3 z 1] (+ y z))))
  (is (= 1 (let [x 7 y 3 z 1] z))))

;; problem 37
(deftest can-regular-expressions
  (is (= regular-expressions-solution (apply str (re-seq #"[A-Z]+" "bA1B3Ce ")))))

;; problem 38
(deftest can-maximum-value
  (is (= (maximum-value-solution 1 8 3 4) 8))
  (is (= (maximum-value-solution 30 20) 30))
  (is (= (maximum-value-solution 45 67 11) 67)))

;; problem 39
(deftest can-interleave-two-seqs
  (is (= (interleave-two-seqs-solution [1 2 3] [:a :b :c]) '(1 :a 2 :b 3 :c)))
  (is (= (interleave-two-seqs-solution [1 2] [3 4 5 6]) '(1 3 2 4)))
  (is (= (interleave-two-seqs-solution [1 2 3 4] [5]) [1 5]))
  (is (= (interleave-two-seqs-solution [30 20] [25 15]) [30 25 20 15])))

;; problem 40
(deftest can-interpose-a-seq
  (is (= (interpose-a-seq-solution 0 [1 2 3]) [1 0 2 0 3]))
  (is (= (apply str (interpose-a-seq-solution ", " ["one" "two" "three"])) "one, two, three"))
  (is (= (interpose-a-seq-solution :z [:a :b :c :d]) [:a :z :b :z :c :z :d])))

;; problem 41
(deftest can-drop-every-nth-item
  (is (= (drop-every-nth-item-solution [1 2 3 4 5 6 7 8] 3) [1 2 4 5 7 8]))
  (is (= (drop-every-nth-item-solution [:a :b :c :d :e :f] 2) [:a :c :e]))
  (is (= (drop-every-nth-item-solution [1 2 3 4 5 6] 4) [1 2 3 5 6])))
