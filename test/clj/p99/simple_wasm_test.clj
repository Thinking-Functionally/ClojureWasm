;; Simple WASM backend tests - only expressions, no def/require/println

;; Arithmetic
(+ 1 2)
(* 3 4)
(- 10 5)
(/ 20 4)

;; Vectors
[1 2 3]
[4 5 6 7]

;; Simple calls
(last [1 2 3 4])
(count [1 2 3])
(first [99 88 77])
