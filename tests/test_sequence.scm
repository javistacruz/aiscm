(use-modules (srfi srfi-1)
             (oop goops)
             (aiscm sequence)
             (aiscm element)
             (aiscm bool)
             (aiscm int)
             (aiscm pointer)
             (aiscm jit)
             (aiscm util)
             (guile-tap))
(define s1 (make (sequence <sint>) #:size 3))
(define s2 (make (sequence <sint>) #:size 3))
(define s3 (make (sequence <sint>) #:size 3))
(set s1 0 2) (set s1 1 3) (set s1 2 5)
(define a (make <var> #:type <long> #:symbol 'a))
(define b (make <var> #:type <long> #:symbol 'b))
(define c (make <var> #:type <long> #:symbol 'c))
(define d (make <var> #:type <long> #:symbol 'd))
(define e (make <var> #:type <long> #:symbol 'e))
(ok (equal? <sint> (typecode (sequence <sint>)))
    "Query element type of sequence class")
(ok (equal? (sequence <sint>) (sequence <sint>))
    "equality of classes")
(ok (eqv? 3 (size s1))
    "Query size of sequence")
(ok (equal? <sint> (typecode s1))
    "Query typecode of sequence")
(ok (equal? (pointer <sint>) (project (sequence <sint>)))
    "Query element type of sequence")
(ok (eqv? 9 (begin (set s2 2 9) (get s2 2)))
    "Write value to sequence")
(ok (eqv? 1 (dimensions (sequence <sint>)))
    "Check number of dimensions of sequence type")
(ok (eqv? 3 (dimension s1))
    "Query dimension of sequence")
(ok (equal? '(3) (shape s1))
    "Query shape of sequence")
(ok (equal? 1 (stride s1))
    "Query stride of sequence")
(ok (equal? '(1) (strides s1))
    "query strides of sequence")
(ok (equal? '(2 3 5) (to-list s1))
    "Convert sequence to list")
(ok (make (sequence <int>) #:size 0)
    "Make empty sequence")
(ok (equal? '<sequence<int<16,signed>>> (class-name (sequence <sint>)))
    "Class name of 16-bit integer sequence")
(ok (equal? "#<sequence<int<32,signed>>>:\n()"
      (call-with-output-string (lambda (port) (write (make (sequence <int>) #:size 0) port))))
    "Write empty sequence")
(ok (equal? "#<sequence<int<16,signed>>>:\n(2 3 5)"
      (call-with-output-string (lambda (port) (write s1 port))))
    "Write sequence object")
(ok (equal? "#<sequence<int<8,unsigned>>>:\n(100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 ...)"
      (call-with-output-string (lambda (port) (write (to-array (make-list 40 100)) port))))
    "Write longer sequence object")
(ok (equal? "#<<sequence<int<8,signed>>> c (a) (b)>"
      (let [(s (make (sequence <byte>) #:value c #:shape (list a) #:strides (list b)))]
        (call-with-output-string (lambda (port) (write s port)))))
    "Write sequence object made from variables")
(ok (equal? <ubyte> (typecode (to-array '(1 2 3))))
    "Typecode of converted list of unsigned bytes")
(ok (equal? <byte> (typecode (to-array '(1 -1))))
    "Typecode of converted list of signed bytes")
(ok (eqv? 6 (size-of (make (sequence <sint>) #:size 3)))
    "storage size of short integer sequence")
(ok (eqv? 3 (size (to-array '(1 2 3))))
    "Size of converted list")
(ok (equal? '(2 3 5) (begin (set s3 '(2 3 5)) (to-list s3)))
    "Assignment list to sequence")
(ok (equal? '(3 3 3) (begin (set s3 3) (to-list s3)))
    "Assignment number to sequence")
(ok (equal? '(2 3 5) (set s3 '(2 3 5)))
    "Return value of assignment to sequence")
(ok (equal? '(2 4 8) (to-list (to-array '(2 4 8))))
    "Convert list of integers to multiarray and back")
(ok (equal? '(#t #f #t) (to-list (to-array '(#t #f #t))))
    "Convert list of boleans to multiarray and back")
(ok (equal? '(2 3 5) (to-list (sequence 2 3 (+ 2 3))))
    "Short form for specifying sequences")
(ok (equal? '(2 3 5) (to-list (seq 2 3 (+ 2 3))))
    "Short short form for specifying sequences")
(ok (equal? '(2 3 5) (to-list (seq <int> 2 3 5)))
    "Checking content of short form for integer sequence")
(ok (equal? <int> (typecode (seq <int> 2 3 5)))
    "Checking type of short form for integer sequence ")
(ok (equal? '(-1 128) (to-list (seq -1 128)))
    "Selection of fitting datatype for signed-unsigned combinations")
(ok (equal? '((2 3) (5 7)) (to-list (arr (2 3) (5 7))))
    "Short form for specifying arrays")
(ok (equal? '((2 3) (5 7)) (to-list (arr <int> (2 3) (5 7))))
    "Checking content of short form for specifying integer arrays")
(ok (equal? <int> (typecode (arr <int> (2 3) (5 7))))
    "Checking type of short form for specifying integer arrays")
(ok (equal? <int> (typecode (to-array <int> '(1 2 3))))
    "Convert list of integers to integer array")
(ok (equal? '(1 2 3) (to-list (to-array <int> '(1 2 3))))
    "Convert list of integers to integer array and back")
(ok (equal? "#<sequence<sequence<int<8,unsigned>>>>:\n((1 2 3)\n (4 5 6))"
      (call-with-output-string (lambda (port) (write (arr (1 2 3) (4 5 6)) port))))
    "Write 2D array")
(ok (equal? "#<sequence<sequence<int<8,unsigned>>>>:\n((100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 100 ...))"
      (call-with-output-string (lambda (port) (write (to-array (list (make-list 40 100))) port))))
    "Write 2D array with large first dimension")
(ok (equal? "#<sequence<sequence<int<8,unsigned>>>>:\n((1)\n (1)\n (1)\n (1)\n (1)\n (1)\n (1)\n (1)\n (1)\n (1)\n ..."
      (call-with-output-string (lambda (port) (write (to-array (make-list 11 '(1))) port))))
    "Write 2D array with large second dimension")
(ok (equal? "#<sequence<sequence<sequence<int<8,unsigned>>>>>:\n(((1 1)\n  (1 1))\n ((1 1)\n  (1 1)))"
      (call-with-output-string (lambda (port) (write (to-array (make-list 2 (make-list 2 '(1 1)))) port))))
    "Write 3D array")
(ok (equal? "#<sequence<sequence<sequence<int<8,unsigned>>>>>:\n(((1 1)\n  (1 1)\n  (1 1))\n ((1 1)\n  (1 1)\n  (1 1))\n ((1 1)\n  (1 1)\n  (1 1))\n ((1 1)\n ..."
      (call-with-output-string (lambda (port) (write (to-array (make-list 4 (make-list 3 '(1 1)))) port))))
    "Write 4x3x2 array")
(ok (equal? "#<sequence<sequence<sequence<int<8,unsigned>>>>>:\n(((1 1)\n  (1 1)\n  (1 1))\n ((1 1)\n  (1 1)\n  (1 1))\n ((1 1)\n  (1 1)\n  (1 1))\n ((1 1)\n ..."
      (call-with-output-string (lambda (port) (write (to-array (make-list 5 (make-list 3 '(1 1)))) port))))
    "Write  5x3x2 array")
(ok (equal? (sequence <int>) (coerce <int> (sequence <sint>)))
    "Coercion of sequences")
(ok (equal? (sequence <int>) (coerce (sequence <int>) <byte>))
    "Coercion of sequences")
(ok (equal? (sequence <int>) (coerce (sequence <int>) (sequence <byte>)))
    "Coercion of sequences")
(ok (equal? (multiarray <int> 2) (coerce (multiarray <int> 2) <int>))
    "Coercion of multi-dimensional arrays")
(ok (equal? '<sequence<sequence<int<16,signed>>>> (class-name (sequence (sequence <sint>))))
    "Class name of 16-bit integer 2D array")
(ok (equal? (multiarray <sint> 2) (sequence (sequence (integer 16 signed))))
    "Multi-dimensional array is the same as a sequence of sequences")
(ok (equal? (sequence <sint>) (project (multiarray <sint> 2)))
    "Get element type of 2D array")
(ok (null? (shape 1))
    "Shape of arbitrary object is empty list")
(ok (equal? '(3) (shape '(1 2 3)))
    "Shape of flat list")
(ok (equal? '(3 2) (shape '((1 2 3) (4 5 6))))
    "Shape of nested list")
(ok (equal? '(5 4 3) (shape (make (multiarray <int> 3) #:shape '(5 4 3))))
    "Query shape of multi-dimensional array")
(ok (equal? '(1 5 20) (strides (make (multiarray <int> 3) #:shape '(5 4 3))))
    "Query strides of multi-dimensional array")
(ok (eqv? 20 (stride (make (multiarray <int> 3) #:shape '(5 4 3))))
    "Query last stride of multi-dimensional array")
(ok (equal? 3 (dimension (make (multiarray <int> 3) #:shape '(5 4 3))))
    "Query last dimension of multi-dimensional array")
(ok (equal? '(1 2 3) (to-list (get (seq 1 2 3))))
    "'get' without additional arguments should return the sequence itself")
(ok (equal? '((1 2 3) (4 5 6)) (to-list (arr (1 2 3) (4 5 6))))
    "Content of converted 2D array")
(ok (equal? '(4 5 6) (to-list (get (arr (1 2 3) (4 5 6)) 1)))
    "Getting row of 2D array")
(ok (equal? 2 (get (arr (1 2 3) (4 5 6)) 1 0))
    "Getting element of 2D array with one call to 'get'")
(ok (equal? 2 (get (get (arr (1 2 3) (4 5 6)) 0) 1))
    "Getting element of 2D array with two calls to 'get'")
(ok (equal? 42 (let [(m (arr (1 2 3) (4 5 6)))] (set m 1 0 42) (get m 1 0)))
    "Setting an element in a 2D array")
(ok (equal? '((1 2) (5 6)) (let [(m (arr (1 2) (3 4)))]
                             (set m 1 '(5 6))
                             (to-list m)))
    "Setting a row in a 2D array")
(ok (equal? '(3 4 5) (to-list (dump 2 (seq 1 2 3 4 5))))
    "Drop 2 elements of an array")
(ok (equal? '((2 3) (5 6)) (to-list (dump '(1 0) (arr (1 2 3) (4 5 6)))))
    "Drop rows and columns from 2D array")
(ok (equal? '(3 3 3) (shape (dump '(1 2) (make (multiarray <int> 3) #:shape '(3 4 5)))))
    "Drop elements from a 3D array")
(ok (equal? '(1 2 3) (to-list (project (arr (1 2 3) (4 5 6)))))
    "project 2D array")
(ok (equal? '(1 2 3) (to-list (crop 3 (seq 1 2 3 4))))
    "Crop an array down to 3 elements")
(ok (equal? '((1 2)) (to-list (crop '(2 1) (arr (1 2 3) (4 5 6)))))
    "Crop 2D array to size 2x1")
(ok (equal? '(3 1 2) (shape (crop '(1 2) (make (multiarray <int> 3) #:shape '(3 4 5)))))
    "Crop 3D array")
(ok (equal? '(((1)) ((2))) (to-list (roll (arr ((1 2))))))
    "Rolling an array should cycle the indices")
(ok (equal? '(((1) (2))) (to-list (unroll (arr ((1 2))))))
    "Unrolling an array should reverse cycle the indices")
(ok (equal? '(1 3 5) (to-list (downsample 2 (seq 1 2 3 4 5))))
    "Downsampling by 2 with phase 0")
(ok (equal? '((1) (3) (5)) (to-list (downsample 2 (arr (1) (2) (3) (4) (5)))))
    "Downsampling of 2D array")
(ok (equal? '((1 2 3)) (to-list (downsample '(1 2) (arr (1 2 3) (4 5 6)))))
    "1-2 Downsampling of 2D array")
(ok (equal? '((1 3) (4 6)) (to-list (downsample '(2 1) (arr (1 2 3) (4 5 6)))))
    "2-1 Downsampling of 2D array")
(ok (equal? '(6 3 2) (shape (downsample '(2 3) (make (multiarray <int> 3) #:shape '(6 6 6)))))
    "Downsample 3D array")
(ok (equal? '(3 1) (take (content s1) 2))
    "'content' for an array should return size and stride")
(ok (equal? '(4 6 6 1) (take (content (make (multiarray <byte> 2) #:shape '(6 4))) 4))
    "'content' for a 2D array should return shape and strides")
(run-tests)
