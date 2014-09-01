(define-module (aiscm sequence)
  #:use-module (oop goops)
  #:use-module (ice-9 optargs)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (aiscm element)
  #:use-module (aiscm pointer)
  #:use-module (aiscm util)
  #:use-module (aiscm mem)
  #:export (<meta<sequence<>>> <sequence<>>
            sequence multiarray multiarray->list list->multiarray strides
            dump crop project rebase roll unroll downsample))
(define-generic element-type)
(define-class <meta<sequence<>>> (<meta<element>>))
(define-class <sequence<>> (<element>)
              (shape #:init-keyword #:shape #:getter shape)
              (strides #:init-keyword #:strides #:getter strides)
              #:metaclass <meta<sequence<>>>)
(define-method (sequence-name (type <meta<element>>))
  (format #f "<sequence~a>" (class-name type)))
(define-method (sequence-name (type <meta<sequence<>>>))
  (format #f "<multiarray~a,~a>" (class-name (typecode type)) (1+ (dimension type))))
(define (default-strides shape)
  (map (compose (cut apply * <>) (cut take shape <>)) (upto 0 (1- (length shape)))))
(define (sequence type)
  (let* [(name      (sequence-name type))
         (metaname  (format #f "<meta~a>" name))
         (metaclass (def-once metaname (make <class>
                                             #:dsupers (list <meta<sequence<>>>)
                                             #:name metaname)))
         (retval    (def-once name (make metaclass
                                         #:dsupers (list <sequence<>>)
                                         #:name name)))]
    (define-method (initialize (self retval) initargs)
      (let-keywords initargs #f (shape size value strides)
        (let* [(value   (or value (make <mem>
                                   #:size (* (size-of (typecode type))
                                             (or size (apply * shape))))))
               (shape   (or shape (list size)))
               (strides (or strides (default-strides shape)))]
          (next-method self (list #:value value #:shape shape #:strides strides)))))
    (define-method (element-type (self metaclass)) (pointer type))
    (define-method (dimension (self metaclass)) (1+ (dimension type)))
    (define-method (typecode (self metaclass)) (typecode type))
    retval))
(define-method (pointer (target-class <meta<sequence<>>>)) target-class)
(define (multiarray type dimension)
  (if (zero? dimension) (pointer type) (multiarray (sequence type) (1- dimension))))
(define-method (size (self <sequence<>>)) (apply * (shape self)))
(define (project self)
  (make (element-type (class-of self))
        #:value   (get-value self)
        #:shape   (all-but-last (shape self))
        #:strides (all-but-last (strides self))))
(define-method (crop (n <integer>) (self <sequence<>>))
  (make (class-of self)
        #:value   (get-value self)
        #:shape   (attach (all-but-last (shape self)) n)
        #:strides (strides self)))
(define-method (crop (n <null>) (self <sequence<>>)) self)
(define-method (crop (n <pair>) (self <sequence<>>))
  (crop (last n) (roll (crop (all-but-last n) (unroll self)))))
(define (rebase value self)
  (make (class-of self) #:value value #:shape (shape self) #:strides (strides self)))
(define-method (dump (offset <integer>) (self <sequence<>>))
  (let [(value (+ (get-value self) (* offset (last (strides self)) (size-of (typecode self)))))]
    (rebase value (crop (- (last (shape self)) offset) self))))
(define-method (dump (n <null>) (self <sequence<>>)) self)
(define-method (dump (n <pair>) (self <sequence<>>))
  (dump (last n) (roll (dump (all-but-last n) (unroll self)))))
(define (element offset self) (project (dump offset self)))
(define-method (fetch (self <sequence<>>)) self)
(define-method (get (self <sequence<>>) . args)
  (if (null? args) self (get (fetch (fold-right element self args)))))
(define-method (set (self <sequence<>>) . args)
  (store (fold-right element self (all-but-last args)) (last args)))
(define-method (store (self <sequence<>>) value)
  (for-each (compose (cut store <> value) (cut element <> self))
            (upto 0 (1- (last (shape self)))))
  value)
(define-method (store (self <sequence<>>) (value <null>)) value)
(define-method (store (self <sequence<>>) (value <pair>))
  (store (project self) (car value))
  (store (dump 1 self) (cdr value))
  value)
(define-method (multiarray->list self) self)
(define-method (multiarray->list (self <sequence<>>))
  (map (compose multiarray->list (cut get self <>)) (upto 0 (1- (last (shape self))))))
(define-method (shape (self <null>)) #f)
(define-method (shape (self <pair>)) (attach (shape (car self)) (length self)))
(define (list->multiarray lst)
  (let* [(type   (reduce coerce #f (map match (flatten lst))))
         (shape  (shape lst))
         (retval (make (multiarray type (length shape)) #:shape shape))]
    (store retval lst)
    retval))
(define (to-string self)
  (define (finish-sequence lst)
    (string-append "(" (string-join lst " ") ")"))
  (define (finish-multiarray lst)
    (let [(intermediate (cons (string-append "(" (car lst))
                         (map (cut string-append " " <>) (cdr lst))))]
      (attach (all-but-last intermediate) (string-append (last intermediate) ")"))))
  (define (recur self w h)
    (if (zero? (size self))
      '()
      (if (eqv? (dimension self) 0)
        (format #f "~a" (get-value (fetch self)))
        (let [(head (recur (project self) (- w 2) h))]
         (cond
           ((eqv? (dimension self) 1)
            (let [(len (string-length head))]
             (if (<= w len)
               (list "...")
               (cons head (recur (dump 1 self) (- w len 1) h)))))
           ((eqv? (dimension self) 2)
            (let [(conv (finish-sequence head))]
             (if (<= h 1)
               (list conv)
               (cons conv (recur (dump 1 self) w (- h 1))))))
           (else
             (let [(conv (finish-multiarray head))
                   (len   (length head))]
               (if (<= h len)
                 conv
                 (append conv (recur (dump 1 self) w (- h len)))))))))))
  (let [(lst (recur self 80 11))]
    (if (<= (dimension self) 1)
      (finish-sequence lst)
      (if (> (length lst) 10)
        (string-join (attach (all-but-last (finish-multiarray lst)) " ...") "\n")
        (string-join (finish-multiarray lst) "\n")))))
(define-method (write (self <sequence<>>) port)
  (format port "#~a:~&~a" (class-name (class-of self)) (to-string self)))
(define-method (display (self <sequence<>>) port)
  (format port "#~a:~&~a" (class-name (class-of self)) (to-string self)))
(define-method (coerce (a <meta<sequence<>>>) (b <meta<element>>))
  (multiarray (coerce (typecode a) b) (dimension a)))
(define-method (coerce (a <meta<element>>) (b <meta<sequence<>>>))
  (multiarray (coerce a (typecode b)) (dimension b)))
(define-method (coerce (a <meta<sequence<>>>) (b <meta<sequence<>>>))
  (multiarray (coerce (typecode a) (typecode b)) (max (dimension a) (dimension b))))
(define (roll self) (make (class-of self)
        #:value   (get-value self)
        #:shape   (cycle (shape self))
        #:strides (cycle (strides self))))
(define (unroll self) (make (class-of self)
        #:value   (get-value self)
        #:shape   (uncycle (shape self))
        #:strides (uncycle (strides self))))
(define-method (downsample (n <integer>) (self <sequence<>>))
   (let [(shape   (shape self))
         (strides (strides self))]
     (make (class-of self)
           #:value   (get-value self)
           #:shape   (attach (all-but-last shape) (quotient (+ (1- n) (last shape)) n))
           #:strides (attach (all-but-last strides) (* n (last strides))))))
(define-method (downsample (n <null>) (self <sequence<>>)) self)
(define-method (downsample (n <pair>) (self <sequence<>>))
  (downsample (last n) (roll (downsample (all-but-last n) (unroll self)))))
