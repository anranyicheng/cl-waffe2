

(in-package :cl-waffe2/vm.nodes.generic-tensor.test)

(in-suite :test-tensor)


;; Problems: Compile-Speed (add config) (there's no need)
;; (10 a) (10 10) <- a = 10 (DONE)

;; Making Add/Sub/Mul/Div Nodes
;; OpenBLAS/Common Lisp backend.
;; update: construct-forward (InputTensor UI)
;; add:    construct-backward
;; view -> view.
;; ViewNode


(defun test-simple-forward ()
  (with-single-device (LispTensor)
    (let ((out (!add (make-tensor `(10 10))
		     (make-tensor `(10 10)))))
      (funcall (construct-forward out)))))

(defun test-simple-forward-with-view ()
  (with-single-device (LispTensor)
    (let ((out (!add (!view (make-tensor `(10 1)) t `(:broadcast 10))
		     (make-tensor `(10 10)))))
      (funcall (construct-forward out :macroexpand nil)))))

(test test-forward
  (is (test-simple-forward)))

(test forward-with-view-simple-test
  (is (test-simple-forward-with-view)))


;; Still in Concept Stage but illustrates what cl-waffe can do.
(defun test-complicated-network-forward ()
  ;; with-devices ... Priority of devices
  ;; LispTensor <- AVX2, Common Lisp's simple-array
  ;; CPUTensor  <- Accelerated by OpenBLAS
  (with-devices (LispTensor)

    ;; make-input  -> Initializes InputTensor (shape is any)
    ;; make-tensor -> Initialises AbstractTensor (shape is determined)
    
    (let* ((train-x (make-input  `(batch-size 256) :train-x))
	   (weight  (make-tensor `(100 256) :requires-grad t))
	   (bias    (make-tensor `(1 256)   :requires-grad t)))

      (let ((out (!add (!mul train-x weight) (!view bias `(:broadcast 100) t))))
	(multiple-value-bind (forward variables parameters) (construct-forward out :macroexpand nil)

	  ;; Embody InputTensor with actual datum
	  (embody-input variables :train-x (make-tensor `(100 256)))
	  ;; (print variables)  ;; an list of variables used
	  ;; (print parameters) ;; parameters to be optimized.
	  (time (funcall forward))
	  t)))))

(test test-complicated-netowrk-forward
  (is (test-complicated-network-forward)))

;; Tests call-with-view, view=t, dtype=uint8
(defun test-elementwise-unroll-forward ()
  (with-devices (LispTensor)
    (let ((a (make-tensor `(3 3) :dtype :uint8))
	  (b (make-tensor `(3 3) :dtype :uint8)))
      (dotimes (i 9)
	(setf (vref a i) 1)
	(setf (vref b i) 1))
      (let ((out (!add a b)))
	(multiple-value-bind (forward vars params) (construct-forward out :macroexpand nil)
	  (let ((result (tensor-vec (funcall forward))))
	    (every #'(lambda (elm) (= elm 2)) result)))))))

(defun test-elementwise-forward ()
  (with-devices (LispTensor)
    (let ((a (make-tensor `(100 100) :dtype :uint8))
	  (b (make-tensor `(100 100) :dtype :uint8)))
      (dotimes (i 10000)
	(setf (vref a i) 1)
	(setf (vref b i) 1))
      (let ((out (!add a b)))
	(multiple-value-bind (forward vars params) (construct-forward out :macroexpand nil)
	  (let ((result (tensor-vec (funcall forward))))
	    (every #'(lambda (elm) (= elm 2)) result)))))))

(test test-call-with-view
  (is (test-elementwise-unroll-forward))
  (is (test-elementwise-forward))
  )

