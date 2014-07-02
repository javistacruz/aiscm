(define-module (aiscm sequence)
  #:use-module (oop goops)
  #:use-module (ice-9 optargs)
  #:use-module (srfi srfi-1)
  #:use-module (aiscm element)
  #:use-module (aiscm util)
  #:use-module (aiscm mem)
  #:use-module (aiscm pointer)
  #:export (<meta<sequence<>>> <sequence<>>
            sequence
            sequence->list
            list->sequence))
(define-class <meta<sequence<>>> (<meta<element>>))
(define-class <sequence<>> (<element>)
              (size #:init-keyword #:size #:getter get-size)
              #:metaclass <meta<sequence<>>>)
(define (sequence type)
  (let* [(name (format #f "<sequence~a>" (class-name type)))
         (metaname (format #f "<meta~a>" name))
         (metaclass (def-once metaname (make <class>
                                             #:dsupers (list <meta<sequence<>>>)
                                             #:slots '()
                                             #:name metaname)))
         (retval (def-once name (make metaclass
                                      #:dsupers (list <sequence<>>)
                                      #:slots '()
                                      #:name name)))]
    (define-method (initialize (self retval) initargs)
      (let-keywords initargs #f (size value)
        (let* [(mem (make <mem> #:size (* (size-of type) size)))
               (ptr (or value (make (pointer type) #:value mem)))]
          (next-method self `(#:value ,ptr #:size ,size)))))
    (define-method (typecode (self metaclass)) type)
    retval))
(define-method (shape (self <sequence<>>)) (list (get-size self)))
(define-method (set (self <sequence<>>) (i <integer>) o)
  (begin (store (+ (get-value self) i) (make (typecode self) #:value o)) o))
(define-method (set (self <sequence<>>) o)
    (if (> (get-size self) 0)
      (begin (set self 0 (car o))
             (set (slice self 1 (- (get-size self) 1)) (cdr o))
             o)
      o))
(define-method (get (self <sequence<>>) (i <integer>))
  (get-value (fetch (+ (get-value self) i))))
(define-method (slice (self <sequence<>>) (offset <integer>) (size <integer>))
  (make (class-of self) #:value (+ (get-value self) offset) #:size size))
(define (sequence->list seq)
  (if (> (get-size seq) 0)
    (cons (get seq 0) (sequence->list (slice seq 1 (- (get-size seq) 1)))) '()))
(define (list->sequence lst)
  (let* [(t      (reduce coerce '() (map match lst)))
         (retval (make (sequence t) #:size (length lst)))]
    (set retval lst)
    retval))
(define-method (write (self <sequence<>>) port)
  (format port "#~a:~&~a" (class-name (class-of self)) (sequence->list self)))
(define-method (display (self <sequence<>>) port)
  (format port "#~a:~&~a" (class-name (class-of self)) (sequence->list self)))
(define-method (coerce (a <meta<sequence<>>>) (b <meta<element>>))
  (sequence (coerce (typecode a) b)))
(define-method (coerce (a <meta<element>>) (b <meta<sequence<>>>))
  (sequence (coerce a (typecode b))))
(define-method (coerce (a <meta<sequence<>>>) (b <meta<sequence<>>>))
  (sequence (coerce (typecode a) (typecode b))))
