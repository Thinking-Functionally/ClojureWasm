(ns p99.multitrees
  "L-99 P70-P73: multiway trees. A tree is [label child ...]; a leaf is [label].
  Plain portable Clojure (also runs on JVM Clojure, the oracle for the tests)."
  (:require [clojure.string :as str]))

(defn label [t] (first t))
(defn children [t] (rest t))

;; ---- P70C: node count

(defn node-count [t]
  (inc (reduce + (map node-count (children t)))))

;; ---- P70: node string, e.g. afg^^c^bd^e^^^

(defn tree->string [t]
  (str (label t) (apply str (map tree->string (children t))) "^"))

(defn string->tree
  "Parse the P70 notation; labels are single characters."
  [s]
  (let [parse (fn parse [i]
                ;; returns [tree index-after-its-closing-^]
                (loop [j (inc i) kids []]
                  (if (= \^ (nth s j))
                    [(into [(nth s i)] kids) (inc j)]
                    (let [[k j2] (parse j)] (recur j2 (conj kids k))))))]
    (first (parse 0))))

;; ---- P71: internal path length (sum of the depths of all nodes)

(defn ipl
  ([t] (ipl t 0))
  ([t depth] (+ depth (reduce + (map #(ipl % (inc depth)) (children t))))))

;; ---- P72: nodes bottom-up (children before their parent)

(defn bottom-up [t]
  (concat (mapcat bottom-up (children t)) [(label t)]))

;; ---- P73: lisp notation, e.g. (a (f g) c (b d e))

(defn tree->lisp [t]
  (if (empty? (children t))
    (str (label t))
    (str "(" (label t) " " (str/join " " (map tree->lisp (children t))) ")")))

(defn lisp->tree
  "Parse the P73 notation; labels are single characters."
  [s]
  (let [toks (vec (re-seq #"[()]|[^\s()]+" s))
        parse (fn parse [i]
                (if (= "(" (nth toks i))
                  (loop [j (+ i 2) kids []]
                    (if (= ")" (nth toks j))
                      [(into [(first (nth toks (inc i)))] kids) (inc j)]
                      (let [[k j2] (parse j)] (recur j2 (conj kids k)))))
                  [[(first (nth toks i))] (inc i)]))]
    (first (parse 0))))
