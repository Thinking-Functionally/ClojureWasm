(ns p99.trees
  "L-99 P54-P69: binary trees. A tree is nil (empty) or [value left right].
  Plain portable Clojure (also runs on JVM Clojure, the oracle for the tests)."
  (:require [clojure.string :as str]))

(defn value [t] (nth t 0))
(defn left [t] (nth t 1))
(defn right [t] (nth t 2))

;; ---- P54

(defn tree? [t]
  (or (nil? t)
      (and (sequential? t) (= 3 (count t)) (tree? (left t)) (tree? (right t)))))

(defn size [t] (if (nil? t) 0 (+ 1 (size (left t)) (size (right t)))))
(defn height [t] (if (nil? t) 0 (inc (max (height (left t)) (height (right t))))))

;; ---- P55: completely balanced trees

(defn cbal-tree
  "All completely balanced trees with n nodes (every node: subtree sizes differ by <= 1)."
  [n]
  (if (zero? n)
    [nil]
    (let [m (dec n) q (quot m 2)]
      (if (even? m)
        (for [l (cbal-tree q) r (cbal-tree q)] ['x l r])
        (concat (for [l (cbal-tree q) r (cbal-tree (inc q))] ['x l r])
                (for [l (cbal-tree (inc q)) r (cbal-tree q)] ['x l r]))))))

(defn cbal? [t]
  (or (nil? t)
      (and (<= (Math/abs (- (size (left t)) (size (right t)))) 1)
           (cbal? (left t))
           (cbal? (right t)))))

;; ---- P56: symmetry

(defn mirror? [a b]
  (cond (and (nil? a) (nil? b)) true
        (or (nil? a) (nil? b)) false
        :else (and (mirror? (left a) (right b)) (mirror? (right a) (left b)))))

(defn symmetric? [t] (or (nil? t) (mirror? (left t) (right t))))

;; ---- P57: binary search trees

(defn bst-add [t x]
  (cond (nil? t) [x nil nil]
        (< x (value t)) [(value t) (bst-add (left t) x) (right t)]
        (> x (value t)) [(value t) (left t) (bst-add (right t) x)]
        :else t))

(defn construct [xs] (reduce bst-add nil xs))

;; ---- P58: symmetric completely balanced trees

(defn mirror-tree [t]
  (when-not (nil? t) [(value t) (mirror-tree (right t)) (mirror-tree (left t))]))

(defn sym-cbal-trees
  "All symmetric, completely balanced trees with n nodes. A symmetric tree is a root over
  some subtree and its mirror image, so only odd n can qualify."
  [n]
  (cond (zero? n) [nil]
        (even? n) []
        :else (for [l (cbal-tree (quot n 2))] ['x l (mirror-tree l)])))

;; ---- P59-P60: height-balanced trees

(def hbal-tree
  "All height-balanced trees of height h (subtree heights differ by <= 1)."
  (memoize
   (fn [h]
     (cond (neg? h) []
           (zero? h) [nil]
           :else (vec (for [[hl hr] [[(dec h) (dec h)] [(dec h) (- h 2)] [(- h 2) (dec h)]]
                            l (hbal-tree hl)
                            r (hbal-tree hr)]
                        ['x l r]))))))

(defn min-nodes
  "Fewest nodes in a height-balanced tree of height h."
  [h]
  (loop [i 0 a 0 b 1]
    (if (>= i h) a (recur (inc i) b (+ 1 a b)))))

(defn max-nodes [h] (dec (bit-shift-left 1 h)))

(defn min-height [n]
  (first (filter #(>= (max-nodes %) n) (range))))

(defn max-height [n]
  (dec (first (filter #(> (min-nodes %) n) (range)))))

(def ^:private hbal-n-h
  (memoize
   (fn [n h]
     (cond (or (neg? h) (neg? n)) []
           (zero? h) (if (zero? n) [nil] [])
           (zero? n) []
           :else (vec (for [nl (range n)
                            [hl hr] [[(dec h) (dec h)] [(dec h) (- h 2)] [(- h 2) (dec h)]]
                            l (hbal-n-h nl hl)
                            r (hbal-n-h (- n 1 nl) hr)]
                        ['x l r]))))))

(defn hbal-tree-nodes
  "All height-balanced trees with exactly n nodes."
  [n]
  (vec (mapcat #(hbal-n-h n %) (range (min-height n) (inc (max-height n))))))

;; ---- P61-P62: leaves, internals, levels

(defn leaves
  "Values of the leaves, left to right."
  [t]
  (cond (nil? t) []
        (and (nil? (left t)) (nil? (right t))) [(value t)]
        :else (concat (leaves (left t)) (leaves (right t)))))

(defn count-leaves [t] (count (leaves t)))

(defn internals
  "Values of the nodes that have at least one child, in preorder."
  [t]
  (if (or (nil? t) (and (nil? (left t)) (nil? (right t))))
    []
    (cons (value t) (concat (internals (left t)) (internals (right t))))))

(defn at-level
  "Values of the nodes at level k (the root is level 1), left to right."
  [t k]
  (cond (nil? t) []
        (= k 1) [(value t)]
        :else (concat (at-level (left t) (dec k)) (at-level (right t) (dec k)))))

(defn level-order [t]
  (loop [queue (if (nil? t) [] [t]) out []]
    (if (empty? queue)
      out
      (let [[n & more] queue]
        (recur (into (vec more) (remove nil? [(left n) (right n)]))
               (conj out (value n)))))))

;; ---- P63: complete binary trees

(defn complete-binary-tree
  ([n] (complete-binary-tree n 1))
  ([n addr]
   (when (<= addr n)
     ['x (complete-binary-tree n (* 2 addr)) (complete-binary-tree n (inc (* 2 addr)))])))

(defn complete? [t]
  (= (mapv count (map #(at-level t %) (range 1 (inc (height t)))))
     (mapv count (map #(at-level (complete-binary-tree (size t)) %) (range 1 (inc (height t)))))))

;; ---- P64-P66: layouts. A positioned node is [[v x y] left right].

(defn layout1
  "x = position in the inorder sequence, y = depth (root is 1)."
  [t]
  (let [go (fn go [t x0 y]
             (if (nil? t)
               nil
               (let [lsize (size (left t)) x (+ x0 lsize 1)]
                 [[(value t) x y] (go (left t) x0 (inc y)) (go (right t) x (inc y))])))]
    (go t 0 1)))

(defn layout2
  "Horizontal distance between a node and its children halves at each level."
  [t]
  (when-not (nil? t)
    (let [k (height t)
          place (fn place [t x y]
                  (when-not (nil? t)
                    (let [d (if (< y k) (bit-shift-left 1 (- k y 1)) 0)]
                      [[(value t) x y] (place (left t) (- x d) (inc y)) (place (right t) (+ x d) (inc y))])))
          raw (place t 0 1)
          xs (fn xs [t] (when-not (nil? t) (cons (second (first t)) (concat (xs (second t)) (xs (nth t 2))))))
          dx (- 1 (reduce min (xs raw)))
          shift (fn shift [t] (when-not (nil? t)
                                (let [[[v x y] l r] t] [[v (+ x dx) y] (shift l) (shift r)])))]
      (shift raw))))

(defn- merge-contours
  "Per-level merge of two contours; `pick` chooses which wins where both have a level."
  [a b pick]
  (vec (for [i (range (max (count a) (count b)))]
         (cond (>= i (count a)) (nth b i)
               (>= i (count b)) (nth a i)
               :else (pick (nth a i) (nth b i))))))

(defn- lay3
  "Lay out t with its root at x=0 -> [rel-tree left-contour right-contour]. A rel-tree
  node is [[value 0] [left-rel offset] [right-rel offset]] (children optional);
  contours hold the leftmost/rightmost x per depth, relative to the root."
  [t]
  (if (nil? t)
    [nil [] []]
    (let [[lt llc lrc] (lay3 (left t))
          [rt rlc rrc] (lay3 (right t))]
      (cond
        (and (nil? lt) (nil? rt))
        [[[(value t) 0] nil nil] [0] [0]]

        (nil? rt)
        [[[(value t) 0] [lt -1] nil] (into [0] (map dec llc)) (into [0] (map dec lrc))]

        (nil? lt)
        [[[(value t) 0] nil [rt 1]] (into [0] (map inc rlc)) (into [0] (map inc rrc))]

        :else
        (let [m (reduce max (map - lrc rlc))
              d (quot (+ m 2) 2)]
          [[[(value t) 0] [lt (- d)] [rt d]]
           (into [0] (merge-contours (map #(- % d) llc) (map #(+ % d) rlc) (fn [a _] a)))
           (into [0] (merge-contours (map #(- % d) lrc) (map #(+ % d) rrc) (fn [_ b] b)))])))))

(defn layout3
  "As compact as possible: sibling subtrees are pushed together until their facing
  contours are one apart; each parent is centred over its two children."
  [t]
  (when-not (nil? t)
    (let [[rel lc _] (lay3 t)
          dx (- 1 (reduce min lc))
          expand (fn expand [n x y]
                   (when-not (nil? n)
                     (let [[[v _] l r] n]
                       [[v x y]
                        (when l (expand (first l) (+ x (second l)) (inc y)))
                        (when r (expand (first r) (+ x (second r)) (inc y)))])))]
      (expand rel dx 1))))

;; ---- P67: string representation a(b(d,e),c(,f(g,)))

(defn tree->string [t]
  (cond (nil? t) ""
        (and (nil? (left t)) (nil? (right t))) (str (value t))
        :else (str (value t) "(" (tree->string (left t)) "," (tree->string (right t)) ")")))

(defn string->tree
  "Parse the P67 notation; labels are single characters."
  [s]
  (let [parse (fn parse [i]
                ;; returns [tree next-index]
                (if (or (>= i (count s)) (contains? #{\, \)} (nth s i)))
                  [nil i]
                  (let [v (nth s i)]
                    (if (and (< (inc i) (count s)) (= \( (nth s (inc i))))
                      (let [[l i1] (parse (+ i 2))
                            [r i2] (parse (inc i1))]
                        [[v l r] (inc i2)])
                      [[v nil nil] (inc i)]))))]
    (first (parse 0))))

;; ---- P68: preorder / inorder

(defn preorder [t]
  (if (nil? t) [] (concat [(value t)] (preorder (left t)) (preorder (right t)))))

(defn inorder [t]
  (if (nil? t) [] (concat (inorder (left t)) [(value t)] (inorder (right t)))))

(defn pre-in-tree
  "Rebuild a tree of distinct values from its preorder and inorder sequences."
  [pre in]
  (when (seq pre)
    (let [root (first pre)
          [lin rin] (split-with #(not= root %) in)
          rin (rest rin)
          lpre (take (count lin) (rest pre))
          rpre (drop (count lin) (rest pre))]
      [root (pre-in-tree lpre lin) (pre-in-tree rpre rin)])))

;; ---- P69: dot string, e.g. abd..e..c.fg...

(defn tree->ds [t]
  (if (nil? t) "." (str (value t) (tree->ds (left t)) (tree->ds (right t)))))

(defn ds->tree [s]
  (let [parse (fn parse [i]
                (let [c (nth s i)]
                  (if (= \. c)
                    [nil (inc i)]
                    (let [[l i1] (parse (inc i))
                          [r i2] (parse i1)]
                      [[c l r] i2]))))]
    (first (parse 0))))
