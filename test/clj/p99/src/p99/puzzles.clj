(ns p99.puzzles
  "L-99 P90-P99: miscellaneous problems and puzzles. Plain portable Clojure (also
  runs on JVM Clojure, the oracle for the tests)."
  (:require [clojure.string :as str]
            [p99.graphs :as g]))

;; ---- P90: eight queens

(defn queens
  "All solutions on an n x n board as vectors of columns (1-based), one per row,
  in lexicographic order."
  [n]
  (let [safe? (fn [cols c]
                (let [r (count cols)]
                  (every? (fn [i] (let [ci (nth cols i)]
                                    (and (not= ci c) (not= (Math/abs (- ci c)) (- r i)))))
                          (range r))))
        place (fn place [cols]
                (if (= n (count cols))
                  [cols]
                  (mapcat (fn [c] (when (safe? cols c) (place (conj cols c))))
                          (range 1 (inc n)))))]
    (vec (place []))))

;; ---- P91: knight's tour

(defn- knight-moves [n [r c]]
  (for [[dr dc] [[2 1] [1 2] [-1 2] [-2 1] [-2 -1] [-1 -2] [1 -2] [2 -1]]
        :let [r2 (+ r dr) c2 (+ c dc)]
        :when (and (<= 1 r2 n) (<= 1 c2 n))]
    [r2 c2]))

(defn knights-tour
  "A knight's tour of the n x n board from start (squares are [row col], from 1),
  or nil. Warnsdorff ordering with backtracking."
  [n start]
  (let [total (* n n)
        go (fn go [path visited]
             (if (= total (count path))
               path
               (let [cands (remove visited (knight-moves n (peek path)))
                     onward (fn [sq] (count (remove visited (knight-moves n sq))))]
                 (some (fn [sq] (go (conj path sq) (conj visited sq)))
                       (sort-by onward cands)))))]
    (go [start] #{start})))

(defn knight-step? [[r1 c1] [r2 c2]]
  (let [dr (Math/abs (- r1 r2)) dc (Math/abs (- c1 c2))]
    (or (and (= 1 dr) (= 2 dc)) (and (= 2 dr) (= 1 dc)))))

;; ---- P92: von Koch (graceful labelling of a tree)

(defn von-koch
  "Label the n nodes of an undirected tree (given as a list of edges) with 1..n so
  that the n-1 edge differences are all different. Returns {node label} or nil."
  [edges]
  (let [tg (g/readable->graph false (vec edges))
        n (count (:nodes tg))
        root (first (:nodes tg))
        ;; visit order: each node after the first has a parent earlier in the order
        order (g/depth-first tg root)
        idx (zipmap order (range))
        parent (into {} (for [x (rest order)]
                          [x (first (filter (fn [y] (and (< (idx y) (idx x)) (g/adjacent? tg x y)))
                                            order))]))
        go (fn go [todo labels used diffs]
             (if (empty? todo)
               labels
               (let [x (first todo)]
                 (some (fn [l]
                         (let [d (Math/abs (- l (labels (parent x))))]
                           (when (and (not (contains? used l)) (not (contains? diffs d)))
                             (go (rest todo) (assoc labels x l) (conj used l) (conj diffs d)))))
                       (range 1 (inc n))))))]
    (if (= 1 n)
      {root 1}
      (some (fn [l] (go (rest order) {root l} #{l} #{})) (range 1 (inc n))))))

;; ---- P93: arithmetic puzzle

(defn- all-exprs
  "Every [value expression] over the numbers, in order, with every bracketing and
  operator choice. An expression is a number or [op left right]."
  [nums]
  (if (= 1 (count nums))
    [[(first nums) (first nums)]]
    (vec (for [i (range 1 (count nums))
               [va ea] (all-exprs (subvec nums 0 i))
               [vb eb] (all-exprs (subvec nums i))
               op [:+ :- :* :/]
               :when (not (and (= op :/) (zero? vb)))]
           [(case op :+ (+ va vb) :- (- va vb) :* (* va vb) :/ (/ va vb))
            [op ea eb]]))))

(defn equations
  "All [lhs rhs] expression pairs, splitting the numbers in order, with equal values."
  [nums]
  (let [nums (vec nums)]
    (vec (for [i (range 1 (count nums))
               [vl el] (all-exprs (subvec nums 0 i))
               [vr er] (all-exprs (subvec nums i))
               :when (= vl vr)]
           [el er]))))

(defn expr->string [e]
  (if (vector? e)
    (str "(" (expr->string (nth e 1)) " " (name (first e)) " " (expr->string (nth e 2)) ")")
    (str e)))

(defn equation->string [[l r]]
  (let [strip (fn [s] (if (and (str/starts-with? s "(") (str/ends-with? s ")")) (subs s 1 (dec (count s))) s))]
    (str (strip (expr->string l)) " = " (strip (expr->string r)))))

;; ---- P94: regular graphs

(defn regular-graphs
  "One representative of each isomorphism class of connected-or-not simple k-regular
  graphs on n nodes."
  [n k]
  (let [need0 (vec (repeat n k))
        build (fn build [i need edges]
                (cond
                  (= i n) (if (every? zero? need) [edges] [])
                  :else
                  (let [cands (filter #(pos? (need %)) (range (inc i) n))
                        want (need i)]
                    (if (< (count cands) want)
                      []
                      (mapcat (fn [chosen]
                                (build (inc i)
                                       (reduce #(update %1 %2 dec) (assoc need i 0) chosen)
                                       (into edges (map (fn [j] [i j]) chosen))))
                              (g/combinations (vec cands) want))))))
        graphs (map #(g/graph false (range n) %) (build 0 need0 []))]
    (reduce (fn [reps gr]
              (if (some #(g/isomorphic? gr %) reps) reps (conj reps gr)))
            [] graphs)))

;; ---- P95: full words

(def ^:private digit-words
  ["zero" "one" "two" "three" "four" "five" "six" "seven" "eight" "nine"])

(defn full-words
  "175 -> \"one-seven-five\""
  [n]
  (str/join "-" (map #(digit-words (- (int %) 48)) (str n))))

;; ---- P96: syntax checker (Ada-style identifiers)

(def ^:private letters (set (concat (map char (range 97 123)) (map char (range 65 91)))))
(def ^:private digits (set (map char (range 48 58))))

(defn identifier?
  "identifier ::= letter { [\"_\"] (letter | digit) }"
  [s]
  (let [cs (vec s)]
    (boolean
     (and (seq cs)
          (contains? letters (first cs))
          (loop [i 1]
            (cond (= i (count cs)) true
                  (= \_ (nth cs i)) (and (< (inc i) (count cs))
                                         (or (contains? letters (nth cs (inc i)))
                                             (contains? digits (nth cs (inc i))))
                                         (recur (+ i 2)))
                  (or (contains? letters (nth cs i)) (contains? digits (nth cs i))) (recur (inc i))
                  :else false))))))

;; ---- P97: sudoku

(defn parse-sudoku
  "Nine strings of nine characters; digits or . for blanks -> flat vector of 81 ints (0 = blank)."
  [rows]
  (vec (mapcat (fn [row] (map #(if (= \. %) 0 (- (int %) 48)) row)) rows)))

(defn sudoku->rows [grid]
  (mapv #(apply str %) (partition 9 grid)))

(defn- candidates [grid i]
  (let [r (quot i 9) c (rem i 9)
        br (* 3 (quot r 3)) bc (* 3 (quot c 3))
        used (set (concat (for [cc (range 9)] (grid (+ (* r 9) cc)))
                          (for [rr (range 9)] (grid (+ (* rr 9) c)))
                          (for [rr (range br (+ br 3)) cc (range bc (+ bc 3))] (grid (+ (* rr 9) cc)))))]
    (remove used (range 1 10))))

(defn solve-sudoku
  "Solved flat vector, or nil. Always branches on the blank with fewest candidates."
  [grid]
  (let [blanks (filter #(zero? (grid %)) (range 81))]
    (if (empty? blanks)
      grid
      (let [[i cs] (reduce (fn [[bi bcs] i]
                             (let [cs (candidates grid i)]
                               (if (or (nil? bi) (< (count cs) (count bcs))) [i cs] [bi bcs])))
                           [nil nil] blanks)]
        (some #(solve-sudoku (assoc grid i %)) cs)))))

;; ---- P98: nonograms

(defn- min-len [clue] (if (empty? clue) 0 (+ (reduce + clue) (dec (count clue)))))

(defn- patterns
  "All 0/1 rows of the given width that satisfy a clue."
  [clue width]
  (if (empty? clue)
    [(vec (repeat width 0))]
    (let [b (first clue) more (rest clue)]
      (vec (for [s (range 0 (inc (- width (min-len clue))))
                 p (if (seq more)
                     (patterns more (- width s b 1))
                     [(vec (repeat (- width s b) 0))])]
             (vec (concat (repeat s 0) (repeat b 1) (when (seq more) [0]) p)))))))

(defn runs
  "Lengths of the runs of 1s."
  [cells]
  (->> (partition-by identity cells) (filter #(= 1 (first %))) (map count) vec))

(defn- prefix-ok? [cells clue]
  (let [rs (runs cells)]
    (if (= 1 (peek cells))
      (let [closed (pop rs)]
        (and (< (count closed) (count clue))
             (= closed (vec (take (count closed) clue)))
             (<= (peek rs) (nth clue (count closed)))))
      (and (<= (count rs) (count clue)) (= rs (vec (take (count rs) clue)))))))

(defn nonogram
  "Rows and columns clues -> a grid (vector of 0/1 rows) or nil."
  [row-clues col-clues]
  (let [w (count col-clues)
        pats (mapv #(patterns % w) row-clues)
        go (fn go [i grid]
             (if (= i (count row-clues))
               (when (every? true? (map-indexed (fn [c clue] (= clue (runs (mapv #(nth % c) grid)))) col-clues))
                 grid)
               (some (fn [p]
                       (let [grid2 (conj grid p)]
                         (when (every? true? (map-indexed
                                              (fn [c clue] (prefix-ok? (mapv #(nth % c) grid2) clue))
                                              col-clues))
                           (go (inc i) grid2))))
                     (nth pats i))))]
    (go 0 [])))

;; ---- P99: crossword puzzle

(defn crossword
  "slots: vectors of [row col] cells. Fill every slot with a different word of the
  right length so that crossing letters agree. Returns all solutions, each a vector
  of words in slot order."
  [slots words]
  (let [go (fn go [i grid used]
             (if (= i (count slots))
               [[]]
               (let [slot (nth slots i)]
                 (mapcat
                  (fn [w]
                    (when (and (= (count w) (count slot)) (not (contains? used w)))
                      (let [pairs (map vector slot w)]
                        (when (every? (fn [[cell ch]] (let [cur (get grid cell)] (or (nil? cur) (= cur ch)))) pairs)
                          (map #(into [w] %) (go (inc i) (into grid pairs) (conj used w)))))))
                  words))))]
    (vec (go 0 {} #{}))))
