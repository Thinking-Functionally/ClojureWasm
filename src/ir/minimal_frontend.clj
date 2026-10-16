;; SPDX-License-Identifier: EPL-2.0
;; Minimal Clojure frontend for Phase 1 PoC
;; Compiles simple Clojure forms to IR (EDN format)

(ns cljw.ir.minimal-frontend
  (:require [clojure.string :as str]))

;; ========== Value ID Generation ==========

(def ^:dynamic *val-counter* (atom 0))

(defn reset-val-counter! []
  (reset! *val-counter* 0))

(defn gen-val-id []
  (keyword (str "val/" (swap! *val-counter* inc))))

(defn param-id [name]
  (keyword (str "param/" name)))

;; ========== IR Generation ==========

(defn compile-const [value]
  {:op :const
   :result (gen-val-id)
   :value value})

(defn compile-var-ref [sym params]
  (let [param-name (name sym)]
    (if (contains? (set params) param-name)
      {:op :var-ref
       :result (gen-val-id)
       :var (param-id param-name)}
      (throw (ex-info (str "Unresolved symbol: " sym) {:symbol sym})))))

(declare compile-expr)

(defn compile-call [op args params]
  (let [arg-results (mapv #(compile-expr % params) args)
        arg-vals (mapv :result arg-results)]
    {:instructions (vec (mapcat :instructions arg-results))
     :result (gen-val-id)
     :call-instr {:op :call
                  :result (gen-val-id)
                  :fn (keyword (str "builtin/" (name op)))
                  :args arg-vals}}))

(defn compile-prim-op [op args params]
  (let [arg-results (mapv #(compile-expr % params) args)
        arg-vals (mapv :result arg-results)
        prim-op (case op
                  + :prim-add
                  - :prim-sub
                  * :prim-mul
                  = :prim-eq
                  < :prim-lt
                  > :prim-gt)]
    {:instructions (vec (mapcat :instructions arg-results))
     :result (gen-val-id)
     :prim-instr {:op prim-op
                  :result (gen-val-id)
                  :args arg-vals}}))

(defn compile-if [test then else params]
  (let [test-result (compile-expr test params)
        test-val (:result test-result)
        then-block-id (keyword (str "block/then-" (gen-val-id)))
        else-block-id (keyword (str "block/else-" (gen-val-id)))
        merge-block-id (keyword (str "block/merge-" (gen-val-id)))]
    {:test-instructions (:instructions test-result)
     :test-val test-val
     :then-block-id then-block-id
     :else-block-id else-block-id
     :merge-block-id merge-block-id
     :then-expr then
     :else-expr else}))

(defn compile-expr
  "Compile a single expression to IR instructions + result value"
  [expr params]
  (cond
    (number? expr)
    {:instructions [(compile-const expr)]
     :result (:result (compile-const expr))}

    (symbol? expr)
    (let [instr (compile-var-ref expr params)]
      {:instructions [instr]
       :result (:result instr)})

    (list? expr)
    (let [[op & args] expr]
      (cond
        ;; Primitive operations
        (contains? #{+ - * = < >} op)
        (let [prim-result (compile-prim-op op args params)]
          {:instructions (conj (:instructions prim-result) (:prim-instr prim-result))
           :result (:result (:prim-instr prim-result))})

        ;; Function call
        :else
        (let [call-result (compile-call op args params)]
          {:instructions (conj (:instructions call-result) (:call-instr call-result))
           :result (:result (:call-instr call-result))})))

    :else
    (throw (ex-info (str "Unsupported expression: " expr) {:expr expr}))))

(defn compile-defn
  "Compile a defn form to IR"
  [name params body]
  (reset-val-counter!)

  (let [fn-id (keyword (str "fn/user-" name "-" (swap! *val-counter* inc)))
        param-ids (mapv #(param-id %) params)
        param-names (mapv str params)

        ;; Compile body expression
        body-result (compile-expr body param-names)

        ;; Build entry block
        entry-block {:id :block/entry
                     :instructions (:instructions body-result)
                     :terminator {:op :return
                                  :value (:result body-result)}}]

    {:id fn-id
     :name (str name)
     :namespace "user"
     :arity {:fixed (count params)}
     :params param-ids
     :blocks [:block/entry]
     :entry-block :block/entry
     :block-defs {:block/entry entry-block}}))

;; ========== Public API ==========

(defn compile-form
  "Compile a top-level form to IR (EDN)"
  [form]
  (cond
    ;; (defn name [params] body)
    (and (list? form)
         (= 'defn (first form)))
    (let [[_ name params body] form]
      (compile-defn name params body))

    :else
    (throw (ex-info "Only defn forms are supported in Phase 1" {:form form}))))

(defn compile-to-edn-string
  "Compile a form and return EDN string"
  [form]
  (binding [*print-namespace-maps* false]
    (pr-str (compile-form form))))

;; ========== Examples ==========

(comment
  ;; Example 1: (defn add [x y] (+ x y))
  (compile-form '(defn add [x y] (+ x y)))
  ;=> {:id :fn/user-add-1
  ;    :name "add"
  ;    :namespace "user"
  ;    :arity {:fixed 2}
  ;    :params [:param/x :param/y]
  ;    :blocks [:block/entry]
  ;    :entry-block :block/entry
  ;    :block-defs {:block/entry {:id :block/entry
  ;                               :instructions [{:op :var-ref :result :val/2 :var :param/x}
  ;                                              {:op :var-ref :result :val/3 :var :param/y}
  ;                                              {:op :prim-add :result :val/4 :args [:val/2 :val/3]}]
  ;                               :terminator {:op :return :value :val/4}}}}

  ;; Example 2: (defn abs [x] (if (< x 0) (- x) x))
  ;; Note: if support requires multi-block IR, deferred to later iteration

  ;; Generate EDN string
  (compile-to-edn-string '(defn add [x y] (+ x y)))
  )
