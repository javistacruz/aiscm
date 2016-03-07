(define-module (aiscm jit)
  #:use-module (oop goops)
  #:use-module (ice-9 optargs)
  #:use-module (ice-9 curried-definitions)
  #:use-module (ice-9 binary-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (aiscm util)
  #:use-module (aiscm asm)
  #:use-module (aiscm element)
  #:use-module (aiscm pointer)
  #:use-module (aiscm bool)
  #:use-module (aiscm int)
  #:use-module (aiscm rgb)
  #:use-module (aiscm complex)
  #:use-module (aiscm sequence)
  #:export (<block> <cmd> <var> <ptr> <tensor> <lookup> <function>
            ;<pointer<rgb<>>> <meta<pointer<rgb<>>>>
            ;<pointer<complex<>>> <meta<pointer<complex<>>>>
            ;<fragment<top>> <meta<fragment<top>>>
            ;<fragment<element>> <meta<fragment<element>>>
            ;<fragment<int<>>> <meta<fragment<int<>>>>
            ;<fragment<rgb<>>> <meta<fragment<rgb<>>>>
            ;<fragment<complex<>>> <meta<fragment<complex<>>>>
            ;<fragment<pointer<>>> <meta<fragment<pointer<>>>>
            ;<fragment<sequence<>>> <meta<fragment<sequence<>>>>
            substitute-variables variables get-args input output labels next-indices live-analysis
            callee-saved save-registers load-registers blocked repeat mov-part
            spill-variable save-and-use-registers register-allocate spill-blocked-predefines
            virtual-variables flatten-code relabel idle-live fetch-parameters spill-parameters
            filter-blocks blocked-intervals var skeleton expression term tensor index type subst code
            assemble jit iterator step setup increment body arguments))
(define-method (get-args self) '())
(define-method (input self) '())
(define-method (output self) '())
(define-class <cmd> ()
  (op     #:init-keyword #:op     #:getter get-op)
  (args   #:init-keyword #:args   #:getter get-args)
  (input  #:init-keyword #:input  #:getter get-input)
  (output #:init-keyword #:output #:getter get-output))
(define-method (initialize (self <cmd>) initargs)
  (let-keywords initargs #f (op (out '()) (io '()) (in '()))
    (next-method self (list #:op     op
                            #:args   (append out io in)
                            #:input  (append io in)
                            #:output (append io out)))))
(define-method (write (self <cmd>) port)
  (write (cons (generic-function-name (get-op self)) (get-args self)) port))
(define-method (equal? (a <cmd>) (b <cmd>))
  (and (eq? (get-op a) (get-op b)) (equal? (get-args a) (get-args b))))

(define-syntax-rule (mutable-op op)
  (define-method (op . args) (make <cmd> #:op op #:io (list (car args)) #:in (cdr args))))
(define-syntax-rule (immutable-op op)
  (define-method (op . args) (make <cmd> #:op op #:out (list (car args)) #:in (cdr args))))
(define-syntax-rule (state-setting-op op)
  (define-method (op . args) (make <cmd> #:op op #:in args)))
(define-syntax-rule (state-reading-op op)
  (define-method (op . args) (make <cmd> #:op op #:out args)))

(define-method (mov-part (r <register>) (r/m <operand>))
  (MOV r (reg (/ (get-bits r) 8) (get-code r/m))))
(define-method (cmovnle16 (r <register>) (r/m <operand>))
  (CMOVNLE (reg (/ (max (get-bits r  ) 16) 8) (get-code r  ))
           (reg (/ (max (get-bits r/m) 16) 8) (get-code r/m))))
(define-method (cmovnbe16 (r <register>) (r/m <operand>))
  (CMOVNBE (reg (/ (max (get-bits r  ) 16) 8) (get-code r  ))
           (reg (/ (max (get-bits r/m) 16) 8) (get-code r/m))))
(define-method (cmovl16 (r <register>) (r/m <operand>))
  (CMOVL (reg (/ (max (get-bits r  ) 16) 8) (get-code r  ))
         (reg (/ (max (get-bits r/m) 16) 8) (get-code r/m))))
(define-method (cmovb16 (r <register>) (r/m <operand>))
  (CMOVB (reg (/ (max (get-bits r  ) 16) 8) (get-code r  ))
         (reg (/ (max (get-bits r/m) 16) 8) (get-code r/m))))

(immutable-op     mov-part)
(mutable-op       cmovnle16)
(mutable-op       cmovnbe16)
(mutable-op       cmovl16)
(mutable-op       cmovb16)
(immutable-op     MOV)
(immutable-op     MOVSX)
(immutable-op     MOVZX)
(immutable-op     LEA)
(mutable-op       SHL)
(mutable-op       SHR)
(mutable-op       SAL)
(mutable-op       SAR)
(mutable-op       ADD)
(state-setting-op PUSH)
(state-reading-op POP)
(mutable-op       NOT)
(mutable-op       NEG)
(mutable-op       INC)
(mutable-op       SUB)
(mutable-op       IMUL)
(mutable-op       IDIV)
(mutable-op       DIV)
(mutable-op       AND)
(mutable-op       OR)
(mutable-op       XOR)
(state-setting-op CMP)
(state-setting-op TEST)
(state-reading-op SETB)
(state-reading-op SETNB)
(state-reading-op SETE)
(state-reading-op SETNE)
(state-reading-op SETBE)
(state-reading-op SETNBE)
(state-reading-op SETL)
(state-reading-op SETNL)
(state-reading-op SETLE)
(state-reading-op SETNLE)
(mutable-op       CMOVB)
(mutable-op       CMOVNB)
(mutable-op       CMOVE)
(mutable-op       CMOVNE)
(mutable-op       CMOVBE)
(mutable-op       CMOVNBE)
(mutable-op       CMOVL)
(mutable-op       CMOVNL)
(mutable-op       CMOVLE)
(mutable-op       CMOVNLE)

(define-class <var> ()
  (type   #:init-keyword #:type   #:getter typecode)
  (symbol #:init-keyword #:symbol #:init-form (gensym)))
(define-method (write (self <var>) port) (write (slot-ref self 'symbol) port))
(define-method (size-of (self <var>)) (size-of (typecode self)))
(define-class <ptr> ()
  (type #:init-keyword #:type #:getter typecode)
  (args #:init-keyword #:args #:getter get-args))
(define-method (write (self <ptr>) port)
  (display (cons 'ptr (cons (class-name (typecode self)) (get-args self))) port))
(define-method (equal? (a <ptr>) (b <ptr>))
  (and (eq? (typecode a) (typecode b)) (equal? (get-args a) (get-args b))))
(define-method (ptr (type <meta<element>>) . args) (make <ptr> #:type type #:args args))
(define-method (variables self) '())
(define-method (variables (self <var>)) (list self))
(define-method (variables (self <cmd>)) (variables (get-args self)))
(define-method (variables (self <ptr>)) (variables (get-args self)))
(define-method (variables (self <list>)) (delete-duplicates (concatenate (map variables self))))
(define-method (input (self <cmd>))
  (delete-duplicates (variables (append (get-input self) (filter (cut is-a? <> <ptr>) (get-args self))))))
(define-method (output (self <cmd>)) (variables (get-output self)))
(define-method (substitute-variables self alist) self)
(define-method (substitute-variables (self <var>) alist)
  (let [(target (assq-ref alist self))]
    (if (is-a? target <register>)
      (reg (size-of self) (get-code target))
      (or target self))))
(define-method (substitute-variables (self <ptr>) alist)
  (apply ptr (cons (typecode self) (map (cut substitute-variables <> alist) (get-args self)))))
(define-method (substitute-variables (self <cmd>) alist)
  (apply (get-op self) (map (cut substitute-variables <> alist) (get-args self))))
(define-method (substitute-variables (self <list>) alist) (map (cut substitute-variables <> alist) self))

(define-method (var (self <meta<element>>)) (make <var> #:type self))
(define-method (var (self <meta<bool>>)) (var <ubyte>))
(define-method (var (self <meta<pointer<>>>)) (var <long>))
(define-method (var (self <meta<rgb<>>>)) (let [(t (base self))] (rgb (var t) (var t) (var t))))
(define-method (var (self <meta<complex<>>>)) (let [(t (base self))]
  (make <internalcomplex> #:real-part (var t) #:imag-part (var t))))

(define (labels prog) (filter (compose symbol? car) (map cons prog (iota (length prog)))))
(define-method (next-indices cmd k labels) (if (equal? cmd (RET)) '() (list (1+ k))))
(define-method (next-indices (cmd <jcc>) k labels)
  (let [(target (assq-ref labels (get-target cmd)))]
    (if (conditional? cmd) (list (1+ k) target) (list target))))
(define (live-analysis prog)
  (letrec* [(inputs    (map input prog))
            (outputs   (map output prog))
            (indices   (iota (length prog)))
            (lut       (labels prog))
            (flow      (map (lambda (cmd k) (next-indices cmd k lut)) prog indices))
            (same?     (cut every (cut lset= equal? <...>) <...>))
            (track     (lambda (value)
                         (lambda (in ind out)
                           (union in (difference (apply union (map (cut list-ref value <>) ind)) out)))))
            (initial   (map (const '()) prog))
            (iteration (lambda (value) (map (track value) inputs flow outputs)))]
    (map union (fixed-point initial iteration same?) outputs)))
(define default-registers (list RAX RCX RDX RSI RDI R10 R11 R9 R8 RBX RBP R12 R13 R14 R15))
(define (callee-saved registers)
  (lset-intersection eq? (delete-duplicates registers) (list RBX RSP RBP R12 R13 R14 R15)))
(define (save-registers registers offset)
  (map (lambda (register offset) (MOV (ptr <long> RSP offset) register))
       registers (iota (length registers) offset -8)))
(define (load-registers registers offset)
  (map (lambda (register offset) (MOV register (ptr <long> RSP offset)))
       registers (iota (length registers) offset -8)))
(define (relabel prog)
  (let* [(labels       (filter symbol? prog))
         (replacements (map (compose gensym symbol->string) labels))
         (translations (map cons labels replacements))]
    (map (lambda (x)
           (cond
             ((symbol? x)     (assq-ref translations x))
             ((is-a? x <jcc>) (retarget x (assq-ref translations (get-target x))))
             ((list? x)       (relabel x))
             (else            x)))
         prog)))
(define (flatten-code prog)
  (let [(instruction? (lambda (x) (and (list? x) (not (every integer? x)))))]
    (concatenate (map-if instruction? flatten-code list prog))))

(define ((insert-temporary target) cmd)
  (let [(temporary (var (typecode target)))]
    (compact
      (and (memv target (input cmd)) (MOV temporary target))
      (substitute-variables cmd (list (cons target temporary)))
      (and (memv target (output cmd)) (MOV target temporary)))))
(define (spill-variable var location prog)
  (substitute-variables (map (insert-temporary var) prog) (list (cons var location))))

(define ((idle-live prog live) var)
  (count (lambda (cmd active) (and (not (memv var (variables cmd))) (memv var active))) prog live))
(define ((spill-parameters parameters) colors)
  (filter-map (lambda (parameter register)
    (let [(value (assq-ref colors parameter))]
      (if (is-a? value <address>) (MOV value (reg (size-of parameter) (get-code register))) #f)))
    parameters (list RDI RSI RDX RCX R8 R9)))
(define ((fetch-parameters parameters) colors)
  (filter-map (lambda (parameter offset)
    (let [(value (assq-ref colors parameter))]
      (if (is-a? value <register>) (MOV (reg (size-of parameter) (get-code value))
                                        (ptr (typecode parameter) RSP offset)) #f)))
    parameters (iota (length parameters) 8 8)))
(define (save-and-use-registers prog colors parameters offset)
  (let [(need-saving (callee-saved (map cdr colors)))]
    (append (save-registers need-saving offset)
            ((spill-parameters (take-up-to parameters 6)) colors)
            ((fetch-parameters (drop-up-to parameters 6)) colors)
            (all-but-last (substitute-variables prog colors))
            (load-registers need-saving offset)
            (list (RET)))))

(define (with-spilled-variable var location prog predefined blocked fun)
  (let* [(spill-code (spill-variable var location prog))]
    (fun (flatten-code spill-code)
         (assq-set predefined var location)
         (update-intervals blocked (index-groups spill-code)))))

(define* (register-allocate prog
                            #:key (predefined '())
                                  (blocked '())
                                  (registers default-registers)
                                  (parameters '())
                                  (offset -8))
  (let* [(live       (live-analysis prog))
         (all-vars   (variables prog))
         (vars       (difference (variables prog) (map car predefined)))
         (intervals  (live-intervals live all-vars))
         (adjacent   (overlap intervals))
         (colors     (color-intervals intervals
                                      vars
                                      registers
                                      #:predefined predefined
                                      #:blocked blocked))
         (unassigned (find (compose not cdr) (reverse colors)))]
    (if unassigned
      (let* [(target       (argmax (idle-live prog live) (adjacent (car unassigned))))
             (stack-param? (and (index-of target parameters) (>= (index-of target parameters) 6)))
             (location     (if stack-param?
                               (ptr (typecode target) RSP (* 8 (- (index-of target parameters) 5)))
                               (ptr (typecode target) RSP offset)))]
        (with-spilled-variable target location prog predefined blocked
          (lambda (prog predefined blocked)
            (register-allocate prog
                               #:predefined predefined
                               #:blocked blocked
                               #:registers registers
                               #:parameters parameters
                               #:offset (if stack-param? offset (- offset 8))))))
      (save-and-use-registers prog colors parameters offset))))

(define (blocked-predefined blocked predefined)
  (find (lambda (x) (memv (cdr x) (map car blocked))) predefined))

(define (spill-blocked-predefines prog . args)
  (let-keywords args #f [(predefined '())
                         (blocked '())
                         (registers default-registers)
                         (parameters '())
                         (offset -8)]
    (let [(conflict (blocked-predefined blocked predefined))]
      (if conflict
        (let* [(target   (car conflict))
               (location (ptr (typecode target) RSP offset))]
        (with-spilled-variable target location prog predefined blocked
          (lambda (prog predefined blocked)
            (spill-blocked-predefines prog
                                      #:predefined predefined
                                      #:blocked blocked
                                      #:registers registers
                                      #:parameters parameters
                                      #:offset (- offset 8)))))
      (apply register-allocate (cons prog args))))))

(define* (virtual-variables result-vars arg-vars intermediate #:key (registers default-registers))
  (let* [(result-regs  (map cons result-vars (list RAX)))
         (arg-regs     (map cons arg-vars (list RDI RSI RDX RCX R8 R9)))]
    (spill-blocked-predefines (flatten-code (relabel (filter-blocks intermediate)))
                              #:predefined (append result-regs arg-regs)
                              #:blocked (blocked-intervals intermediate)
                              #:registers registers
                              #:parameters arg-vars)))

(define (repeat n . body)
  (let [(i (var (typecode n)))]
    (list (MOV i 0) 'begin (CMP i n) (JE 'end) (INC i) body (JMP 'begin) 'end)))

(define-class <block> ()
  (reg  #:init-keyword #:reg  #:getter get-reg)
  (code #:init-keyword #:code #:getter get-code))
(define (blocked reg . body)
  (make <block> #:reg reg #:code body))
(define (filter-blocks prog)
  (cond
    ((is-a? prog <block>) (filter-blocks (get-code prog)))
    ((list? prog)         (map filter-blocks prog))
    (else                 prog)))
(define ((bump-interval offset) interval)
  (cons (car interval) (cons (+ (cadr interval) offset) (+ (cddr interval) offset))))
(define code-length (compose length flatten-code filter-blocks))
(define (blocked-intervals prog)
  (cond
    ((is-a? prog <block>) (cons (cons (get-reg prog) (cons 0 (1- (code-length (get-code prog)))))
                            (blocked-intervals (get-code prog))))
    ((pair? prog) (append (blocked-intervals (car prog))
                    (map (bump-interval (code-length (list (car prog))))
                         (blocked-intervals (cdr prog)))))
    (else '())))

(define ((binary-cmp set1 set2) r a b)
  (list (CMP a b) ((if (signed? (typecode a)) set1 set2) r)))
(define ((binary-bool op) r a b)
  (let [(r1 (var <byte>))
        (r2 (var <byte>))]
    (list (TEST a a) (SETNE r1) (TEST b b) (SETNE r2) (op r1 r2) (MOV r r1))))
(define ((binary-cmov op1 op2) r a b)
  (if (= (size-of r) 1)
    (list (CMP a b) (MOV r a) ((if (signed? (typecode r)) op1 op2) r b))
    (list (CMP a b) (MOV r a) ((if (signed? (typecode r)) op1 op2) r b))))
(define (expand reg) (case (get-bits reg) ((8) (CBW)) ((16) (CWD)) ((32) (CDQ)) ((64) (CQO))))
(define (div/mod r a b pick)
  (let* [(size   (size-of r))
         (ax     (reg size 0))
         (dx     (reg size 2))
         (result (pick (cons ax dx)))]
    (blocked RAX
      (if (signed? (typecode r))
        (if (= size 1)
          (list (MOV ax a) (expand ax) (IDIV b) (blocked RDX (MOV DL AH) (MOV r result)))
          (list (MOV ax a) (blocked RDX (expand ax) (IDIV b) (MOV r result))))
        (if (= size 1)
          (list (MOVZX AX a) (DIV b) (blocked RDX (MOV DL AH) (MOV r result)))
          (list (MOV ax a) (blocked RDX (MOV dx 0) (DIV b) (MOV r result))))))))
(define (div r a b) (div/mod r a b car))
(define (mod r a b) (div/mod r a b cdr))
(define (sign-space a b)
  (let [(coerced (coerce a b))]
    (if (eqv? (signed? (typecode a)) (signed? (typecode b)))
      coerced
      (to-type (integer (min 64 (* 2 (bits (typecode coerced)))) signed) coerced))))
(define (shl r x) (blocked RCX (mov-part CL x) ((if (signed? (typecode r)) SAL SHL) r CL)))
(define (shr r x) (blocked RCX (mov-part CL x) ((if (signed? (typecode r)) SAR SHR) r CL)))

(define-method (skeleton (self <meta<element>>)) (make self #:value (var self)))
(define-method (skeleton (self <meta<sequence<>>>))
  (let [(slice (skeleton (project self)))]
    (make self
          #:value   (value slice)
          #:shape   (cons (var <long>) (shape   slice))
          #:strides (cons (var <long>) (strides slice)))))

(define-class <tensor> ()
  (dimension #:init-keyword #:dimension #:getter dimension)
  (index     #:init-keyword #:index     #:getter index)
  (term      #:init-keyword #:term      #:getter term))
(define (tensor dimension index term)
  (make <tensor> #:dimension dimension #:index index #:term term))
(define-class <lookup> ()
  (index    #:init-keyword #:index    #:getter index)
  (term     #:init-keyword #:term     #:getter term)
  (stride   #:init-keyword #:stride   #:getter stride)
  (iterator #:init-keyword #:iterator #:getter iterator)
  (step     #:init-keyword #:step     #:getter step))
(define-method (lookup index term stride iterator step)
  (make <lookup> #:index index #:term term #:stride stride #:iterator iterator #:step step))
(define-method (lookup idx (obj <tensor>) stride iterator step)
  (tensor (dimension obj) (index obj) (lookup idx (term obj) stride iterator step)))
(define-method (type (self <element>)) (typecode self))
(define-method (type (self <tensor>)) (sequence (type (term self))))
(define-method (type (self <lookup>)) (type (term self)))
(define-method (typecode (self <tensor>)) (typecode (type self)))
(define-method (shape (self <tensor>)) (attach (shape (term self)) (dimension self)))
(define-method (stride (self <tensor>)) (stride (term self))); TODO: get correct stride
(define-method (iterator (self <tensor>)) (iterator (term self))); TODO: get correct iterator
(define-method (step (self <tensor>)) (step (term self))); TODO: get correct step
(define-method (expression self) self); TODO: rename to parameter?
(define-method (expression (self <sequence<>>))
  (let [(idx (var <long>))]
    (tensor (dimension self)
            idx
            (lookup idx (expression (project self)) (stride self) (var <long>) (var <long>)))))
(define-method (subst self candidate replacement) self)
(define-method (subst (self <tensor>) candidate replacement)
  (tensor (dimension self) (index self) (subst (term self) candidate replacement)))
(define-method (subst (self <lookup>) candidate replacement)
  (lookup (if (eq? (index self) candidate) replacement (index self))
          (subst (term self) candidate replacement)
          (stride self)
          (iterator self)
          (step self)))
(define-method (value (self <tensor>)) (value (term self)))
(define-method (value (self <lookup>)) (value (term self)))
(define-method (rebase value (self <tensor>))
  (tensor (dimension self) (index self) (rebase value (term self))))
(define-method (rebase value (self <lookup>))
  (lookup (index self) (rebase value (term self)) (stride self) (iterator self) (step self))); TODO: still used?
(define-method (project (self <tensor>)) (project (term self) (index self)))
(define-method (project (self <tensor>) (idx <var>))
  (tensor (dimension self) (index self) (project (term self) idx)))
(define-method (project (self <lookup>) (idx <var>))
  (if (eq? (index self) idx)
      (term self)
      (lookup (index self) (project (term self)) (stride self) (iterator self) (step self)))); TODO: still used?
(define-method (get (self <tensor>) idx) (subst (term self) (index self) idx))

(define-class <function> ()
  (type      #:init-keyword #:type      #:getter type)
  (arguments #:init-keyword #:arguments #:getter arguments))

(define-method (setup self) '())
(define-method (setup (self <tensor>))
  (list (IMUL (step self) (stride self) (size-of (typecode self)))
        (MOV (iterator self) (value self))))
(define-method (setup (self <function>)) (concatenate (map setup (arguments self)))); TODO: redundant traversing code here
(define-method (increment self) '())
(define-method (increment (self <tensor>)) (list (ADD (iterator self) (step self))))
(define-method (increment (self <function>)) (concatenate (map increment (arguments self))))
(define-method (body self) self)
(define-method (body (self <tensor>)) (project (rebase (iterator self) self))); TODO: potential for simplification
(define-method (body (self <function>))
  (make <function> #:type (typecode (type self)) #:arguments (map (cut body <>) (arguments self))))

(define (mov-cmd a b)
  (cond ((eqv? (size-of b) (size-of a)) MOV)
        ((>    (size-of b) (size-of a)) mov-part)
        ((signed? b)                    MOVSX)
        (else                           MOVZX)))
(define-method (code (a <element>) (b <element>))
  (list ((mov-cmd a b) (get a) (get b))))
(define-method (code (a <element>) (b <pointer<>>))
  (list ((mov-cmd a (typecode b)) (get a) (ptr (typecode b) (get b)))))
(define-method (code (a <pointer<>>) (b <element>))
  (list (MOV (ptr (typecode a) (get a)) (get b))))
(define-method (code (a <pointer<>>) (b <pointer<>>))
  (let [(intermediate (skeleton (typecode a)))]
    (append (code intermediate b) (code a intermediate))))
(define-method (code (a <tensor>) b)
  (list (setup a)
        (setup b)
        (repeat (dimension a)
                (append (code (body a) (body b))
                        (increment a)
                        (increment b)))))

(define-method (add (a <element>) (b <element>))
  (if (eqv? (size-of b) (size-of a))
    (list (ADD (get a) (get b)))
    (let [(intermediate (skeleton (typecode a)))]
      (append (code intermediate b) (add a intermediate)))))
(define-method (add (a <element>) (b <pointer<>>))
  (if (eqv? (size-of (typecode b)) (size-of a))
    (list (ADD (get a) (ptr (typecode a) (get b))))
    (let [(intermediate (skeleton (typecode a)))]
      (append (code intermediate b) (add a intermediate)))))
(define-method (code (out <element>) (fun <function>))
  (append (code out (car (arguments fun))) (add out (cadr (arguments fun)))))
(define-method (code (out <pointer<>>) (fun <function>))
  (let [(intermediate (skeleton (typecode out)))]
    (append (code intermediate fun) (code out intermediate))))

(define-method (+ (a <element>) b); TODO: use base node class for tensor and element
  (make <function> #:arguments (list a b) #:type (coerce (type a) (type b))))
(define-method (+ (a <tensor>) b)
  (make <function> #:arguments (list a b) #:type (coerce (type a) (type b))))

(define-method (returnable self) #f)
(define-method (returnable (self <meta<bool>>)) <ubyte>)
(define-method (returnable (self <meta<int<>>>)) self)
(define (assemble retval vars expr virtual-variables)
  (virtual-variables (if (returnable (class-of retval)) (list (get retval)) '())
                     (concatenate (map content (if (returnable (class-of retval)) vars (cons retval vars))))
                     (attach (code (expression retval) expr) (RET))))

(define (jit context classes proc)
  (let* [(vars        (map skeleton classes))
         (expr        (apply proc (map expression vars)))
         (target      (type expr))
         (return-type (returnable target))
         (retval      (skeleton target))
         (args        (if return-type vars (cons retval vars)))
         (code        (asm context
                           (or return-type <null>)
                           (map typecode (concatenate (map content args)))
                           (assemble retval vars expr virtual-variables)))
         (fun         (lambda header (apply code (concatenate (map content header)))))]
    (if return-type
      (lambda args
        (let [(result (apply fun args))]
          (get (build target result))))
      (lambda args
        (let [(result (make target #:shape (argmax length (map shape args))))]
          (apply fun (cons result args))
          (get (build target result)))))))
;(define-class* <fragment<top>> <object> <meta<fragment<top>>> <class>
;              (name  #:init-keyword #:name  #:getter get-name)
;              (args  #:init-keyword #:args  #:getter get-args)
;              (code  #:init-keyword #:code  #:getter code)
;              (value #:init-keyword #:value #:getter value))
;(define-generic type)
;(define (fragment t)
;  (template-class (fragment t) (fragment (super t))
;    (lambda (class metaclass)
;      (define-method (type (self metaclass)) t)
;      (define-method (type (self class)) t))))
;(fragment <element>)
;(fragment <int<>>)
;(define-method (parameter self)
;  (make (fragment (class-of self)) #:args (list self) #:name parameter #:code '() #:value (get self)))
;(define-method (parameter (p <pointer<>>))
;  (let [(result (var (typecode p)))]
;    (make (fragment (typecode p))
;          #:args (list p)
;          #:name parameter
;          #:code (list (MOV result (ptr (typecode p) (get p))))
;          #:value result)))
;(pointer <rgb<>>)
;(pointer <complex<>>)
;(define-method (parameter (p <pointer<rgb<>>>))
;  (let [(result (var (typecode p)))
;        (size   (size-of (base (typecode p))))]
;    (make (fragment (typecode p))
;          #:args (list p)
;          #:name parameter
;          #:code (list (MOV (red   result) (ptr (base (typecode p)) (get p)          ))
;                       (MOV (green result) (ptr (base (typecode p)) (get p)      size))
;                       (MOV (blue  result) (ptr (base (typecode p)) (get p) (* 2 size))))
;          #:value result)))
;(define-method (parameter (p <pointer<complex<>>>))
;  (let [(result (var (typecode p)))
;        (size   (size-of (base (typecode p))))]
;    (make (fragment (typecode p))
;          #:args (list p)
;          #:name parameter
;          #:code (list (MOV (real-part result) (ptr (base (typecode p)) (get p)     ))
;                       (MOV (imag-part result) (ptr (base (typecode p)) (get p) size)))
;          #:value result)))
;(define-method (parameter (self <sequence<>>))
;  (make (fragment (class-of self)) #:args (list self) #:name parameter #:code '() #:value self))
;(define-method (to-type (target <meta<element>>) (self <meta<element>>))
;  target)
;(define-method (to-type (target <meta<element>>) (self <meta<sequence<>>>))
;  (multiarray target (dimensions self)))
;  (define-method (to-type (target <meta<element>>) (frag <fragment<element>>))
;    (let [(source (typecode (type frag)))]
;      (if (eq? target source)
;          frag
;          (let [(result (var target))
;                (mov    (if (>= (size-of source) (size-of target))
;                            mov-part
;                            (if (signed? source)
;                                MOVSX
;                                (if (>= (size-of source) 4) MOV MOVZX))))]
;            (make (fragment (to-type target (type frag)))
;                  #:args (list target frag)
;                  #:name to-type
;                  #:code (append (code frag) (list (mov result (value frag))))
;                  #:value result)))))
;(define (strip-code frag) (parameter (make (type frag) #:value (value frag))))
;(fragment <rgb<>>)
;(fragment <complex<>>)
;(define-method (to-type (target <meta<rgb<>>>) (frag <fragment<element>>))
;  (let* [(tmp    (strip-code frag))
;         (r      (to-type (base target) (red   tmp)))
;         (g      (to-type (base target) (green tmp)))
;         (b      (to-type (base target) (blue  tmp)))
;         (result (rgb r g b))]
;    (make (fragment (to-type target (type frag)))
;          #:args (list target frag)
;          #:name to-type
;          #:code (append (code frag) (code result))
;          #:value (value result))))
;(define-method (to-type (target <meta<complex<>>>) (frag <fragment<element>>))
;  (let* [(tmp    (strip-code frag))
;         (re     (to-type (base target) (real-part tmp)))
;         (im     (to-type (base target) (imag-part tmp)))
;         (result (complex re im))]
;    (make (fragment (to-type target (type frag)))
;          #:args (list target frag)
;          #:name to-type
;          #:code (append (code frag) (code result))
;          #:value (value result))))
;(define-method (rgb (r <fragment<element>>) (g <fragment<element>>) (b <fragment<element>>))
;  (let* [(target (reduce coerce #f (map type (list r g b))))
;         (r~     (to-type (typecode target) r))
;         (g~     (to-type (typecode target) g))
;         (b~     (to-type (typecode target) b))]
;     (make (fragment (rgb target))
;           #:args (list r g b)
;           #:name rgb
;           #:code (append (code r~) (code g~) (code b~))
;           #:value (make <rgb> #:red (value r~) #:green (value g~) #:blue (value b~)))))
;(define-method (complex (real <fragment<element>>) (imag <fragment<element>>))
;  (let* [(target (reduce coerce #f (map type (list real imag))))
;         (real~  (to-type (typecode target) real))
;         (imag~  (to-type (typecode target) imag))]
;     (make (fragment (complex target))
;           #:args (list real imag)
;           #:name complex
;           #:code (append (code real~) (code imag~))
;           #:value (make <internalcomplex> #:real-part (value real~) #:imag-part (value imag~)))))
;(fragment <pointer<>>)
;(fragment <sequence<>>)
;(define (mutable-unary op result a)
;  (append (code a) (list (MOV result (value a)) (op result))))
;(define (immutable-unary op result a)
;  (append (code a) (list (op result (value a)))))
;(define-syntax-rule (unary-op name mode op conversion)
;  (define-method (name (a <fragment<element>>))
;    (let* [(target (conversion (type a)))
;           (result (var (typecode target)))]
;      (make (fragment target)
;            #:args (list a)
;            #:name name
;            #:code (mode op result a)
;            #:value result))))
;(define (mutable-binary op result intermediate a b)
;  (let [(a~  (to-type intermediate a))
;        (b~  (to-type intermediate b))
;        (tmp (skeleton intermediate))]
;    (append (code a~) (code b~)
;            (list (MOV result    (value a~))
;                  (MOV (get tmp) (value b~))
;                  (op result (get tmp))))))
;(define (immutable-binary op result intermediate a b)
;  (let [(a~ (to-type intermediate a))
;        (b~ (to-type intermediate b))]
;    (append (code a~) (code b~)
;            (list (op result (value a~) (value b~))))))
;(define (shift-binary op result intermediate a b)
;  (append (code a) (code b) (list (MOV result (value a)) (op result (value b)))))
;(define-method (protect self fun) fun)
;(define-method (protect (self <meta<sequence<>>>) fun) list)
;(define-syntax-rule (binary-op name mode coercion op conversion)
;  (define-method (name (a <fragment<element>>) (b <fragment<element>>))
;    (let* [(intermediate (coercion (type a) (type b)))
;           (target       (conversion intermediate))
;           (result       (var (typecode target)))]
;      (make (fragment target)
;            #:args (list a b)
;            #:name name
;            #:code ((protect intermediate mode) op result intermediate a b)
;            #:value result))))
;
;(define-method (+ (self <fragment<element>>)) self)
;(define-method (conj (self <fragment<int<>>>)) self)
;(define-method (conj (self <fragment<sequence<>>>))
;  (make (class-of self)
;        #:args (list self)
;        #:name conj
;        #:code #f
;        #:value #f))
;
;(unary-op -      mutable-unary NEG identity)
;(unary-op ~      mutable-unary NOT identity)
;(unary-op =0     immutable-unary (lambda (r a) (list (TEST a a) (SETE r))) (cut to-type <bool> <>))
;(unary-op !=0    immutable-unary (lambda (r a) (list (TEST a a) (SETNE r))) (cut to-type <bool> <>))
;(binary-op +     mutable-binary   coerce     ADD                               identity)
;(binary-op -     mutable-binary   coerce     SUB                               identity)
;(binary-op *     mutable-binary   coerce     IMUL                              identity)
;(binary-op &     mutable-binary   coerce     AND                               identity)
;(binary-op |     mutable-binary   coerce     OR                                identity)
;(binary-op ^     mutable-binary   coerce     XOR                               identity)
;(binary-op <<    shift-binary     coerce     shl                               identity)
;(binary-op >>    shift-binary     coerce     shr                               identity)
;(binary-op /     immutable-binary coerce     div                               identity)
;(binary-op %     immutable-binary coerce     mod                               identity)
;(binary-op =     immutable-binary coerce     (binary-cmp SETE SETE)            (cut to-type <bool> <>))
;(binary-op !=    immutable-binary coerce     (binary-cmp SETNE SETNE)          (cut to-type <bool> <>))
;(binary-op <     immutable-binary sign-space (binary-cmp SETL SETB)            (cut to-type <bool> <>))
;(binary-op <=    immutable-binary sign-space (binary-cmp SETLE SETBE)          (cut to-type <bool> <>))
;(binary-op >     immutable-binary sign-space (binary-cmp SETNLE SETNBE)        (cut to-type <bool> <>))
;(binary-op >=    immutable-binary sign-space (binary-cmp SETNL SETNB)          (cut to-type <bool> <>))
;(binary-op &&    immutable-binary coerce     (binary-bool AND)                 (cut to-type <bool> <>))
;(binary-op ||    immutable-binary coerce     (binary-bool OR)                  (cut to-type <bool> <>))
;(binary-op min   immutable-binary sign-space (binary-cmov cmovnle16 cmovnbe16) identity)
;(binary-op max   immutable-binary sign-space (binary-cmov cmovl16 cmovb16)     identity)
;
;(define-method (peel (self <fragment<element>>)) self)
;(define-method (peel (self <fragment<rgb<>>>))
;  (make <rgb> #:red (red self) #:green (green self) #:blue (blue self)))
;(define-method (peel (self <fragment<complex<>>>))
;  (make <internalcomplex> #:real-part (real-part self) #:imag-part (imag-part self)))
;
;(define (do-unary-struct-op op self)
;  (let [(result (op (peel (strip-code self))))]
;    (make (fragment (type self))
;          #:args (list self)
;          #:name op
;          #:code (append (code self) (code result))
;          #:value (value result))))
;(define-syntax-rule (unary-struct-op struct op)
;  (define-method (op (a struct)) (do-unary-struct-op op a)))
;(define (do-binary-struct-op op a b coercion)
;  (let* [(target (coercion (type a) (type b)))
;         (result ((protect target op) (peel (strip-code a)) (peel (strip-code b))))]
;    (make (fragment target)
;          #:args (list a b)
;          #:name op
;          #:code (append (code a) (code b) ((protect target code) result))
;          #:value ((protect target value) result))))
;(define-syntax-rule (binary-struct-op struct op coercion)
;  (begin
;    (define-method (op (a struct) (b struct))
;      (do-binary-struct-op op a b coercion))
;    (define-method (op (a struct) (b <fragment<element>>))
;      (do-binary-struct-op op a b coercion))
;    (define-method (op (a <fragment<element>>) (b struct))
;      (do-binary-struct-op op a b coercion))))
;
;(unary-struct-op  <fragment<rgb<>>> -)
;(unary-struct-op  <fragment<rgb<>>> ~)
;(binary-struct-op <fragment<rgb<>>> +   coerce)
;(binary-struct-op <fragment<rgb<>>> -   coerce)
;(binary-struct-op <fragment<rgb<>>> *   coerce)
;(binary-struct-op <fragment<rgb<>>> &   coerce)
;(binary-struct-op <fragment<rgb<>>> |   coerce)
;(binary-struct-op <fragment<rgb<>>> ^   coerce)
;(binary-struct-op <fragment<rgb<>>> <<  coerce)
;(binary-struct-op <fragment<rgb<>>> >>  coerce)
;(binary-struct-op <fragment<rgb<>>> /   coerce)
;(binary-struct-op <fragment<rgb<>>> %   coerce)
;(binary-struct-op <fragment<rgb<>>> =   (const <bool>))
;(binary-struct-op <fragment<rgb<>>> !=  (const <bool>))
;(binary-struct-op <fragment<rgb<>>> max coerce)
;(binary-struct-op <fragment<rgb<>>> min coerce)
;
;(unary-struct-op  <fragment<complex<>>> -)
;(unary-struct-op  <fragment<complex<>>> conj)
;(binary-struct-op <fragment<complex<>>> + coerce)
;(binary-struct-op <fragment<complex<>>> - coerce)
;(binary-struct-op <fragment<complex<>>> * coerce)
;(binary-struct-op <fragment<complex<>>> / coerce)
;
;(define-method (project self) self)
;(define-method (project (self <fragment<sequence<>>>))
;  (apply (get-name self) (map project (get-args self))))
;(define-method (store (a <element>) (b <fragment<element>>))
;  (append (code b) (list (MOV (get a) (value b)))))
;(define (component self name)
;  (make (fragment (base (type self)))
;          #:args (list self)
;          #:name name
;          #:code (code self)
;          #:value ((protect (type self) name) (value self))))
;(define-method (red   (self <fragment<element>>)) (component self red  ))
;(define-method (green (self <fragment<element>>)) (component self green))
;(define-method (blue  (self <fragment<element>>)) (component self blue ))
;(define-method (real-part (self <fragment<element>>)) self)
;(define-method (real-part (self <fragment<complex<>>>)) (component self real-part))
;(define-method (real-part (self <fragment<sequence<>>>)) (component self real-part))
;(define-method (imag-part (self <fragment<element>>)) (component self imag-part))
;
;(define-method (store (p <pointer<>>) (a <fragment<element>>))
;  (append (code a) (list (MOV (ptr (typecode p) (get p)) (value a)))))
;(define-method (store (p <pointer<>>) (a <fragment<rgb<>>>))
;  (let [(size (size-of (base (typecode p))))]
;    (append (code a)
;            (list (MOV (ptr (base (typecode p)) (get p)           ) (red   (value a)))
;                  (MOV (ptr (base (typecode p)) (get p)       size) (green (value a)))
;                  (MOV (ptr (base (typecode p)) (get p) (* 2 size)) (blue  (value a)))))))
;(define-method (store (p <pointer<>>) (a <fragment<complex<>>>))
;  (let [(size (size-of (base (typecode p))))]
;    (append (code a)
;            (list (MOV (ptr (base (typecode p)) (get p)     ) (real-part (value a)))
;                  (MOV (ptr (base (typecode p)) (get p) size) (imag-part (value a)))))))
;(define-class <elementwise> ()
;  (setup     #:init-keyword #:setup     #:getter get-setup)
;  (increment #:init-keyword #:increment #:getter get-increment)
;  (body      #:init-keyword #:body      #:getter get-body))
;(define-method (element-wise self)
;  (make <elementwise> #:setup '() #:increment '() #:body self))
;(define-method (element-wise (s <sequence<>>))
;  (let [(incr (var <long>))
;        (p    (var <long>))]
;    (make <elementwise>
;          #:setup (list (IMUL incr (last (strides s)) (size-of (typecode s)))
;                        (MOV p (value s)))
;          #:increment (list (ADD p incr))
;          #:body (project (rebase p s)))))
;(define-method (element-wise (self <fragment<sequence<>>>))
;  (let [(loops (map element-wise (get-args self)))]
;    (make <elementwise>
;          #:setup (map get-setup loops)
;          #:increment (map get-increment loops)
;          #:body (apply (get-name self) (map get-body loops)))))
;(define-method (store (s <sequence<>>) (a <fragment<sequence<>>>))
;  (let [(destination (element-wise s))
;        (source      (element-wise a))]
;    (list (get-setup destination)
;          (get-setup source)
;          (repeat (last (shape s))
;                  (append (store (get-body destination) (get-body source))
;                          (get-increment destination)
;                          (get-increment source))))))
;
