(ns p99.lists
  "L-99 problems P01-P28 (working with lists).

  Conventions follow the L-99 statements: positions are 1-based, ranges are
  inclusive, results are sequences (compare with `=`, so a vector equals a
  list). The code is plain portable Clojure: it runs unchanged on JVM Clojure,
  which is the oracle for the expected values in the tests.")

;; ---- P01-P07: the basics, written out by hand

(defn my-last
  "P01: the last element of a list (nil for an empty list)."
  [xs]
  (loop [xs (seq xs)]
    (when xs
      (if (next xs) (recur (next xs)) (first xs)))))

(defn my-but-last
  "P02: the last two elements of a list as a list (nil if fewer than two)."
  [xs]
  (loop [xs (seq xs)]
    (cond (or (nil? xs) (nil? (next xs))) nil
          (nil? (nnext xs)) (list (first xs) (second xs))
          :else (recur (next xs)))))

(defn element-at
  "P03: the K'th element, counting from 1 (nil when out of range)."
  [xs k]
  (loop [xs (seq xs) i k]
    (cond (nil? xs) nil
          (= i 1) (first xs)
          :else (recur (next xs) (dec i)))))

(defn my-length
  "P04: the number of elements."
  [xs]
  (reduce (fn [n _] (inc n)) 0 xs))

(defn my-reverse
  "P05: the elements in reverse order."
  [xs]
  (reduce conj () xs))

(defn palindrome?
  "P06: true if the list reads the same in both directions."
  [xs]
  (= (vec xs) (vec (my-reverse xs))))

(defn my-flatten
  "P07: flatten a nested list structure."
  [xs]
  (mapcat (fn [x] (if (sequential? x) (my-flatten x) [x])) xs))

;; ---- P08-P13: runs and run-length encoding

(defn compress
  "P08: eliminate consecutive duplicates."
  [xs]
  (reduce (fn [acc x]
            (if (and (seq acc) (= (peek acc) x)) acc (conj acc x)))
          [] xs))

(defn pack
  "P09: pack consecutive duplicates into sublists."
  [xs]
  (reduce (fn [acc x]
            (if (and (seq acc) (= (first (peek acc)) x))
              (conj (pop acc) (conj (peek acc) x))
              (conj acc [x])))
          [] xs))

(defn encode
  "P10: run-length encoding, each run as [n element]."
  [xs]
  (mapv (fn [run] [(count run) (first run)]) (pack xs)))

(defn encode-modified
  "P11: like encode, but a run of one is just the element."
  [xs]
  (mapv (fn [[n x]] (if (= n 1) x [n x])) (encode xs)))

(defn- run-pair? [e]
  (and (sequential? e) (= 2 (count e)) (integer? (first e))))

(defn decode
  "P12: decode a list produced by encode-modified."
  [xs]
  (mapcat (fn [e] (if (run-pair? e) (repeat (first e) (second e)) [e])) xs))

(defn encode-direct
  "P13: run-length encoding in one pass, without building the sublists."
  [xs]
  (mapv (fn [[n x]] (if (= n 1) x [n x]))
        (reduce (fn [acc x]
                  (let [[n y] (peek acc)]
                    (if (and (seq acc) (= y x))
                      (conj (pop acc) [(inc n) x])
                      (conj acc [1 x]))))
                [] xs)))

;; ---- P14-P21: duplicating, dropping, splitting, rotating

(defn dupli
  "P14: duplicate each element."
  [xs]
  (mapcat (fn [x] [x x]) xs))

(defn repli
  "P15: replicate each element N times."
  [xs n]
  (mapcat (fn [x] (repeat n x)) xs))

(defn drop-every
  "P16: drop every N'th element."
  [xs n]
  (->> xs
       (map-indexed vector)
       (remove (fn [[i _]] (zero? (mod (inc i) n))))
       (map second)))

(defn split
  "P17: split into [first-N rest], without take/drop/split-at."
  [xs n]
  (loop [i n front [] more (seq xs)]
    (if (and (pos? i) more)
      (recur (dec i) (conj front (first more)) (next more))
      [front (or more ())])))

(defn slice
  "P18: elements from the I'th to the K'th, both included, counting from 1."
  [xs i k]
  (->> xs (drop (dec i)) (take (inc (- k i)))))

(defn rotate
  "P19: rotate N places to the left (a negative N rotates right)."
  [xs n]
  (let [c (count xs)]
    (if (zero? c)
      xs
      (let [k (mod n c)]
        (concat (drop k xs) (take k xs))))))

(defn remove-at
  "P20: remove the K'th element (counting from 1)."
  [xs k]
  (concat (take (dec k) xs) (drop k xs)))

(defn insert-at
  "P21: insert ITEM so that it becomes the K'th element (counting from 1)."
  [item xs k]
  (concat (take (dec k) xs) [item] (drop (dec k) xs)))

;; ---- P22-P28: ranges, random selection, combinations, groups, sorting

(defn int-range
  "P22: all integers from I to K inclusive; decreasing if I is larger than K."
  [i k]
  (if (<= i k) (range i (inc k)) (range i (dec k) -1)))

(defn rnd-select
  "P23: K randomly selected elements of the list."
  [xs k]
  (take k (shuffle xs)))

(defn lotto-select
  "P24: N different random numbers from 1..M."
  [n m]
  (rnd-select (int-range 1 m) n))

(defn rnd-permu
  "P25: a random permutation of the list."
  [xs]
  (shuffle xs))

(defn combination
  "P26: all combinations of K distinct elements, in positional order."
  [k xs]
  (cond (zero? k) [[]]
        (empty? xs) []
        :else (let [x (first xs) more (rest xs)]
                (concat (map (fn [c] (cons x c)) (combination (dec k) more))
                        (combination k more)))))

(defn group
  "P27b: all ways to split the (distinct) elements into disjoint groups of the
  given sizes. The groups are in size order, so group order matters."
  [xs sizes]
  (if (empty? sizes)
    [[]]
    (for [c (combination (first sizes) xs)
          more (group (remove (set c) xs) (rest sizes))]
      (cons c more))))

(defn group3
  "P27a: group nine people into groups of 2, 3 and 4."
  [xs]
  (group xs [2 3 4]))

(defn lsort
  "P28a: sort a list of lists by length of the sublists (short first, stable)."
  [xs]
  (sort-by count xs))

(defn lfsort
  "P28b: sort a list of lists by the frequency of their length (rare lengths
  first, stable)."
  [xs]
  (let [freq (frequencies (map count xs))]
    (sort-by (fn [l] (get freq (count l))) xs)))
