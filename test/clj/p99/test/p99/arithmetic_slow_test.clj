(ns p99.arithmetic-slow-test
  "The heavy arithmetic cases, kept out of the default gate (suite marked slow)."
  (:require [clojure.test :refer [deftest is]]
            [p99.arithmetic :as a]))

(deftest p37-p38-large-totients
  (is (= 4032 (a/phi-improved 10090)))
  (is (= {:n 10090 :phi 4032 :phi-improved 4032 :equal true} (a/compare-phi 10090)))
  (is (= (map a/totient-phi (range 1 200)) (map a/phi-improved (range 1 200))))
  (is (every? :equal (map a/compare-phi (range 1 300)))))

(deftest p40-p41-goldbach-large
  (is (every? (fn [n] (let [[p q] (a/goldbach n)]
                        (and (a/prime? p) (a/prime? q) (= n (+ p q)))))
              (range 4 1001 2)))
  (is (= [[992 [73 919]] [1382 [61 1321]] [1856 [67 1789]] [1928 [61 1867]]]
         (a/goldbach-list 1 2000 50))))
