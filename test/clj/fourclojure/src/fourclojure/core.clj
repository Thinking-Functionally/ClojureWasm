(ns fourclojure.core
  "Solutions for the 4clojure problems (see ../reference/core.clj for the
  statements). Plain portable Clojure: runs unchanged on JVM Clojure, which is
  the oracle for the expected values in the tests.

  Problems 1-14, 17-18 and 35-37 are \"fill in the blank\" values; the rest are
  functions. Functions are written out by hand (loops, reduce, recursion)
  instead of calling the obvious core function, so the suite exercises the
  language rather than one builtin.")

;; ---- 1-14: values

(def nothing-but-the-truth-solution true)                  ; 1
(def simple-math-solution 4)                               ; 2
(def intro-to-strings-solution "HELLO WORLD")              ; 3
(def intro-to-lists-solution [:a :b :c])                   ; 4 (the elements of the list)
(def lists-conj-solution '(1 2 3 4))                       ; 5
(def intro-to-vectors-solution [:a :b :c])                 ; 6 (the elements of the vector)
(def vectors-conj-solution [1 2 3 4])                      ; 7
(def intro-to-sets-solution #{:a :b :c :d})                ; 8
(def sets-conj-solution 2)                                 ; 9
(def intro-to-maps-solution 20)                            ; 10
(def maps-conj-solution [:b 2])                            ; 11
(def intro-to-sequences-solution 3)                        ; 12
(def sequences-rest-solution [20 30 40])                   ; 13
(def intro-to-functions-solution 8)                        ; 14

;; ---- 15-16: simple functions

(def double-down-solution (fn [n] (* 2 n)))                              ; 15
(def hello-world-solution (fn [name] (str "Hello, " name "!")))          ; 16

;; ---- 17-18: values

(def sequences-map-solution [6 7 8])                       ; 17
(def sequences-filter-solution [6 7])                      ; 18

;; ---- 19-34: sequence functions

(def last-element-solution                                 ; 19
  (fn [xs]
    (loop [xs (seq xs)]
      (if (next xs) (recur (next xs)) (first xs)))))

(def penultimate-element-solution                          ; 20
  (fn [xs]
    (loop [xs (seq xs)]
      (if (next (next xs)) (recur (next xs)) (first xs)))))

(def nth-element-solution                                  ; 21
  (fn [xs n]
    (loop [xs (seq xs) i n]
      (if (zero? i) (first xs) (recur (next xs) (dec i))))))

(def count-a-sequence-solution                             ; 22
  (fn [xs] (reduce (fn [n _] (inc n)) 0 xs)))

(def reverse-a-sequence-solution                           ; 23
  (fn [xs] (reduce conj () xs)))

(def sum-it-all-up-solution                                ; 24
  (fn [xs] (reduce + xs)))

(def find-the-odd-numbers-solution                         ; 25
  (fn [xs] (filter odd? xs)))

(def fibonacci-sequence-solution                           ; 26
  (fn [n]
    (take n (map first (iterate (fn [[a b]] [b (+ a b)]) [1 1])))))

(def palindrome-detector-solution                          ; 27
  (fn [xs] (= (seq xs) (seq (reverse xs)))))

(def flatten-a-sequence-solution                           ; 28
  (fn flat [xs]
    (mapcat (fn [x] (if (sequential? x) (flat x) [x])) xs)))

(def get-the-caps-solution                                 ; 29
  (fn [s] (apply str (filter (fn [c] (Character/isUpperCase c)) s))))

(def compress-a-sequence-solution                          ; 30
  (fn [xs] (map first (partition-by identity xs))))

(def pack-a-sequence-solution                              ; 31
  (fn [xs] (partition-by identity xs)))

(def duplicate-a-sequence-solution                         ; 32
  (fn [xs] (mapcat (fn [x] [x x]) xs)))

(def replicate-a-sequence-solution                         ; 33
  (fn [xs n] (mapcat (fn [x] (repeat n x)) xs)))

(def implement-range-solution                              ; 34
  (fn [lo hi] (take (- hi lo) (iterate inc lo))))

;; ---- 35-37: bindings and regular expressions

(def local-bindings-solution 7)                            ; 35
(def let-it-be-solution '[x 7 y 3 z 1])                    ; 36 (the binding vector)
(def regular-expressions-solution "ABC")                   ; 37

;; ---- 38-41: more sequence functions

(def maximum-value-solution                                ; 38
  (fn [x & more]
    (reduce (fn [m y] (if (> y m) y m)) x more)))

(def interleave-two-seqs-solution                          ; 39
  (fn il [a b]
    (lazy-seq
      (when (and (seq a) (seq b))
        (cons (first a) (cons (first b) (il (rest a) (rest b))))))))

(def interpose-a-seq-solution                              ; 40
  (fn [sep xs] (rest (mapcat (fn [x] [sep x]) xs))))

(def drop-every-nth-item-solution                          ; 41
  (fn [xs n]
    (->> xs
         (map-indexed vector)
         (remove (fn [[i _]] (zero? (mod (inc i) n))))
         (map second))))
