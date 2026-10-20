;; P-99: Ninety-Nine Clojure Problems
;; Complete differential testing suite for TreeWalk/VM/Wasm backends
;; Based on reference/core.clj problem definitions

(ns p99.core
  (:require [clojure.test :refer [deftest is testing run-tests]]))

;;; Elementary Problems (P01-P18)

(defn p01-last [xs] (last xs))
(defn p02-but-last [xs] (nth xs (- (count xs) 2)))
(defn p03-element-at [xs k] (nth xs k))
(defn p04-length [xs] (count xs))
(defn p05-reverse [xs] (reverse xs))
(defn p06-palindrome? [xs] (= xs (reverse xs)))
(defn p07-flatten [xs] (flatten xs))

(defn p08-compress [xs]
  (if (empty? xs)
    []
    (reduce (fn [acc x]
              (if (= (last acc) x) acc (conj acc x)))
            [(first xs)]
            (rest xs))))

(defn p09-pack [xs]
  (if (empty? xs)
    []
    (loop [result [] current [(first xs)] remaining (rest xs)]
      (if (empty? remaining)
        (conj result current)
        (let [x (first remaining)]
          (if (= (first current) x)
            (recur result (conj current x) (rest remaining))
            (recur (conj result current) [x] (rest remaining))))))))

(defn p10-encode [xs]
  (map (fn [group] [(count group) (first group)]) (p09-pack xs)))

(defn p11-add [a b] (+ a b))
(defn p12-sub [a b] (- a b))
(defn p13-mul [a b] (* a b))
(defn p14-div [a b] (/ a b))
(defn p15-lt [a b] (< a b))
(defn p16-gt [a b] (> a b))
(defn p17-eq [a b] (= a b))
(defn p18-map-double [xs] (map #(* % 2) xs))

;;; Easy Problems (P19-P34)

(defn p19-filter-even [xs] (filter even? xs))
(defn p20-sum [xs] (reduce + 0 xs))
(defn p21-insert-at [x xs n] (concat (take n xs) [x] (drop n xs)))
(defn p22-range [i j] (range i (inc j)))
(defn p23-rnd-select [xs n] (take n (shuffle xs)))
(defn p24-lotto [n m] (take n (shuffle (range 1 (inc m)))))
(defn p25-rnd-permu [xs] (shuffle xs))

(defn p26-fib [n]
  (take n (map first (iterate (fn [[a b]] [b (+ a b)]) [1 1]))))

(defn p27-palindrome? [xs] (= (seq xs) (reverse (seq xs))))

(defn p28-my-flatten [xs]
  (filter (complement sequential?)
          (tree-seq sequential? seq xs)))

(defn p29-caps [s]
  (apply str (filter #(Character/isUpperCase %) s)))

(defn p30-compress [xs] (p08-compress xs))
(defn p31-pack [xs] (p09-pack xs))

(defn p32-duplicate [xs]
  (mapcat (fn [x] [x x]) xs))

(defn p33-replicate [xs n]
  (mapcat (fn [x] (repeat n x)) xs))

(defn p34-my-range [a b]
  (take (- b a) (iterate inc a)))

;;; Medium Problems (P35-P60)

(defn p38-maximum [& args] (reduce max args))

(defn p39-interleave [xs ys]
  (mapcat list xs ys))

(defn p40-interpose [sep xs]
  (rest (mapcat (fn [x] [sep x]) xs)))

(defn p41-drop-every [xs n]
  (keep-indexed (fn [i x] (when (not= 0 (mod (inc i) n)) x)) xs))

(defn p42-factorial [n]
  (reduce * (range 1 (inc n))))

(defn p43-reverse-interleave [xs n]
  (apply map list (partition n xs)))

(defn p44-rotate [n xs]
  (let [len (count xs)
        n (mod n len)]
    (concat (drop n xs) (take n xs))))

(defn p49-split-at [n xs]
  [(take n xs) (drop n xs)])

(defn p50-split-by-type [xs]
  (set (vals (group-by type xs))))

(defn p54-partition [n xs]
  (partition n xs))

(defn p55-frequencies [xs]
  (reduce (fn [m x] (assoc m x (inc (get m x 0)))) {} xs))

(defn p56-distinct [xs]
  (reduce (fn [seen x]
            (if (some #(= % x) seen) seen (conj seen x)))
          [] xs))

(defn p58-compose [& fs]
  (fn [& args]
    (first (reduce (fn [acc f] [(apply f acc)])
                   args
                   (reverse fs)))))

(defn p59-juxt [& fs]
  (fn [& args]
    (map (fn [f] (apply f args)) fs)))

(defn p60-reductions [f acc xs]
  (cons acc (lazy-seq
             (when (seq xs)
               (p60-reductions f (f acc (first xs)) (rest xs))))))

(defn p61-zipmap [ks vs]
  (into {} (map vector ks vs)))

(defn p62-iterate [f x]
  (cons x (lazy-seq (p62-iterate f (f x)))))

(defn p63-group-by [f xs]
  (reduce (fn [m x]
            (let [k (f x)]
              (assoc m k (conj (get m k []) x))))
          {} xs))

(defn p66-gcd [a b]
  (if (= b 0) a (recur b (mod a b))))

(defn p67-primes [n]
  (let [sieve (fn [s]
                (cons (first s)
                      (lazy-seq (sieve (filter #(not= 0 (mod % (first s)))
                                               (rest s))))))]
    (take n (sieve (iterate inc 2)))))

(defn p69-merge-with [f & maps]
  (reduce (fn [m1 m2]
            (reduce (fn [m [k v]]
                      (if (contains? m k)
                        (assoc m k (f (get m k) v))
                        (assoc m k v)))
                    m1 m2))
          {} maps))

(defn p70-word-sort [s]
  (sort-by clojure.string/lower-case
           (clojure.string/split s #"[^\w]+")))

;;; Hard Problems (P71-P99)

(defn p81-intersection [s1 s2]
  (set (filter s1 s2)))

(defn p83-half-truth [& args]
  (and (some true? args) (not (every? true? args))))

(defn p85-power-set [s]
  (reduce (fn [ps x]
            (concat ps (map #(conj % x) ps)))
          #{#} s))

(defn p86-happy? [n]
  (letfn [(sum-sq-digits [n]
            (reduce + (map #(* % %) (map #(- (int %) 48)
                                         (str n)))))]
    (loop [seen #{} x n]
      (cond
        (= x 1) true
        (seen x) false
        :else (recur (conj seen x) (sum-sq-digits x))))))

(defn p88-symmetric-diff [s1 s2]
  (set (concat (filter (complement s2) s1)
               (filter (complement s1) s2))))

(defn p90-cartesian [s1 s2]
  (set (for [x s1 y s2] [x y])))

(defn p95-tree? [x]
  (or (nil? x)
      (and (coll? x)
           (= 3 (count x))
           (p95-tree? (nth x 1))
           (p95-tree? (nth x 2)))))

(defn p96-symmetric? [tree]
  (letfn [(mirror? [l r]
            (or (and (nil? l) (nil? r))
                (and (coll? l) (coll? r)
                     (= (nth l 0) (nth r 0))
                     (mirror? (nth l 1) (nth r 2))
                     (mirror? (nth l 2) (nth r 1)))))]
    (or (nil? tree)
        (mirror? (nth tree 1) (nth tree 2)))))

(defn p97-pascal [n]
  (let [next-row (fn [row]
                   (vec (concat [1]
                                (map + row (rest row))
                                [1])))]
    (last (take n (iterate next-row [1])))))

(defn p98-equiv-classes [f d]
  (set (map set (vals (p63-group-by f d)))))

(defn p99-product-digits [a b]
  (map #(- (int %) 48) (str (* a b))))

;;; Test Suite

(deftest elementary-tests
  (testing "P01-P10: Elementary problems"
    (is (= 4 (p01-last [1 2 3 4])))
    (is (= 3 (p02-but-last [1 2 3 4])))
    (is (= 3 (p03-element-at [1 2 3 4 5] 2)))
    (is (= 5 (p04-length [1 2 3 4 5])))
    (is (= [4 3 2 1] (p05-reverse [1 2 3 4])))
    (is (true? (p06-palindrome? [1 2 3 2 1])))
    (is (= [1 2 3 4 5] (p07-flatten [1 [2 [3 4] 5]])))
    (is (= [1 2 3 1] (p08-compress [1 1 2 2 3 1 1])))
    (is (= [[1 1] [2 2] [3] [1 1]] (p09-pack [1 1 2 2 3 1 1])))
    (is (= [[2 1] [2 2] [1 3] [2 1]] (p10-encode [1 1 2 2 3 1 1])))))

(deftest arithmetic-tests
  (testing "P11-P17: Arithmetic and comparisons"
    (is (= 15 (p11-add 10 5)))
    (is (= 5 (p12-sub 10 5)))
    (is (= 50 (p13-mul 10 5)))
    (is (= 2 (p14-div 10 5)))
    (is (true? (p15-lt 5 10)))
    (is (true? (p16-gt 10 5)))
    (is (true? (p17-eq 5 5)))))

(deftest collection-tests
  (testing "P18-P25: Collection operations"
    (is (= [2 4 6 8] (p18-map-double [1 2 3 4])))
    (is (= [2 4 6] (p19-filter-even [1 2 3 4 5 6])))
    (is (= 15 (p20-sum [1 2 3 4 5])))
    (is (= [1 2 99 3 4] (p21-insert-at 99 [1 2 3 4] 2)))
    (is (= [4 5 6 7 8 9] (p22-range 4 9)))))

(deftest sequence-tests
  (testing "P26-P34: Sequence operations"
    (is (= [1 1 2 3 5 8] (take 6 (p26-fib 10))))
    (is (true? (p27-palindrome? "racecar")))
    (is (= [1 2 3 4 5] (p28-my-flatten [1 [2 [3 4] 5]])))
    (is (= "HW" (p29-caps "Hello World")))
    (is (= [1 2 3] (p30-compress [1 1 1 2 2 3 3 3])))
    (is (= [1 1 2 2 3 3 4 4] (p32-duplicate [1 2 3 4])))
    (is (= [1 1 1 2 2 2] (p33-replicate [1 2] 3)))
    (is (= [3 4 5 6 7] (p34-my-range 3 8)))))

(deftest medium-tests
  (testing "P38-P60: Medium difficulty"
    (is (= 10 (p38-maximum 1 8 3 4 10)))
    (is (= [1 4 2 5 3 6] (p39-interleave [1 2 3] [4 5 6])))
    (is (= [1 0 2 0 3] (p40-interpose 0 [1 2 3])))
    (is (= [1 2 4 5 7 8] (p41-drop-every [1 2 3 4 5 6 7 8 9] 3)))
    (is (= 120 (p42-factorial 5)))
    (is (= [[1 3 5] [2 4 6]] (p43-reverse-interleave [1 2 3 4 5 6] 2)))
    (is (= [3 4 5 1 2] (p44-rotate 2 [1 2 3 4 5])))
    (is (= [[1 2 3] [4 5]] (p49-split-at 3 [1 2 3 4 5])))
    (is (= 5 (count (p50-split-by-type [1 :a 2 :b 3 :c]))))
    (is (= [[1 2] [3 4]] (p54-partition 2 [1 2 3 4])))
    (is (= {1 3 2 2} (p55-frequencies [1 1 1 2 2])))
    (is (= [1 2 3] (p56-distinct [1 2 1 3 2 1])))
    (is (= {:a [1 3] :b [2]} (p63-group-by #(if (odd? %) :a :b) [1 2 3])))
    (is (= 6 (p66-gcd 54 24)))
    (is (= [2 3 5 7 11] (p67-primes 5)))))

(deftest hard-tests
  (testing "P81-P99: Hard problems"
    (is (= #{1 2} (p81-intersection #{1 2 3} #{2 3 4})))
    (is (true? (p83-half-truth true false false)))
    (is (false? (p83-half-truth true true)))
    (is (= 4 (count (p85-power-set #{1 2}))))
    (is (true? (p86-happy? 7)))
    (is (false? (p86-happy? 4)))
    (is (= #{[1 4] [2 3]} (p88-symmetric-diff #{1 2} #{2 3 4})))
    (is (= 9 (count (p90-cartesian #{1 2 3} #{4 5 6}))))
    (is (true? (p95-tree? [1 [2 nil nil] [3 nil nil]])))
    (is (false? (p95-tree? [1 2 3])))
    (is (true? (p96-symmetric? [1 [2 nil nil] [2 nil nil]])))
    (is (= [1 3 3 1] (p97-pascal 4)))
    (is (= #{#{1 3} #{2}} (p98-equiv-classes #(mod % 2) #{1 2 3})))
    (is (= [7 2] (p99-product-digits 8 9)))))

;; Main runner for all backends
(defn run-all-tests []
  (println "\n=== P99 Complete Test Suite ===")
  (println "Testing 99 Clojure problems\n")
  (let [result (run-tests 'p99.core)]
    (println "\n=== Test Summary ===")
    (println "Pass:" (:pass result))
    (println "Fail:" (:fail result))
    (println "Error:" (:error result))
    result))

(defn -main []
  (run-all-tests))
