
(in-package :cl-waffe2/viz)

;; Print out to terminal

(defparameter *indent-level* 0)
(defparameter *indent-with* " ")

;; └┘
(defun dprint (toplevel &key (stream t) (print-device t) (indent-width 4) &aux (seen nil))
  "
## [function] dprint
"
  (declare (type AbstractNode))

  ;;(cl-waffe2/vm:disassemble-waffe2-ir toplevel)
  
  (labels ((indent (stream)
	     (dotimes (i *indent-level*) (princ *indent-with* stream)))
	   (print-tensor (stream tensor)
	     (let* ((tensor-name (format nil "┌<~a:~a>┐"
					 (if (slot-value tensor 'requires-grad)
					     "Param"
					     (if (eql (tensor-attribute tensor) :input)
						 "TMP"
						 "Input"))
					 (class-name (class-of tensor))))
		    (midpoint (floor (/ (length tensor-name) 2)))
		    (tensor-info (format nil "~a~a"
					 (tensor-id tensor)
					 (if (scalar-p tensor)
					     "(1)"
					     (shape tensor)))))
	       (indent stream)
	       (format stream "~a~%" tensor-name)
	       (indent stream)
	       (format stream "└")
	       
	       
	       (let ((*indent-level* (1- (- midpoint (floor (/ (length tensor-info) 2)))))
		     (*indent-with* "─"))
		 (indent stream)
		 (format stream "~a" tensor-info)
		 (indent stream)
		 (format stream "┘~%"))))
	   
	   (print-edge (stream tensor)
	     (let* ((node-name (cl-ppcre:split "-" (format nil "~a" (class-name (class-of (tensor-backward tensor))))))
		    (op-name (apply
			      #'concatenate
			      'string
			      (butlast node-name)))
		    (device-name (if print-device (format nil " ~a" (class-name (class-of tensor))) ""))
		    (line1       (format nil "┌Node:~a ~a┐" device-name op-name))
		    (midline (floor (/ (length line1) 2)))
		    (tensor-info (format nil "~a~a"
					 (tensor-id tensor)
					 (if (scalar-p tensor)
					     "(1)"
					     (shape tensor)))))
	       (indent stream)
	       (format stream "~a~%" line1)
	       (indent stream)
	       (format stream "└")
	       (let ((*indent-level* (1- (- midline (floor (/ (length tensor-info) 2)))))
		     (*indent-with* "─"))
		 (indent stream)
		 (format stream "~a" tensor-info)
		 (indent stream)
		 (format stream "┘~%"))))

	   (explore-node (stream tensor)
	     (when (null (find (tensor-iid tensor) seen))
	       (push (tensor-iid tensor) seen)
	       (if (or (detach-p tensor)
		       (null (tensor-backward tensor)))
		   (print-tensor stream tensor)
		   (print-edge stream tensor)))

	     (let ((*indent-level* (+ indent-width *indent-level*)))
	       (dolist (var (tensor-variables tensor))
		 (explore-node stream var)))))
    

    (format stream "~%~a"
	    (with-output-to-string (out)
	      (explore-node out toplevel)))
    toplevel))
