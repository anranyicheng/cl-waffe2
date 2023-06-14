
(in-package :cl-waffe2/base-impl.test)

(in-suite :base-impl-test)

;; == Here, we provide testing framework. ========
;;
;; You can perform tests like:
;; (sum-tester LispTensor)
;; (mathematical-test-set LispTensor)
;;
;; ===============================================

;; To Add: node-test-tools
;; Testing:
;;
;; [X X X] <- <Nodes> <- Input
;;    ↑ (Check) Is it correct?

;; [1 1 1] -> <Nodes> -> Gradient
;;                           ↑ (Check) Is it correct?

;; Memo:
;; Check that operations are correctly defined and executed, node by node.
;; Composite several nodes -> testing will be done at generic-tensor/t
(macrolet ((define-arith-tester (name op result grad1 grad2)
	     `(define-tester ,name :all
		(let ((a (make-tensor `(100 100) :initial-element 10))
		      (b (make-tensor `(100 100) :initial-element 1)))
		  (let ((c (proceed (,op a b)))
			(all-p t))
		    (loop while all-p
			  for i fixnum upfrom 0 below 10000
			  do (setq all-p (= (vref c i) ,result)))
		    (when all-p
		      (let ((a (make-tensor `(100 100) :initial-element 10 :requires-grad t))
			    (b (make-tensor `(100 100) :initial-element 1 :requires-grad t)))
			(proceed-backward (,op a b))
			(let ((all-p t))
			  (loop while all-p
				for i fixnum upfrom 0 below 10000
				do (setq all-p (and (= (vref (grad a) i) ,grad1)
						    (= (vref (grad b) i) ,grad2))))
			  (if all-p
			    t
			    :backward)))))))))
  (define-arith-tester add-tester  !add  11 1  1)
  (define-arith-tester sub-tester  !sub  9  1 -1)
  (define-arith-tester mul-tester  !mul  10 1 1)
  (define-arith-tester div-tester  !div  10 1 -1)
  (define-arith-tester move-tester !move 1 1 1))

(macrolet ((define-scalar-mat-tester (name op result grad1 grad2)
	     `(define-tester ,name :all
		(let ((a (make-tensor `(100 100) :initial-element 10))
		      (k (make-tensor 1)))
		  (let ((c (proceed (,op k a)))
			(all-p t))
		    (loop while all-p
			  for i upfrom 0 below 10000
			  do (setq all-p (= (vref c i) ,result)))
		    (when all-p
		      (let ((a (make-tensor `(100 100) :initial-element 10 :requires-grad t))
			    (k (make-tensor 1 :requires-grad t)))
			(proceed-backward (,op k a))
			(let ((all-p t))
			  (loop while all-p
				for i upfrom 0 below 10000
				do (setq all-p (and (= (vref (grad a) i) ,grad1)
						    (= (tensor-vec (grad k)) ,grad2))))
			  (if all-p
			      t
			      :backward)))))))))
  (define-scalar-mat-tester scalar-add-tester !scalar-add 11 1 1)
  (define-scalar-mat-tester scalar-sub-tester !scalar-sub 10 1 -1)
  (define-scalar-mat-tester scalar-mul-tester !scalar-mul 10 10 10)
  (define-scalar-mat-tester scalar-div-tester !scalar-div 10 10 -10))

;; Add: Tests on
;; !matmul/!dot (<=> sum)
;; !transposed matmul
;; argmax/argmin/max/min
;; einsum
;;

(macrolet ((define-ss-tester (name op lisp-op grad1 grad2)
	     `(define-tester ,name :all
		(let ((a (make-tensor 1 :requires-grad t))
		      (b (make-tensor 1 :requires-grad t)))
		  (let ((c (proceed (,op a b)))
			(r (,lisp-op 1 1)))
		    (when (= r (tensor-vec c))
		      (proceed-backward (,op a b))
		      (if (and (= (tensor-vec a) ,grad1)
			       (= (tensor-vec b) ,grad2))
			  t
			  :backward)))))))
  (define-ss-tester ss-add-tester !add + 1 1)
  (define-ss-tester ss-sub-tester !sub - 1 -1)
  (define-ss-tester ss-mul-tester !mul * 1 1)
  (define-ss-tester ss-div-tester !div / -1 -1))

(ss-add-tester nil)
(ss-sub-tester nil)
(ss-mul-tester nil)
(ss-div-tester nil)

