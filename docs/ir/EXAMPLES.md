# ClojureWasm IR Examples

**Version**: 0.1.0-draft  
**Last Updated**: 2026-10-15

This document provides comprehensive examples of ClojureWasm IR, showing how various Clojure constructs are represented in the IR.

## Table of Contents

1. [Basic Values](#basic-values)
2. [Arithmetic Operations](#arithmetic-operations)
3. [Conditionals](#conditionals)
4. [Local Bindings](#local-bindings)
5. [Functions](#functions)
6. [Closures](#closures)
7. [Recursion](#recursion)
8. [Data Structures](#data-structures)
9. [Higher-Order Functions](#higher-order-functions)
10. [Complex Examples](#complex-examples)

---

## Basic Values

### Constants

#### Clojure
```clojure
42
```

#### IR
```edn
{:id :fn/user-const-1
 :name "const-example"
 :namespace "user"
 :arity {:fixed 0}
 :params []
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:id :block/entry
   :instructions [{:op :const :result :val/1 :value 42}]
   :terminator {:op :return :value :val/1}}}}
```

### String

#### Clojure
```clojure
"hello"
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value "hello"}]
 :terminator {:op :return :value :val/1}}
```

### Boolean and Nil

#### Clojure
```clojure
true
false
nil
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value true}
                {:op :const :result :val/2 :value false}
                {:op :const :result :val/3 :value nil}]}
```

---

## Arithmetic Operations

### Simple Addition

#### Clojure
```clojure
(+ 1 2)
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value 1}
                {:op :const :result :val/2 :value 2}
                {:op :call
                 :result :val/3
                 :fn :builtin/add
                 :args [:val/1 :val/2]}]
 :terminator {:op :return :value :val/3}}
```

### Nested Operations

#### Clojure
```clojure
(* (+ 1 2) (- 4 3))
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value 1}
                {:op :const :result :val/2 :value 2}
                {:op :call :result :val/3 :fn :builtin/add :args [:val/1 :val/2]}
                {:op :const :result :val/4 :value 4}
                {:op :const :result :val/5 :value 3}
                {:op :call :result :val/6 :fn :builtin/sub :args [:val/4 :val/5]}
                {:op :call :result :val/7 :fn :builtin/mul :args [:val/3 :val/6]}]
 :terminator {:op :return :value :val/7}}
```

---

## Conditionals

### Simple If

#### Clojure
```clojure
(if true 1 2)
```

#### IR
```edn
{:blocks [:block/entry :block/then :block/else :block/merge]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :const :result :val/1 :value true}]
   :terminator {:op :branch
                :condition :val/1
                :true-target :block/then
                :false-target :block/else}}
  
  :block/then
  {:instructions [{:op :const :result :val/2 :value 1}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/else
  {:instructions [{:op :const :result :val/3 :value 2}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/merge
  {:instructions [{:op :phi
                   :result :val/4
                   :sources [{:block :block/then :value :val/2}
                            {:block :block/else :value :val/3}]}]
   :terminator {:op :return :value :val/4}}}}
```

### If with Comparison

#### Clojure
```clojure
(if (< x 10) "small" "large")
```

#### IR
```edn
{:blocks [:block/entry :block/then :block/else :block/merge]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/x}
                  {:op :const :result :val/2 :value 10}
                  {:op :prim-lt :result :val/3 :args [:val/1 :val/2]}]
   :terminator {:op :branch
                :condition :val/3
                :true-target :block/then
                :false-target :block/else}}
  
  :block/then
  {:instructions [{:op :const :result :val/4 :value "small"}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/else
  {:instructions [{:op :const :result :val/5 :value "large"}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/merge
  {:instructions [{:op :phi
                   :result :val/6
                   :sources [{:block :block/then :value :val/4}
                            {:block :block/else :value :val/5}]}]
   :terminator {:op :return :value :val/6}}}}
```

---

## Local Bindings

### Let

#### Clojure
```clojure
(let [x 10
      y 20]
  (+ x y))
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value 10}
                {:op :bind :name :local/x :value :val/1}
                {:op :const :result :val/2 :value 20}
                {:op :bind :name :local/y :value :val/2}
                {:op :var-ref :result :val/3 :var :local/x}
                {:op :var-ref :result :val/4 :var :local/y}
                {:op :call :result :val/5 :fn :builtin/add :args [:val/3 :val/4]}]
 :terminator {:op :return :value :val/5}}
```

### Nested Let

#### Clojure
```clojure
(let [x 10]
  (let [y (* x 2)]
    (+ x y)))
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value 10}
                {:op :bind :name :local/x :value :val/1}
                {:op :var-ref :result :val/2 :var :local/x}
                {:op :const :result :val/3 :value 2}
                {:op :call :result :val/4 :fn :builtin/mul :args [:val/2 :val/3]}
                {:op :bind :name :local/y :value :val/4}
                {:op :var-ref :result :val/5 :var :local/x}
                {:op :var-ref :result :val/6 :var :local/y}
                {:op :call :result :val/7 :fn :builtin/add :args [:val/5 :val/6]}]
 :terminator {:op :return :value :val/7}}
```

---

## Functions

### Simple Function

#### Clojure
```clojure
(defn add [x y]
  (+ x y))
```

#### IR
```edn
{:id :fn/user-add-1
 :name "add"
 :namespace "user"
 :arity {:fixed 2}
 :params [:param/x :param/y]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/x}
                  {:op :var-ref :result :val/2 :var :param/y}
                  {:op :call :result :val/3 :fn :builtin/add :args [:val/1 :val/2]}]
   :terminator {:op :return :value :val/3}}}}
```

### Function with Conditional

#### Clojure
```clojure
(defn max [a b]
  (if (> a b) a b))
```

#### IR
```edn
{:id :fn/user-max-2
 :name "max"
 :namespace "user"
 :arity {:fixed 2}
 :params [:param/a :param/b]
 :blocks [:block/entry :block/then :block/else :block/merge]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/a}
                  {:op :var-ref :result :val/2 :var :param/b}
                  {:op :prim-gt :result :val/3 :args [:val/1 :val/2]}]
   :terminator {:op :branch
                :condition :val/3
                :true-target :block/then
                :false-target :block/else}}
  
  :block/then
  {:instructions [{:op :var-ref :result :val/4 :var :param/a}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/else
  {:instructions [{:op :var-ref :result :val/5 :var :param/b}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/merge
  {:instructions [{:op :phi
                   :result :val/6
                   :sources [{:block :block/then :value :val/4}
                            {:block :block/else :value :val/5}]}]
   :terminator {:op :return :value :val/6}}}}
```

### Multi-Arity Function

#### Clojure
```clojure
(defn greet
  ([] (greet "World"))
  ([name] (str "Hello, " name "!")))
```

#### IR
```edn
{:id :fn/user-greet-3
 :name "greet"
 :namespace "user"
 :arities [{:arity {:fixed 0}
            :fn :fn/user-greet-arity0-3a}
           {:arity {:fixed 1}
            :fn :fn/user-greet-arity1-3b}]}

;; 0-arity
{:id :fn/user-greet-arity0-3a
 :name "greet$arity0"
 :namespace "user"
 :arity {:fixed 0}
 :params []
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :const :result :val/1 :value "World"}
                  {:op :call :result :val/2 :fn :fn/user-greet-arity1-3b :args [:val/1]}]
   :terminator {:op :return :value :val/2}}}}

;; 1-arity
{:id :fn/user-greet-arity1-3b
 :name "greet$arity1"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/name]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :const :result :val/1 :value "Hello, "}
                  {:op :var-ref :result :val/2 :var :param/name}
                  {:op :const :result :val/3 :value "!"}
                  {:op :call :result :val/4 :fn :builtin/str :args [:val/1 :val/2 :val/3]}]
   :terminator {:op :return :value :val/4}}}}
```

---

## Closures

### Simple Closure

#### Clojure
```clojure
(defn make-adder [n]
  (fn [x]
    (+ x n)))
```

#### IR
```edn
;; Outer function
{:id :fn/user-make-adder-4
 :name "make-adder"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/n]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/n}
                  {:op :make-closure
                   :result :val/2
                   :fn :fn/user-make-adder-inner-5
                   :captures [:val/1]}]
   :terminator {:op :return :value :val/2}}}}

;; Inner function (closure)
{:id :fn/user-make-adder-inner-5
 :name "make-adder$inner"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/x]
 :captures [:capture/n]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/x}
                  {:op :capture-ref :result :val/2 :capture :capture/n}
                  {:op :call :result :val/3 :fn :builtin/add :args [:val/1 :val/2]}]
   :terminator {:op :return :value :val/3}}}}
```

### Multiple Captures

#### Clojure
```clojure
(defn make-multiplier [a b]
  (fn [x]
    (* x (+ a b))))
```

#### IR
```edn
;; Outer function
{:id :fn/user-make-multiplier-6
 :name "make-multiplier"
 :namespace "user"
 :arity {:fixed 2}
 :params [:param/a :param/b]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/a}
                  {:op :var-ref :result :val/2 :var :param/b}
                  {:op :make-closure
                   :result :val/3
                   :fn :fn/user-make-multiplier-inner-7
                   :captures [:val/1 :val/2]}]
   :terminator {:op :return :value :val/3}}}}

;; Inner function
{:id :fn/user-make-multiplier-inner-7
 :name "make-multiplier$inner"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/x]
 :captures [:capture/a :capture/b]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/x}
                  {:op :capture-ref :result :val/2 :capture :capture/a}
                  {:op :capture-ref :result :val/3 :capture :capture/b}
                  {:op :call :result :val/4 :fn :builtin/add :args [:val/2 :val/3]}
                  {:op :call :result :val/5 :fn :builtin/mul :args [:val/1 :val/4]}]
   :terminator {:op :return :value :val/5}}}}
```

---

## Recursion

### Simple Recursion

#### Clojure
```clojure
(defn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (dec n)))))
```

#### IR
```edn
{:id :fn/user-factorial-8
 :name "factorial"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/n]
 :blocks [:block/entry :block/base :block/recursive :block/merge]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/n}
                  {:op :const :result :val/2 :value 1}
                  {:op :prim-lte :result :val/3 :args [:val/1 :val/2]}]
   :terminator {:op :branch
                :condition :val/3
                :true-target :block/base
                :false-target :block/recursive}}
  
  :block/base
  {:instructions [{:op :const :result :val/4 :value 1}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/recursive
  {:instructions [{:op :var-ref :result :val/5 :var :param/n}
                  {:op :var-ref :result :val/6 :var :param/n}
                  {:op :call :result :val/7 :fn :builtin/dec :args [:val/6]}
                  {:op :call :result :val/8 :fn :fn/user-factorial-8 :args [:val/7]}
                  {:op :call :result :val/9 :fn :builtin/mul :args [:val/5 :val/8]}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/merge
  {:instructions [{:op :phi
                   :result :val/10
                   :sources [{:block :block/base :value :val/4}
                            {:block :block/recursive :value :val/9}]}]
   :terminator {:op :return :value :val/10}}}}
```

### Tail Recursion (loop/recur)

#### Clojure
```clojure
(defn sum [n acc]
  (if (<= n 0)
    acc
    (recur (dec n) (+ acc n))))
```

#### IR
```edn
{:id :fn/user-sum-9
 :name "sum"
 :namespace "user"
 :arity {:fixed 2}
 :params [:param/n :param/acc]
 :blocks [:block/entry :block/loop :block/base :block/recur-step]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/n}
                  {:op :var-ref :result :val/2 :var :param/acc}]
   :terminator {:op :jump :target :block/loop}}
  
  :block/loop
  {:instructions [{:op :phi :result :val/3 :sources [{:block :block/entry :value :val/1}
                                                      {:block :block/recur-step :value :val/8}]}
                  {:op :phi :result :val/4 :sources [{:block :block/entry :value :val/2}
                                                      {:block :block/recur-step :value :val/9}]}
                  {:op :const :result :val/5 :value 0}
                  {:op :prim-lte :result :val/6 :args [:val/3 :val/5]}]
   :terminator {:op :branch
                :condition :val/6
                :true-target :block/base
                :false-target :block/recur-step}}
  
  :block/base
  {:instructions []
   :terminator {:op :return :value :val/4}}
  
  :block/recur-step
  {:instructions [{:op :call :result :val/8 :fn :builtin/dec :args [:val/3]}
                  {:op :call :result :val/9 :fn :builtin/add :args [:val/4 :val/3]}]
   :terminator {:op :jump :target :block/loop}}}}
```

---

## Data Structures

### Vector

#### Clojure
```clojure
[1 2 3]
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value 1}
                {:op :const :result :val/2 :value 2}
                {:op :const :result :val/3 :value 3}
                {:op :make-vector :result :val/4 :elements [:val/1 :val/2 :val/3]}]
 :terminator {:op :return :value :val/4}}
```

### Map

#### Clojure
```clojure
{:name "Alice" :age 30}
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value :name}
                {:op :const :result :val/2 :value "Alice"}
                {:op :const :result :val/3 :value :age}
                {:op :const :result :val/4 :value 30}
                {:op :make-map :result :val/5
                 :entries [{:key :val/1 :value :val/2}
                          {:key :val/3 :value :val/4}]}]
 :terminator {:op :return :value :val/5}}
```

### Vector Access

#### Clojure
```clojure
(get [1 2 3] 1)
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value 1}
                {:op :const :result :val/2 :value 2}
                {:op :const :result :val/3 :value 3}
                {:op :make-vector :result :val/4 :elements [:val/1 :val/2 :val/3]}
                {:op :const :result :val/5 :value 1}
                {:op :vector-get :result :val/6 :vector :val/4 :index :val/5}]
 :terminator {:op :return :value :val/6}}
```

---

## Higher-Order Functions

### Map

#### Clojure
```clojure
(map inc [1 2 3])
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value 1}
                {:op :const :result :val/2 :value 2}
                {:op :const :result :val/3 :value 3}
                {:op :make-vector :result :val/4 :elements [:val/1 :val/2 :val/3]}
                {:op :var-ref :result :val/5 :var :builtin/inc}
                {:op :call :result :val/6 :fn :builtin/map :args [:val/5 :val/4]}]
 :terminator {:op :return :value :val/6}}
```

### Filter

#### Clojure
```clojure
(filter even? [1 2 3 4])
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value 1}
                {:op :const :result :val/2 :value 2}
                {:op :const :result :val/3 :value 3}
                {:op :const :result :val/4 :value 4}
                {:op :make-vector :result :val/5 :elements [:val/1 :val/2 :val/3 :val/4]}
                {:op :var-ref :result :val/6 :var :builtin/even?}
                {:op :call :result :val/7 :fn :builtin/filter :args [:val/6 :val/5]}]
 :terminator {:op :return :value :val/7}}
```

### Reduce

#### Clojure
```clojure
(reduce + 0 [1 2 3])
```

#### IR
```edn
{:instructions [{:op :const :result :val/1 :value 1}
                {:op :const :result :val/2 :value 2}
                {:op :const :result :val/3 :value 3}
                {:op :make-vector :result :val/4 :elements [:val/1 :val/2 :val/3]}
                {:op :var-ref :result :val/5 :var :builtin/add}
                {:op :const :result :val/6 :value 0}
                {:op :call :result :val/7 :fn :builtin/reduce :args [:val/5 :val/6 :val/4]}]
 :terminator {:op :return :value :val/7}}
```

---

## Complex Examples

### FizzBuzz

#### Clojure
```clojure
(defn fizzbuzz [n]
  (cond
    (zero? (mod n 15)) "FizzBuzz"
    (zero? (mod n 3))  "Fizz"
    (zero? (mod n 5))  "Buzz"
    :else              (str n)))
```

#### IR (Simplified)
```edn
{:id :fn/user-fizzbuzz-10
 :name "fizzbuzz"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/n]
 :blocks [:block/entry :block/check15 :block/check3 :block/check5 :block/else
          :block/fizzbuzz :block/fizz :block/buzz :block/number :block/merge]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/n}
                  {:op :const :result :val/2 :value 15}
                  {:op :call :result :val/3 :fn :builtin/mod :args [:val/1 :val/2]}
                  {:op :call :result :val/4 :fn :builtin/zero? :args [:val/3]}]
   :terminator {:op :branch
                :condition :val/4
                :true-target :block/fizzbuzz
                :false-target :block/check3}}
  
  :block/fizzbuzz
  {:instructions [{:op :const :result :val/5 :value "FizzBuzz"}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/check3
  {:instructions [{:op :var-ref :result :val/6 :var :param/n}
                  {:op :const :result :val/7 :value 3}
                  {:op :call :result :val/8 :fn :builtin/mod :args [:val/6 :val/7]}
                  {:op :call :result :val/9 :fn :builtin/zero? :args [:val/8]}]
   :terminator {:op :branch
                :condition :val/9
                :true-target :block/fizz
                :false-target :block/check5}}
  
  :block/fizz
  {:instructions [{:op :const :result :val/10 :value "Fizz"}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/check5
  {:instructions [{:op :var-ref :result :val/11 :var :param/n}
                  {:op :const :result :val/12 :value 5}
                  {:op :call :result :val/13 :fn :builtin/mod :args [:val/11 :val/12]}
                  {:op :call :result :val/14 :fn :builtin/zero? :args [:val/13]}]
   :terminator {:op :branch
                :condition :val/14
                :true-target :block/buzz
                :false-target :block/number}}
  
  :block/buzz
  {:instructions [{:op :const :result :val/15 :value "Buzz"}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/number
  {:instructions [{:op :var-ref :result :val/16 :var :param/n}
                  {:op :call :result :val/17 :fn :builtin/str :args [:val/16]}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/merge
  {:instructions [{:op :phi
                   :result :val/18
                   :sources [{:block :block/fizzbuzz :value :val/5}
                            {:block :block/fizz :value :val/10}
                            {:block :block/buzz :value :val/15}
                            {:block :block/number :value :val/17}]}]
   :terminator {:op :return :value :val/18}}}}
```

### Quicksort

#### Clojure
```clojure
(defn qsort [xs]
  (if (empty? xs)
    []
    (let [pivot (first xs)
          rest (rest xs)
          smaller (filter #(< % pivot) rest)
          larger (filter #(>= % pivot) rest)]
      (concat (qsort smaller) [pivot] (qsort larger)))))
```

#### IR (Outline - Full version would be very long)
```edn
{:id :fn/user-qsort-11
 :name "qsort"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/xs]
 :blocks [:block/entry :block/empty :block/partition :block/merge]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:instructions [{:op :var-ref :result :val/1 :var :param/xs}
                  {:op :call :result :val/2 :fn :builtin/empty? :args [:val/1]}]
   :terminator {:op :branch
                :condition :val/2
                :true-target :block/empty
                :false-target :block/partition}}
  
  :block/empty
  {:instructions [{:op :make-vector :result :val/3 :elements []}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/partition
  {:instructions [;; pivot = (first xs)
                  {:op :var-ref :result :val/4 :var :param/xs}
                  {:op :call :result :val/5 :fn :builtin/first :args [:val/4]}
                  ;; rest-xs = (rest xs)
                  {:op :var-ref :result :val/6 :var :param/xs}
                  {:op :call :result :val/7 :fn :builtin/rest :args [:val/6]}
                  ;; Create filter predicates (closures)
                  {:op :make-closure :result :val/8 :fn :fn/qsort-filter-lt :captures [:val/5]}
                  {:op :make-closure :result :val/9 :fn :fn/qsort-filter-gte :captures [:val/5]}
                  ;; Filter
                  {:op :call :result :val/10 :fn :builtin/filter :args [:val/8 :val/7]}
                  {:op :call :result :val/11 :fn :builtin/filter :args [:val/9 :val/7]}
                  ;; Recursive calls
                  {:op :call :result :val/12 :fn :fn/user-qsort-11 :args [:val/10]}
                  {:op :call :result :val/13 :fn :fn/user-qsort-11 :args [:val/11]}
                  ;; Concat
                  {:op :make-vector :result :val/14 :elements [:val/5]}
                  {:op :call :result :val/15 :fn :builtin/concat :args [:val/12 :val/14 :val/13]}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/merge
  {:instructions [{:op :phi
                   :result :val/16
                   :sources [{:block :block/empty :value :val/3}
                            {:block :block/partition :value :val/15}]}]
   :terminator {:op :return :value :val/16}}}}
```

---

## Notes

### ID Generation

In practice, IDs are generated systematically:
- `:val/NNN` - Sequential integers for SSA values
- `:block/name` - Descriptive names for blocks
- `:fn/namespace-name-NNN` - Namespace + name + unique ID
- `:param/name` - Parameter names from source
- `:local/name` - Local binding names from source

### Optimization Opportunities

These examples show the IR before optimization. After optimization passes:
- Constant folding would evaluate `(+ 1 2)` to `3`
- Dead code elimination would remove unused values
- Inlining would inline small functions
- Tail call optimization would optimize `recur`

### Metadata

In production IR, nodes would include metadata:
```edn
{:op :call
 :result :val/3
 :fn :builtin/add
 :args [:val/1 :val/2]
 :meta {:source-location {:file "user.clj" :line 5 :column 3}
        :infer-type :i64}}
```

This metadata helps with:
- Error messages (show source location)
- Optimization (use type information)
- Debugging (map IR back to source)

---

## See Also

- [SPECIFICATION.md](./SPECIFICATION.md) - Full IR specification
- [DESIGN_RATIONALE.md](./DESIGN_RATIONALE.md) - Design decisions and trade-offs
