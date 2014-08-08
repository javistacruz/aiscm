(use-modules (aiscm sequence)
             (aiscm element)
             (aiscm int)
             (oop goops)
             (guile-tap))
(planned-tests 50)
(define s1 (make (sequence <sint>) #:size 3))
(define s2 (make (sequence <sint>) #:size 3))
(define s3 (make (sequence <sint>) #:size 3))
(set s1 0 2) (set s1 1 3) (set s1 2 5)
(ok (equal? <sint> (typecode (sequence <sint>)))
    "Query element type of sequence class")
(ok (equal? (sequence <sint>) (sequence <sint>))
    "equality of classes")
(ok (eqv? 3 (size s1))
    "Query size of sequence")
(ok (equal? <sint> (typecode s1))
    "Query element type of sequence")
(ok (eqv? 9 (begin (set s2 2 9) (get s2 2)))
    "Write value to sequence")
(ok (eqv? 9 (set s2 2 9))
    "Write value returns input value")
(ok (eqv? 1 (dimension (sequence <sint>)))
    "Check number of dimensions of sequence type")
(ok (equal? '(3) (shape s1))
    "Query shape of sequence")
(ok (equal? '(2 3 5) (multiarray->list s1))
    "Convert sequence to list")
(ok (equal? "<sequence<int<16,signed>>>" (class-name (sequence <sint>)))
    "Class name of 16-bit integer sequence")
(ok (equal? "#<sequence<int<16,signed>>>:\n(2 3 5)"
      (call-with-output-string (lambda (port) (write s1 port))))
    "Write lambda object")
(ok (equal? "#<sequence<int<16,signed>>>:\n(2 3 5)"
      (call-with-output-string (lambda (port) (display s1 port))))
    "Display lambda object")
(ok (equal? <ubyte> (typecode (list->multiarray '(1 2 3))))
    "Typecode of converted list of unsigned bytes")
(ok (equal? <byte> (typecode (list->multiarray '(1 -1))))
    "Typecode of converted list of signed bytes")
(ok (eqv? 3 (size (list->multiarray '(1 2 3))))
    "Size of converted list")
(ok (equal? '(2 3 5) (begin (set s3 '(2 3 5)) (multiarray->list s3)))
    "Assignment list to sequence")
(ok (equal? '(3 3 3) (begin (set s3 3) (multiarray->list s3)))
    "Assignment number to sequence")
(ok (equal? '(2 3 5) (set s3 '(2 3 5)))
    "Return value of assignment to sequence")
(ok (equal? '(2 4 8) (multiarray->list (list->multiarray '(2 4 8))))
    "Content of converted list")
(ok (equal? (sequence <int>) (coerce <int> (sequence <sint>)))
    "Coercion of sequences")
(ok (equal? (sequence <int>) (coerce (sequence <int>) <byte>))
    "Coercion of sequences")
(ok (equal? (sequence <int>) (coerce (sequence <int>) (sequence <byte>)))
    "Coercion of sequences")
(ok (equal? (multiarray <int> 2) (coerce (multiarray <int> 2) <int>))
    "Coercion of multi-dimensional arrays")
(ok (equal? "<multiarray<int<16,signed>>,2>" (class-name (sequence (sequence <sint>))))
    "Class name of 16-bit integer 2D array")
(ok (equal? (multiarray <sint> 2) (sequence (sequence (integer 16 signed))))
    "Multi-dimensional array is the same as a sequence of sequences")
(ok (null? (shape 1))
    "Shape of arbitrary object is empty list")
(ok (equal? '(3) (shape '(1 2 3)))
    "Shape of flat list")
(ok (equal? '(3 2) (shape '((1 2 3) (4 5 6))))
    "Shape of nested list")
(ok (equal? '(5 4 3) (shape (make (multiarray <int> 3) #:shape '(5 4 3))))
    "Query shape of multi-dimensional array")
(ok (equal? '(1 2 3) (multiarray->list (get (list->multiarray '(1 2 3)))))
    "'get' without additional arguments should return the sequence itself")
(ok (equal? '((1 2 3) (4 5 6)) (multiarray->list (list->multiarray '((1 2 3) (4 5 6)))))
    "Content of converted 2D array")
(ok (equal? '(4 5 6) (multiarray->list (get (list->multiarray '((1 2 3) (4 5 6))) 1)))
    "Getting row of 2D array")
(ok (equal? 2 (get (list->multiarray '((1 2 3) (4 5 6))) 1 0))
    "Getting element of 2D array with one call to 'get'")
(ok (equal? 2 (get (get (list->multiarray '((1 2 3) (4 5 6))) 0) 1))
    "Getting element of 2D array with two calls to 'get'")
(ok (equal? 42 (let [(m (list->multiarray '((1 2 3) (4 5 6))))] (set m 1 0 42) (get m 1 0)))
    "Setting an element in a 2D array")
(ok (equal? '((1 2) (5 6)) (let [(m (list->multiarray '((1 2) (3 4))))]
                             (set m 1 '(5 6))
                             (multiarray->list m)))
    "Setting a row in a 2D array")
(ok (equal? '(3 4 5) (multiarray->list (drop 2 (list->multiarray '(1 2 3 4 5)))))
    "Drop 2 elements of an array")
(ok (equal? '((2 3) (5 6)) (multiarray->list (drop '(1 0) (list->multiarray '((1 2 3) (4 5 6))))))
    "Drop rows and columns from 2D array")
(ok (equal? '(3 3 3) (shape (drop '(1 2) (make (multiarray <int> 3) #:shape '(3 4 5)))))
    "Drop elements from a 3D array")
(ok (equal? '(1 2 3) (multiarray->list (project (list->multiarray '((1 2 3) (4 5 6))))))
    "project 2D array")
(ok (equal? '(1 2 3) (multiarray->list (crop 3 (list->multiarray '(1 2 3 4)))))
    "Crop an array down to 3 elements")
(ok (equal? '((1 2)) (multiarray->list (crop '(2 1) (list->multiarray '((1 2 3) (4 5 6))))))
    "Crop 2D array to size 2x1")
(ok (equal? '(3 1 2) (shape (crop '(1 2) (make (multiarray <int> 3) #:shape '(3 4 5)))))
    "Crop 3D array")
(ok (equal? '(((1)) ((2))) (multiarray->list (roll (list->multiarray '(((1 2)))))))
    "Rolling an array should cycle the indices")
(ok (equal? '(((1) (2))) (multiarray->list (unroll (list->multiarray '(((1 2)))))))
    "Unrolling an array should reverse cycle the indices")
(ok (equal? '(1 3 5) (multiarray->list (downsample 2 (list->multiarray '(1 2 3 4 5)))))
    "Downsampling by 2 with phase 0")
(ok (equal? '((1) (3) (5)) (multiarray->list (downsample 2 (list->multiarray '((1) (2) (3) (4) (5))))))
    "Downsampling of 2D array")
(ok (equal? '((1 2 3)) (multiarray->list (downsample '(1 2) (list->multiarray '((1 2 3) (4 5 6))))))
    "1-2 Downsampling of 2D array")
(ok (equal? '((1 3) (4 6)) (multiarray->list (downsample '(2 1) (list->multiarray '((1 2 3) (4 5 6))))))
    "2-1 Downsampling of 2D array")
(ok (equal? '(6 3 2) (shape (downsample '(2 3) (make (multiarray <int> 3) #:shape '(6 6 6)))))
    "Downsample 3D array")
(format #t "~&")
