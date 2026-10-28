(ns p99.puzzles-test
  (:require [clojure.test :refer [deftest is]]
            [p99.puzzles :as p]))

(deftest p90-eight-queens
  (is (= [1 0 0 2 10 4 40 92] (map #(count (p/queens %)) (range 1 9))))
  (is (= [1 5 8 6 3 7 2 4] (first (p/queens 8))))
  (is (= [[2 4 1 3] [3 1 4 2]] (p/queens 4)))
  (is (= [[1]] (p/queens 1)))
  (doseq [s (p/queens 6)]
    (is (= (range 1 7) (sort s)))
    (is (every? (fn [[i a] ] (every? (fn [[j b]] (not= (Math/abs (- a b)) (- j i)))
                                     (drop (inc i) (map-indexed vector s))))
                (map-indexed vector s)))))

(deftest p91-knights-tour
  (is (nil? (p/knights-tour 4 [1 1])))
  (is (nil? (p/knights-tour 3 [1 1])))
  (is (= [[1 1]] (p/knights-tour 1 [1 1])))
  (doseq [n [5 6 8]]
    (let [tour (p/knights-tour n [1 1])]
      (is (= (* n n) (count tour)))
      (is (= (* n n) (count (set tour))))
      (is (every? (fn [[r c]] (and (<= 1 r n) (<= 1 c n))) tour))
      (is (every? (fn [[a b]] (p/knight-step? a b)) (partition 2 1 tour)))))
  (is (= [[1 1] [3 2] [5 1]] (take 3 (p/knights-tour 5 [1 1])))))

(deftest p92-von-koch
  (let [check (fn [edges]
                (let [labels (p/von-koch edges)
                      nodes (set (mapcat identity edges))
                      diffs (map (fn [[a b]] (Math/abs (- (labels a) (labels b)))) edges)]
                  (and (= nodes (set (keys labels)))
                       (= (range 1 (inc (count nodes))) (sort (vals labels)))
                       (= (range 1 (inc (count edges))) (sort diffs)))))]
    (is (check '[[d a] [a b] [b c] [e d] [f d] [g d]]))
    (is (check '[[a b] [b c]]))
    (is (check '[[a b] [a c] [a d] [a e]]))
    (is (check '[[a b] [b c] [c d] [d e] [e f]]))
    (is (check '[[a b] [a c] [b d] [b e] [c f] [c g]])))
  (is (= '{a 1, b 5, c 3, d 7, e 2, f 4, g 6}
         (p/von-koch '[[d a] [a b] [b c] [e d] [f d] [g d]])))
  (is (= '{a 1, b 3, c 2} (p/von-koch '[[a b] [b c]]))))

(defn- ev [e]
  (if (vector? e)
    (let [a (ev (nth e 1)) b (ev (nth e 2))]
      (case (first e) :+ (+ a b) :- (- a b) :* (* a b) :/ (/ a b)))
    e))

(defn- leaves [e]
  (if (vector? e) (concat (leaves (nth e 1)) (leaves (nth e 2))) [e]))

(deftest p93-arithmetic-puzzle
  (is (= [[2 2]] (p/equations [2 2])))
  (is (= ["2 = 2"] (map p/equation->string (p/equations [2 2]))))
  (is (= [] (p/equations [1 2])))
  (let [eqs (p/equations [2 3 5 7 11])]
    (is (= 12 (count eqs)))
    (is (every? (fn [[l r]] (= (ev l) (ev r))) eqs))
    (is (every? (fn [[l r]] (= [2 3 5 7 11] (vec (concat (leaves l) (leaves r))))) eqs))
    (is (some #{"2 = 3 - ((5 + 7) - 11)"} (map p/equation->string eqs)))
    (is (= "2 = (3 - 5) - (7 - 11)" (nth (map p/equation->string eqs) 2)))))

(deftest p94-regular-graphs
  (is (= [1 2 2 1 0 1 1]
         (map (fn [[n k]] (count (p/regular-graphs n k)))
              [[4 3] [6 3] [6 2] [5 2] [5 3] [6 4] [6 1]])))
  (is (every? (fn [gr] (every? #(= 3 (count (filter (fn [e] (some #{%} (take 2 e))) (:edges gr)))) (:nodes gr)))
              (p/regular-graphs 6 3))))

(deftest p95-full-words
  (is (= "one-seven-five" (p/full-words 175)))
  (is (= "zero" (p/full-words 0)))
  (is (= "nine" (p/full-words 9)))
  (is (= "one-zero-zero-zero" (p/full-words 1000))))

(deftest p96-identifiers
  (is (every? p/identifier? ["x" "this_is_ok" "a_1" "abc123" "a1_b2_c3" "A" "ThisIsOk"]))
  (is (not-any? p/identifier? ["" "bad_" "2x" "a__b" "_a" "a-b" "a b" "9"]))
  (is (= [true false] (map p/identifier? ["valid_name" "in__valid"]))))

(def sudoku
  ["53..7...."
   "6..195..."
   ".98....6."
   "8...6...3"
   "4..8.3..1"
   "7...2...6"
   ".6....28."
   "...419..5"
   "....8..79"])

(def sudoku-solved
  ["534678912"
   "672195348"
   "198342567"
   "859761423"
   "426853791"
   "713924856"
   "961537284"
   "287419635"
   "345286179"])

(deftest p97-sudoku
  (is (= sudoku-solved (p/sudoku->rows (p/solve-sudoku (p/parse-sudoku sudoku)))))
  (is (= (p/parse-sudoku sudoku-solved) (p/solve-sudoku (p/parse-sudoku sudoku-solved))))
  (let [solved (p/solve-sudoku (p/parse-sudoku sudoku))
        given (p/parse-sudoku sudoku)
        rows (partition 9 solved)
        cols (apply map vector rows)
        boxes (for [br [0 3 6] bc [0 3 6]]
                (for [r (range br (+ br 3)) c (range bc (+ bc 3))] (nth (nth rows r) c)))]
    (is (every? #(= (range 1 10) (sort %)) (concat rows cols boxes)))
    (is (every? (fn [[a b]] (or (zero? a) (= a b))) (map vector given solved))))
  (is (nil? (p/solve-sudoku (p/parse-sudoku (assoc (vec sudoku) 0 "55..7....")))))
  (is (= [0 5 3] (take 3 (p/parse-sudoku [".53......" "........." "........." "........." "........." "........." "........." "........." "........."])))))

(deftest p98-nonogram
  (let [rows '[[3] [2 1] [3 2] [2 2] [6] [1 5] [6] [1] [2]]
        cols '[[1 2] [3 1] [1 5] [7 1] [5] [3] [4] [3]]
        grid (p/nonogram rows cols)]
    (is (= [[0 1 1 1 0 0 0 0]
            [1 1 0 1 0 0 0 0]
            [0 1 1 1 0 0 1 1]
            [0 0 1 1 0 0 1 1]
            [0 0 1 1 1 1 1 1]
            [1 0 1 1 1 1 1 0]
            [1 1 1 1 1 1 0 0]
            [0 0 0 0 1 0 0 0]
            [0 0 0 1 1 0 0 0]]
           grid))
    (is (= rows (mapv p/runs grid)))
    (is (= cols (mapv #(p/runs (mapv (fn [row] (nth row %)) grid)) (range 8)))))
  (is (= [[1]] (p/nonogram [[1]] [[1]])))
  (is (= [[0]] (p/nonogram [[]] [[]])))
  (is (nil? (p/nonogram [[2]] [[1] [1] [1]]))))

(deftest p99-crossword
  (let [slots [[[0 0] [0 1] [0 2]] [[0 0] [1 0] [2 0]] [[0 2] [1 2] [2 2]] [[2 0] [2 1] [2 2]]]
        sols (p/crossword slots ["cat" "cow" "tap" "wip" "dog" "pig"])]
    (is (= [["cat" "cow" "tap" "wip"] ["cow" "cat" "wip" "tap"]] sols))
    (is (every? (fn [s] (= (count s) (count (set s)))) sols))
    (is (every? (fn [[top left right bottom]]
                  (and (= (first top) (first left))
                       (= (last top) (first right))
                       (= (last left) (first bottom))
                       (= (last right) (last bottom))))
                sols)))
  (is (= [] (p/crossword [[[0 0] [0 1]] [[0 0] [1 0]]] ["ab" "cd"])))
  (is (= [["ab" "ac"] ["ac" "ab"]] (p/crossword [[[0 0] [0 1]] [[0 0] [1 0]]] ["ab" "ac"])))
  (is (= [] (p/crossword [[[0 0] [0 1]]] ["abc"]))))
