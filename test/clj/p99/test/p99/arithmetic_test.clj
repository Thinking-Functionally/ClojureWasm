(ns p99.arithmetic-test
  (:require [clojure.test :refer [deftest is testing]]
            [p99.arithmetic :as a]))

(deftest p31-prime?
  (is (a/prime? 7))
  (is (not (a/prime? 1)))
  (is (not (a/prime? 0)))
  (is (a/prime? 2))
  (is (not (a/prime? 9)))
  (is (a/prime? 7919))
  (is (not (a/prime? 7917)))
  (is (= [2 3 5 7 11 13 17 19 23 29] (filter a/prime? (range 30)))))

(deftest p32-my-gcd
  (is (= 9 (a/my-gcd 36 63)))
  (is (= 1 (a/my-gcd 35 64)))
  (is (= 5 (a/my-gcd 0 5)))
  (is (= 12 (a/my-gcd 12 12)))
  (is (= 6 (a/my-gcd -12 18))))

(deftest p33-coprime?
  (is (a/coprime? 35 64))
  (is (not (a/coprime? 36 63)))
  (is (a/coprime? 1 99)))

(deftest p34-totient-phi
  (is (= 4 (a/totient-phi 10)))
  (is (= 1 (a/totient-phi 1)))
  (is (= 6 (a/totient-phi 7)))
  (is (= [1 1 2 2 4 2 6 4 6 4] (map a/totient-phi (range 1 11)))))

(deftest p35-prime-factors
  (is (= [3 3 5 7] (a/prime-factors 315)))
  (is (= [2 2 2] (a/prime-factors 8)))
  (is (= [97] (a/prime-factors 97)))
  (is (= [] (a/prime-factors 1)))
  (is (= [2 3 5 7 11 13] (a/prime-factors 30030)))
  (is (= 600851475143 (reduce * (a/prime-factors 600851475143)))))

(deftest p36-prime-factors-mult
  (is (= [[3 2] [5 1] [7 1]] (a/prime-factors-mult 315)))
  (is (= [[2 3]] (a/prime-factors-mult 8)))
  (is (= [] (a/prime-factors-mult 1))))

(deftest p37-phi-improved
  (is (= 4 (a/phi-improved 10)))
  (is (= 1 (a/phi-improved 1)))
  (is (= 4032 (a/phi-improved 10090)))
  (is (= (map a/totient-phi (range 1 200)) (map a/phi-improved (range 1 200)))))

(deftest p38-compare-phi
  (is (= {:n 10090 :phi 4032 :phi-improved 4032 :equal true} (a/compare-phi 10090)))
  (is (every? :equal (map a/compare-phi (range 1 300)))))

(deftest p39-list-primes
  (is (= [7 11 13 17 19 23 29 31] (a/list-primes 7 31)))
  (is (= [] (a/list-primes 24 28)))
  (is (= 25 (count (a/list-primes 1 100)))))

(deftest p40-goldbach
  (is (= [5 23] (a/goldbach 28)))
  (is (= [3 7] (a/goldbach 10)))
  (is (= [2 2] (a/goldbach 4)))
  (testing "every even number up to 1000 is a sum of two primes"
    (is (every? (fn [n] (let [[p q] (a/goldbach n)]
                          (and (a/prime? p) (a/prime? q) (= n (+ p q)))))
                (range 4 1001 2)))))

(deftest p41-goldbach-list
  (is (= [[10 [3 7]] [12 [5 7]] [14 [3 11]] [16 [3 13]] [18 [5 13]] [20 [3 17]]]
         (a/goldbach-list 9 20)))
  (is (= [[992 [73 919]] [1382 [61 1321]] [1856 [67 1789]] [1928 [61 1867]]]
         (a/goldbach-list 1 2000 50))))
