(define-module (aiscm bool)
  #:use-module (aiscm element)
  #:use-module (oop goops)
  #:use-module (rnrs bytevectors)
  #:export (<bool>
            <meta<bool>>
            make-bool
            pack
            unpack))
(define-class <meta<bool>> (<class>))
(define-class <bool> (<element>) #:metaclass <meta<bool>>)
(define (make-bool value)
  (make <bool> #:value value))
(define-method (equal? (a <bool>) (b <bool>))
  (equal? (slot-ref a 'value) (slot-ref b 'value)))
(define-method (pack (self <bool>))
  (u8-list->bytevector (list (if (slot-ref self 'value) 1 0))))
(define-method (unpack (self <meta<bool>>) (packed <bytevector>))
  (make-bool (if (eq? (car (bytevector->u8-list packed)) 0) #f #t)))
