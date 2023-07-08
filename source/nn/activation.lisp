
(in-package :cl-waffe2/nn)

;; Softmax
;; ReLU
;; GeLU
;; Leakey-ReLU
;;

(defun !relu (x)
  "
## [function] !relu

..."

  (!mul x (A>scal x 0.0)))

(defun !gelu (x)
  "
## [function] !gelu

"
  
  )

;; todo (!matmul !t !t) test
(defun !softmax (x)
  "
## [function] !softmax
"
  
  (let* ((x1 (!sub x (!mean x  :axis 1 :keepdims t)))
	 (z  (!sum   (!exp x1) :axis 1 :keepdims t)))
    (!div (!exp x1) (with-instant-kernel z
		      `(progn
			 ;; cacheの作り方が悪いかも？
			 (print ,z)
			 (print (tensor-vec ,z))
			 ;; #(31.786076 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0)
			 ;; Called with MLP Sequence...
			 ,z
			 )))))
