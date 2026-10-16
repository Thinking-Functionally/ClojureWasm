;; SPDX-License-Identifier: EPL-2.0
;; Phase 2: Extended Clojure frontend
;; Supports: if/else, let bindings, comparison ops, recursion

(ns cljw.ir.minimal-frontend-phase2
  (:require [clojure.string :as str]))

;; ========== Value ID Generation ==========

(def ^:dynamic *val-counter* (atom 0))
(def ^:dynamic *block-counter* (atom 0))

(defn reset-counters! []
  (reset! *val-counter* 0)
  (reset! *block-counter* 0))

(defn gen-val-id []
  (keyword (str "val/" (swap! *val-counter* inc))))

(defn gen-block-id [prefix]
  (keyword (str "block/" prefix "-" (swap! *block-counter* inc))))

(defn param-id [name]
  (keyword (str "param/" (str name))))

(defn let-id [name]
  (keyword (str "let/" (str name))))

;; ========== Environment Management ==========

(defn extend-env [env bindings]
  (merge env bindings))

(defn lookup-var [env sym]
  (or (get env (keyword (name sym)))
      (param-id (name sym))))

;; ========== Expression Compilation ==========

(declare compile-expr)

(defn compile-const [value]
  (let [result-id (gen-val-id)]
    {:instructions [{:op :const
                     :result result-id
                     :value value}]
     :result result-id}))

(defn compile-var-ref [sym env]
  (let [result-id (gen-val-id)
        var-id (lookup-var env sym)]
    {:instructions [{:op :var-ref
                     :result result-id
                     :var var-id}]
     :result result-id}))

(defn compile-if
  "Compile if expression to multi-block IR"
  [test then else env]
  (let [;; Compile test
        test-result (compile-expr test env)
        test-val (:result test-result)

        ;; Block IDs
        then-block-id (gen-block-id "then")
        else-block-id (gen-block-id "else")
        merge-block-id (gen-block-id "merge")

        ;; Compile branches
        then-result (compile-expr then env)
        else-result (compile-expr else env)

        ;; Phi node result
        phi-result (gen-val-id)]

    {:instructions (:instructions test-result)
     :result phi-result
     :terminator {:op :branch
                 :condition test-val
                 :then then-block-id
                 :else else-block-id}
     :blocks {then-block-id {:id then-block-id
                            :instructions (:instructions then-result)
                            :terminator {:op :jump
                                        :target merge-block-id
                                        :value (:result then-result)}}
              else-block-id {:id else-block-id
                            :instructions (:instructions else-result)
                            :terminator {:op :jump
                                        :target merge-block-id
                                        :value (:result else-result)}}
              merge-block-id {:id merge-block-id
                             :instructions [{:op :phi
                                           :result phi-result
                                           :sources [{:block then-block-id :value (:result then-result)}
                                                    {:block else-block-id :value (:result else-result)}]}]
                             :terminator nil}}}))

(defn compile-let
  "Compile let bindings"
  [bindings body env]
  (let [binding-pairs (partition 2 bindings)

        ;; Compile each binding and extend environment
        compile-binding (fn [[name-sym expr] current-env]
                         (let [result (compile-expr expr current-env)
                               binding-id (let-id (name name-sym))
                               bind-instr {:op :let-bind
                                          :name binding-id
                                          :value (:result result)}
                               new-env (assoc current-env (keyword (name name-sym)) binding-id)]
                           {:instructions (conj (:instructions result) bind-instr)
                            :env new-env}))

        ;; Fold over bindings
        bindings-result (reduce (fn [acc pair]
                                 (let [binding-result (compile-binding pair (:env acc))]
                                   {:instructions (vec (concat (:instructions acc) (:instructions binding-result)))
                                    :env (:env binding-result)}))
                               {:instructions []
                                :env env}
                               binding-pairs)

        ;; Compile body with extended environment
        body-result (compile-expr body (:env bindings-result))]

    {:instructions (vec (concat (:instructions bindings-result) (:instructions body-result)))
     :result (:result body-result)
     :blocks (:blocks body-result)
     :terminator (:terminator body-result)}))

(defn compile-call
  "Compile function call (builtin or user-defined)"
  [op args env]
  (let [;; Compile all arguments
        arg-results (mapv #(compile-expr % env) args)
        arg-vals (mapv :result arg-results)
        all-instrs (vec (mapcat :instructions arg-results))

        ;; Generate result
        result-id (gen-val-id)

        ;; Determine function reference
        fn-ref (cond
                (contains? #{'+ '- '* '= '< '> '<= '>= 'not} op)
                (keyword (str "builtin/" (name op)))

                :else
                (keyword (str "fn/user-" (name op))))]

    {:instructions (conj all-instrs
                        {:op :call
                         :result result-id
                         :fn fn-ref
                         :args arg-vals})
     :result result-id}))

(defn compile-expr
  "Compile expression to IR"
  [expr env]
  (cond
    ;; Number literal
    (number? expr)
    (compile-const expr)

    ;; Boolean literal
    (or (true? expr) (false? expr))
    (compile-const expr)

    ;; Symbol (variable reference)
    (symbol? expr)
    (compile-var-ref expr env)

    ;; List (special form or call)
    (list? expr)
    (let [[op & rest] expr]
      (case op
        if   (let [[test then else] rest]
               (compile-if test then else env))
        let  (let [[bindings body] rest]
               (compile-let bindings body env))
        (compile-call op rest env)))

    :else
    (throw (ex-info (str "Unsupported expression: " expr) {:expr expr}))))

;; ========== Function Compilation ==========

(defn compile-defn
  "Compile defn form to IR"
  [fn-name params body]
  (reset-counters!)

  (let [fn-id (keyword (str "fn/user-" (clojure.core/name fn-name)))
        param-ids (mapv #(param-id (clojure.core/name %)) params)

        ;; Initial environment maps param symbols to param IDs
        initial-env (into {} (map (fn [p] [(keyword (clojure.core/name p)) (param-id (clojure.core/name p))]) params))

        ;; Compile body
        body-result (compile-expr body initial-env)]

    ;; Check if body has control flow (multi-block)
    (if (:blocks body-result)
      ;; Multi-block function (has if/else)
      (let [entry-block {:id :block/entry
                        :instructions (:instructions body-result)
                        :terminator (:terminator body-result)}
            all-blocks (assoc (:blocks body-result) :block/entry entry-block)
            block-ids (vec (keys all-blocks))]
        {:id fn-id
         :name (str fn-name)
         :namespace "user"
         :arity {:fixed (count params)}
         :params param-ids
         :blocks block-ids
         :entry-block :block/entry
         :block-defs all-blocks})

      ;; Single-block function (simple expression)
      (let [entry-block {:id :block/entry
                        :instructions (:instructions body-result)
                        :terminator {:op :return
                                    :value (:result body-result)}}]
        {:id fn-id
         :name (str fn-name)
         :namespace "user"
         :arity {:fixed (count params)}
         :params param-ids
         :blocks [:block/entry]
         :entry-block :block/entry
         :block-defs {:block/entry entry-block}}))))

;; ========== Public API ==========

(defn compile-form
  "Compile a top-level form to IR"
  [form]
  (cond
    (and (list? form) (= 'defn (first form)))
    (let [[_ name params body] form]
      (compile-defn name params body))

    :else
    (throw (ex-info "Only defn forms are supported" {:form form}))))

(defn compile-to-edn-string
  "Compile form and return EDN string (without namespaced maps)"
  [form]
  (binding [*print-namespace-maps* false]
    (pr-str (compile-form form))))

;; ========== Examples ==========

(comment
  ;; Simple arithmetic
  (compile-to-edn-string '(defn add [x y] (+ x y)))

  ;; Conditional
  (compile-to-edn-string '(defn abs [x] (if (< x 0) (- x) x)))

  ;; Let binding
  (compile-to-edn-string '(defn square-sum [x y] (let [x2 (* x x) y2 (* y y)] (+ x2 y2))))

  ;; Recursion (factorial)
  (compile-to-edn-string '(defn fact [n] (if (<= n 1) 1 (* n (fact (- n 1))))))

  ;; Comparison operators
  (compile-to-edn-string '(defn max [a b] (if (> a b) a b)))
  )
