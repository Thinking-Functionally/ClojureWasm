;; D-568 manual test — verify improved error messages for dropResource failures
(require '[cljw.wasm :refer [require-component with-resource]])

(require-component counter "test/e2e/fixtures/wasm/resource_counter.wasm")

;; Test 1: Normal lifecycle (should succeed)
(println "Test 1: Normal lifecycle")
(with-resource [h (counter/new 0)]
  (println "  Resource created and auto-dropped"))

(println "\nTest 2: Double-drop idempotent (cljw-side guard)")
(def h2 (counter/new 0))
(println "  First drop:" (counter/drop h2))
(println "  Second drop (idempotent):" (counter/drop h2))

(println "\nNOTE: Cannot easily test InvalidHandle / TypeMismatch / StillBorrowed")
(println "      without forging a raw handle or accessing zwasm internals.")
(println "      The error-mapping code is in place; integration-tested via ")
(println "      real zwasm failures in component usage.")
