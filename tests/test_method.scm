(use-modules (oop goops)
             (srfi srfi-26)
             (aiscm asm)
             (aiscm jit)
             (aiscm bool)
             (aiscm int)
             (aiscm obj)
             (aiscm method)
             (guile-tap))

(define ctx (make <context>))

(define main                (dynamic-link))
(define guile-aiscm-tests   (dynamic-link "libguile-aiscm-tests"))

(define cabs (dynamic-func "abs" main))
(define jit-side-effect     (dynamic-func "jit_side_effect"     guile-aiscm-tests))
(define jit-constant-fun    (dynamic-func "jit_constant_fun"    guile-aiscm-tests))
(define jit-subtracting-fun (dynamic-func "jit_subtracting_fun" guile-aiscm-tests))
(define jit-seven-arguments (dynamic-func "jit_seven_arguments" guile-aiscm-tests))
(define jit-boolean-not     (dynamic-func "jit_boolean_not"     guile-aiscm-tests))

(let [(method (native-method <int> '() jit-constant-fun))]
  (ok (equal? jit-constant-fun (function-pointer method))
      "Query function pointer of method")
  (ok (eq? <int> (return-type method))
      "Query return type of method")
  (ok (equal? '() (argument-types method))
      "Query argument list of constant method")
  (ok (eqv? 42 ((jit ctx '() (const (native-call (native-method <int> '() jit-constant-fun))))))
      "Compile method call to function returning constant value"))
(ok (eqv? 63 ((jit ctx (list <int>)
                   (lambda (x) (+ x (native-call (native-method <int> (list <int>) jit-constant-fun))))) 21))
    "Compile function call and plus operation to test that caller-saved registers get blocked")
(ok (eqv? 2 ((jit ctx (list <int> <int>)
                  (lambda (x y) (native-call (native-method <int> (list <int> <int>) jit-subtracting-fun) y x))) 5 7))
    "Compile function call taking two arguments after swapping them")
(ok (eqv? 5 ((jit ctx (make-list 3 <int>)
                  (lambda (x y z) (native-call (native-method <int> (list <int> <int>) jit-subtracting-fun) x (+ y z)))) 10 2 3))
    "Pass result of expression to function call")
(ok (eqv? 5 ((jit ctx (list <int> <obj> <obj>)
                  (lambda (x y z) (native-call (native-method <int> (list <int> <int>) jit-subtracting-fun) x (+ y z)))) 10 2 3))
    "Convert result of expression before passing to native function call")
(ok (eqv? 42 ((jit ctx (list <int> <int>)
                   (lambda (a b) (native-call (native-method <int> (make-list 7 <int>) jit-seven-arguments) a a a a a a b))) 123 42))
    "Compile function call with seven arguments (requires stack parameters)")
(ok (equal? '(#t #f) (map (jit ctx (list <bool>) (cut native-call (native-method <bool> (list <bool>) jit-boolean-not) <>)) '(#f #t)))
    "Compile and run native boolean negation function")
(ok (equal? 42 ((jit ctx (list <int>) (cut native-call (native-method <int> (list <int>) cabs) <>)) -42))
    "call C standard library abs function")
(ok (eq? <int> (return-type (native-value <int> 42)))
    "check type of native value")
(ok (eqv? 42 (get (native-value <int> 42)))
    "check value of native value")
(ok (eqv? 42 ((jit ctx '() (lambda () (native-constant (native-value <int> 42))))))
    "put native constant into compiled code")
(ok ((jit ctx (list <ulong>) (cut native-call scm-gc-malloc-pointerless <>)) 128)
    "allocate memory in compiled method")
(ok ((jit ctx (list <ulong>) (cut native-call scm-gc-malloc <>)) 128)
    "allocate memory in compiled method")
(run-tests)
