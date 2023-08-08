
(in-package :cl-waffe2/vm)


;; TODO LIST
;; In-place mutation実装
;;FW/BW Test
;;標準でこれを使う
;;JITCPUTensorを更新


;; funcall多用する・・・

;; In-place mutation ... Flattenにした後
;; JITCPUTensor ... もっと単純にできる

;; The goal: cl-waffe2 is a specializer on DAG nodes ... 数万のDAG回路を取り扱うことに特化している・・・

(defstruct (WFInstruction
	    (:conc-name wfop-)
	    (:constructor make-wfop (op self node args)))
  "
## [struct] WFInstruction

Instruction: Sets the result of λ function op called with `args`, into self.state.forward_result

Basically follows this format:

 out_target <- Args1 Args2 Args3 ...

cl-waffe2 vm specializes on  the sequence of above format.
"
  (op   op   :type function)
  (node node :type (or null AbstractNode))
  (self self :type AbstractTensor)
  (args args :type list)
  (bw-is-leaf-p nil :type boolean))

;; (defstruct (Composable-Operator <- separate call-with-view from body
;; (defun .cop (cop1 cop2) ...)

(defmethod print-object ((inst WFInstruction) stream)
  (format stream
	  "<WfInst[Compiled: ~a] : ~a.state <= apply(~a)>~%"
	  (if (movetensor-p (wfop-node inst))
	      (if (movetensor-ignore-me (wfop-node inst))
		  "<DELETED>"
		  (class-name (class-of (wfop-node inst))))
	      (class-name (class-of (wfop-node inst))))
	  (tensor-id (wfop-self inst))
	  (with-output-to-string (out)
	    (dolist (var (wfop-args inst))
	      (format out "~a~a~a "
		      (if (slot-value var 'cl-waffe2/vm.generic-tensor::requires-grad)
			  "<Param>"
			  "")
		      (tensor-id var) (shape var))))))

;; In-place mutation

;;      v judge:is this usage of A is the last?
;; A <- A B
;;   ...
;; K <- A B

(defun apply-in-place-mutation! (iseq leaves)
  (declare (type list iseq leaves))
  (let ((ref-table (make-hash-table)))

    ;; First, Register all tensors appeared in the computation node
    (mapc
     #'(lambda (variable)
	 ;; Tensors that can be destructed is:
	 ;; InputTensor
	 ;; Set 100 as for ExistTensor, in order not to destruct training data/parameters

	 (if (eql (tensor-attribute variable) :chain)
	     (setf (gethash (tensor-id variable) ref-table) 0)
	     (setf (gethash (tensor-id variable) ref-table) nil)))
     leaves)


    ;; Tracing all the computation nodes, counting up reference tables
    (mapc
     #'(lambda (instruction)
	 (when (not (movetensor-p (wfop-node instruction)))
	   (mapc
	    #'(lambda (arg)
		(if (gethash (tensor-id arg) ref-table)
		    (incf (gethash (tensor-id arg) ref-table) 1)))
	    (wfop-args instruction))))
     iseq)

    ;; Based on ref-table, we retribute whether MoveTensor should be ignored or not.

    (mapc
     #'(lambda (instruction)
	 (when (movetensor-p (wfop-node instruction))
	   ;; MoveTensor: A B -> A (Place Target -> Place)
	   ;; In-place MoveTensor: A B -> B

	   (let* ((bw     (wfop-node instruction))
		  (past-variables (tensor-variables (wfop-self instruction)))
		  (target (second (wfop-args instruction)))
		  (in-place-p
		    (and
		     (gethash (tensor-id target) ref-table)
		     (<= (gethash (tensor-id target) ref-table) 1)

		     ;; :force t is not subject to in-place

		     ;; The problem is that: it is unknown wheter movetensor returns Viewed Input or not.
		     ;; So Tensors whose place has multi-dimensional offset, is ignored

		     (apply #'cl-waffe2/vm.generic-tensor::order-reductable-p 0 past-variables) ;; <- is it worth it? test
		     (not (tensor-protect-me (car past-variables)))
		     (not (movetensor-save-for-backward bw)))))
	     
	     (if in-place-p
		 ;; Decrease the count
		 
		 (setf (movetensor-ignore-me (wfop-node instruction)) t)
		 (when (gethash (tensor-id target) ref-table)
		   (decf (gethash (tensor-id target) ref-table)))))))
     iseq)
    nil))

