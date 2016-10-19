(use-modules (oop goops)
             (system foreign)
             (aiscm element)
             (aiscm bool)
             (aiscm float)
             (aiscm int)
             (aiscm jit)
             (guile-tap))
(ok (equal? (integer 32 signed) (integer 32 signed))
    "equality of classes")
(ok (equal? <int> (integer 32 signed))
    "equality of predefined classes")
(ok (equal? <meta<int>> (class-of (integer 32 signed)))
    "equality of predefined metaclass")
(ok (eqv? 64 (bits (integer 64 signed)))
    "number of bits of integer class")
(ok (signed? (integer 64 signed))
    "signed-ness of signed integer class")
(ok (not (signed? (integer 64 unsigned)))
    "signed-ness of unsigned integer class")
(ok (eqv? 1 (size-of <byte>))
    "storage size of byte")
(ok (eqv? 2 (size-of <sint>))
    "storage size of short integer")
(ok (eqv? 4 (size-of <uint>))
    "storage size of unsigned integer")
(ok (eqv? 8 (size-of <long>))
    "storage size of long integer")
(ok (eqv? 2 (size-of (make <sint> #:value #x21)))
    "storage size of short integer instance")
(ok (equal? (make <ubyte> #:value #x21) (make <ubyte> #:value #x21))
    "equal integer objects")
(ok (not (equal? (make <ubyte> #:value #x21) (make <usint> #:value #x4321)))
    "unequal integer objects")
(ok (not (equal? (make <ubyte> #:value #x21) (make <usint> #:value #x21)))
    "unequal integer objects of different classes")
(ok (eqv? 128 (bits (integer 128 signed)))
    "integer class maintains number of bits")
(ok (signed? (integer 128 signed))
    "integer class maintains signedness for signed integer")
(ok (not (signed? (integer 128 unsigned)))
    "integer class maintains signedness for unsigned integer")
(ok (signed? (make <int> #:value #x21))
    "signed-ness of integer instance")
(ok (eqv? 32 (bits (make <int> #:value #x21)))
    "number of bits of integer instance")
(ok (equal? #vu8(#x01 #x02)
            (pack (make (integer 16 unsigned) #:value #x0201)))
    "pack custom integer value")
(ok (equal? #vu8(#xff) (pack (make <ubyte> #:value #xff)))
    "pack unsigned byte value")
(ok (equal? #vu8(#x01 #x02) (pack (make <usint> #:value #x0201)))
    "pack unsigned short integer value")
(ok (equal? #vu8(#x01 #x02 #x03 #x04) (pack (make <uint> #:value #x04030201)))
    "pack unsigned integer value")
(ok (equal? (unpack <ubyte> #vu8(#xff)) (make <ubyte> #:value #xff))
    "unpack unsigned byte value")
(ok (equal? (unpack <usint> #vu8(#x01 #x02)) (make <usint> #:value #x0201))
    "unpack unsigned short integer value")
(ok (equal? (unpack <uint> #vu8(#x01 #x02 #x03 #x04))
            (make <uint> #:value #x04030201))
    "unpack unsigned integer value")
(ok (eqv? 127 (get (unpack <byte> (pack (make <byte> #:value 127)))))
    "pack and unpack signed byte")
(ok (eqv? -128 (get (unpack <byte> (pack (make <byte> #:value -128)))))
    "pack and unpack signed byte with negative number")
(ok (eqv? 32767 (get (unpack <sint> (pack (make <sint> #:value 32767)))))
    "pack and unpack signed short integer")
(ok (eqv? -32768 (get (unpack <sint> (pack (make <sint> #:value -32768)))))
    "pack and unpack signed short integer with negative number")
(ok (eqv? 2147483647
          (get (unpack <int> (pack (make <int> #:value 2147483647)))))
    "pack and unpack signed integer")
(ok (eqv? -2147483648
          (get (unpack <int> (pack (make <int> #:value -2147483648)))))
    "pack and unpack signed integer with negative number")
(ok (eqv? 1 (size (make <int> #:value 123)))
    "querying element size of integer")
(ok (null? (shape (make <int> #:value 123)))
    "querying shape of integer")
(ok (equal? "#<<int<16,signed>> 1234>"
            (call-with-output-string (lambda (port) (display (make <sint> #:value 1234) port))))
    "display short integer object")
(ok (equal? "#<<int<16,signed>> 1234>"
            (call-with-output-string (lambda (port) (write (make <sint> #:value 1234) port))))
    "write short integer object")
(ok (eqv? 32 (bits (coerce (integer 16 signed) (integer 32 signed))))
    "signed coercion returns largest integer type")
(ok (eqv? 16 (bits (coerce (integer 16 signed) (integer 8 signed))))
    "signed coercion returns largest integer type")
(ok (not (signed? (coerce (integer 8 unsigned) (integer 16 unsigned))))
    "coercion of signed-ness")
(ok (signed? (coerce (integer 8 unsigned) (integer 16 signed)))
    "coercion of signed-ness")
(ok (signed? (coerce (integer 8 signed) (integer 16 unsigned)))
    "coercion of signed-ness")
(ok (signed? (coerce (integer 8 signed) (integer 16 signed)))
    "coercion of signed-ness")
(ok (eqv? 32 (bits (coerce (integer 16 signed) (integer 16 unsigned))))
    "make space for signed-unsigned operation")
(ok (eqv? 32 (bits (coerce (integer 8 signed) (integer 16 unsigned))))
    "make space for signed-unsigned operation")
(ok (eqv? 16 (bits (coerce (integer 16 signed) (integer 8 unsigned))))
    "check whether unsigned value fits into signed value")
(ok (eqv? 64 (bits (coerce (integer 64 signed) (integer 64 unsigned))))
    "coercion does not allocate more than 64 bits")
(ok (equal? <float> (coerce (integer 32 signed) (floating-point single-precision)))
    "coercion of integer and single-precision floating point")
(ok (equal? <double> (coerce (floating-point double-precision) (integer 32 signed)))
    "coercion of double-precision floating point and integer")
(ok (equal? int8 (foreign-type (integer 8 signed)))
    "foreign type of byte")
(ok (equal? uint16 (foreign-type (integer 16 unsigned)))
    "foreign type of unsigned short int")
(ok (equal? <ubyte> (native-type 255))
    "type matching for 255")
(ok (equal? <usint> (native-type 256))
    "type matching for 256")
(ok (equal? <usint> (native-type 65535))
    "type matching for 65535")
(ok (equal? <uint> (native-type 65536))
    "type matching for 65536")
(ok (equal? <uint> (native-type 4294967295))
    "type matching for 4294967295")
(ok (equal? <ulong> (native-type 4294967296))
    "type matching for 4294967296")
(ok (equal? <ulong> (native-type 18446744073709551615))
    "type matching for 18446744073709551615")
(ok (equal? <double> (native-type 18446744073709551616))
    "type matching for 18446744073709551616")
(ok (equal? <byte> (native-type -128))
    "type matching for -128")
(ok (equal? <sint> (native-type -129))
    "type matching for -129")
(ok (equal? <sint> (native-type -32768))
    "type matching for -32768")
(ok (equal? <int> (native-type -32769))
    "type matching for -32769")
(ok (equal? <int> (native-type -2147483648))
    "type matching for -2147483648")
(ok (equal? <long> (native-type -2147483649))
    "type matching for -2147483649")
(ok (equal? <long> (native-type -9223372036854775808))
    "type matching for -9223372036854775808")
(ok (equal? <double> (native-type -9223372036854775809))
    "type matching for -9223372036854775809")
(ok (equal? <byte> (native-type 1 -1))
    "match two integers")
(ok (is-a? (wrap 125) <ubyte>)
    "wrapping 125 creates a byte container")
(ok (eqv? 125 (get (wrap 125)))
    "wrapping 125 maintains value")
(ok (eqv? 125 (get (wrap (wrap 125))))
    "don't wrap twice")
(ok (equal? <double> (native-type 1 1.5))
    "type matching for 1 and 1.5")
(ok (eqv? 123 (get (make <int> #:value 123)))
    "get value of integer")
(ok (eqv? 123 (let [(i (make <int> #:value 0))] (set i 123) (get i)))
    "set value of integer")
(ok (eqv? 123 (set (make <int> #:value 0) 123))
    "return-value of setting integer")
(ok (equal? (make <sint> #:value 42) (build <sint> 42))
    "build short integer")
(ok (equal? '(42) (content <int<>> 42))
    "'content' returns integer values")
(ok (equal? -43 (~ 42))
    "invert integer using '~'")
(ok (equal? 2 (& 3 6))
    "bitwise and using '&'")
(ok (equal? 4 (& 7 14 28))
    "bitwise and with three arguments")
(ok (equal? 7 (| 3 6))
    "bitwise or using '|'")
(ok (equal? 7 (| 1 2 4))
    "bitwise or with three arguments")
(ok (equal? 5 (^ 3 6))
    "bitwise xor using '^'")
(ok (equal? 21 (^ 7 14 28))
    "bitwise xor using '^'")
(ok (equal? 12 (<< 3 2))
    "shift left using '<<'")
(ok (equal? 3 (>> 12 2))
    "shift right using '>>'")
(ok (equal? 33 (% 123 45))
    "remainder of division using '%'")
(ok (equal? '(#f #t) (map != '(3 4) '(3 5)))
    "'!=' for integers")
(ok (equal? '(#t #f) (map =0 '(0 1)))
    "'=0' for integers")
(ok (equal? '(#f #t) (map !=0 '(0 1)))
    "'!=0' for integers")
(ok (eq? <int> (base <int>))
    "base type of integer is integer")
(ok (eqv? 3 (conj 3))
    "conjugate of integer")
(ok (pointerless? <int>)
    "integer memory is pointerless")
(run-tests)
