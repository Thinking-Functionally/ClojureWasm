(ns p99.graphs-test
  (:require [clojure.test :refer [deftest is]]
            [p99.graphs :as g]))

(def ug (g/readable->graph false '[[b c] [f c] [g h] d [f b] [k f] [h g]]))
(def dg (g/graph true [1 2 3 4 5 6] [[1 2] [2 3] [1 3] [3 4] [4 2] [5 6] [4 1]]))
(def k4 (g/graph false [1 2 3 4] [[1 2] [1 3] [1 4] [2 3] [2 4] [3 4]]))
(def c5 (g/graph false [1 2 3 4 5] [[1 2] [2 3] [3 4] [4 5] [5 1]]))
(def c6 (g/graph false [1 2 3 4 5 6] [[1 2] [2 3] [3 4] [4 5] [5 6] [6 1]]))
(def wg (g/graph false '[a b c d e f g]
                 '[[a b 5] [a d 3] [b c 2] [b e 4] [c e 6] [d e 7] [d f 4] [d g 3] [e g 5] [f g 4]]))

(defn- proper-colouring? [gr colours]
  (and (= (set (:nodes gr)) (set (keys colours)))
       (every? (fn [[a b]] (not= (colours a) (colours b))) (:edges gr))))

(deftest p80-representations
  (is (= {:directed? false :nodes '[b c d f g h k]
          :edges '[[b c] [f c] [g h] [f b] [k f] [h g]]}
         ug))
  (is (= '[[b [c f]] [c [b f]] [d []] [f [c b k]] [g [h]] [h [g]] [k [f]]] (g/adjacency-list ug)))
  (is (= '[d [b c] [f c] [g h] [f b] [k f] [h g]] (g/graph->readable ug)))
  (is (= ug (g/readable->graph false (g/graph->readable ug))))
  (is (= [[1 [2 3]] [2 [3]] [3 [4]] [4 [2 1]] [5 [6]] [6 []]] (g/adjacency-list dg)))
  (is (= (update dg :edges set) (update (g/adjacency->graph true (g/adjacency-list dg)) :edges set)))
  (is (= k4 (g/adjacency->graph false (g/adjacency-list k4))))
  (is (= 3 (g/degree ug 'f)))
  (is (= 0 (g/degree ug 'd)))
  (is (= [:a :b] (:nodes (g/readable->graph false [[:a :b]])))))

(deftest p81-paths
  (is (= [[1 2 3 4] [1 3 4]] (g/paths dg 1 4)))
  (is (= [] (g/paths dg 2 6)))
  (is (= [[5 6]] (g/paths dg 5 6)))
  (is (= [[1]] (g/paths dg 1 1)))
  (is (= 2 (count (g/paths c5 1 3))))
  (is (every? #(and (apply distinct? %) (= 1 (first %)) (= 3 (last %))) (g/paths k4 1 3)))
  (is (= 5 (count (g/paths k4 1 3)))))

(deftest p82-cycles
  (is (= [[2 3 4 2] [2 3 4 1 2]] (g/cycles dg 2)))
  (is (= [] (g/cycles dg 5)))
  (is (= [[1 2 3 4 5 1] [1 5 4 3 2 1]] (g/cycles c5 1)))
  (is (= [] (g/cycles (g/graph false [1 2] [[1 2]]) 1)))
  (is (= 12 (count (g/cycles k4 1)))))

(deftest p83-spanning-trees
  (is (= 16 (count (g/spanning-trees k4))))
  (is (= 5 (count (g/spanning-trees c5))))
  (is (= 79 (count (g/spanning-trees wg))))
  (is (= 1 (count (g/spanning-trees (g/graph false [1 2 3] [[1 2] [2 3]])))))
  (is (every? #(and (= 3 (count %)) (g/tree? (g/graph false (:nodes k4) %))) (g/spanning-trees k4)))
  (is (g/tree? (g/graph false [1 2 3] [[1 2] [2 3]])))
  (is (not (g/tree? c5)))
  (is (g/connected? k4))
  (is (not (g/connected? ug))))

(deftest p84-minimum-spanning-tree
  (is (= [[['b 'c 2] ['a 'd 3] ['d 'g 3] ['b 'e 4] ['d 'f 4] ['a 'b 5]] 21] (g/min-spanning-tree wg)))
  (is (= 21 (apply min (map (fn [es] (reduce + (map #(nth % 2) es))) (g/spanning-trees wg)))))
  (is (= [[[1 2 1] [2 3 2]] 3]
         (g/min-spanning-tree (g/graph false [1 2 3] [[1 2 1] [2 3 2] [1 3 9]])))))

(deftest p85-isomorphism
  (is (= {1 :a, 2 :c, 3 :e, 4 :b, 5 :d}
         (g/isomorphism c5 (g/graph false [:a :b :c :d :e] [[:a :c] [:c :e] [:e :b] [:b :d] [:d :a]]))))
  (is (g/isomorphic? c5 c5))
  (is (g/isomorphic? k4 (g/graph false [:w :x :y :z] [[:w :x] [:w :y] [:w :z] [:x :y] [:x :z] [:y :z]])))
  (is (not (g/isomorphic? c5 (g/graph false [1 2 3 4 5] [[1 2] [2 3] [3 4] [4 5] [1 3]]))))
  (is (not (g/isomorphic? c6 (g/graph false [1 2 3 4 5 6] [[1 2] [2 3] [3 1] [4 5] [5 6] [6 4]]))))
  (is (not (g/isomorphic? c5 c6)))
  (let [m (g/isomorphism c6 (g/graph false [6 5 4 3 2 1] [[6 5] [5 4] [4 3] [3 2] [2 1] [1 6]]))]
    (is (every? (fn [[a b]] (g/adjacent? (g/graph false [6 5 4 3 2 1] [[6 5] [5 4] [4 3] [3 2] [2 1] [1 6]])
                                         (m a) (m b)))
                (:edges c6)))))

(deftest p86-degree-and-colouring
  (is (= '[f b c g h k d] (g/nodes-by-degree ug)))
  (is (= '{f 1, g 1, d 1, b 2, h 2, k 2, c 3} (g/colour ug)))
  (is (proper-colouring? ug (g/colour ug)))
  (is (= 4 (count (set (vals (g/colour k4))))))
  (is (= 3 (count (set (vals (g/colour c5))))))
  (is (= 2 (count (set (vals (g/colour c6))))))
  (is (proper-colouring? wg (g/colour wg)))
  (is (proper-colouring? c5 (g/colour c5))))

(deftest p87-depth-first
  (is (= '[b c f k] (g/depth-first ug 'b)))
  (is (= '[d] (g/depth-first ug 'd)))
  (is (= [1 2 3 4] (g/depth-first dg 1)))
  (is (= [1 2 3 4 5] (g/depth-first c5 1)))
  (is (= (set (:nodes k4)) (set (g/depth-first k4 3)))))

(deftest p88-connected-components
  (is (= '[#{b c f k} #{d} #{g h}] (g/connected-components ug)))
  (is (= [(set (:nodes k4))] (g/connected-components k4)))
  (is (= [] (g/connected-components (g/graph false [] []))))
  (is (= [#{1 2} #{3}] (g/connected-components (g/graph false [1 2 3] [[1 2]])))))

(deftest p89-bipartite
  (is (= false (g/bipartite? ug)))
  (is (= true (g/bipartite? c6)))
  (is (= false (g/bipartite? c5)))
  (is (= false (g/bipartite? k4)))
  (is (= true (g/bipartite? (g/graph false [1 2 3 4 5] [[1 2] [2 3] [4 5]]))))
  (is (= true (g/bipartite? (g/graph false [] []))))
  (is (= true (g/bipartite? (g/graph false [1 2 3 4] [[1 2] [1 3] [1 4]]))))
  (is (= false (g/bipartite? (g/graph false [1 2 3 4 5 6] [[1 2] [2 3] [3 1] [4 5]])))))
