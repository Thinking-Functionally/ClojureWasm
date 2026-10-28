(ns p99.trees-test
  (:require [clojure.test :refer [deftest is]]
            [p99.trees :as t]))

(defn- symbolize
  "Characters (as parsed from the string notation) -> symbols."
  [t]
  (when-not (nil? t) [(symbol (str (first t))) (symbolize (second t)) (symbolize (nth t 2))]))

(def sample '[a [b [d nil nil] [e nil nil]] [c nil [f [g nil nil] nil]]])
(def lsample (symbolize (t/string->tree "n(k(c(a,h(g(e,),)),m),u(p(,s(q,)),))")))

(defn- positions
  "[value x y] of every node, in preorder."
  [t]
  (if (nil? t)
    []
    (concat [(first t)] (positions (second t)) (positions (nth t 2)))))

(deftest p54-tree?
  (is (t/tree? '(a (b nil nil) nil)))
  (is (not (t/tree? '(a (b nil nil)))))
  (is (t/tree? nil))
  (is (not (t/tree? [1 [2 nil nil] [3 nil nil] [4 nil nil]])))
  (is (not (t/tree? [1 [2 [3 [4 false nil] nil] nil] nil])))
  (is (t/tree? sample)))

(deftest p55-cbal-tree
  (is (= [1 1 2 1 4 4 4 1 8 16 32] (map #(count (t/cbal-tree %)) (range 0 11))))
  (is (= ['x nil nil] (first (t/cbal-tree 1))))
  (is (= #{['x ['x nil nil] ['x nil ['x nil nil]]]
           ['x ['x nil nil] ['x ['x nil nil] nil]]
           ['x ['x nil ['x nil nil]] ['x nil nil]]
           ['x ['x ['x nil nil] nil] ['x nil nil]]}
         (set (t/cbal-tree 4))))
  (doseq [n (range 0 10)
          tr (t/cbal-tree n)]
    (is (and (= n (t/size tr)) (t/cbal? tr)))))

(deftest p56-symmetric
  (is (t/symmetric? '[x [x nil nil] [x nil nil]]))
  (is (not (t/symmetric? '[x [x nil nil] nil])))
  (is (t/symmetric? nil))
  (is (not (t/symmetric? sample)))
  (is (t/symmetric? '[a [b nil [c nil nil]] [b [c nil nil] nil]]))
  (is (not (t/symmetric? '[a [b nil [c nil nil]] [b nil [c nil nil]]]))))

(deftest p57-construct
  (is (= [3 [2 [1 nil nil] nil] [5 nil [7 nil nil]]] (t/construct [3 2 5 7 1])))
  (is (= nil (t/construct [])))
  (is (= [1 nil [2 nil [3 nil nil]]] (t/construct [1 2 3])))
  (is (= [2 nil nil] (t/construct [2 2 2])))
  (is (t/symmetric? (t/construct [5 3 18 1 4 12 21])))
  (is (t/symmetric? (t/construct [3 2 5 7 1])))
  (is (not (t/symmetric? (t/construct [3 2 5 7 4]))))
  (is (= (range 1 8) (t/inorder (t/construct [4 2 6 1 3 5 7])))))

(deftest p58-sym-cbal-trees
  (is (= [1 1 0 1 0 2 0 1 0 4 0 4 0 4 0 1] (map #(count (t/sym-cbal-trees %)) (range 0 16))))
  (is (= #{['x ['x nil ['x nil nil]] ['x ['x nil nil] nil]]
           ['x ['x ['x nil nil] nil] ['x nil ['x nil nil]]]}
         (set (t/sym-cbal-trees 5))))
  (is (= 256 (count (t/sym-cbal-trees 57))))
  (is (every? #(and (t/symmetric? %) (t/cbal? %) (= 21 (t/size %))) (t/sym-cbal-trees 21))))

(deftest p59-hbal-tree
  (is (= [1 1 3 15 315] (map #(count (t/hbal-tree %)) (range 0 5))))
  (is (= [['x nil nil]] (t/hbal-tree 1)))
  (is (every? #(= 3 (t/height %)) (t/hbal-tree 3)))
  (is (every? (fn hb [tr] (or (nil? tr)
                              (and (<= (Math/abs (- (t/height (second tr)) (t/height (nth tr 2)))) 1)
                                   (hb (second tr)) (hb (nth tr 2)))))
              (t/hbal-tree 4))))

(deftest p60-hbal-tree-nodes
  (is (= [0 1 2 4 7 12 20] (map t/min-nodes (range 0 7))))
  (is (= 4 (t/min-height 15)))
  (is (= 5 (t/max-height 15)))
  (is (= [1 1 2 1 4 6 4 17 32 44 60] (map #(count (t/hbal-tree-nodes %)) (range 0 11))))
  (is (every? #(= 9 (t/size %)) (t/hbal-tree-nodes 9)))
  (is (= 1553 (count (t/hbal-tree-nodes 15)))))

(deftest p61-leaves
  (is (= '[d e g] (t/leaves sample)))
  (is (= 3 (t/count-leaves sample)))
  (is (= 0 (t/count-leaves nil)))
  (is (= ['x] (t/leaves ['x nil nil])))
  (is (= 1 (t/count-leaves ['x ['x nil nil] nil]))))

(deftest p62-internals
  (is (= '[a b c f] (t/internals sample)))
  (is (= [] (t/internals ['x nil nil])))
  (is (= [] (t/internals nil)))
  (is (= (t/size sample) (+ (t/count-leaves sample) (count (t/internals sample))))))

(deftest p62b-levels
  (is (= '[a] (t/at-level sample 1)))
  (is (= '[b c] (t/at-level sample 2)))
  (is (= '[d e f] (t/at-level sample 3)))
  (is (= '[g] (t/at-level sample 4)))
  (is (= [] (t/at-level sample 5)))
  (is (= '[a b c d e f g] (t/level-order sample)))
  (is (= [] (t/level-order nil)))
  (is (= '[a b c d e f g] (mapcat #(t/at-level sample %) (range 1 (inc (t/height sample)))))))

(deftest p63-complete-binary-tree
  (is (= ['x ['x nil nil] nil] (t/complete-binary-tree 2)))
  (is (= nil (t/complete-binary-tree 0)))
  (is (= ['x ['x ['x nil nil] ['x nil nil]] ['x ['x nil nil] nil]] (t/complete-binary-tree 6)))
  (is (every? #(= % (t/size (t/complete-binary-tree %))) (range 0 20)))
  (is (every? #(t/complete? (t/complete-binary-tree %)) (range 1 20)))
  (is (not (t/complete? sample))))

(deftest p64-layout-inorder
  (is (= [['b 2 1] [['a 1 2] nil nil] [['c 3 2] nil nil]]
         (t/layout1 ['b ['a nil nil] ['c nil nil]])))
  (is (nil? (t/layout1 nil)))
  (let [ps (positions (t/layout1 lsample))]
    (is (= 12 (count ps)))
    (is (= (range 1 13) (sort (map second ps))))
    (is (= (t/inorder lsample) (map first (sort-by second ps))))
    (is (= (t/preorder lsample) (map first ps)))
    (is (= [1 2 3 4 4 5 6 3 2 3 4 5] (map #(nth % 2) ps)))))

(def ^:private complete7 (t/complete-binary-tree 7))

(defn- xs-by-level
  "Map of level -> the xs at that level, left to right."
  [t]
  (let [ps (positions t)]
    (into (sorted-map)
          (map (fn [[y grp]] [y (sort (map second grp))]) (group-by #(nth % 2) ps)))))

(deftest p65-layout-constant-distance
  (is (= [['x 4 1] [['x 2 2] [['x 1 3] nil nil] [['x 3 3] nil nil]]
          [['x 6 2] [['x 5 3] nil nil] [['x 7 3] nil nil]]]
         (t/layout2 complete7)))
  (is (nil? (t/layout2 nil)))
  (let [ps (positions (t/layout2 sample))]
    (is (= [['a 7 1] ['b 3 2] ['d 1 3] ['e 5 3] ['c 11 2] ['f 13 3] ['g 12 4]] ps))
    (is (= 1 (reduce min (map second ps))))
    (is (= (count ps) (count (set (map rest ps)))))))

(deftest p66-layout-compact
  (is (= (t/layout2 complete7) (t/layout3 complete7)))
  (is (nil? (t/layout3 nil)))
  (is (= [['a 1 1] nil nil] (t/layout3 ['a nil nil])))
  (is (= [['a 2 1] [['b 1 2] nil nil] nil] (t/layout3 ['a ['b nil nil] nil])))
  (is (= [['a 1 1] nil [['b 2 2] nil nil]] (t/layout3 ['a nil ['b nil nil]])))
  (let [ps (positions (t/layout3 sample))]
    (is (= [['a 3 1] ['b 2 2] ['d 1 3] ['e 3 3] ['c 4 2] ['f 5 3] ['g 4 4]] ps)))
  (let [lt (t/layout3 lsample)
        ps (positions lt)]
    (is (= 1 (reduce min (map second ps))))
    (is (= (count ps) (count (set (map rest ps)))))
    (is (= (t/preorder lsample) (map first ps)))
    ;; at every level, nodes keep their left-to-right order and never share a position
    (is (every? (fn [[_ xs]] (apply < xs)) (xs-by-level lt)))
    ;; a parent is centred over two children, and one apart from a lone child
    (is ((fn ok? [n]
           (or (nil? n)
               (let [[[_ x _] l r] n
                     lx (some-> l first second)
                     rx (some-> r first second)]
                 (and (cond (and lx rx) (= (* 2 x) (+ lx rx))
                            lx (= 1 (- x lx))
                            rx (= 1 (- rx x))
                            :else true)
                      (ok? l) (ok? r)))))
         lt))
    ;; and it is no wider than the constant-distance layout
    (let [width (fn [t] (let [xs (map second (positions t))] (- (reduce max xs) (reduce min xs))))]
      (is (< (width lt) (width (t/layout2 lsample)))))))

(deftest p67-tree-string
  (is (= "a(b(d,e),c(,f(g,)))" (t/tree->string sample)))
  (is (= [\a [\b [\d nil nil] [\e nil nil]] [\c nil [\f [\g nil nil] nil]]]
         (t/string->tree "a(b(d,e),c(,f(g,)))")))
  (is (= sample (symbolize (t/string->tree "a(b(d,e),c(,f(g,)))"))))
  (is (= "" (t/tree->string nil)))
  (is (= "x" (t/tree->string [\x nil nil])))
  (is (= nil (t/string->tree "")))
  (is (= [\x nil nil] (t/string->tree "x")))
  (is (= [\a nil [\b nil nil]] (t/string->tree "a(,b)")))
  (doseq [s ["a" "a(b,c)" "a(,b(c,))" "a(b(d,e),c(,f(g,)))" "n(k(c(a,h(g(e,),)),m),u(p(,s(q,)),))"]]
    (is (= s (t/tree->string (t/string->tree s))))))

(deftest p68-preorder-inorder
  (is (= '[a b d e c f g] (t/preorder sample)))
  (is (= '[d b e a c g f] (t/inorder sample)))
  (is (= [] (t/preorder nil)))
  (is (= sample (t/pre-in-tree (t/preorder sample) (t/inorder sample))))
  (is (= lsample (t/pre-in-tree (t/preorder lsample) (t/inorder lsample))))
  (is (nil? (t/pre-in-tree [] [])))
  (let [bt (t/construct [5 3 8 1 4 7 9 2])]
    (is (= bt (t/pre-in-tree (t/preorder bt) (t/inorder bt))))))

(deftest p69-dot-string
  (is (= "abd..e..c.fg..." (t/tree->ds sample)))
  (is (= "." (t/tree->ds nil)))
  (is (= "x.." (t/tree->ds [\x nil nil])))
  (is (= sample (symbolize (t/ds->tree "abd..e..c.fg..."))))
  (is (nil? (t/ds->tree ".")))
  (is (= lsample (symbolize (t/ds->tree (t/tree->ds lsample)))))
  (is (= (inc (t/size sample)) (count (filter #{\.} (t/tree->ds sample)))))
  (is (= (inc (* 2 (t/size sample))) (count (t/tree->ds sample)))))
