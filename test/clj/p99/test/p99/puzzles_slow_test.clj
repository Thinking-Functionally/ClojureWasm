(ns p99.puzzles-slow-test
  "Heavier L-99 cases, kept out of the default gate (suite marked slow)."
  (:require [clojure.test :refer [deftest is]]
            [p99.puzzles :as p]))

(deftest p94-regular-graphs-seven-nodes
  (is (= [2 2 1 1]
         (map (fn [[n k]] (count (p/regular-graphs n k))) [[7 2] [7 4] [7 6] [7 0]])))
  (is (= 0 (count (p/regular-graphs 7 3)))))

(deftest p91-knights-tour-8x8-from-corners
  (doseq [start [[1 1] [1 8] [8 1] [8 8] [4 5]]]
    (let [tour (p/knights-tour 8 start)]
      (is (= 64 (count (set tour))))
      (is (= start (first tour)))
      (is (every? (fn [[a b]] (p/knight-step? a b)) (partition 2 1 tour))))))
