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
  #:use-module (aiscm sequence)
  #:export (<block> <cmd> <var> <ptr>
            substitute-variables variables get-args input output labels next-indices live-analysis
            callee-saved save-registers load-registers
            spill-variable save-and-use-registers register-allocate
            pass-parameter-variables virtual-variables flatten-code relabel
            collate translate idle-live fetch-parameters spill-parameters
            filter-blocks blocked-intervals
            fragment type compose-from decompose skel
            <pointer<rgb<>>> <meta<pointer<rgb<>>>>
            <fragment<top>> <meta<fragment<top>>>
            <fragment<element>> <meta<fragment<element>>>
            <fragment<rgb<>>> <meta<fragment<rgb<>>>>
            <fragment<pointer<>>> <meta<fragment<pointer<>>>>
            <fragment<sequence<>>> <meta<fragment<sequence<>>>>
            parameter code get-args get-op get-name to-type type assemble jit
            ~ & | ^ =0 !=0 != && ||)
  #:export-syntax (let-vars blocked until for repeat))

(define-method (get-args self) '())
(define-method (input self) '())
(define-method (output self) '())
(define-class <cmd> ()
  (op #:init-keyword #:op #:getter get-op)
  (args #:init-keyword #:args #:getter get-args)
  (input #:init-keyword #:input #:getter get-input)
  (output #:init-keyword #:output #:getter get-output))
(define-method (initialize (self <cmd>) initargs)
  (let-keywords initargs #f (op (out '()) (io '()) (in '()))
    (next-method self (list #:op op
                            #:args (append out io in)
                            #:input (append io in)
                            #:output (append io out)))))

(define-method (input (self <cmd>))
  (delete-duplicates
    (filter is-var?
            (concatenate (cons (get-input self)
                               (map get-args
                                    (filter is-ptr? (get-args self))))))))
(define-method (output (self <cmd>)) (delete-duplicates (filter is-var? (get-output self))))
(define-method (write (self <cmd>) port)
  (write (cons (generic-function-name (get-op self)) (get-args self)) port))
(define-class <var> ()
  (type #:init-keyword #:type #:getter typecode)
  (symbol #:init-keyword #:symbol #:init-form (gensym)))
(define-method (write (self <var>) port) (write (slot-ref self 'symbol) port))
(define (is-var? value) (is-a? value <var>))
(define-class <ptr> ()
  (type #:init-keyword #:type #:getter typecode)
  (args #:init-keyword #:args #:getter get-args))
(define-method (write (self <ptr>) port)
  (display (cons 'ptr (cons (class-name (typecode self)) (get-args self))) port))
(define (is-ptr? value) (is-a? value <ptr>))
(define-method (substitute-variables self alist) self)
(define-method (substitute-variables (self <var>) alist)
  (let [(target (assq-ref alist self))]
    (if (is-a? target <register>)
      (reg (size-of (typecode self)) (get-code target)); TODO: do type conversion elsewhere
      (or target self))))
(define-method (substitute-variables (self <ptr>) alist)
  (apply ptr (cons (typecode self) (map (cut substitute-variables <> alist) (get-args self)))))
(define-method (substitute-variables (self <cmd>) alist)
  (apply (get-op self) (map (cut substitute-variables <> alist) (get-args self))))
(define-method (substitute-variables (self <list>) alist) (map (cut substitute-variables <> alist) self))

(define-syntax let-vars
  (syntax-rules ()
    ((let-vars [(name type) vars ...] body ...)
     (let [(name (make <var> #:type type #:symbol (quote name)))]
       (let-vars [vars ...] body ...)))
    ((let-vars [] body ...)
     (begin body ...))))

(define-method (ptr (type <meta<element>>) . args)
  (make <ptr> #:type type #:args args))

(define-method (MOV arg1 arg2) (make <cmd> #:op MOV #:out (list arg1) #:in (list arg2)))
(define-method (MOVSX arg1 arg2) (make <cmd> #:op MOVSX #:out (list arg1) #:in (list arg2)))
(define-method (MOVZX arg1 arg2) (make <cmd> #:op MOVZX #:out (list arg1) #:in (list arg2)))
(define-method (LEA arg1 arg2) (make <cmd> #:op LEA #:out (list arg1) #:in (list arg2)))
(define-method (SHL arg) (make <cmd> #:op SHL #:io (list arg)))
(define-method (SHR arg) (make <cmd> #:op SHR #:io (list arg)))
(define-method (SAL arg) (make <cmd> #:op SAL #:io (list arg)))
(define-method (SAR arg) (make <cmd> #:op SAR #:io (list arg)))
(define-method (ADD arg1 arg2) (make <cmd> #:op ADD #:io (list arg1) #:in (list arg2)))
(define-method (PUSH arg) (make <cmd> #:op PUSH #:in (list arg)))
(define-method (POP arg) (make <cmd> #:op POP #:out (list arg)))
(define-method (NOT arg) (make <cmd> #:op NOT #:io (list arg)))
(define-method (NEG arg) (make <cmd> #:op NEG #:io (list arg)))
(define-method (INC arg) (make <cmd> #:op INC #:io (list arg)))
(define-method (SUB arg1 arg2) (make <cmd> #:op SUB #:io (list arg1) #:in (list arg2)))
(define-method (IMUL arg1 . args) (make <cmd> #:op IMUL #:io (list arg1) #:in args))
(define-method (IDIV arg) (make <cmd> #:op IDIV #:io (list arg)))
(define-method (DIV arg) (make <cmd> #:op DIV #:io (list arg)))
(define-method (AND arg1 arg2) (make <cmd> #:op AND #:io (list arg1) #:in (list arg2)))
(define-method (OR arg1 arg2) (make <cmd> #:op OR #:io (list arg1) #:in (list arg2)))
(define-method (XOR arg1 arg2) (make <cmd> #:op XOR #:io (list arg1) #:in (list arg2)))
(define-method (CMP arg1 arg2) (make <cmd> #:op CMP #:in (list arg1 arg2)))
(define-method (TEST arg1 arg2) (make <cmd> #:op TEST #:in (list arg1 arg2)))
(define-method (SETB   arg) (make <cmd> #:op SETB   #:out (list arg)))
(define-method (SETNB  arg) (make <cmd> #:op SETNB  #:out (list arg)))
(define-method (SETE   arg) (make <cmd> #:op SETE   #:out (list arg)))
(define-method (SETNE  arg) (make <cmd> #:op SETNE  #:out (list arg)))
(define-method (SETBE  arg) (make <cmd> #:op SETBE  #:out (list arg)))
(define-method (SETNBE arg) (make <cmd> #:op SETNBE #:out (list arg)))
(define-method (SETL   arg) (make <cmd> #:op SETL   #:out (list arg)))
(define-method (SETNL  arg) (make <cmd> #:op SETNL  #:out (list arg)))
(define-method (SETLE  arg) (make <cmd> #:op SETLE  #:out (list arg)))
(define-method (SETNLE arg) (make <cmd> #:op SETNLE #:out (list arg)))

(define (variables prog) (delete-duplicates (filter is-var? (concatenate (map get-args prog)))))
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
  (concatenate (map (lambda (x)
                      (if (and (list? x) (not (every integer? x)))
                        (flatten-code x)
                        (list x))) prog)))

(define ((insert-temporary var) cmd)
  (let-vars [(temporary (typecode var))]
    (compact
      (and (memv var (input cmd)) (MOV temporary var))
      (substitute-variables cmd (list (cons var temporary)))
      (and (memv var (output cmd)) (MOV var temporary)))))
(define (spill-variable var location prog)
  (substitute-variables (map (insert-temporary var) prog) (list (cons var location))))

(define ((idle-live prog live) var)
  (count (lambda (cmd active) (and (not (memv var (get-args cmd))) (memv var active))) prog live))
(define ((spill-parameters parameters) colors)
  (filter-map (lambda (parameter register)
    (let [(value (assq-ref colors parameter))]; TODO: do type conversion elsewhere
      (if (is-a? value <address>) (MOV value (reg (size-of (typecode parameter)) (get-code register))) #f)))
    parameters (list RDI RSI RDX RCX R8 R9)))
(define ((fetch-parameters parameters) colors)
  (filter-map (lambda (parameter offset)
    (let [(value (assq-ref colors parameter))]
      (if (is-a? value <register>) (MOV (reg (size-of (typecode parameter)) (get-code value))
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
         (colors     (color-intervals intervals
                                      vars
                                      registers
                                      #:predefined predefined
                                      #:blocked blocked))
         (unassigned (find (compose not cdr) (reverse colors)))]
    (if unassigned
      (let* [(participants ((overlap intervals) (car unassigned)))
             (var          (argmax (idle-live prog live) participants))
             (stack-param? (and (index var parameters) (<= 6 (index var parameters))))
             (location     (if stack-param?
                               (ptr (typecode var) RSP (* 8 (- (index var parameters) 5)))
                               (ptr (typecode var) RSP offset)))
             (spill-code   (spill-variable var location prog))]
        (register-allocate (flatten-code spill-code)
                           #:predefined (assq-set predefined var location)
                           #:blocked (update-intervals blocked (index-groups spill-code))
                           #:registers registers
                           #:parameters parameters
                           #:offset (if stack-param? offset (- offset 8))))
      (save-and-use-registers prog colors parameters offset))))

(define* (virtual-variables result-vars arg-vars intermediate #:key (registers default-registers))
  (let* [(result-regs  (map cons result-vars (list RAX)))
         (arg-regs     (map cons arg-vars (list RDI RSI RDX RCX R8 R9)))
         (predefined   (append result-regs arg-regs))
         (blocked      (blocked-intervals intermediate))
         (prog         (flatten-code (relabel (filter-blocks intermediate))))]
    (register-allocate prog
                       #:predefined predefined
                       #:blocked blocked
                       #:registers registers
                       #:parameters arg-vars)))

(define* (pass-parameter-variables result-type arg-types proc #:key (registers default-registers))
  (let* [(result-types (if (eq? result-type <null>) '() (list result-type)))
         (arg-vars     (map (cut make <var> #:type <>) arg-types))
         (result-vars  (map (cut make <var> #:type <>) result-types))
         (vars         (append result-vars arg-vars))
         (intermediate (apply proc vars))]
    (virtual-variables result-vars arg-vars intermediate #:registers registers)))

(define (collate classes vars)
  (map param classes (gather (map (compose length types) classes) vars)))
(define (translate ctx result-type arg-classes proc)
  (let* [(arg-types    (concatenate (map types arg-classes)))
         (result-types (if (eq? result-type <null>) '() (list result-type)))
         (code         (asm ctx result-type arg-types
                         (pass-parameter-variables result-type arg-types
                           (lambda args (apply proc (collate (append result-types arg-classes) args))))))]
    (lambda params (apply code (concatenate (map content params))))))

(define-syntax-rule (until condition body ...)
  (list 'begin condition (JE 'end) body ... (JMP 'begin) 'end))
(define-syntax-rule (for [(index type) setup condition step] body ...)
  (let-vars [(index type)] (list setup (until condition body ... step))))
(define-syntax-rule (repeat n body ...)
  (for [(i (typecode n)) (MOV i 0) (CMP i n) (INC i)] body ...))

(define-class <block> ()
  (reg #:init-keyword #:reg #:getter get-reg)
  (code #:init-keyword #:code #:getter get-code))
(define-syntax-rule (blocked reg body ...)
  (make <block> #:reg reg #:code (list body ...)))
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
  (let-vars [(r1 <bool>)
             (r2 <bool>)]
    (list (TEST a a) (SETNE r1) (TEST b b) (SETNE r2) (op r1 r2) (MOV r r1))))
(define (divide r a b)
  (let* [(size (size-of (typecode r)))
         (ax   (reg size 0))
         (dx   (reg size 2))]
    (blocked RAX
      (if (signed? (typecode r))
        (if (= size 1)
          (list
            (MOV AL a)
            (CBW)
            (IDIV b)
            (MOV r AL))
          (list
            (MOV ax a)
            (blocked RDX
              (case size ((2) (CWD)) ((4) (CDQ)) ((8) (CQO)))
              (IDIV b)
              (MOV r ax))))
        (if (= size 1)
          (list
            (MOVZX AX a)
            (DIV b)
            (MOV r AL))
          (list
            (MOV ax a)
            (blocked RDX
              (MOV dx 0)
              (DIV b)
              (MOV r ax))))))))
(define (sign-space a b)
  (let [(coerced (coerce a b))]
    (if (eq? (signed? (typecode a)) (signed? (typecode b)))
      coerced
      (to-type (integer (min 64 (* 2 (bits (typecode coerced)))) signed) coerced))))
(define-class* <fragment<top>> <object> <meta<fragment<top>>> <class>
              (name #:init-keyword #:name #:getter get-name)
              (args #:init-keyword #:args #:getter get-args)
              (code #:init-keyword #:code #:getter code))
(define-generic type)
(define (fragment t)
  (template-class (fragment t) (fragment (super t))
    (lambda (class metaclass)
      (define-method (type (self metaclass)) t))))
(fragment <element>)
(define-method (parameter (var <var>))
  (make (fragment (typecode var))
        #:args (list var)
        #:name parameter
        #:code (lambda (result) (list (MOV result var)))))
(pointer <rgb<>>)
(define-method (parameter (p <pointer<rgb<>>>))
  (make (fragment (typecode p))
        #:args (list p)
        #:name parameter
        #:code (lambda (result) (list (MOV (red   result) (ptr (base (typecode p)) (get-value p)  ))
                                      (MOV (green result) (ptr (base (typecode p)) (get-value p) 1))
                                      (MOV (blue  result) (ptr (base (typecode p)) (get-value p) 2))))))
(define-method (parameter (p <pointer<>>))
  (make (fragment (typecode p))
        #:args (list p)
        #:name parameter
        #:code (lambda (result) (list (MOV result (ptr (typecode p) (get-value p)))))))
(define-method (parameter (s <sequence<>>))
  (make (fragment (class-of s))
        #:args (list s)
        #:name parameter
        #:code (lambda (result) '())))
(define-method (to-type (target <meta<element>>) (self <meta<element>>))
  target)
(define-method (to-type (target <meta<element>>) (self <meta<sequence<>>>))
  (multiarray target (dimension self)))
(define-method (to-type (target <meta<element>>) (frag <fragment<element>>))
  (let* [(source (typecode (type (class-of frag))))
         (tmp    (make <var> #:type source))
         (mov    (if (>= (size-of source) (size-of target))
                     MOV
                     (if (signed? source)
                         MOVSX
                         (if (>= (size-of source) 4) MOV MOVZX))))]
    (make (fragment (to-type target (type (class-of frag))))
          #:args (list target frag)
          #:name to-type
          #:code (lambda (result)
                         (append ((code frag) tmp) (list (mov result tmp)))))))
(fragment <pointer<>>)
(fragment <sequence<>>)
(define (mutable-unary op a)
  (lambda (result) (append ((code a) result) (list (op result)))))
(define (immutable-unary op a)
  (let-vars [(tmp (type (class-of a)))]
    (lambda (result) (append ((code a) tmp) (list (op result tmp))))))
(define-syntax-rule (unary-op name mode op conversion)
  (define-method (name (a <fragment<element>>))
    (let* [(target (conversion (type (class-of a))))]
      (make (fragment target)
            #:args (list a)
            #:name name
            #:code (mode op a)))))
(unary-op - mutable-unary NEG identity)
(unary-op ~ mutable-unary NOT identity)
(unary-op =0 immutable-unary (lambda (r a) (list (TEST a a) (SETE r))) (cut to-type <bool> <>))
(unary-op !=0 immutable-unary (lambda (r a) (list (TEST a a) (SETNE r))) (cut to-type <bool> <>))
; TODO: unary operation conj
; TODO: unary operation abs (scalar)
; TODO: unary operation arg (float-scalar)
; TODO: unary operation floor
; TODO: unary operation ceil
; TODO: unary operation round
(define (mutable-binary op intermediate a b)
  (let-vars [(tmp intermediate)]
    (lambda (result) (append ((code (to-type intermediate a)) result)
                             ((code (to-type intermediate b)) tmp)
                             (list (op result tmp))))))
(define (immutable-binary op intermediate a b)
  (let-vars [(tmp1 intermediate)
             (tmp2 intermediate)]
    (lambda (result) (append ((code (to-type intermediate a)) tmp1)
                             ((code (to-type intermediate b)) tmp2)
                             (list (op result tmp1 tmp2))))))
(define-syntax-rule (binary-op name mode coercion op conversion)
  (define-method (name (a <fragment<element>>) (b <fragment<element>>))
    (let* [(intermediate (coercion (type (class-of a)) (type (class-of b))))
           (target       (conversion intermediate))]
      (make (fragment target)
            #:args (list a b)
            #:name name
            #:code (mode op intermediate a b)))))
(binary-op + mutable-binary coerce ADD identity)
(binary-op - mutable-binary coerce SUB identity)
(binary-op * mutable-binary coerce IMUL identity)
(binary-op & mutable-binary coerce AND identity)
(binary-op | mutable-binary coerce OR identity)
(binary-op ^ mutable-binary coerce XOR identity)
(binary-op / immutable-binary coerce divide identity)
(binary-op = immutable-binary coerce (binary-cmp SETE SETE) (cut to-type <bool> <>))
(binary-op != immutable-binary coerce (binary-cmp SETNE SETNE) (cut to-type <bool> <>))
(binary-op < immutable-binary sign-space (binary-cmp SETL SETB) (cut to-type <bool> <>))
(binary-op <= immutable-binary sign-space (binary-cmp SETLE SETBE) (cut to-type <bool> <>))
(binary-op > immutable-binary sign-space (binary-cmp SETNLE SETNBE) (cut to-type <bool> <>))
(binary-op >= immutable-binary sign-space (binary-cmp SETNL SETNB) (cut to-type <bool> <>))
(binary-op && immutable-binary coerce (binary-bool AND) (cut to-type <bool> <>))
(binary-op || immutable-binary coerce (binary-bool OR) (cut to-type <bool> <>))
; TODO: binary operation ** (coercion-maxint)
; TODO: binary operation %
; TODO: binary operation fmod
; TODO: binary operation and (coercion-bool)
; TODO: binary operation or (coercion-bool)
; TODO: binary operation <<
; TODO: binary operation >>
; TODO: conditional -> minor, major
(define-method (compose-from (self <meta<element>>) vars) (param self vars)); TODO: <-> param
(define-method (compose-from (self <meta<pointer<>>>) vars) (make self #:value (car vars)))
(define-method (decompose (self <var>)) (list self))
(define-method (decompose (self <pointer<>>)) (list (get-value self))); TODO: <-> content
(define-method (decompose (self <sequence<>>))
  (append (map last (list (shape self) (strides self))) (decompose (project self))))
(define (skel self)
  (compose-from self (map (cut make <var> #:type <>) (types self))))
(define-method (project self) self)
(define-method (project (self <fragment<sequence<>>>))
  (apply (get-name self) (map project (get-args self))))
(define-method (store (a <var>) (b <fragment<element>>))
  ((code b) a))
(fragment <rgb<>>)
(define-method (store (a <rgb>) (b <fragment<rgb<>>>))
  ((code b) a))
(define-method (store (p <pointer<>>) (a <fragment<element>>))
  (let-vars [(tmp (type (class-of a)))]
    (append (store tmp a) (list (MOV (ptr (typecode p) (get-value p)) tmp)))))
(define-method (store (p <pointer<rgb<>>>) (a <fragment<rgb<>>>))
  (let [(tmp (skel (typecode p)))]
    (append (store tmp a) (list (MOV (ptr (base (typecode p)) (get-value p)  ) (red   tmp))
                                (MOV (ptr (base (typecode p)) (get-value p) 1) (green tmp))
                                (MOV (ptr (base (typecode p)) (get-value p) 2) (blue  tmp))))))
(define-method (element-wise s)
  (list '() '() s))
(define-method (element-wise (s <sequence<>>))
  (let-vars [(incr  <long>)
             (p     <long>)]
    (list (list (IMUL incr (last (strides s)) (size-of (typecode s)))
                (MOV p (get-value s)))
          (list (ADD p incr))
          (project (rebase p s)))))
(define-method (element-wise (self <fragment<sequence<>>>))
  (let [(loops (map element-wise (get-args self)))]
    (list (map setup loops)
          (map increment loops)
          (apply (get-name self) (map body loops)))))
(define setup car)
(define increment cadr)
(define body caddr)
(define-method (store (s <sequence<>>) (a <fragment<sequence<>>>))
  (let [(destination (element-wise s))
        (source      (element-wise a))]
    (list (setup destination)
          (setup source)
          (repeat (last (shape s))
                  (append (store (body destination) (body source))
                          (increment destination)
                          (increment source))))))
(define (returnable? value) (is-a? value <var>))
(define (assemble retval vars fragment)
  (virtual-variables (if (returnable? retval) (list retval) '())
                     (concatenate (map decompose (if (returnable? retval) vars (cons retval vars))))
                     (append (store retval fragment) (list (RET)))))
(define (jit ctx classes proc); TODO: how to return boolean?
  (let* [(vars        (map skel classes))
         (fragment    (apply proc (map parameter vars)))
         (return-type (type (class-of fragment)))
         (retval      (skel return-type))
         (fun         (asm ctx
                           (if (returnable? retval) return-type <null>)
                           (concatenate
                             (map types (if (returnable? retval) classes (cons return-type classes))))
                           (assemble retval vars fragment)))]
    (if (returnable? retval)
        (lambda args
                (apply fun (concatenate (map content args))))
        (lambda args
                (let [(result (make return-type #:shape (argmax length (map shape args))))]
                  (apply fun (concatenate (map content (cons result args))))
                  result)))))
