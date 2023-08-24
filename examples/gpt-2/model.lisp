
(in-package :gpt-2-example)

;; In order to measure the performance of Fusion Ops, I've deciced to make a inference on GPT-2 on cl-waffe2 in advance.

;; This file provides an example case of inferecing GPT-2 Model with cl-waffe2

;; [TODO] Python script Converting ONNX model into cl-waffe2 model (make any format? for cl-waffe2?)
;; [TODO] Add: EmbeddingLayer, !split !concatenate?


(defparameter *model-params*
  `((:n-vocab . 50257)
    (:n-ctx   . 1024)
    (:n-emb   . 768)
    (:n-head  . 12)
    (:n-layer . 12)))

(defmacro with-gpt2-config ((&key
			       (n-vocab 50257)
			       (n-ctx 1024)
			       (n-emb 786)
			       (n-head 12)
			       (n-layer 12))
			    &body
			      body)
  `(let ((*model-params*
	   `((:n-vocab . ,,n-vocab)
	     (:n-ctx   . ,,n-ctx)
	     (:n-emb   . ,,n-emb)
	     (:n-head  . ,,n-head)
	     (:n-layer . ,,n-layer))))
     ,@body))

(defun read-config (keyword)
  "(read-config :n-vocab) ;; => 50257"
  (let ((result (find keyword *model-params* :test #'eql :key #'car)))
    (if result
	(cdr result)
	(error "No such a keyword: ~a" keyword))))

(defmodel (GPT2Layer (self)
	   :slots ((ln-1-g)
		   (ln-1-b)
		   
		   (ln-2-g)
		   (ln-2-a)

		   ;; Attention
		   (attn-attn-w)
		   (attn-attn-b)

		   (attn-proj-w)
		   (attn-proj-b)

		   ;; MLP
		   (mlp-fc-w)
		   (mlp-fc-b)

		   (mlp-proj-w)
		   (mlp-proj-b))
	   :on-call-> ((self x)
		       x)))


(defmethod load-weights-layer ((self GPT2Layer))

  )


(defmodel (GPT2 (self)
	   :slots ((ln-f-g)
		   (ln-f-b)
		   (wte)
		   (wpe)
		   (lm-head)
		   (layers)
		   (memory-k)
		   (memory-v))
	   :on-call-> ((self x)

		       ;; repeat for nlayer
		       x)))

(defmethod load-weights-model ((self GPT2))
  (let ((n-layer (read-config :n-layer)))

    ))


