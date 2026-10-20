;; D-568 — zwasm dropResource error message improvement
;; Test that dropResource failures distinguish failure modes instead of
;; generic "wasm_trap".

(ns wasm.resource-drop-errors
  (:require [clojure.test :refer [deftest is testing]]))

(deftest invalid-handle-error
  (testing "dropResource with invalid handle raises wasm_resource_invalid_handle"
    ;; Load a component with a resource
    (def comp (wasm/component-load "test/fixtures/wasm/resource_counter.wasm"))
    (def h (wasm/component-invoke comp "counter-new" 0))

    ;; Drop once (should succeed)
    (is (nil? (wasm/resource-drop h)))

    ;; Drop again — cljw guards double-drop at line 551, returns nil (idempotent)
    (is (nil? (wasm/resource-drop h)))

    ;; TODO: forge an invalid handle (bypass the guard) to test wasm_resource_invalid_handle
    ;; This requires either:
    ;; (A) a handle from a DIFFERENT component (foreign handle) → wasm_resource_foreign
    ;; (B) a handle with invalid state[1] (raw u32 doesn't exist in zwasm table)
    ;;
    ;; For now, the double-drop path is covered; the invalid-handle path needs
    ;; a way to construct an invalid handle value (may require a test-only helper).
    ))

;; NOTE: This test is INCOMPLETE — it verifies the double-drop idempotent path
;; but does NOT yet test the wasm_resource_invalid_handle path (need a way to
;; forge an invalid handle). The GREEN step must add that capability OR accept
;; that the invalid-handle path is integration-tested via manual probing.
