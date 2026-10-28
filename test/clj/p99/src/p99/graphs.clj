(ns p99.graphs
  "L-99 P80-P89: graphs. A graph is {:directed? bool :nodes [n ...] :edges [[a b] ...]};
  an edge may carry a weight as a third element. Undirected edges are stored once.
  Plain portable Clojure (also runs on JVM Clojure, the oracle for the tests).")

;; ---- P80: representations

(defn graph [directed? nodes edges]
  {:directed? directed? :nodes (vec nodes) :edges (vec edges)})

(defn neighbors
  "Distinct neighbours of n, in edge order."
  [g n]
  (vec (distinct
        (concat
         (for [[a b] (:edges g) :when (= a n)] b)
         (when-not (:directed? g)
           (for [[a b] (:edges g) :when (= b n)] a))))))

(defn adjacency-list [g]
  (vec (for [n (:nodes g)] [n (neighbors g n)])))

(defn adjacency->graph [directed? al]
  (let [reverse-seen? (fn [acc n m] (some (fn [[a b]] (and (= a m) (= b n))) acc))
        edges (reduce (fn [acc [n ms]]
                        (reduce (fn [acc m]
                                  (if (and (not directed?) (reverse-seen? acc n m))
                                    acc
                                    (conj acc [n m])))
                                acc ms))
                      [] al)]
    (graph directed? (map first al) edges)))

(defn readable->graph
  "Items are either an edge [a b] / [a b weight] or a lone node."
  [directed? items]
  (let [edges (filter vector? items)
        lone (remove vector? items)
        nodes (sort (distinct (concat lone (mapcat #(take 2 %) edges))))]
    (graph directed? nodes edges)))

(defn graph->readable [g]
  (let [touched (set (mapcat #(take 2 %) (:edges g)))]
    (vec (concat (remove touched (:nodes g)) (:edges g)))))

;; ---- helpers

(defn adjacent? [g a b] (boolean (some #{b} (neighbors g a))))

(defn degree [g n] (count (neighbors g n)))

(defn depth-first
  "Nodes reachable from start, in depth-first preorder."
  [g start]
  (let [go (fn go [order n]
             (if (some #{n} order)
               order
               (reduce go (conj order n) (neighbors g n))))]
    (go [] start)))

(defn connected? [g]
  (or (empty? (:nodes g))
      (= (count (:nodes g)) (count (depth-first g (first (:nodes g)))))))

(defn tree? [g]
  (and (not (:directed? g)) (connected? g)
       (= (count (:edges g)) (dec (count (:nodes g))))))

(defn combinations [coll k]
  (cond (zero? k) [[]]
        (empty? coll) []
        :else (concat (map #(into [(first coll)] %) (combinations (rest coll) (dec k)))
                      (combinations (rest coll) k))))

;; ---- P81: paths

(defn paths
  "All simple paths from a to b."
  [g a b]
  (let [go (fn go [path]
             (let [cur (peek path)]
               (if (= cur b)
                 [path]
                 (mapcat (fn [n] (when-not (some #{n} path) (go (conj path n))))
                         (neighbors g cur)))))]
    (vec (go [a]))))

;; ---- P82: cycles

(defn cycles
  "All simple cycles through a (a closes the path). Undirected: at least 3 distinct nodes."
  [g a]
  (let [min-k (if (:directed? g) 2 3)
        go (fn go [path]
             (mapcat (fn [n]
                       (cond (= n a) (if (>= (count path) min-k) [(conj path a)] [])
                             (some #{n} path) []
                             :else (go (conj path n))))
                     (neighbors g (peek path))))]
    (vec (go [a]))))

;; ---- P83: spanning trees

(defn- spans? [g edges]
  (connected? (graph false (:nodes g) edges)))

(defn spanning-trees
  "All spanning trees of an undirected graph, each as a vector of edges."
  [g]
  (vec (filter #(spans? g %) (combinations (:edges g) (dec (count (:nodes g)))))))

;; ---- P84: minimum spanning tree (Kruskal)

(defn min-spanning-tree
  "[edges total-weight]; edges are [a b w]."
  [g]
  (let [sorted (sort-by #(nth % 2) (:edges g))
        comp0 (into {} (map (fn [n] [n n]) (:nodes g)))
        root (fn root [comp n] (let [p (comp n)] (if (= p n) n (root comp p))))
        [edges _] (reduce (fn [[acc comp] [a b _ :as e]]
                            (let [ra (root comp a) rb (root comp b)]
                              (if (= ra rb) [acc comp] [(conj acc e) (assoc comp ra rb)])))
                          [[] comp0] sorted)]
    [edges (reduce + (map #(nth % 2) edges))]))

;; ---- P85: isomorphism (simple undirected graphs)

(defn isomorphism
  "A node mapping g1 -> g2 that preserves adjacency, or nil."
  [g1 g2]
  (when (and (= (count (:nodes g1)) (count (:nodes g2)))
             (= (count (:edges g1)) (count (:edges g2)))
             (= (sort (map #(degree g1 %) (:nodes g1))) (sort (map #(degree g2 %) (:nodes g2)))))
    (let [adj (fn [gr] (into {} (map (fn [n] [n (set (neighbors gr n))]) (:nodes gr))))
          a1 (adj g1)
          a2 (adj g2)
          order (sort-by #(- (count (a1 %))) (:nodes g1))
          go (fn go [todo mapping used]
               (if (empty? todo)
                 mapping
                 (let [n (first todo)]
                   (some (fn [m]
                           (when (and (not (contains? used m))
                                      (= (count (a1 n)) (count (a2 m)))
                                      (every? (fn [[x y]] (= (contains? (a1 n) x) (contains? (a2 m) y))) mapping))
                             (go (rest todo) (assoc mapping n m) (conj used m))))
                         (:nodes g2)))))]
      (go order {} #{}))))

(defn isomorphic? [g1 g2] (boolean (isomorphism g1 g2)))

;; ---- P86: node degree and graph colouring (Welsh-Powell)

(defn nodes-by-degree
  "Nodes by decreasing degree (stable)."
  [g]
  (vec (sort-by #(- (degree g %)) (:nodes g))))

(defn colour
  "Map node -> colour number (from 1)."
  [g]
  (loop [uncoloured (nodes-by-degree g) colours {} c 1]
    (if (empty? uncoloured)
      colours
      (let [[colours-now left]
            (reduce (fn [[cs left chosen] n]
                      (if (some #(adjacent? g n %) chosen)
                        [cs (conj left n) chosen]
                        [(assoc cs n c) left (conj chosen n)]))
                    [colours [] []] uncoloured)]
        (recur left colours-now (inc c))))))

;; ---- P88: connected components

(defn connected-components [g]
  (loop [todo (:nodes g) seen #{} out []]
    (cond (empty? todo) out
          (contains? seen (first todo)) (recur (rest todo) seen out)
          :else (let [c (depth-first g (first todo))]
                  (recur (rest todo) (into seen c) (conj out (set c)))))))

;; ---- P89: bipartite

(defn bipartite? [g]
  (loop [todo (:nodes g) side {}]
    (cond
      (empty? todo) true
      (contains? side (first todo)) (recur (rest todo) side)
      :else
      (let [result (loop [stack [(first todo)] side (assoc side (first todo) 0)]
                     (if (empty? stack)
                       side
                       (let [n (peek stack)
                             step (reduce (fn [[side stack] m]
                                            (cond (nil? side) [nil stack]
                                                  (not (contains? side m)) [(assoc side m (- 1 (side n))) (conj stack m)]
                                                  (= (side m) (side n)) [nil stack]
                                                  :else [side stack]))
                                          [side (pop stack)] (neighbors g n))]
                         (if (nil? (first step))
                           nil
                           (recur (second step) (first step))))))]
        (if result (recur (rest todo) result) false)))))
