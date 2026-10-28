(ns p99.arithmetic
  "L-99 problems P31-P41 (arithmetic). Plain portable Clojure; see p99.lists.")

(defn prime?
  "P31: true if N is a prime number."
  [n]
  (and (> n 1)
       (loop [d 2]
         (cond (> (* d d) n) true
               (zero? (mod n d)) false
               :else (recur (inc d))))))

(defn my-gcd
  "P32: greatest common divisor (Euclid's algorithm)."
  [a b]
  (if (zero? b) (Math/abs (long a)) (recur b (mod a b))))

(defn coprime?
  "P33: true if A and B share no divisor other than 1."
  [a b]
  (= 1 (my-gcd a b)))

(defn totient-phi
  "P34: Euler's totient: how many r in 1..N-1 are coprime to N (phi(1) = 1)."
  [n]
  (if (= n 1)
    1
    (count (filter (fn [r] (coprime? r n)) (range 1 n)))))

(defn prime-factors
  "P35: the prime factors of N in ascending order, with repetition."
  [n]
  (loop [n n d 2 acc []]
    (cond (< n 2) acc
          (> (* d d) n) (conj acc n)
          (zero? (mod n d)) (recur (quot n d) d (conj acc d))
          :else (recur n (inc d) acc))))

(defn prime-factors-mult
  "P36: the prime factors with multiplicity, as [prime count] pairs."
  [n]
  (mapv (fn [[p c]] [p c]) (sort-by key (frequencies (prime-factors n)))))

(defn phi-improved
  "P37: Euler's totient from the prime factorisation:
  the product of (p - 1) * p^(m - 1) over the factors [p m]."
  [n]
  (reduce (fn [acc [p m]]
            (* acc (dec p) (reduce * (repeat (dec m) p))))
          1
          (prime-factors-mult n)))

(defn compare-phi
  "P38: both totient methods for N and whether they agree."
  [n]
  (let [a (totient-phi n) b (phi-improved n)]
    {:n n :phi a :phi-improved b :equal (= a b)}))

(defn list-primes
  "P39: all primes in the inclusive range A..B."
  [a b]
  (filter prime? (range a (inc b))))

(defn goldbach
  "P40: two primes [p q] with p <= q that add up to the even number N,
  choosing the smallest p."
  [n]
  (first (for [p (range 2 (inc (quot n 2)))
               :when (and (prime? p) (prime? (- n p)))]
           [p (- n p)])))

(defn goldbach-list
  "P41: the Goldbach composition [n [p q]] of every even number in A..B.
  With a threshold, keep only the cases where both primes exceed it."
  ([a b] (goldbach-list a b 0))
  ([a b threshold]
   (for [n (range (max a 4) (inc b))
         :when (even? n)
         :let [[p q :as g] (goldbach n)]
         :when (and g (> p threshold))]
     [n g])))
