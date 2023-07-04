
(in-package :cl-waffe2/vm.generic-tensor)

;; Here we provide two macros:
;; define-tensor (Tensors and Backend are strongly combined.)
;; CFFI-Style
;; Column-Major And Row-Major
;; TODO: Detect it: (make-tensor `(10 a)) <- use (make-input)

(defparameter *using-backend*
  `()
  "cl-waffe searches for computation nodes in the following order and uses the first one it finds. (Priority1 Priority2 ...)
Default: `(cl-waffe2/vm.generic-tensor:CPUTensor)
PriorityN must be a subclass of cl-waffe2/vm.generic-tensor:AbstractTensor")

(defparameter *default-dtype* :float  "")
(defparameter *default-order* :column "")

(defparameter *with-printing-tensor-omitted* nil "If t, the displayed tensor is omitted")

(defun order-p (name)
  (declare (type keyword name))
  (or (eql name :column) (eql name :row)))

(defclass AbstractTensor ()
  ((nodes :initarg :nodes :initform nil :reader tensor-nodes :type list) ;; maybe unused...

   ;; MultiDimensional APIs
   (orig-shape :initarg :shape :initform nil :reader original-shape :type list)
   (stride :initform nil :accessor tensor-stride :type list)
   (visible-shape :initform nil :reader shape :accessor tensor-visible-shape :type list)
   (view :initarg :view :initform nil :accessor tensor-view :type list)

   ;; Viewed?
   (projected-p :initarg :projected-p :initform nil :type boolean :reader tensor-projected-p)

   ;; Is it scalar?
   (scalar-p :initarg :scalar-p :initform nil :reader scalar-p)
   (detach-p :initform nil :accessor detach-p)
   ;; vec container
   (vec :initarg :vec :initform nil :reader vec :writer write-vec)
   (dtype :initform :float :initarg :dtype :reader dtype)

   ;; Building Computation Nodes
   (backward  :initform nil :accessor tensor-backward)
   (state     :initform nil :accessor tensor-state)
   (variables :initform nil :accessor tensor-variables)

   (tensor-id :initform (gensym "TID") :accessor tensor-id)
   (nth-value :initform 0 :accessor tensor-out-n :type fixnum)

   (grad :initform nil :reader grad :writer set-grad)
   (gradient-adder :accessor gradient-adder)

   (save-for-backward-space :initform nil :accessor save-for-backward-space)
   (save-for-backward-cloner :initform nil :accessor save-for-backward-cloner)
   
   (requires-grad :initform nil :initarg :requires-grad :reader requires-grad :type boolean)
   (ancestor-param-p :initarg :requires-grad :initform nil :accessor ancestor-param-p :type boolean)
   (order :initarg :order :initform :column :type (satisfies order-p) :accessor order)
   (flexible-p :initform nil :accessor tensor-flexible-p :type boolean)
   (tensor-n-ref :initform 0 :accessor tensor-n-ref :type fixnum) ;; For optimizing
   (tensor-already-traced :initform nil :accessor tensor-traced-p :type boolean)
   
   (facet :initarg :facet :initform :exist :type (member :exist :input) :accessor tensor-facet)
   (named :initform :tensor :initarg :named :type keyword :accessor tensor-name)

   (input-shape :initarg :input-shape :initform nil :accessor tensor-input-shape))
  (:documentation "
AbstractTensor is a primal class for all devices. Each devices (e.g.: `ScalarTensor` `LispTensor` `CPUTensor` etc...) is a subclass of this.

The class provides the fundamental and necessary features for tensors.

1. Lazy-Evaluated and Multi-Dimensional APIs, stride computations.

2. `View APIs` multi-dimensional offsets

3. To construct backward, AbstractTensor records variables called with.

4. `vec` container.

5. an space for saving gradients, copies for backward.

6. Lazy-Evaluated Shapings

7. Trace Informations for JIT to create well-optimized computation node.

### Creating a new backend.

Users can create a new backend by extending this abstract class.

```lisp
(defclass MyBackend (AbstractNode) nil)
```

To use the `MyBackend` as a tensor, users also has to override these methods:

1. `initialize-instance` ... An allocator for tensor's vec.

2. `vref` `(setf vref)` ... an generic function to access/write tensor's vec.

```lisp
;; TODO: Establish a common API for initargs
(defmethod initialize-instance :before ((tensor MyBackend)
					&rest initargs
					&key &allow-other-keys)
  ;; if projected-p -> alloc new vec
  (let* ((shape (getf initargs :shape))
 	 (dtype (dtype->lisp-type (getf initargs :dtype)))
	 (vec   (getf initargs :vec))
	 (facet (getf initargs :facet))
	 (initial-element (coerce (or (getf initargs :initial-element) 0) dtype)))
    (when (eql facet :exist)
      (if vec
	  (setf (tensor-vec tensor) vec)
	  (setf (tensor-vec tensor) ;; vec can be anything.
		(make-array
		 (apply #'* shape)
		 :element-type dtype
		 :initial-element initial-element))))))
```

```lisp
(defmethod vref ((tensor MyBackend) index)
  (aref (tensor-vec tensor) index))

(defmethod (setf vref) (new-value (tensor MyBackend) index)
  (setf (aref (tensor-vec tensor) index) new-value))
```

Now, the name `MyBackend` is available as a brand-new cl-waffe2 backend!

Users can define a new implementation following `(define-impl (Name :device MyBackend) ...)`

(See the examples to understand how this could be achieved at ./source/backends/lisp/tensor.lisp. or ./source/backends/cpu.)

### [function] shape

Returns a visible shape of tensor

### [function] dims

Returns the number of axes of tensor

### [function] total

Returns the number of total visible elements in tensor.

### [slot] orig-shape (List)

the original shape of `vec`. `(apply #'* orig-shape)` must correspond with the number of total elements of `vec`.

### [slot] stride (list)

An stride of tensor, can be chosen from `:column` `:row`.

This slot can be accessed by `(tensor-stride object)`.

### [slot] visible-shape (list)

An shape of visible-area of tensor, visible-area is that an viewed size of tensor.

Can be accessed by `(shape object)`

### [slot] view (list)

An list of multidimensional offsets, view.

Can be accessed by `(tensor-view object)`

### [slot] projected-p (boolean)

Set t if `(apply #'* orig-shape) == (apply #'* visible-shape)` otherwise set nil.

If t, the tensor is produced by `!view` or `view` functions.

### [slot] scalar-p

If t, the tensor is regarded as a Scalar.

### [slot] detach-p

If t, JIT compilers stop tracing at the tensor.

### [slot] state

Stores a corresponding `StateContainer`.

### [slot] variables

`(tensor-variables object)`

Records variables called with the tensor.

### [slot] tensor-id (symbol)

Corresponding variable name that used in JIT compiler.

### [slot] grad (AbstractTensor)

If the tensor is a parameter, (i.e.: requires-grad t) and backward propagation has called, the gradients has set to this slot.

Reader: `(grad object)`.  Writer: `(set-grad object value)`

### [slot] backward (AbstractNode)

the node called with.

### [slot] requires-grad (Boolean)

If t, the tensor become a `parameter` that gradients are saved.

### [slot] ancestor-param-p (Boolean)

If t, the tensor has created by `parameter` or tensors whose ancestor-param-p=t.

### [slot] flexible-p (Boolean)

If t, the tensor is `broadcastable`

### [slot] facet (keyword)

Tensors has a two state:

1. :input

2. :exist

`:exist` tensor is a just normal state, which `vec` is already allocated.

`:input` tensor is a lazy-evaluated tensor, which allocation will be done until they're really needed. (often used as a cache, or training data.)
...

"))

(defun total (tensor)
  (declare (type AbstractTensor tensor))
  (apply #'lazy-mulup (shape tensor)))

(defun dims (tensor)
  (declare (type AbstractTensor tensor))
  (length (shape tensor)))

(defmethod tensor-delete ((tensor AbstractTensor))
  ""
  nil
  )

;; Inline
;;(declaim (inline tensor-vec))
(defun tensor-vec (tensor)
  "

## [function] tensor-vec

The function tensor-vec has a multiple behaviours depending on the state of tensor.

1. If the given tensor is existing, or is input but allocated. -> Returns the given tensor's vec.

2. If the given tensor is Input, and still not yet being accessed. -> Allocates the new area for matrix, and set tensor's vec slot it. The allocated area of tensor is returned.

In a short words:

```
In general, tensor-vec is a function where:
  Input  -> AbstractTensor
  Output -> The tensor's vec slot (depends on their kernel)
```

By using `tensor-vec`, allocation of InputTensor will be done until they're really needed.

Note:

1. this function is inlined.

2. this function is setfable
"
  (declare (type AbstractTensor tensor))

  (cond
    ((and
      (not (scalar-p tensor))
      (stringp (tensor-name tensor))) ;; ChainTMP Vector -> get-from-memory-pool is MUST
     (get-from-memory-pool tensor))
    (T
     (if (or (null (tensor-name tensor))
	     (vec tensor))
	 (vec tensor) ;; tensor is created by make-tensor
	 (get-from-memory-pool tensor)))))

(defun (setf tensor-vec) (new-value tensor)
  (declare (type AbstractTensor tensor))
  (write-vec new-value tensor))

(defun make-gradient-adder (target shape)
  "Returns a instant-kernel to add the new-gradient to given target."
  (let ((out (make-input shape nil
			 :dtype (dtype target)
			 :order (order target))))
    (let ((*no-grad* t))
      (let* ((node-out (cl-waffe2/vm.nodes:forward (cl-waffe2/base-impl:AddNode (dtype (grad target))) (grad target) out))
	     (forward-fn (compile-forward-kernel node-out)))
	#'(lambda (new-value)
	    (assert (equal (shape new-value) shape)
		    nil
		    "Attempted to add a new grad: ~a to ~a but failed due to shaping problems."
		    (shape new-value)
		    shape)
	    (embody-actual-tensor out new-value)
	    (state-reset! node-out)
	    (funcall forward-fn)
	    nil)))))

(defun make-gradient-adder-scal (target)
  #'(lambda (new-value)
      (assert (scalar-p new-value)
	      nil
	      "Attempted to add a new grad but failed because the gradient isn't scalar")
      (incf (tensor-vec (grad target)) (tensor-vec new-value))
      nil))

(defmethod initialize-instance :after ((tensor AbstractTensor) &rest initargs &key &allow-other-keys)
  (let ((scalar-p   (getf initargs :scalar-p))
	(view       (getf initargs :view))
	(order      (getf initargs :order))
	(orig-shape (getf initargs :shape)))

    ;; orig-shape = used to compute strides.
    (setf (slot-value tensor 'orig-shape)  orig-shape)
    (setf (slot-value tensor 'projected-p) (getf initargs :projected-p))

    (setf (slot-value tensor 'ancestor-param-p) (ancestor-param-p tensor))
    
    (cond
      ((eql (getf initargs :facet) :input)
       (when (not scalar-p)
	 (setf (tensor-stride tensor) (calc-strides orig-shape order))
	 (setf (tensor-view tensor)
	       (parse-view-subscripts tensor (getf initargs :past-view) (or view `(t))))
	 (setf (tensor-visible-shape tensor)
	       (compute-visible-shape orig-shape (tensor-view tensor)))
	 nil))
      (T
       (when (not scalar-p)
	 (setf (tensor-stride tensor) (calc-strides orig-shape order))
	 (setf (tensor-view tensor) (parse-view-subscripts tensor (getf initargs :past-view) (or view `(t))))
	 (setf (tensor-visible-shape tensor)
	       (compute-visible-shape orig-shape (tensor-view tensor)))
	 nil)))

    ;; Setup utils for collecting gradients.
    (when (slot-value tensor 'requires-grad)
      (if (scalar-p tensor)
	  (set-grad (make-tensor 0
				 :dtype (dtype tensor)
				 :requires-grad nil)
		    tensor)
	  (set-grad (make-tensor
		     (tensor-visible-shape tensor)
		     :dtype (getf initargs :dtype)
		     :requires-grad nil
		     :order (getf initargs :order))
		    tensor))
      (if (scalar-p tensor)
	  (setf (gradient-adder tensor)
		(make-gradient-adder-scal tensor))
	  (setf (gradient-adder tensor)
		(make-gradient-adder tensor (tensor-visible-shape tensor)))))))

(defmethod add-grads ((tensor AbstractTensor) new-value)
  "tensor's gradient += new-value"
  (assert (slot-value tensor 'requires-grad)
	  nil
	  "Assertion Failed with requires-grad = t")
  (funcall (gradient-adder tensor) new-value))

;; (defmethod init-grads ())
(defmacro assure-dimensions (mat1 mat2)
  "Does nothing if mat1 and mat2 has a completely the same shape, otherwise throws shaping-error."
  `(if (equal (the list (shape ,mat1)) (the list (shape ,mat2)))
       t
       (shaping-error "Assertion Failed because two matrices ~a and ~a couldn't operated together." (shape ,mat1) (shape ,mat2))))


(defmethod calc-strides ((shape list) (order (eql :column)))
  "Computes column-major-strides"
  (column-major-calc-strides shape))

(defmethod calc-strides ((shape list) (order (eql :row)))
  "Computes row-major-strides"
  (row-major-calc-strides shape))

(defun make-tensor (shape-or-scalar
		    &key
		      (requires-grad nil)
		      (dtype *default-dtype*)
		      (vec  nil)
		      (view nil)
		      (order *default-order*)
		      (initial-element))
  "
## [function] make-tensor

```
(make-tensor shape-or-scalar
		   &key
		      (requires-grad nil)
		      (dtype *default-dtype*)
		      (vec  nil)
		      (view nil)
		      (order *default-order*)
		      (initial-element))
```

Refering a first-priority of  *using-backends* (i.e.: `car` of `*using-backends*`) to know what device to use, the function `make-tensor` creates and allocate a new matrix instantly.

### Input

1. `shape-or-scalar (Any)` set list (consisted of fixnum) here to create a matrix, otherwise the ScalarTensor is forcibly created.

2. `requires-grad` (Boolean) Set t to create gradient. (e.g.: the tensor is needed to be optimized.)

3. `dtype` (keyword) Set dtype you wanna use. See also: (Dtype API)

4. `vec` (Anything) If you wanna pass the make-instance to already-allocated matrix, use this parameter.

5. `order` (member :column :row)

6. `initial-element` (Optional)
"
  (declare (type list view)
	   (ignore vec))
  (if (typep shape-or-scalar 'list)
      (make-instance (car *using-backend*)
		     :dtype dtype
		     :order order
		     :requires-grad requires-grad
		     :shape shape-or-scalar
		     :projected-p nil
		     :facet :exist
		     :initial-element initial-element
		     :view view)
      (make-instance 'ScalarTensor
		     :scalar-p t
		     :vec (coerce shape-or-scalar (dtype->lisp-type dtype))
		     :shape nil
		     :dtype dtype
		     :requires-grad requires-grad
		     :projected-p nil
		     :facet :exist
		     :view view)))

;; It is allowed: (make-input `(batch-size 512))
(defun make-input (shape
		   named
		   &key
		     (scalar-p nil)
		     (dtype *default-dtype*)
		     (order *default-order*))
  "
## [function] make-input

Referring a first-priority of `*using-backend*` (i.e.: car part), the function make-input creates a InputTensor.

In contrast to `make-tensor`, allocation of `vec` is lazy-evaluated, and `shape` can include symbols. (Lazy-Evaluated Shape).

For example, whichever `(make-input (list 256 256 256 ... 256 256 256) nil)` or `(make-input (list 256) nil)` is called, the memory-usage is the same until `(tensor-vec tensor)` is called but the moment `(tensor-vec tensor)` is called, the first one would cause `CUDA OUT OF MEMORY` or something :(.

### Inputs

`Shape` [list] consisted of fixnum or symbol. (e.g.: `(a 10)` is OK for make-input.)

`Named` [keyword] the name of input. If nil, the tensor is regarded as just cache. If you want to change the content of inputs later (e.g.: training data), set an appropriate name to `InputTensor` (e.g.: `:training-data` `:train-x`).

`scalar-p` [boolean] set t is the input is scalar.

`dtype` [keyword] as it is.

`order` [keyword] an member of :column :row
"
  (declare (type list shape)
	   (type (or null keyword) named))
  (make-instance (if scalar-p 'ScalarTensor (car *using-backend*))
		 :scalar-p scalar-p
		 :dtype dtype
		 :order order
		 :shape shape
		 :input-shape shape
		 :named (or named (symbol-name (gensym "ChainTMP")))
		 :facet :input))

(defun mref (tensor &rest subscripts)
  "The function mref is only used to print/initialize tensors, accessing the index of subscripts **with** considering views..

If you cares about performance, dont' use `mref`, but `!view`.

This function is setfable."
  (declare (type list subscripts))
  (assert (not (null (vec tensor)))
	  nil
	  "Can't reference tensors which doesn't have a existing vec.")
  (vref tensor
	(apply #'+
	       (map 'list
		    #'(lambda (stride s view shape)
			(declare (ignore shape))
			(* stride (compute-stepby (subscript-view view))
			   (+ s (compute-visible-start-idx (subscript-view view)))))
		    (tensor-stride tensor)
		    subscripts
		    (tensor-view tensor)
		    (slot-value tensor 'orig-shape)))))

;; Note that mref is super slow and only used in a limited situation.
(defun (setf mref) (new-value tensor &rest subscripts)
  (declare (type list subscripts))
  
  (assert (not (null (vec tensor)))
	  nil
	  "Can't reference tensors which doesn't have a existing vec.")

  (setf (vref tensor
	      (apply #'+
		     (map 'list
			  #'(lambda (stride s view shape)
			      (declare (ignore shape))
			      (* stride (compute-stepby (subscript-view view))
				 (+ s (compute-visible-start-idx (subscript-view view)))))
			  (tensor-stride tensor)
			  subscripts
			  (tensor-view tensor)
			  (slot-value tensor 'orig-shape))))
	new-value))

;; If you've created a new backend with different ptr, only you have to do is to define vref.
(defmethod vref ((tensor AbstractTensor) index)
  "`vref` is a generic-function to access the `vec` slot of specific backends tensor, and returns `index`th element on `vec` slot **without** considering views.

If you added a new backend with having different ptr-type (can't be accessed by aref), override this method and `(setf vref)`.

### Example

```lisp
(defmethod vref ((tensor YourBackend) index)
    (aref (tensor-vec tensor) index))

(defmethod (setf vref) (new-value (tensor YourBackend) index)
    (setf (aref (tensor-vec tensor) index) new-value))
```
"
  (declare (type fixnum index))
  (assert (not (null (vec tensor)))
	  nil
	  "Can't reference tensors which doesn't have a existing vec.")
  (aref (tensor-vec tensor) index))

(defmethod (setf vref) (new-value (tensor AbstractTensor) index)
    "An setfable version of vref."
  (declare (type fixnum index))
  (assert (not (null (vec tensor)))
	  nil
	  "Can't reference tensors which doesn't have a existing vec.")
  (setf (aref (tensor-vec tensor) index) new-value))

;; input <- actual
(defun embody-actual-tensor (input-tensor actual-tensor)
  "Moves actual-tensor(ExistTensor) -> input-tensor(InputTensor). (Pointers are shared.)"
  (declare (type AbstractTensor input-tensor actual-tensor))

  ;;(assert (eql (tensor-facet input-tensor) :input)
  ;;	  nil
  ;;	  "Assertion Failed with (eql (tensor-facet input-facet) :input)")

  (assert (vec actual-tensor)
	  nil
	  "Assertion Failed because the given actual-tensor doesn't have a existing vec.")

  (when (and (numberp (vec input-tensor))
	     (numberp (vec actual-tensor)))
    (setf (tensor-vec input-tensor) (tensor-vec actual-tensor))
    (return-from embody-actual-tensor t))

  ;; Offsets?
  (setf (tensor-vec input-tensor) (tensor-vec actual-tensor)
	(slot-value input-tensor 'orig-shape) (slot-value actual-tensor 'orig-shape)
	(tensor-view input-tensor) (tensor-view actual-tensor)
	(tensor-stride input-tensor) (tensor-stride actual-tensor)
	(tensor-visible-shape input-tensor) (tensor-visible-shape actual-tensor)

	(slot-value input-tensor 'projected-p) (slot-value actual-tensor 'projected-p)
	)
  t)

(defun view (tensor &rest subscripts)
  "The function view creates a view of given tensor.
Note that the function *view* doesn't records ANY NODES, while the function *!view* does.

Subscripts can be following:

- fixnum
- (start stop)
- (start stop by)
- t
- (:indices ...)
- (:tflist ...)
- (:broadcast fixnum)

Note that view is only created for Tensors, not a Scalar.
"
  ;; TODO: When tensor is scalar, return error.

  (let ((subscripts
	  (loop for s in subscripts collect (force-list s))))
    (when (typep tensor 'ScalarTensor)
      (if (and subscripts
	       (not (every #'(lambda (x) (eql t x)) subscripts)))
	  (format t ":BROADCAST IS IGNORED for scalar input (TODO)"))
      (return-from view tensor))

    (make-instance (car *using-backend*)
		   :dtype (dtype tensor)
		   :order (order tensor)
		   :requires-grad (slot-value tensor 'requires-grad)
		   :shape         (slot-value tensor 'orig-shape)
		   :projected-p   t
		   :past-view (tensor-view tensor)
		   :view subscripts
		   :input-shape (tensor-input-shape tensor)
		   :facet (tensor-facet tensor)
		   :named (tensor-name tensor)
		   :vec (vec tensor))))

(defun detach! (tensor)
  "detach tensor from computation node."
  (setf (detach-p tensor) t)
  tensor)

(defun parameter (tensor)
  "

## [function] parameter

```
(parameter tensor)
```

The function parameter computes all the previous nodes of the given tensor if any, returning the new tensor with `requires-grad=t`.

### Example

```lisp
(parameter (randn `(3 3)))
```

"
  
  (declare (type AbstractTensor tensor))
  (let ((out (cl-waffe2/base-impl:proceed tensor)))
    (setf (tensor-facet out) :exist)
    (setf (slot-value out 'requires-grad) t)
    (setf (tensor-name out) nil)
    (if (scalar-p tensor)
	(make-tensor (tensor-vec tensor)
		     :requires-grad t
		     :dtype (dtype tensor)
		     :order (order tensor))
	(view out))))


(defun render-shape (tensor)
  "Returns a shape"
  (let ((flexible-p (tensor-flexible-p tensor))
	(shape      (shape tensor)))
    (with-output-to-string (str)
      (format str "(")
      (when flexible-p
	(format str "<1 x N> "))
      (loop for i upfrom 0
	    for s in shape
	    do (format str "~a" s)
	    unless (= i (1- (length shape))) ;; unless the last
	      do (format str " "))
      (format str ")"))))

(defun state-name (tensor state)
  (declare (type StateContainer state))
  (let ((f-exist-p (statecontainer-forward-result state))
	(b-exist-p (statecontainer-backward-result state)))
    (cond
      ((subtypep (class-of (tensor-backward tensor))
		 'cl-waffe2/base-impl::ProceedNode)
       :computed)
      ((and (null f-exist-p)
	    (null b-exist-p))
       :maybe-not-computed)
      ((and (null b-exist-p))
       :wait-for-backward)
      (T
       :wait-for-reset))))

(defmethod print-object ((tensor AbstractTensor) stream)

  (when *with-printing-tensor-omitted*
    (format stream "<<~a Tensor (Omitted)>>" (shape tensor))
    (return-from print-object))
  
  (format stream
	  "{~a[~(~a~)] ~a ~a ~a
  ~a
  :facet :~(~a~)
  :requires-grad ~a
  :backward ~a}"
	  (class-name (class-of tensor))
	  (dtype tensor)
	  (if (slot-value tensor 'scalar-p)
	      ""
	      (cond
		((null (slot-value tensor 'projected-p))
		 ;; Orig-Shape
		 (format nil ":shape ~a" (render-shape tensor)))
		(T
		 ;; It has a view
		 (format nil ":shape ~a -> :view ~a -> :visible-shape ~a"
			 (slot-value tensor 'orig-shape)
			 (slot-value tensor 'view)
			 (render-shape tensor)))))
	  (if (eql (tensor-facet tensor) :input)
	      (format nil ":named ~a" (tensor-name tensor))
	      "")
	  (let ((state (tensor-state tensor)))
	    (if state
		;; TODO: Update vec-state
		(format nil "~%  :vec-state [~(~a~)]" (state-name tensor state))
		""))
	  (if (and (eql (tensor-facet tensor) :input)
		   (null (vec tensor)))
	      (format nil "<<Not-Embodied ~a Tensor>>" (shape tensor))
	      ;; TODO: View -> View for printing 3d, 4d... tensor.
	      (render-tensor tensor :indent 2))
	  (tensor-facet tensor)
	  (slot-value tensor 'requires-grad)
	  (tensor-backward tensor)))


;; FixME:
;; The Problem is that: after calling forward :around, set-save-for-backward is called.
(defun set-save-for-backward (tensor)
  ;; FIXME: How to ignore save-for-backward when predicting? compiling again?
  (let ((space-tmp (make-clone tensor)))
    ;;(setf (save-for-backward-space tensor) tensor)
    (let ((result (cl-waffe2/base-impl:!move space-tmp tensor :force t)))
      (setf (save-for-backward-space result) tensor)
      ;; result = space-tmp
      result)))

;; read-save-for-backward is actually working, but the problem is movetensor doesn't tell the variable well.
(defun read-save-for-backward (tensor)
  (save-for-backward-space tensor))


