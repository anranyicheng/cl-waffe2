
(in-package :cl-waffe2/backends.lisp)

(defun iterator-symbols (rank)
  (loop for r upfrom 0 below rank
	collect
	(intern (format nil "~a~a" (gensym "L") (code-char (+ 65 r))))))

(defun lisp-name (value)
  (typecase value
    (symbol     
     `(the fixnum (cl-waffe2/vm.generic-tensor::read-symbol ',value)))
    (T
     value)))

(defstruct (LazyLispInstruction
	    (:conc-name lli-)
	    (:constructor make-lli (opform out-to args &key (apply nil) (reduced-to 1))))
  "LazyLispInstruction, an blueprint for expand-iteration.
apply - Set to (apply function array). nil to (dotimes (...) ... )"
  (apply  apply  :type boolean)
  (out-to out-to :type AbstractTensor)
  (args   args   :type list)
  (opform opform :type (or function symbol list))
  (reduced-to reduced-to :type fixnum))

(defun expand-iteration (tensors instructions)
  (declare (type list tensors instructions))
  (let* ((abstract-loop (solve-loop-order tensors 1 T :mode :runtime))
	 (indices       (iterator-symbols (dims (car tensors)))))
    (labels ((expand-helper (rank)
	       (let ((aloop (nth rank abstract-loop))
		     (index (nth rank indices)))
		 (case (aloop-mode aloop)
		   (:batch
		    `(dotimes (,index ,(lisp-name (aloop-size aloop)))
		       ,(expand-helper (1+ rank))))
		   (T
		    `(progn
		       ,@(map
			  'list
			  #'(lambda (inst)
			      (expand-instruction
			       aloop
			       inst
			       index
			       indices))
			  instructions)))))))
      (expand-helper 0))))

(defun lazy-aref-form (tensor indices)
  `(aref ,(tensor-id tensor)
	 (the (unsigned-byte 32)
	      (+
	       ,@(loop for dim upfrom 0 below (dims tensor)
		       for stride in (tensor-actual-stride tensor)
		       for index in indices
		       collect
		       `(the (unsigned-byte 32) (* ,stride ,index)))))))

(defun expand-instruction (aloop instruction index-symbol indices)
  (declare (type LazyLispInstruction instruction))
  (if (lli-apply instruction)
      `(let ((,index-symbol 0))
	 (declare (ignorable ,index-symbol)
		  (type (unsigned-byte 32) ,index-symbol))
	 ;; [TODO] Support Reduce-To, implement TopK
	 (setf ,(lazy-aref-form (lli-out-to instruction) indices)
	       (apply ,(lli-opform instruction)
		      ,@(loop for tensor in (lli-args instruction)
			      collect
			      `(loop for ,index-symbol of-type (unsigned-byte 32)
				     upfrom 0
				       below ,(lisp-name (car (last (shape tensor))))
				     collect
				     (lazy-aref-form tensor indices))))))
      `(dotimes (,index-symbol ,(lisp-name (aloop-element-n aloop)))
	 (setf ,(lazy-aref-form (lli-out-to instruction) indices)
	       (funcall
		,(lli-opform instruction)
		,@(loop for tensor in (lli-args instruction)
			collect
			(lazy-aref-form tensor indices)))))))

(defun lazy-call-form (tensors instructions finally-return)
  `(progn
     (let* (,@(loop for tensor in tensors
		    collect
		    `(,(tensor-id tensor) (tensor-vec ,tensor))))
       (declare ,@(loop for tensor in tensors
			collect
			`(type (simple-array ,(dtype->lisp-type (dtype tensor)) (*)) ,(tensor-id tensor)))
		(optimize (speed 3)))
       ,(expand-iteration tensors instructions))
     ,finally-return))

