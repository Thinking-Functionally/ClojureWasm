;; P-99: Ninety-Nine Clojure Problems
;; Test suite for differential backend validation
;; Each problem tests specific language features across TreeWalk/VM/Wasm backends

;; P01: Find last element of a list
(def p01-input [1 2 3 4])
(def p01-expected 4)
(defn p01-solution [xs] (last xs))

;; P02: Find last but one element
(def p02-input [1 2 3 4])
(def p02-expected 3)
(defn p02-solution [xs] (nth xs (- (count xs) 2)))

;; P03: Find Kth element (0-indexed)
(def p03-input [[1 2 3 4 5] 2])
(def p03-expected 3)
(defn p03-solution [xs k] (nth xs k))

;; P04: Count elements
(def p04-input [1 2 3 4 5])
(def p04-expected 5)
(defn p04-solution [xs] (count xs))

;; P05: Reverse a list
(def p05-input [1 2 3 4])
(def p05-expected [4 3 2 1])
(defn p05-solution [xs] (reverse xs))

;; P06: Palindrome check
(def p06-input [1 2 3 2 1])
(def p06-expected true)
(defn p06-solution [xs] (= xs (reverse xs)))

;; P07: Flatten nested list
(def p07-input [1 [2 [3 4] 5]])
(def p07-expected [1 2 3 4 5])
(defn p07-solution [xs] (flatten xs))

;; P08: Eliminate consecutive duplicates
(def p08-input [1 1 2 2 3 1 1])
(def p08-expected [1 2 3 1])
(defn p08-solution [xs]
  (if (empty? xs)
    []
    (reduce (fn [acc x]
              (if (= (last acc) x)
                acc
                (conj acc x)))
            [(first xs)]
            (rest xs))))

;; P09: Pack consecutive duplicates
(def p09-input [1 1 2 2 3 1 1])
(def p09-expected [[1 1] [2 2] [3] [1 1]])
(defn p09-solution [xs]
  (if (empty? xs)
    []
    (loop [result []
           current [(first xs)]
           remaining (rest xs)]
      (if (empty? remaining)
        (conj result current)
        (let [x (first remaining)]
          (if (= (first current) x)
            (recur result (conj current x) (rest remaining))
            (recur (conj result current) [x] (rest remaining))))))))

;; P10: Run-length encoding
(def p10-input [1 1 2 2 3 1 1])
(def p10-expected [[2 1] [2 2] [1 3] [2 1]])
(defn p10-solution [xs]
  (map (fn [group] [(count group) (first group)])
       (p09-solution xs)))

;; P11: Simple arithmetic
(def p11-input [10 5])
(def p11-expected 15)
(defn p11-solution [a b] (+ a b))

;; P12: Subtraction
(def p12-input [10 5])
(def p12-expected 5)
(defn p12-solution [a b] (- a b))

;; P13: Multiplication
(def p13-input [10 5])
(def p13-expected 50)
(defn p13-solution [a b] (* a b))

;; P14: Division
(def p14-input [10 5])
(def p14-expected 2)
(defn p14-solution [a b] (/ a b))

;; P15: Comparison operators
(def p15-input [5 10])
(def p15-expected true)
(defn p15-solution [a b] (< a b))

;; P16: Greater than
(def p16-input [10 5])
(def p16-expected true)
(defn p16-solution [a b] (> a b))

;; P17: Equality
(def p17-input [5 5])
(def p17-expected true)
(defn p17-solution [a b] (= a b))

;; P18: Map function
(def p18-input [1 2 3 4])
(def p18-expected [2 4 6 8])
(defn p18-solution [xs] (map (fn [x] (* x 2)) xs))

;; P19: Filter function
(def p19-input [1 2 3 4 5 6])
(def p19-expected [2 4 6])
(defn p19-solution [xs] (filter even? xs))

;; P20: Reduce/fold
(def p20-input [1 2 3 4 5])
(def p20-expected 15)
(defn p20-solution [xs] (reduce + 0 xs))
