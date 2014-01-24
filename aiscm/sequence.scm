(define-module (aiscm sequence)
  #:use-module (aiscm element)
  #:use-module (aiscm mem)
  #:use-module (aiscm pointer)
  #:use-module (aiscm lookup)
  #:use-module (aiscm lambda)
  #:use-module (aiscm var)
  #:use-module (ice-9 optargs)
  #:use-module (oop goops)
  #:export (sequence
            sequence->list))
(define-class <meta<sequence<>>> (<class>))
(define-class <sequence<>> (<element>) #:metaclass <meta<sequence<>>>)
(define (sequence type)
  (let* ((name (format #f "<sequence~a>" (class-name type)))
         (metaname (format #f "<meta~a>" name))
         (metaclass (make <class>
                          #:dsupers (list <meta<sequence<>>>)
                          #:slots '()
                          #:name metaname))
         (retval (make metaclass
                       #:dsupers (list <sequence<>>)
                       #:slots '()
                       #:name name)))
    (define-method (typecode (self metaclass)) type)
    (define-method (make (class metaclass) . initargs)
      (let-keywords initargs #f (size)
        (let* ((mem (make <mem> #:size (* (storage-size (typecode class)) size)))
               (ptr (make (pointer type) #:value mem))
               (var (make <var>))
               (lookup (make <lookup> #:value ptr #:var var #:stride 1)))
          (make <lambda> #:value lookup #:index var #:length size))))
    retval))
(define (sequence->list seq)
  (let ((n (get-length seq)))
    (if (> n 0)
      (cons (get seq 0) (sequence->list (slice seq 1 (- n 1))))
      '())))
(define-method (write (self <lambda>) port)
  (format port "#<sequence~a>:~&~a"
          (class-name (typecode self))
          (sequence->list self)))
(define-method (display (self <lambda>) port)
  (format port "#<sequence~a>:~&~a"
          (class-name (typecode self))
          (sequence->list self)))
