(ns cljtest.runner
  "Shared entry point for every suite under test/clj.

  `test/clj/run.sh` calls one of the two `run-*` fns below as the only form of a
  cljw process, once per backend. Each prints exactly one machine-readable line

      CLJTEST-SUMMARY {:suite \"name\" :test N :pass N :fail N :error N}

  and exits 0 only if nothing failed AND at least one test ran (so a suite that
  silently loses its tests, or never calls run-tests, cannot pass)."
  (:require [clojure.test :as t]))

(defn- finish [suite m]
  (println (str "CLJTEST-SUMMARY "
                (pr-str {:suite suite
                         :test (:test m) :pass (:pass m)
                         :fail (:fail m) :error (:error m)})))
  (System/exit (if (and (zero? (:fail m)) (zero? (:error m)) (pos? (:test m))) 0 1)))

(defn run-files
  "Evaluate each file (forms register their deftests in the current ns), then
  run them. For suites whose files have no `ns` form."
  [suite files]
  (doseq [f files]
    (load-string (slurp f)))
  (finish suite (t/run-tests)))

(defn run-namespaces
  "Require each namespace (resolved from the classpath given to cljw), then run
  its tests."
  [suite nss]
  (apply require nss)
  (finish suite (apply t/run-tests nss)))
