(ns p99.lists-test
  (:require [clojure.test :refer [deftest is testing]]
            [p99.lists :as l]))

(deftest p01-my-last
  (is (= 'd (l/my-last '(a b c d))))
  (is (= 1 (l/my-last [1])))
  (is (nil? (l/my-last '())))
  (is (= :z (l/my-last (list :x :y :z)))))

(deftest p02-my-but-last
  (is (= '(c d) (l/my-but-last '(a b c d))))
  (is (= '(a b) (l/my-but-last '(a b))))
  (is (nil? (l/my-but-last '(a))))
  (is (nil? (l/my-but-last '()))))

(deftest p03-element-at
  (is (= 'c (l/element-at '(a b c d e) 3)))
  (is (= 'a (l/element-at '(a b c d e) 1)))
  (is (= 'e (l/element-at '(a b c d e) 5)))
  (is (nil? (l/element-at '(a b c d e) 6)))
  (is (nil? (l/element-at '(a b c d e) 0))))

(deftest p04-my-length
  (is (= 3 (l/my-length '(a b c))))
  (is (= 0 (l/my-length '())))
  (is (= 1000 (l/my-length (range 1000)))))

(deftest p05-my-reverse
  (is (= '(c b a) (l/my-reverse '(a b c))))
  (is (= '() (l/my-reverse '())))
  (is (= '(1) (l/my-reverse [1])))
  (is (= (reverse (range 100)) (l/my-reverse (range 100)))))

(deftest p06-palindrome?
  (is (l/palindrome? '(x a m a x)))
  (is (not (l/palindrome? '(a b c))))
  (is (l/palindrome? '()))
  (is (l/palindrome? [1]))
  (is (l/palindrome? [1 2 2 1])))

(deftest p07-my-flatten
  (is (= '(a b c d e) (l/my-flatten '(a (b (c d) e)))))
  (is (= '() (l/my-flatten '())))
  (is (= '(1 2 3) (l/my-flatten [[1] [[2]] 3])))
  (is (= '(a) (l/my-flatten '(((a)))))))

(deftest p08-compress
  (is (= '(a b c a d e) (l/compress '(a a a a b c c a a d e e e e))))
  (is (= '() (l/compress '())))
  (is (= '(a) (l/compress '(a a a))))
  (is (= '(a b) (l/compress '(a b)))))

(deftest p09-pack
  (is (= '((a a a a) (b) (c c) (a a) (d) (e e e e))
         (l/pack '(a a a a b c c a a d e e e e))))
  (is (= '() (l/pack '())))
  (is (= '((a)) (l/pack '(a)))))

(deftest p10-encode
  (is (= '((4 a) (1 b) (2 c) (2 a) (1 d) (4 e))
         (l/encode '(a a a a b c c a a d e e e e))))
  (is (= '() (l/encode '()))))

(deftest p11-encode-modified
  (is (= '((4 a) b (2 c) (2 a) d (4 e))
         (l/encode-modified '(a a a a b c c a a d e e e e))))
  (is (= '(a) (l/encode-modified '(a)))))

(deftest p12-decode
  (is (= '(a a a a b c c a a d e e e e)
         (l/decode '((4 a) b (2 c) (2 a) d (4 e)))))
  (is (= '() (l/decode '())))
  (testing "decode is the inverse of encode-modified"
    (let [xs '(x x y z z z w)]
      (is (= xs (l/decode (l/encode-modified xs)))))))

(deftest p13-encode-direct
  (is (= '((4 a) b (2 c) (2 a) d (4 e))
         (l/encode-direct '(a a a a b c c a a d e e e e))))
  (is (= '() (l/encode-direct '())))
  (testing "agrees with the two-step encoding"
    (let [xs '(1 1 2 3 3 3 1)]
      (is (= (l/encode-modified xs) (l/encode-direct xs))))))

(deftest p14-dupli
  (is (= '(a a b b c c c c d d) (l/dupli '(a b c c d))))
  (is (= '() (l/dupli '()))))

(deftest p15-repli
  (is (= '(a a a b b b c c c) (l/repli '(a b c) 3)))
  (is (= '() (l/repli '(a b c) 0)))
  (is (= '(a b) (l/repli '(a b) 1))))

(deftest p16-drop-every
  (is (= '(a b d e g h k) (l/drop-every '(a b c d e f g h i k) 3)))
  (is (= '(a) (l/drop-every '(a b) 2)))
  (is (= '() (l/drop-every '(a b c) 1)))
  (testing "nil and false elements are kept"
    (is (= '(nil false) (l/drop-every '(nil false 1) 3)))))

(deftest p17-split
  (is (= '[(a b c) (d e f g h i k)] (l/split '(a b c d e f g h i k) 3)))
  (is (= '[() (a b)] (l/split '(a b) 0)))
  (is (= '[(a b) ()] (l/split '(a b) 5)))
  (is (= '[() ()] (l/split '() 2))))

(deftest p18-slice
  (is (= '(c d e f g) (l/slice '(a b c d e f g h i k) 3 7)))
  (is (= '(a) (l/slice '(a b c) 1 1)))
  (is (= '(a b c) (l/slice '(a b c) 1 3))))

(deftest p19-rotate
  (is (= '(d e f g h a b c) (l/rotate '(a b c d e f g h) 3)))
  (is (= '(g h a b c d e f) (l/rotate '(a b c d e f g h) -2)))
  (is (= '(a b c) (l/rotate '(a b c) 0)))
  (is (= '(a b c) (l/rotate '(a b c) 3)))
  (is (= '(b c a) (l/rotate '(a b c) 4)))
  (is (= '() (l/rotate '() 5))))

(deftest p20-remove-at
  (is (= '(a c d) (l/remove-at '(a b c d) 2)))
  (is (= '(b c d) (l/remove-at '(a b c d) 1)))
  (is (= '(a b c) (l/remove-at '(a b c d) 4))))

(deftest p21-insert-at
  (is (= '(a alfa b c d) (l/insert-at 'alfa '(a b c d) 2)))
  (is (= '(x a b) (l/insert-at 'x '(a b) 1)))
  (is (= '(a b x) (l/insert-at 'x '(a b) 3))))

(deftest p22-int-range
  (is (= '(4 5 6 7 8 9) (l/int-range 4 9)))
  (is (= '(9 8 7 6 5 4) (l/int-range 9 4)))
  (is (= '(3) (l/int-range 3 3))))

(deftest p23-rnd-select
  (let [xs '(a b c d e f g h)
        pick (l/rnd-select xs 3)]
    (is (= 3 (count pick)))
    (is (every? (set xs) pick))
    (is (= 3 (count (set pick)))))
  (is (= 8 (count (l/rnd-select '(a b c d e f g h) 8)))))

(deftest p24-lotto-select
  (let [draw (l/lotto-select 6 49)]
    (is (= 6 (count draw)))
    (is (= 6 (count (set draw))))
    (is (every? (fn [n] (<= 1 n 49)) draw))))

(deftest p25-rnd-permu
  (let [xs '(a b c d e f)
        perm (l/rnd-permu xs)]
    (is (= (sort xs) (sort perm)))
    (is (= 6 (count perm))))
  (is (= '() (l/rnd-permu '()))))

(deftest p26-combination
  (is (= 220 (count (l/combination 3 (range 12)))))
  (is (= '((a b) (a c) (a d) (b c) (b d) (c d)) (l/combination 2 '(a b c d))))
  (is (= '((a b c) (a b d) (a b e)) (take 3 (l/combination 3 '(a b c d e f)))))
  (is (= '(()) (l/combination 0 '(a b))))
  (is (= '() (l/combination 3 '(a b)))))

(deftest p27-group
  (testing "P27b: groups of given sizes"
    (is (= 6 (count (l/group '(a b c d) [2 2]))))
    (is (= '[((a b) (c d)) ((a c) (b d)) ((a d) (b c))
             ((b c) (a d)) ((b d) (a c)) ((c d) (a b))]
           (vec (l/group '(a b c d) [2 2]))))
    (is (= 1260 (count (l/group (range 9) [2 3 4])))))
  (testing "P27a: nine people into groups of 2, 3 and 4"
    (let [people '(aldo beat carla david evi flip gary hugo ida)
          gs (l/group3 people)]
      (is (= 1260 (count gs)))
      (is (= '((aldo beat) (carla david evi) (flip gary hugo ida)) (first gs)))
      (is (every? (fn [g] (= (set people) (set (apply concat g)))) (take 50 gs))))))

(deftest p28-lsort
  (is (= '((o) (d e) (d e) (m n) (a b c) (f g h) (i j k l))
         (l/lsort '((a b c) (d e) (f g h) (d e) (i j k l) (m n) (o)))))
  (is (= '() (l/lsort '()))))

(deftest p28-lfsort
  (is (= '((i j k l) (o) (a b c) (f g h) (d e) (d e) (m n))
         (l/lfsort '((a b c) (d e) (f g h) (d e) (i j k l) (m n) (o)))))
  (is (= '() (l/lfsort '()))))
