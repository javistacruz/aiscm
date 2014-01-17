(use-modules (aiscm element)
             (aiscm bool)
             (oop goops)
             (guile-tap))
(define bool-false (make-bool #f))
(define bool-true (make-bool #t))
(planned-tests 9)
(ok (equal? bool-false bool-false)
  "equal boolean objects")
(ok (not (get-value bool-false))
  "get boolean value from bool-false")
(ok (get-value bool-true)
  "get boolean value from bool-true")
(ok (not (equal? bool-true bool-false))
  "unequal boolean objects")
(ok (eqv? 1 (storage-size <bool>))
  "storage size of booleans")
(ok (equal? #vu8(0) (pack bool-false))
  "pack 'false' value")
(ok (equal? #vu8(1) (pack bool-true))
  "pack 'true' value")
(ok (equal? bool-false (unpack <bool> #vu8(0)))
  "unpack 'false' value")
(ok (equal? bool-true (unpack <bool> #vu8(1)))
  "unpack 'true' value")
(format #t "~&")
