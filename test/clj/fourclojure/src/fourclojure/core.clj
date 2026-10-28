(ns fourclojure.core
  "Solutions for the 4clojure problems (see ../reference/core.clj for the
  statements). Plain portable Clojure: runs unchanged on JVM Clojure, which is
  the oracle for the expected values in the tests.

  Problems 1-14, 17-18 and 35-37 are \"fill in the blank\" values; the rest are
  functions. Functions are written out by hand (loops, reduce, recursion)
  instead of calling the obvious core function, so the suite exercises the
  language rather than one builtin."
  (:require [clojure.string]))

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

;; ---- 42-98

(def factorial-fun-solution                                ; 42
  (fn [n] (reduce * 1 (range 1 (inc n)))))

(def reverse-interleave-solution                           ; 43
  (fn [xs n] (map (fn [i] (take-nth n (drop i xs))) (range n))))

(def rotate-sequence-solution                              ; 44
  (fn [n xs]
    (let [k (mod n (count xs))]
      (concat (drop k xs) (take k xs)))))

(def intro-to-iterate-solution [1 4 7 10 13])              ; 45 (blank)

(def flipping-out-solution                                 ; 46
  (fn [f] (fn [a b] (f b a))))

(def contain-yourself-solution 4)                          ; 47 (blank)
(def intro-to-some-solution 6)                             ; 48 (blank)

(def split-a-sequence-solution                             ; 49
  (fn [n xs] [(take n xs) (drop n xs)]))

(def split-by-type-solution                                ; 50
  (fn [xs] (vals (group-by type xs))))

(def advanced-destructuring-solution [1 2 3 4 5])          ; 51 (blank)
(def intro-to-destructuring-solution '[c e])               ; 52 (blank, a binding form)

(def longest-increasing-sub-seq-solution                   ; 53
  (fn [xs]
    (let [runs (reduce (fn [acc x]
                         (let [cur (peek acc)]
                           (if (and (seq cur) (> x (peek cur)))
                             (conj (pop acc) (conj cur x))
                             (conj acc [x]))))
                       [] xs)
          best (reduce (fn [b r] (if (> (count r) (count b)) r b)) [] runs)]
      (if (> (count best) 1) best []))))

(def partition-a-sequence-solution                         ; 54
  (fn [n xs]
    (loop [xs xs acc []]
      (if (= n (count (take n xs)))
        (recur (drop n xs) (conj acc (take n xs)))
        acc))))

(def count-occurrences-solution                            ; 55
  (fn [xs] (reduce (fn [m x] (assoc m x (inc (get m x 0)))) {} xs)))

(def find-distinct-items-solution                          ; 56
  (fn [xs]
    (first (reduce (fn [[out seen] x]
                     (if (contains? seen x) [out seen] [(conj out x) (conj seen x)]))
                   [[] #{}] xs))))

(def simple-recursion-solution [5 4 3 2 1])                ; 57 (blank)

(def function-composition-solution                         ; 58
  (fn [& fs]
    (let [fs (reverse fs)]
      (fn [& args]
        (loop [r (apply (first fs) args) fs (rest fs)]
          (if (seq fs) (recur ((first fs) r) (rest fs)) r))))))

(def juxtaposition-solution                                ; 59
  (fn [& fs] (fn [& args] (vec (map (fn [f] (apply f args)) fs)))))

(def sequence-reductions-solution                          ; 60
  (fn rs
    ([f xs] (if (seq xs) (rs f (first xs) (rest xs)) (list (f))))
    ([f init xs]
     (cons init (lazy-seq (when (seq xs) (rs f (f init (first xs)) (rest xs))))))))

(def map-construction-solution                             ; 61
  (fn [ks vs]
    (loop [m {} ks (seq ks) vs (seq vs)]
      (if (and ks vs)
        (recur (assoc m (first ks) (first vs)) (next ks) (next vs))
        m))))

(def re-implement-iterate-solution                         ; 62
  (fn it [f x] (cons x (lazy-seq (it f (f x))))))

(def group-a-sequence-solution                             ; 63
  (fn [f xs]
    (reduce (fn [m x] (let [k (f x)] (assoc m k (conj (get m k []) x)))) {} xs)))

(def intro-to-reduce-solution +)                           ; 64 (blank)

(def black-box-testing-solution                            ; 65
  (fn [c]
    (let [e (empty c)]
      (cond (= e {}) :map
            (= e #{}) :set
            (= (conj e 1 2) [1 2]) :vector
            :else :list))))

(def greatest-common-divisor-solution                      ; 66
  (fn g [a b] (if (zero? b) a (g b (mod a b)))))

(def prime-numbers-solution                                ; 67
  (fn [n]
    (loop [c 2 acc []]
      (if (= (count acc) n)
        acc
        (recur (inc c)
               (if (every? (fn [p] (pos? (mod c p))) (take-while (fn [p] (<= (* p p) c)) acc))
                 (conj acc c)
                 acc))))))

(def recurring-theme-solution [7 6 5 4 3])                 ; 68 (blank)

(def merge-with-a-function-solution                        ; 69
  (fn [f & ms]
    (reduce (fn [acc m]
              (reduce (fn [a [k v]] (assoc a k (if (contains? a k) (f (get a k) v) v)))
                      acc m))
            {} ms)))

(def word-sorting-solution                                 ; 70
  (fn [s] (sort-by clojure.string/lower-case (re-seq #"\w+" s))))

(def rearranging-code-solution (fn [xs] (last xs)))        ; 71 (blank, a function)

(def analyze-a-tic-tac-toe-board-solution                  ; 73
  (fn [b]
    (let [cell (fn [r c] (nth (nth b r) c))
          lines (concat b
                        (apply map vector b)
                        [[(cell 0 0) (cell 1 1) (cell 2 2)]
                         [(cell 0 2) (cell 1 1) (cell 2 0)]])]
      (first (for [l lines
                   :let [a (first l)]
                   :when (and (not= a :e) (every? (fn [x] (= a x)) l))]
               a)))))

(def filter-perfect-squares-solution                       ; 74
  (fn [s]
    (let [square? (fn [n] (= n (let [r (first (filter (fn [i] (>= (* i i) n)) (range)))] (* r r))))]
      (clojure.string/join
       ","
       (filter square? (map read-string (clojure.string/split s #",")))))))

(def euler-s-totient-function-solution                     ; 75
  (fn [n]
    (if (= n 1)
      1
      (count (filter (fn [i] (= 1 (greatest-common-divisor-solution n i))) (range 1 n))))))

(def intro-to-trampoline-solution [1 3 5 7 9 11])          ; 76 (blank)

(def anagram-finder-solution                               ; 77
  (fn [ws]
    (set (map set (filter (fn [g] (> (count g) 1))
                          (vals (group-by (fn [w] (sort w)) ws)))))))

(def reimplement-trampoline-solution                       ; 78
  (fn t
    ([f] (let [r (f)] (if (fn? r) (t r) r)))
    ([f & args] (t (fn [] (apply f args))))))

(def triangle-minimal-path-solution                        ; 79
  (fn [tri]
    (first (reduce (fn [below row]
                     (map-indexed (fn [i x] (+ x (min (nth below i) (nth below (inc i))))) row))
                   (last tri)
                   (rest (reverse tri))))))

(def perfect-numbers-solution                              ; 80
  (fn [n] (= n (reduce + (filter (fn [d] (zero? (mod n d))) (range 1 n))))))

(def set-intersection-solution                             ; 81
  (fn [a b] (set (filter (fn [x] (contains? b x)) a))))

(def word-chains-solution                                  ; 82
  (fn [ws]
    (let [one-edit? (fn d [a b]
                      (let [la (count a) lb (count b)]
                        (cond
                          (= la lb) (= 1 (count (filter false? (map = a b))))
                          (= la (inc lb)) (d b a)
                          (= (inc la) lb) (boolean
                                           (some (fn [i] (= (vec a) (vec (concat (take i b) (drop (inc i) b)))))
                                                 (range lb)))
                          :else false)))
          walk (fn walk [cur remaining]
                 (or (empty? remaining)
                     (boolean (some (fn [nx] (walk nx (disj remaining nx)))
                                    (filter (fn [w] (one-edit? cur w)) remaining)))))]
      (boolean (some (fn [w] (walk w (disj ws w))) ws)))))

(def a-half-truth-solution                                 ; 83
  (fn [& bs] (and (boolean (some identity bs)) (not (every? identity bs)))))

(def transitive-closure-solution                           ; 84
  (fn [rel]
    (loop [r rel]
      (let [n (into r (for [[a b] r [c d] r :when (= b c)] [a d]))]
        (if (= n r) r (recur n))))))

(def power-set-solution                                    ; 85
  (fn [s] (reduce (fn [ps x] (into ps (map (fn [p] (conj p x)) ps))) #{#{}} s)))

(def happy-numbers-solution                                ; 86
  (fn [n]
    (let [step (fn [m] (loop [m m s 0]
                         (if (zero? m) s (recur (quot m 10) (+ s (* (mod m 10) (mod m 10)))))))]
      (loop [n n seen #{}]
        (cond (= n 1) true
              (contains? seen n) false
              :else (recur (step n) (conj seen n)))))))

(def symmetric-difference-solution                         ; 88
  (fn [a b]
    (into (set (remove (fn [x] (contains? b x)) a))
          (remove (fn [x] (contains? a x)) b))))

(def graph-reach                                           ; helper for 89 and 91
  (fn [edges]
    (let [adj (reduce (fn [m [a b]] (-> m (update a (fnil conj #{}) b) (update b (fnil conj #{}) a)))
                      {} edges)]
      (loop [seen #{} stack [(ffirst edges)]]
        (if (empty? stack)
          [seen adj]
          (let [v (peek stack) st (pop stack)]
            (if (contains? seen v)
              (recur seen st)
              (recur (conj seen v) (into st (get adj v))))))))))

(def graph-tour-solution                                   ; 89
  (fn [edges]
    (let [deg (reduce (fn [m [a b]] (-> m (update a (fnil inc 0)) (update b (fnil inc 0)))) {} edges)
          odd (count (filter odd? (vals deg)))
          [seen _] (graph-reach edges)]
      (and (= (count seen) (count deg)) (contains? #{0 2} odd)))))

(def cartesian-product-solution                            ; 90
  (fn [a b] (set (for [x a y b] [x y]))))

(def graph-connectivity-solution                           ; 91
  (fn [edges]
    (let [[seen adj] (graph-reach edges)]
      (= (count seen) (count adj)))))

(def read-roman-numerals-solution                          ; 92
  (fn [s]
    (let [v {\I 1 \V 5 \X 10 \L 50 \C 100 \D 500 \M 1000}
          ns (map v s)]
      (reduce + (map (fn [a b] (if (< a b) (- a) a)) ns (concat (rest ns) [0]))))))

(def partially-flatten-a-sequence-solution                 ; 93
  (fn pf [xs]
    (mapcat (fn [x] (if (and (sequential? x) (some sequential? x)) (pf x) [x])) xs)))

(def game-of-life-solution                                 ; 94
  (fn [board]
    (let [h (count board)
          w (count (first board))
          alive? (fn [r c] (and (< -1 r h) (< -1 c w) (= \# (nth (nth board r) c))))
          nbrs (fn [r c] (count (for [dr [-1 0 1] dc [-1 0 1]
                                      :when (not (and (zero? dr) (zero? dc)))
                                      :when (alive? (+ r dr) (+ c dc))]
                                  1)))]
      (vec (for [r (range h)]
             (apply str (for [c (range w)]
                          (let [n (nbrs r c)]
                            (if (alive? r c)
                              (if (or (= n 2) (= n 3)) \# \space)
                              (if (= n 3) \# \space))))))))))

(def to-tree-or-not-to-tree-solution                       ; 95
  (fn t [n]
    (or (nil? n)
        (and (sequential? n) (= 3 (count n)) (t (nth n 1)) (t (nth n 2))))))

(def beauty-is-symmetry-solution                           ; 96
  (fn [t]
    (let [mirror (fn m [n] (when-not (nil? n) (let [[v l r] n] [v (m r) (m l)])))]
      (= (mirror (nth t 1)) (nth t 2)))))

(def pascal-s-triangle-solution                            ; 97
  (fn [n]
    (loop [row [1] i 1]
      (if (= i n)
        row
        (recur (vec (map + (concat [0] row) (concat row [0]))) (inc i))))))

(def equivalence-classes-solution                          ; 98
  (fn [f s] (set (map set (vals (group-by f s))))))
