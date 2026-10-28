(ns p99.logic
  "L-99 P46-P50: logic and codes. Plain portable Clojure (also runs on JVM Clojure,
  the oracle for the expected values in the tests).")

;; ---- P46-P48: truth tables

(defn and* [a b] (boolean (and a b)))
(defn or* [a b] (boolean (or a b)))
(defn nand* [a b] (not (and* a b)))
(defn nor* [a b] (not (or* a b)))
(defn xor* [a b] (not= (boolean a) (boolean b)))
(defn impl* [a b] (or* (not a) b))
(defn equ* [a b] (= (boolean a) (boolean b)))

(defn- bool-rows
  "All n-long boolean vectors, true before false, leftmost varying slowest."
  [n]
  (if (zero? n)
    [[]]
    (for [b [true false] r (bool-rows (dec n))] (into [b] r))))

(defn truth-table
  "Rows [in1 ... inN result] of the n-ary predicate f, in L-99 order (TT first)."
  [n f]
  (vec (for [inputs (bool-rows n)] (conj inputs (boolean (apply f inputs))))))

(defmacro table
  "(table [a b] (and a (or a b))) -> the truth table of the expression."
  [vars expr]
  `(truth-table ~(count vars) (fn ~vars ~expr)))

;; ---- P49: Gray code

(defn gray
  "The n-bit Gray code as a vector of bit strings."
  [n]
  (if (zero? n)
    [""]
    (let [g (gray (dec n))]
      (vec (concat (map #(str "0" %) g)
                   (map #(str "1" %) (reverse g)))))))

;; ---- P50: Huffman codes

(defn- huffman-tree [freqs]
  (loop [nodes (map-indexed (fn [i [s w]] [w i [:leaf s]]) freqs)
         counter (count freqs)]
    (if (= 1 (count nodes))
      (nth (first nodes) 2)
      (let [[[w1 _ t1] [w2 _ t2] & more] (sort-by (fn [[w i _]] [w i]) nodes)]
        (recur (cons [(+ w1 w2) counter [:node t1 t2]] more) (inc counter))))))

(defn- walk-codes [t prefix]
  (if (= :leaf (first t))
    [[(second t) (if (= "" prefix) "0" prefix)]]
    (concat (walk-codes (nth t 1) (str prefix "0"))
            (walk-codes (nth t 2) (str prefix "1")))))

(defn huffman
  "Given [[symbol frequency] ...] return [[symbol code-string] ...] sorted by symbol.
  Ties are broken by input order, so the result is deterministic."
  [freqs]
  (vec (sort-by first (walk-codes (huffman-tree freqs) ""))))
