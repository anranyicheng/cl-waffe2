
(in-package :cl-waffe2/vm.generic-tensor)

;; Comment out in English:
;; NFA <-> DFA
;; DFA --> NFA

;; out-tensorからTraceして、ノードに含まれる ignore-me optionをTにするか、
;; 遷移先(variables)を適度置き換える

;; deterministic-p
;; nondeterministic-p

;; Speed-Majorな最適化と (First)
;; Memory-Majorな最適化のアルゴリズムがある (Second)

;; Speed-Major
;; Tensorで分岐しているノードをCopyして依存関係をなくす
;; 非決定的な計算ノードに直してlparallelで並列化する


;; 計算木の各部分は、一つのTensor-Inputに依存する
;; この依存を解決するには
;; NFA -> DFAに変換 (Memory-Major)
;; TensorをCopy (Speed-Major)

(defun deterministic-p (tensor)
  "Returns t if tensor's node is deterministic
[Any-Previous-Node]
    |
[AnyNode] <- The Given Tensor
    |"
  (declare (type AbstractTensor tensor))
  (= (length (tensor-variables tensor)) 1))

(defun non-deterministic-p (tensor)
  "Returns t if tensor's node is non-deterministic
[Node1] [Node2] ...
    |------|
[AnyNode] <- The Given Tensor
    |"
  (declare (type AbstractTensor tensor))
  (> (length (tensor-variables tensor)) 1))

(deftype node-state-t ()
  "The type node-state-t indicates the keywords that used to express node's transmission state."
  `(member :deterministic :non-deterministic))

(declaim (ftype (function (AbstractTensor) node-state-t) node-state))
(defun node-state (tensor)
  (if (deterministic-p tensor)
      :deterministic
      :non-deterministic))

(defun movetensor-p (node)
  (subtypep (class-of node) 'cl-waffe2/base-impl:MoveTensorNode))

(defmacro ignore-me? (node)
  `(cl-waffe2/base-impl:movetensor-ignore-me ,node))

(defmacro move-ignorable-p (node)
  `(cl-waffe2/vm.nodes:node-passed-p ,node))

(defun tensor-attribute (tensor)
  (declare (type AbstractTensor tensor))
  (let ((name (tensor-name tensor)))
    (typecase name
      (string  :chain) ;; :chain = auto-generated
      (keyword :input)
      (T       :input))))

(defun trace-and-explore-nodes! (out-tensor)
  "Incf tensor-ref-n
tensor-ref-n indicates that how many times the tensor was used in the node."
  (declare (type AbstractTensor out-tensor)
	   (optimize (speed 3)))
  (mapc
   #'(lambda (tensor)
       (incf (the fixnum (tensor-n-ref tensor)) 1)
       (trace-and-explore-nodes! tensor))
   (tensor-variables out-tensor)))

(defun trace-and-optimize-node! (out-tensor major n-cores)
  "TODO: DOC"
  (declare (type AbstractTensor out-tensor)
	   (type fixnum n-cores)
	   (optimize (speed 3))
	   (type (and keyword (member :speed :memory)) major))

  ;; TODO: (setf lparallel:*kernel* (make-kernel 4))

  ;; MoveTensor(Input/Parameter, ChainTMP) <- COPY it.
  ;; MoveTensor.n_ref = 1, 0 <- DONT COPY IT.
  
  (let* ((current-node   (tensor-backward out-tensor))
 	 (past-variables (tensor-variables out-tensor)))

    (when (and (movetensor-p current-node)
	       ;; (!copy place past-out) i.e. (!copy Chain Past-Out)
	       (eql (tensor-attribute (car past-variables)) :chain)
	       (let* ((prev-out (second past-variables))
		      (attr     (tensor-attribute prev-out)))
		 (and (<= (the fixnum (tensor-n-ref prev-out)) 1)
		      ;; prev-out is deterministic
		      (not (eql attr :input)))))
      (setf (ignore-me? current-node) t))

    (mapc
     #'(lambda (tensor)
	 (trace-and-optimize-node! tensor major n-cores))
     past-variables)))

(defun optimize-computation-node! (out-tensor major n-cores)
  "The function optimize-computation-node! do these works:

1. Optimize MoveTensorNode
2. Optimize the connection of ChainTMP
3. Scheduling the lparallel depending on their nodes and threads."
  (declare (type AbstractTensor out-tensor)
	   (type (and keyword (member :speed :memory)) major)
	   (type fixnum n-cores)
	   (optimize (speed 3)))
  (when (tensor-traced-p out-tensor)
    (error "The computation nodes are already optimized."))
  
  (trace-and-explore-nodes! out-tensor)
  (trace-and-optimize-node! out-tensor major n-cores)

  (setf (tensor-traced-p out-tensor) t))

