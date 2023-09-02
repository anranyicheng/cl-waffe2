
(in-package :cl-waffe2/vm)

;; Reading List
;; https://www.cspp.cc.u-tokyo.ac.jp/hanawa/class/spc2016s/sp20160426.pdf
;; https://www.r-ccs.riken.jp/wp/wp-content/uploads/2020/09/katagiri190516.pdf

(defun compose (&rest fns)
  (if fns
      (let ((fn1 (car (last fns)))
            (fns (butlast fns)))
        #'(lambda (&rest args)
                   (reduce #'funcall fns
                           :from-end t
                           :initial-value (apply fn1 args))))
      #'identity))

;; Ref: http://www.utkuevci.com/ml/autograd/
(defun topological-sort (var)
  (declare (type AbstractTensor var)
	   (optimize (speed 3)))
  (let ((seen nil)
	(top-sort nil))
    (declare (type list seen top-sort))
    (labels ((top-sort-helper (v is-leaf-p)
	       (if (or (find (the symbol (tensor-iid v))
			     seen :key #'tensor-iid :test #'eql)
		       ;;(null (tensor-backward v))
		       is-leaf-p)
		   nil
		   (progn
		     (push v seen)
		     (dolist (prev (tensor-variables v))
		       (top-sort-helper prev (detach-p v)))
		     (push v top-sort)))))
      (top-sort-helper var (detach-p var))
      (reverse top-sort))))


;; Autograd:
(defun make-backward-wfinst (tensor)
  (multiple-value-bind (bw-kernel iseq out-to) (make-backward tensor)
    (declare (type function bw-kernel))
    (values
     #'(lambda (dout &rest args)
	 (declare (optimize (speed 3))
		  (type AbstractTensor dout))
	 (if *under-benchmark-set*
	     (apply bw-kernel dout args)
	     (apply bw-kernel dout args)))
     #'(lambda ()
	 (format nil "Block -> ~a-BACKWARD {
~a    }
  "
		 (class-name (class-of (tensor-backward tensor)))
		 (with-output-to-string (out)
		   (with-indent-to iseq
		     (dolist (i iseq)
		       (let ((*node-indent* (+ 4 *node-indent*)))
			 (format out "        ~a" i)))))))
     out-to)))

(defun tensor-compiled-kernel (tensor)
  (when (tensor-state tensor)
    (statecontainer-forward-out-form (tensor-state tensor))))

(defun tensor-iter-of (tensor)
  (when (tensor-compiled-kernel tensor)
    (cl-waffe2/vm.generic-tensor::compiled-kernel-call-with-view (tensor-compiled-kernel tensor))))

(defparameter *node-indent* 4)

(defun print-fuse-ops (op1 op2 out)
  (flet ((print-node (op)
	   (format out "~a~a"
		   (with-output-to-string (out) (dotimes (i (+ 8 *node-indent*)) (princ " " out)))
		   op)))

    (if (wfop-fuse-prev op1)
	(print-fuse-ops (car (wfop-fuse-prev op1)) (second (wfop-fuse-prev op1)) out)
	(print-node op1))

    (if (wfop-fuse-prev op2)
	(print-fuse-ops (car (wfop-fuse-prev op2)) (second (wfop-fuse-prev op2)) out)
	(print-node op2))))

(defun collect-fused-ops (op1 op2)
  (alexandria:flatten
   `(,(if (wfop-fuse-prev op1)
	  (collect-fused-ops (car (wfop-fuse-prev op1)) (second (wfop-fuse-prev op1)))
	  op1)
     ,(if (wfop-fuse-prev op2)
	  (collect-fused-ops (car (wfop-fuse-prev op2)) (second (wfop-fuse-prev op2)))
	  op2))))

(defun make-callable-fused-f (ranked-iter body out)
  ;; body ... (lambda (args) (declare ...) body ...)
  ;; TODO: Fuse Memory-Access
  (let ((other-parts (cdddr body))
	(args (gensym))
	(seen nil)
	(all-args (cl-waffe2/vm.generic-tensor::rloop-tensors ranked-iter)))
    `(lambda (&rest ,args)
       (let  (,@(loop for tensor in all-args
		      for nth upfrom 0
		      if (not (find (tensor-id tensor) seen))
			collect `(,(tensor-id tensor) (nth ,nth ,args))
		      do (push (tensor-id tensor) seen)))
	 (locally
	     ,@(cl-waffe2/vm.generic-tensor::tensor->id
		other-parts
		all-args))))))

(defun parse->body (body)
  "body ... (named-lambda xxx (x y z) ...) -> ..."
  (if (eql (car body) 'alexandria:named-lambda)
      `(locally ,@(cddddr body))
      (if (eql (car body) 'lambda)
	  `(progn ,@(cddr body))
	  (error "parse->body given form is not a function. ~a" body))))

(defun compose-two-ops (op1 op2)
  "op1(op2(...))

op1 ... A <- F(B, C, D)
op2 ..  E <- F(X, Y, Z)
"
  (declare (type WFInstruction op1 op2))
  (let* ((prev-iter (or (wfop-call-with-view op1) (tensor-iter-of (wfop-self op1))))
	 (out (wfop-self op2))
	 (composed-iter (it. prev-iter (tensor-iter-of (wfop-self op2))))
	 ;; Here, we gonna apply fuse-ops to the generated Lisp-Code in a meta-programming way.
	 ;;
	 ;; fuse-generated-iteration example:
	 ;; (Anyfunction (X) ...
	 ;;  (let ((x 1) ...)
	 ;;   (cl-waffe2-internal-tagbody ID
	 ;;     <old-call-with-view-content-here> ...
	 ;;
	 ;; Replace <old-call-with-view-content-here> with Compose(AnyFunction, NextFunction)
	 ;; ID = (rloop-tagid <Corresponding Ranked-Loop>)
	 ;;

	 
	 (body (fuse-generated-iteration
	        (wfop-self op2)
		prev-iter;;(tensor-iter-of (wfop-self op1));;prev-iter
		composed-iter
		(or
		 (wfop-fused-body-cache op1)
		 (cl-waffe2/vm.generic-tensor::make-funcallable-kernel-form
		  (tensor-compiled-kernel (wfop-self op1))
		  *compile-option*))
		:merge-body (parse->body
			     (car
			      (cl-waffe2/vm.generic-tensor::compiled-kernel-body
			       (tensor-compiled-kernel (wfop-self op2)))))
		:merge-loop (tensor-iter-of (wfop-self op2)))))
    
    ;; does it works? (!sin (!sum (randn `(10 10))))
    ;; still not working...
    ;; with LispTensor, it works but as for CPUTensor it won't
    ;; 1. x-ptr -> replace with gensym
    ;; 2. returned value is 0
    ;; 3. cache (compile nil)
    
    (make-wfop
     #'(lambda ()) ;; later compiled
     out
     #'(lambda ()
	 (with-indent-to (collect-fused-ops op1 op2)
	   (format nil "Block -> Fused {
~a~a}
~a"		
		   (with-output-to-string (out)
		     (print-fuse-ops op1 op2 out))
		   (with-output-to-string (out)
		     (dotimes (i (+ 4 *node-indent*)) (princ " " out)))
		   (with-output-to-string (out)
		     (dotimes (i (+  *node-indent*)) (princ " " out))))))
     `(,@(wfop-args op1) ,@(wfop-args op2))
     :call-with-view composed-iter
     :fuse-prev `(,op1 ,op2)
     ;; Later Compiled.
     :fused-body-cache body)))


(defun broadcasted-p (tensor)
  (some #'zerop (cl-waffe2/vm.generic-tensor::tensor-actual-stride tensor)))


(defun no-dependency-p (fused-iseq instruction)
  (let ((fused-p (wfop-fuse-prev fused-iseq)))
    (or (null fused-p)
	(let* ((inst-list (apply #'collect-fused-ops fused-p))
	       (prev-vars (map 'list (compose #'tensor-id #'wfop-self) inst-list)))
	  (not (find (tensor-id (wfop-self instruction)) prev-vars))))))

(defun node-out-to (node) (cl-waffe2/vm.nodes::node-out-to node))

(defun init-state-container! (tensor)
  (setf (tensor-state tensor)
	(make-statecontainer :forward-out-form (make-compiled-kernel))))

(defun %vm-wrap-tensor (tensor)
  (init-state-container! tensor)
  (make-wfop
   #'(lambda () tensor)
   tensor
   #'(lambda () "Tensor: ~a" (tensor-id tensor) (shape tensor))
   nil
   :out-to (list tensor)))


(defun sv4bw-p (node)
  (and (movetensor-p node) ;; MoveTensor(SAVE_FOR_BACKWARD) isn't subject to backward. just move tensors
       (cl-waffe2/base-impl:mv-lazy-sv4bw node)))


(defun expand-gradient-adder (tensor grad)
  ;; Tensor += Grad
  (setf (detach-p grad) t)
  (prog1
      (let ((*no-grad* t))
	(reverse
	 (if (scalar-p tensor)
	     (progn
	       (node-compile-into-vm
		(forward
		 (cl-waffe2/base-impl::ScalarAndScalarAdd)
		 (grad tensor)
		 grad)))
	     (if (= (tensor-grad-count tensor) 0)
		 (progn
		   (node-compile-into-vm
		    (forward
		     (cl-waffe2/base-impl:MoveTensorNode (dtype tensor) :save-for-backward t)
		     (grad tensor)
		     grad)))
		 (progn
		   (node-compile-into-vm
		    (forward
		     (cl-waffe2/base-impl:AddNode (dtype tensor))
		     (grad tensor)
		     grad)))))))
    (setf (detach-p grad) nil)))
