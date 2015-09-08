(use-modules (oop goops)
             (system foreign)
             (aiscm element)
             (aiscm rgb)
             (aiscm int)
             (aiscm float)
             (guile-tap))
(planned-tests 7)
(define c (make <ubytergb> #:red 1 #:green 2 #:blue 3))
(ok (equal? (rgb (integer 8 unsigned)) (rgb (integer 8 unsigned)))
    "equality of RGB types")
(ok (eqv? 3 (size-of (rgb <ubyte>)))
    "storage size of unsigned byte RGB")
(ok (eqv? 12 (size-of (rgb (floating-point single-precision))))
    "storage size of single-precision floating-point RGB")
(ok (eq? <int> (type <intrgb>))
    "type of RGB channel")
; TODO: extract "type"
(ok (equal? c (make <ubytergb> #:red 1 #:green 2 #:blue 3))
    "equal RGB objects")
(ok (not (equal? c (make <ubytergb> #:red 1 #:green 4 #:blue 3)))
    "unequal RGB objects")
(ok (equal? #vu8(#x01 #x02 #x03) (pack c))
    "pack RGB value")
; TODO: unpack
; TODO: shape, display, write
; TODO: coercion, value, types, conent, param
