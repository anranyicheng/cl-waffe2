
(in-package :cl-user)

(defpackage :cl-waffe2-asd
  (:use :cl :asdf :uiop))

(in-package :cl-waffe2-asd)

(defsystem :cl-waffe2
  :author "hikettei"
  :licence "MIT"
  :description "Deep Learning Framework"
  :pathname "source"
  :serial t
  :depends-on (:cl-ppcre :fiveam :alexandria)
  :components ((:file "vm/generic-tensor/package")
	       (:file "vm/generic-tensor/conditions")
	       (:file "vm/generic-tensor/utils")
	       (:file "vm/generic-tensor/view")
	       (:file "vm/generic-tensor/tensor")
	       (:file "vm/generic-tensor/default-impls")
	       (:file "vm/generic-tensor/acceptor")
	       

	       (:file "vm/nodes/package")
	       (:file "vm/nodes/shape")
	       (:file "vm/nodes/node")
	       (:file "vm/nodes/conditions")
	       (:file "vm/nodes/defnode")
	       
	       )
  :in-order-to ((test-op (test-op cl-waffe2/test))))

(defpackage :cl-waffe2-test
  (:use :cl :asdf :uiop))

(in-package :cl-waffe2-test)

(defsystem :cl-waffe2/test
  :author "hikettei"
  :licence "MIT"
  :description "Tests for cl-waffe2"
  :serial t
  :pathname "source"
  :depends-on (:cl-waffe2 :fiveam)
  :components ((:file "vm/generic-tensor/t/package")
	       
	       (:file "vm/nodes/t/package")
	       (:file "vm/nodes/t/parser")
	       (:file "vm/nodes/t/shape")

	       )
  :perform (test-op (o s)
		    (symbol-call :fiveam :run! :test-nodes)
		    ))
