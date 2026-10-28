(ns p99.multitrees-test
  (:require [clojure.test :refer [deftest is]]
            [p99.multitrees :as m]))

(def sample '[a [f [g]] [c] [b [d] [e]]])

(deftest p70c-node-count
  (is (= 7 (m/node-count sample)))
  (is (= 1 (m/node-count '[x])))
  (is (= 3 (m/node-count '[x [y [z]]]))))

(deftest p70-node-string
  (is (= "afg^^c^bd^e^^^" (m/tree->string sample)))
  (is (= "x^" (m/tree->string '[x])))
  (is (= (m/tree->string sample)
         (m/tree->string (m/string->tree "afg^^c^bd^e^^^"))))
  (is (= [\a [\f [\g]] [\c] [\b [\d] [\e]]] (m/string->tree "afg^^c^bd^e^^^")))
  (is (= [\x] (m/string->tree "x^")))
  (doseq [s ["a^" "ab^^" "abc^^d^^" "afg^^c^bd^e^^^"]]
    (is (= s (m/tree->string (m/string->tree s))))
    (is (= (count s) (* 2 (m/node-count (m/string->tree s)))))))

(deftest p71-ipl
  (is (= 9 (m/ipl sample)))
  (is (= 0 (m/ipl '[a])))
  (is (= 3 (m/ipl '[a [b] [c] [d]])))
  (is (= 6 (m/ipl '[a [b [c [d]]]]))))

(deftest p72-bottom-up
  (is (= '[g f c d e b a] (m/bottom-up sample)))
  (is (= '[a] (m/bottom-up '[a])))
  (is (= (m/node-count sample) (count (m/bottom-up sample)))))

(deftest p73-lisp-notation
  (is (= "(a (f g) c (b d e))" (m/tree->lisp sample)))
  (is (= "a" (m/tree->lisp '[a])))
  (is (= [\a [\f [\g]] [\c] [\b [\d] [\e]]] (m/lisp->tree "(a (f g) c (b d e))")))
  (is (= [\a] (m/lisp->tree "a")))
  (is (= [\a [\b]] (m/lisp->tree "(a b)")))
  (doseq [s ["a" "(a b)" "(a (b c) d)" "(a (f g) c (b d e))"]]
    (is (= s (m/tree->lisp (m/lisp->tree s))))))
