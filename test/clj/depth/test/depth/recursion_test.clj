(ns depth.recursion-test
  "Recursion depth contract (see project_status.md, \"Recursion depth\"): on every
  backend, non-tail recursion works to at least these depths, a runaway recursion
  raises a catchable StackOverflowError (never a crash or hang), and the thread
  keeps working afterwards. The depths are deliberately far below every backend's
  real limit, so the tests never depend on the exact limit: ClojureScript reaches
  ~9.7k and JVM Clojure ~214k direct, ~2.8k through map."
  (:require [clojure.test :refer [deftest is testing]]))

(def direct-depth 5000)
(def lazy-depth 1000)
(def thread-depth 1000)

(defn deep [n] (if (zero? n) 0 (inc (deep (dec n)))))

(defn runaway [n] (inc (runaway (inc n))))

(declare odd-deep)
(defn even-deep [n] (if (zero? n) 0 (inc (odd-deep (dec n)))))
(defn odd-deep [n] (if (zero? n) 0 (inc (even-deep (dec n)))))

(defn variadic-deep [n & more] (if (zero? n) (count more) (inc (apply variadic-deep (dec n) more))))

(defn via-map [n] (if (zero? n) 0 (inc (first (map via-map [(dec n)])))))

(defn via-reduce [n] (if (zero? n) 0 (inc (reduce (fn [_ x] (via-reduce x)) 0 [(dec n)]))))

(defn overflowed? [f]
  (try (f) false (catch StackOverflowError _ true)))

(deftest direct-recursion
  (is (= direct-depth (deep direct-depth)))
  (is (= 1 (deep 1)))
  (is (= 0 (deep 0))))

(deftest mutual-recursion
  (is (= 2000 (even-deep 2000)))
  (is (= 1999 (odd-deep 1999))))

(deftest variadic-recursion
  ;; JVM Clojure's own limit for apply-through-variadic recursion is only ~270.
  (is (= 200 (variadic-deep 200)))
  (is (= 203 (variadic-deep 200 :a :b :c))))

(deftest recursion-through-lazy-seqs-and-hofs
  (is (= lazy-depth (via-map lazy-depth)))
  (is (= lazy-depth (via-reduce lazy-depth))))

(deftest tail-position-does-not-grow-the-stack
  (is (= 200000 (loop [i 0] (if (< i 200000) (recur (inc i)) i))))
  (is (= 200000 ((fn [i] (if (< i 200000) (recur (inc i)) i)) 0))))

(deftest recursion-inside-a-future
  (is (= thread-depth @(future (deep thread-depth))))
  (is (= [thread-depth thread-depth] (mapv deref [(future (deep thread-depth)) (future (deep thread-depth))]))))

(deftest runaway-recursion-is-catchable
  (testing "on the main thread"
    (is (true? (overflowed? #(runaway 0)))))
  (testing "inside a future"
    (is (true? @(future (overflowed? #(runaway 0))))))
  (testing "twice in a row"
    (is (true? (overflowed? #(runaway 0))))
    (is (true? (overflowed? #(runaway 0))))))

(deftest recovers-after-an-overflow
  (is (true? (overflowed? #(runaway 0))))
  (is (= direct-depth (deep direct-depth)))
  (is (= lazy-depth (via-map lazy-depth)))
  (is (= thread-depth @(future (deep thread-depth)))))

(deftest overflow-is-an-ordinary-throwable
  (let [r (try (runaway 0) (catch Throwable t (if (instance? StackOverflowError t) :so :other)))]
    (is (= :so r)))
  (is (= :done (try (runaway 0) (catch StackOverflowError _ :done) (finally nil)))))
