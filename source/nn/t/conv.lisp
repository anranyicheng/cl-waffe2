
(in-package :cl-waffe2/nn.test)


(in-suite :nn-test)

(defun conv-2d-forward-test ()
  (let ((model (Conv2D 3 6 `(2 2))))
    (equal `(3 6 9 9) (shape (proceed (call model (randn `(3 3 10 10))))))))

(defun conv-2d-fw-bw-test ()
  (let ((model (Conv2D 3 6 `(2 2))))
    (let ((compiled-model
	    (build (!mean (call model (ax+b `(3 3 10 10) 0.001 0))))))
      (forward compiled-model)
      (backward compiled-model)
      (let ((ch1)
	    (f t))
	#|
	(print (progn;change-facet
		(proceed
		 ;; (N H W C) 3 2 1 0 3 0 1 2

		 ;; (0 1 2 3) kamo
		 ;; ( 1 0 2 3)
		 ;; (!permute 2 0 3 1)で(C_out C_in k-h k-w)になる？
		 ;; (W H N C)
		 (!reshape (->contiguous (!permute (grad (weight-of model)) 1 0 2 3))
	6 3 2 2))))
	|#
	(print (grad (weight-of model)))
	(dotimes (i 6)
	  (dotimes (k 3)
	    (let ((out (proceed (->contiguous (!view (grad (weight-of model)) i k)))))
	      ;; [window0]
	      ;; (ch1.grad ..
	      ;;  .. ..)
	      ;;  (ch1.grad ..
	      ;; .. ..)
	      ;; ...
	      
	      (when (and ch1 f)
		(setq f (= (vref out 0) ch1)))
	      (when (every #'= (tensor-vec out))
		;; bug related to permution? im2col?
		(setq f nil))
	      (setq ch1 (vref out 0)))))
	f))))

(defun conv-2d-fw-bw-test-1 ()
  (let ((model (Conv2D 3 6 `(2 2) :bias nil)))
    (let ((compiled-model
	    (build (call model (randn `(3 3 10 10))))))
      (forward compiled-model)
      (backward compiled-model)
      (and
       (grad (weight-of model))
       (null (bias-of   model))))))

(defun unfold-test-forward ()
  (let* ((img (ax+b `(2 2 2 2) 1 0))
	 (out (cl-waffe2/nn::unfold img `(1 1) `(2 2) `(1 1) `(0 0))))
    (every #'=
     #(0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0)
     (change-facet (proceed out) :direction 'simple-array))))

(defun unfold-test-backward ()
  (let* ((img (parameter (ax+b `(2 2 2 2) 1 0)))
	 (out (cl-waffe2/nn::unfold img `(1 1) `(2 2) `(1 1) `(0 0))))
    (proceed-backward
     (!sum
      (!mul out (ax+b `(2 8) 1 0))))
    (every #'=
	   #(0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0)
	   (tensor-vec (grad img)))))

(test conv2d-fw-bw-test
  (is (conv-2d-forward-test))
  (is (conv-2d-fw-bw-test))
  (is (conv-2d-fw-bw-test-1)))

(test im2col-test
  (is (unfold-test-forward))
  (is (unfold-test-backward)))


;; MaxPoolTest
;; AvgPoolTest

;; Building CNN and proceed it.

