(use-modules (oop goops)
             (system foreign)
             (rnrs bytevectors)
             (aiscm jit)
             (aiscm element)
             (aiscm mem)
             (aiscm int)
             (aiscm pointer)
             (guile-tap))
(planned-tests 44)
(define mem  (make <mem> #:size 12))
(define ptr  (make (pointer <int>) #:value mem))
(store ptr (make <int> #:value 42))
(store (+ ptr 1) (make <int> #:value 13))
(ok (equal? '(#xb8 #x2a #x00 #x00 #x00) (MOV EAX 42))
    "MOV EAX, 42")
(ok (equal? '(#xb9 #x2a #x00 #x00 #x00) (MOV ECX 42))
    "MOV ECX, 42")
(ok (equal? '(#x48 #xbe #x2a #x00 #x00 #x00 #x00 #x00 #x00 #x00)
            (MOV RSI 42))
    "MOV RSI, 42")
(ok (equal? '(#x89 #xc3) (MOV EBX EAX))
    "MOV EBX, EAX")
(ok (equal? '(#x89 #xd1) (MOV ECX EDX))
    "MOV ECX, EDX")
(ok (equal? '(#x8b #x0a) (MOV ECX *RDX))
    "Read data from address into register")
(ok (equal? '(#x89 #x11) (MOV *RCX EDX))
    "Write data from register to address")
(ok (equal? '(#xc3) (RET))
    "RET # near return")
(ok (eqv? 42 (jit-call (list (MOV EAX 42)
                             (RET))))
    "Function returning constant in EAX")
(ok (eqv? 42 (jit-call (list (MOV EBX 42)
                             (MOV EAX EBX)
                             (RET))))
    "Function copying content from EBX")
(ok (equal? '(#xd1 #xe5) (SHL EBP))
    "SHL EBP, 1")
(ok (equal? '(#xd1 #xe5) (SAL EBP))
    "SAL EBP, 1")
(ok (eqv? 84 (jit-call (list (MOV EAX 42)
                             (SHL EAX)
                             (RET))))
    "Function shifting left by 1")
(ok (equal? '(#x48 #xd1 #xe5) (SHL RBP))
    "SHL RBP, 1")
(ok (equal? '(#x48 #xd1 #xe5) (SAL RBP))
    "SAL RBP, 1")
(ok (equal? '(#xd1 #xed) (SHR EBP))
    "SHR EBP, 1")
(ok (equal? '(#xd1 #xfd) (SAR EBP))
    "SAR EBP, 1")
(ok (eqv? 21 (jit-call (list (MOV EAX 42)
                             (SHR EAX)
                             (RET))))
    "Function shifting right by 1")
(ok (eqv? -21 (jit-call (list (MOV EAX -42)
                              (SAR EAX)
                              (RET))))
    "Function shifting negative number right by 1")
(ok (equal? '(#x48 #xd1 #xed) (SHR RBP))
    "SHR RBP, 1")
(ok (equal? '(#x48 #xd1 #xfd) (SAR RBP))
    "SAR RBP, 1")
(ok (eqv? (ash 1 30) (jit-call (list (MOV RAX (ash 1 32))
                                     (SHR RAX)
                                     (SHR RAX)
                                     (RET))))
    "Function shifting 64-bit number right by 2")
(ok (eqv? (ash -1 30) (jit-call (list (MOV RAX (ash -1 32))
                                      (SAR RAX)
                                      (SAR RAX)
                                      (RET))))
    "Function shifting signed 64-bit number right by 2")
(ok (equal? '(#x05 #x0d #x00 #x00 #x00) (ADD EAX 13))
    "ADD EAX, 13")
(ok (equal? '(#x48 #x05 #x0d #x00 #x00 #x00) (ADD RAX 13))
    "ADD RAX, 13")
(ok (equal? '(#x81 #xc3 #x0d #x00 #x00 #x00) (ADD EBX 13))
    "ADD EBX, 13")
(ok (equal? '(#x48 #x81 #xc3 #x0d #x00 #x00 #x00) (ADD RBX 13))
    "ADD RBX, 13")
(ok (equal? '(#x01 #xd1) (ADD ECX EDX))
    "ADD ECX, EDX")
(ok (eqv? 55 (jit-call (list (MOV EAX 42)
                             (ADD EAX 13)
                             (RET))))
    "Function using EAX to add 42 and 13")
(ok (eqv? 55 (jit-call (list (MOV EDX 42)
                             (ADD EDX 13)
                             (MOV EAX EDX)
                             (RET))))
    "Function using EDX to add 42 and 13")
(ok (eqv? 55 (jit-call (list (MOV EAX 42)
                             (MOV ECX 13)
                             (ADD EAX ECX)
                             (RET))))
    "Function using EAX and ECX to add 42 and 13")
(ok (equal? '(#x90) (NOP))
    "NOP # no operation")
(ok (eqv? 42 (jit-call (list (MOV EAX 42)
                             (NOP)
                             (NOP)
                             (RET))))
    "Function with some NOP statements inside")
(ok (equal? '(#x52) (PUSH EDX))
    "PUSH EDX")
(ok (equal? '(#x57) (PUSH EDI))
    "PUSH EDI")
(ok (equal? '(#x5a) (POP EDX))
    "POP EDX")
(ok (equal? '(#x5f) (POP EDI))
    "POP EDI")
(ok (eqv? 42 (jit-call (list (MOV EDX 42)
                             (PUSH EDX)
                             (POP EAX)
                             (RET))))
    "Function using PUSH and POP")
(ok (eqv? 42 (jit-call (list (MOV RCX (pointer-address (get-memory mem)))
                             (MOV EAX *RCX)
                             (RET))))
    "Function loading value address given as integer")
(ok (eqv? 42 (jit-call (list (MOV RCX mem)
                             (MOV EAX *RCX)
                             (RET))))
    "Function loading value from address given as pointer")
(ok (eqv? 13 (jit-call (list (MOV RCX mem)
                             (ADD RCX 4)
                             (MOV EAX *RCX)
                             (RET))))
    "Function loading value from address with offset")
(ok (equal? '(#xe9 #x2a #x00 #x00 #x00) (JMP 42))
    "JMP 42")
(ok (eqv? 42 (jit-call (list (MOV EBX 42)
                             (JMP (length (MOV EBX 21)))
                             (MOV EBX 21)
                             (MOV EAX EBX)
                             (RET))))
    "Function with a local jump")
(ok (eqv? 21 (begin (jit-call (list (MOV RSI (+ mem 8))
                                    (MOV EBX 21)
                                    (MOV *RSI EBX)
                                    (RET)))
                    (get-value (fetch (+ ptr 2)))))
    "Function writing value to memory")
(format #t "~&")
