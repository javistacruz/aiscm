;; AIscm - Guile extension for numerical arrays and tensors.
;; Copyright (C) 2013, 2014, 2015, 2016, 2017 Jan Wedekind <jan@wedesoft.de>
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
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
  #:use-module (aiscm composite)
  #:use-module (aiscm scalar)
  #:use-module (aiscm pointer)
  #:use-module (aiscm bool)
  #:use-module (aiscm int)
  #:use-module (aiscm float)
  #:use-module (aiscm obj)
  #:use-module (aiscm method)
  #:use-module (aiscm sequence)
  #:use-module (aiscm composite)
  #:export (<block> <cmd> <var> <ptr> <param> <indexer> <lookup> <function>
            substitute-variables variables get-args input output get-ptr-args labels next-indices
            initial-register-use find-available-register mark-used-till spill-candidate ignore-spilled-variables
            ignore-blocked-registers live-analysis
            unallocated-variables register-allocations assign-spill-locations add-spill-information
            blocked-predefined move-blocked-predefined non-blocked-predefined
            first-argument replace-variables adjust-stack-pointer default-registers
            register-parameters stack-parameters
            register-parameter-locations stack-parameter-locations parameter-locations
            need-to-copy-first move-variable-content update-parameter-locations
            place-result-variable used-callee-saved backup-registers add-stack-parameter-information
            number-spilled-variables temporary-variables unit-intervals temporary-registers
            sort-live-intervals linear-scan-coloring linear-scan-allocate callee-saved caller-saved
            blocked repeat mov-signed mov-unsigned virtual-variables flatten-code relabel
            filter-blocks blocked-intervals native-equivalent var skeleton parameter delegate
            term indexer lookup index type subst code convert-type assemble build-list package-return-content
            jit iterator step setup increment body arguments operand insert-intermediate
            is-pointer? need-conversion? code-needs-intermediate? call-needs-intermediate?
            force-parameters shl shr sign-extend-ax div mod
            test-zero ensure-default-strides unary-extract mutating-code functional-code decompose-value
            decompose-arg delegate-fun generate-return-code
            make-function make-native-function native-call make-constant-function native-const
            scm-eol scm-cons scm-gc-malloc-pointerless scm-gc-malloc)
  #:re-export (min max to-type + - && || ! != ~ & | ^ << >> % =0 !=0 conj)
  #:export-syntax (define-jit-method define-operator-mapping pass-parameters tensor))

(define ctx (make <context>))

; class for defining input and output variables of machine instructions
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
(define-method (equal? (a <cmd>) (b <cmd>)) (equal? (object-slots a) (object-slots b)))

(define (get-ptr-args cmd)
  "get variables used as a pointer in a command"
  (filter (cut is-a? <> <var>) (append-map get-args (filter (cut is-a? <> <ptr>) (get-args cmd)))))

(define-syntax-rule (mutating-op op)
  (define-method (op . args) (make <cmd> #:op op #:io (list (car args)) #:in (cdr args))))
(define-syntax-rule (functional-op op)
  (define-method (op . args) (make <cmd> #:op op #:out (list (car args)) #:in (cdr args))))
(define-syntax-rule (state-setting-op op)
  (define-method (op . args) (make <cmd> #:op op #:in args)))
(define-syntax-rule (state-reading-op op)
  (define-method (op . args) (make <cmd> #:op op #:out args)))

(define (mov-part a b) (MOV a (to-type (integer (* 8 (size-of a)) signed) b)))
(define (movzx32 a b) (MOV (to-type (integer (* 8 (size-of b))unsigned) a) b))
(define (mov-cmd movxx movxx32 a b)
  (cond
        ((eqv? (size-of a) (size-of b)) MOV)
        ((<    (size-of a) (size-of b)) mov-part)
        ((eqv? (size-of b) 4)           movxx32)
        (else                           movxx)))
(define-method (mov-signed   (a <operand>) (b <operand>)) ((mov-cmd MOVSX MOVSX   a b) a b))
(define-method (mov-unsigned (a <operand>) (b <operand>)) ((mov-cmd MOVZX movzx32 a b) a b))
(define (mov a b)
  (list ((if (or (eq? (typecode b) <bool>) (signed? b)) mov-signed mov-unsigned) a b)))

(functional-op    mov-signed  )
(functional-op    mov-unsigned)
(functional-op    MOV         )
(functional-op    MOVSX       )
(functional-op    MOVZX       )
(functional-op    LEA         )
(mutating-op      SHL         )
(mutating-op      SHR         )
(mutating-op      SAL         )
(mutating-op      SAR         )
(state-setting-op PUSH        )
(state-reading-op POP         )
(mutating-op      NEG         )
(mutating-op      NOT         )
(mutating-op      AND         )
(mutating-op      OR          )
(mutating-op      XOR         )
(mutating-op      INC         )
(mutating-op      ADD         )
(mutating-op      SUB         )
(mutating-op      IMUL        )
(mutating-op      IDIV        )
(mutating-op      DIV         )
(state-setting-op CMP         )
(state-setting-op TEST        )
(state-reading-op SETB        )
(state-reading-op SETNB       )
(state-reading-op SETE        )
(state-reading-op SETNE       )
(state-reading-op SETBE       )
(state-reading-op SETNBE      )
(state-reading-op SETL        )
(state-reading-op SETNL       )
(state-reading-op SETLE       )
(state-reading-op SETNLE      )
(mutating-op      CMOVB       )
(mutating-op      CMOVNB      )
(mutating-op      CMOVE       )
(mutating-op      CMOVNE      )
(mutating-op      CMOVBE      )
(mutating-op      CMOVNBE     )
(mutating-op      CMOVL       )
(mutating-op      CMOVNL      )
(mutating-op      CMOVLE      )
(mutating-op      CMOVNLE     )

(define-class <var> ()
  (type   #:init-keyword #:type   #:getter typecode)
  (symbol #:init-keyword #:symbol #:init-form (gensym)))
(define-method (write (self <var>) port)
  (format port "~a:~a" (symbol->string (slot-ref self 'symbol)) (class-name (slot-ref self 'type))))
(define-method (size-of (self <var>)) (size-of (typecode self)))
(define-class <ptr> ()
  (type #:init-keyword #:type #:getter typecode)
  (args #:init-keyword #:args #:getter get-args))
(define-method (write (self <ptr>) port)
  (display (cons 'ptr (cons (class-name (typecode self)) (get-args self))) port))
(define-method (equal? (a <ptr>) (b <ptr>)) (equal? (object-slots a) (object-slots b)))
(define-method (ptr (type <meta<element>>) . args) (make <ptr> #:type type #:args args))
(define-method (variables self) '())
(define-method (variables (self <var>)) (list self))
(define-method (variables (self <cmd>)) (variables (get-args self)))
(define-method (variables (self <ptr>)) (variables (get-args self)))
(define-method (variables (self <list>)) (delete-duplicates (append-map variables self)))
(define-method (input (self <cmd>))
  (delete-duplicates (variables (append (get-input self) (filter (cut is-a? <> <ptr>) (get-args self))))))
(define-method (output (self <cmd>)) (variables (get-output self)))
(define-method (substitute-variables self alist) self)

(define-method (substitute-variables (self <var>) alist)
  "replace variable with associated value if there is one"
  (let [(target (assq-ref alist self))]
    (if (or (is-a? target <register>) (is-a? target <address>))
      (to-type (typecode self) target)
      (or target self))))
(define-method (substitute-variables (self <ptr>) alist)
  (let [(target (substitute-variables (car (get-args self)) alist))]
    (if (is-a? target <pair>)
      (ptr (typecode self) (car target) (+ (cadr (get-args self)) (cdr target)))
      (apply ptr (typecode self) target (cdr (get-args self))))))
(define-method (substitute-variables (self <cmd>) alist)
  (apply (get-op self) (map (cut substitute-variables <> alist) (get-args self))))
(define-method (substitute-variables (self <list>) alist) (map (cut substitute-variables <> alist) self))

(define-method (native-type (i <real>) . args); TODO: remove this when floating point support is ready
  (if (every real? args)
      <obj>
      (apply native-type (sort-by-pred (cons i args) real?))))

(define-method (native-equivalent  self                   ) #f      )
(define-method (native-equivalent (self <meta<bool>>     )) <ubyte> )
(define-method (native-equivalent (self <meta<int<>>>    )) self    )
(define-method (native-equivalent (self <meta<float<>>>  )) self    )
(define-method (native-equivalent (self <meta<obj>>      )) <ulong> )
(define-method (native-equivalent (self <meta<pointer<>>>)) <ulong> )

(define-method (var self) (make <var> #:type (native-equivalent self)))

(define (labels prog)
  "Get positions of labels in program"
  (filter (compose symbol? car) (map cons prog (iota (length prog)))))

(define (initial-register-use registers)
  "Initially all registers are available from index zero on"
  (map (cut cons <> 0) registers))

(define (sort-live-intervals live-intervals predefined-variables)
  "Sort live intervals predefined variables first and then lexically by start point and length of interval"
  (sort-by live-intervals
           (lambda (live) (if (memv (car live) predefined-variables) -1 (- (cadr live) (/ 1 (+ 2 (cddr live))))))))

(define (find-available-register availability first-index)
  "Find register available from the specified first program index onwards"
  (car (or (find (compose (cut <= <> first-index) cdr) availability) '(#f))))

(define (mark-used-till availability element last-index)
  "Mark element in use up to specified index"
  (assq-set availability element (1+ last-index)))

(define (spill-candidate variable-use)
  "Select variable blocking for the longest time as a spill candidate"
  (car (argmax cdr variable-use)))

(define (ignore-spilled-variables variable-use allocation)
  "Remove spilled variables from the variable use list"
  (filter (compose (lambda (var) (cdr (or (assq var allocation) (cons var #t)))) car) variable-use))

(define (ignore-blocked-registers availability interval blocked)
  "Remove blocked registers from the availability list"
  (apply assq-remove availability ((overlap-interval blocked) interval)))

(define-method (next-indices labels cmd k)
  "Determine next program indices for a statement"
  (if (equal? cmd (RET)) '() (list (1+ k))))
(define-method (next-indices labels (cmd <jcc>) k)
  "Determine next program indices for a (conditional) jump"
  (let [(target (assq-ref labels (get-target cmd)))]
    (if (conditional? cmd) (list (1+ k) target) (list target))))

(define (live-analysis prog results)
  "Get list of live variables for program terminated by RET statement"
  (letrec* [(inputs    (map-if (cut equal? (RET) <>) (const results) input prog))
            (outputs   (map output prog))
            (indices   (iota (length prog)))
            (lut       (labels prog))
            (flow      (map (cut next-indices lut <...>) prog indices))
            (same?     (cut every (cut lset= equal? <...>) <...>))
            (track     (lambda (value)
                         (lambda (in ind out)
                           (union in (difference (apply union (map (cut list-ref value <>) ind)) out)))))
            (initial   (map (const '()) prog))
            (iteration (lambda (value) (map (track value) inputs flow outputs)))]
    (map union (fixed-point initial iteration same?) outputs)))

(define (unallocated-variables allocation)
   "Return a list of unallocated variables"
   (map car (filter (compose not cdr) allocation)))

(define (register-allocations allocation)
   "Return a list of variables with register allocated"
   (filter cdr allocation))

(define (assign-spill-locations variables offset increment)
  "Assign spill locations to a list of variables"
  (map (lambda (variable index) (cons variable (ptr <long> RSP index)))
       variables
       (iota (length variables) offset increment)))

(define (add-spill-information allocation offset increment)
  "Allocate spill locations for spilled variables"
  (append (register-allocations allocation)
          (assign-spill-locations (unallocated-variables allocation) offset increment)))

(define (blocked-predefined predefined intervals blocked)
  "Get blocked predefined registers"
  (filter
    (lambda (pair)
      (let [(variable (car pair))
            (register (cdr pair))]
        (and (assq-ref intervals variable)
             (memv register ((overlap-interval blocked) (assq-ref intervals variable))))))
    predefined))

(define (move-blocked-predefined blocked-predefined)
  "Generate code for blocked predefined variables"
  (map (compose MOV car+cdr) blocked-predefined))

(define (non-blocked-predefined predefined blocked-predefined)
  "Compute the set difference of the predefined variables and the variables with blocked registers"
  (difference predefined blocked-predefined))

(define (linear-scan-coloring live-intervals registers predefined blocked)
  "Linear scan register allocation based on live intervals"
  (define (linear-allocate live-intervals register-use variable-use allocation)
    (if (null? live-intervals)
        allocation
        (let* [(candidate    (car live-intervals))
               (variable     (car candidate))
               (interval     (cdr candidate))
               (first-index  (car interval))
               (last-index   (cdr interval))
               (variable-use (mark-used-till variable-use variable last-index))
               (availability (ignore-blocked-registers register-use interval blocked))
               (register     (or (assq-ref predefined variable)
                                 (find-available-register availability first-index)))
               (recursion    (lambda (allocation register)
                               (linear-allocate (cdr live-intervals)
                                                (mark-used-till register-use register last-index)
                                                variable-use
                                                (assq-set allocation variable register))))]
          (if register
            (recursion allocation register)
            (let* [(spill-targets (ignore-spilled-variables variable-use allocation))
                   (target        (spill-candidate spill-targets))
                   (register      (assq-ref allocation target))]
              (recursion (assq-set allocation target #f) register))))))
  (linear-allocate (sort-live-intervals live-intervals (map car predefined))
                   (initial-register-use registers)
                   '()
                   '()))

(define-method (first-argument self)
   "Return false for compiled instructions"
   #f)
(define-method (first-argument (self <cmd>))
   "Get first argument of machine instruction"
   (car (get-args self)))

(define (replace-variables allocation cmd temporary)
  "Replace variables with registers and add spill code if necessary"
  (let* [(location         (cut assq-ref allocation <>))
         (primary-argument (first-argument cmd))
         (primary-location (location primary-argument))]
    ; cases requiring more than one temporary variable are not handled at the moment
    (if (is-a? primary-location <address>)
      (let [(register (to-type (typecode primary-argument) temporary))]
        (compact (and (memv primary-argument (input cmd)) (MOV register primary-location))
                 (substitute-variables cmd (assq-set allocation primary-argument temporary))
                 (and (memv primary-argument (output cmd)) (MOV primary-location register))))
      (let [(spilled-pointer (filter (compose (cut is-a? <> <address>) location) (get-ptr-args cmd)))]
        ; assumption: (get-ptr-args cmd) only returns zero or one pointer argument requiring a temporary variable
        (attach (map (compose (cut MOV temporary <>) location) spilled-pointer)
                (substitute-variables cmd (fold (lambda (var alist) (assq-set alist var temporary)) allocation spilled-pointer)))))))

(define (adjust-stack-pointer offset prog)
  "Adjust stack pointer offset at beginning and end of program"
  (append (list (SUB RSP offset)) (all-but-last prog) (list (ADD RSP offset) (RET))))

(define (number-spilled-variables allocation stack-parameters)
  "Count the number of spilled variables"
  (length (difference (unallocated-variables allocation) stack-parameters)))

(define (temporary-variables prog)
  "Allocate temporary variable for each instruction which has a variable as first argument"
  (map (lambda (cmd) (let [(arg (first-argument cmd))]
         (or (and (not (null? (get-ptr-args cmd))) (var <long>))
             (and (is-a? arg <var>) (var (typecode arg))))))
       prog))

(define (unit-intervals vars)
  "Generate intervals of length one for each temporary variable"
  (filter car (map (lambda (var index) (cons var (cons index index))) vars (iota (length vars)))))

(define (temporary-registers allocation variables)
  "Look up register for each temporary variable given the result of a register allocation"
  (map (cut assq-ref allocation <>) variables))

(define (register-parameter-locations parameters)
  "Create an association list with the initial parameter locations"
  (map cons parameters (list RDI RSI RDX RCX R8 R9)))

(define (stack-parameter-locations parameters offset)
  "Determine initial locations of stack parameters"
  (map (lambda (parameter index) (cons parameter (ptr <long> RSP index)))
       parameters
       (iota (length parameters) (+ 8 offset) 8)))

(define (parameter-locations parameters offset)
  "return association list with default locations for the method parameters"
  (let [(register-parameters (register-parameters parameters))
        (stack-parameters    (stack-parameters parameters))]
    (append (register-parameter-locations register-parameters)
            (stack-parameter-locations stack-parameters offset))))

(define (add-stack-parameter-information allocation stack-parameter-locations)
   "Add the stack location for stack parameters which do not have a register allocated"
   (map (lambda (variable location) (cons variable (or location (assq-ref stack-parameter-locations variable))))
        (map car allocation)
        (map cdr allocation)))

(define (need-to-copy-first initial targets a b)
  "Check whether parameter A needs to be copied before B given INITIAL and TARGETS locations"
  (eq? (assq-ref initial a) (assq-ref targets b)))

(define (move-variable-content variable source destination)
  "move VARIABLE content from SOURCE to DESTINATION unless source and destination are the same"
  (let [(adapt (cut to-type (typecode variable) <>))]
    (if (or (not destination) (equal? source destination)) '() (MOV (adapt destination) (adapt source)))))

(define (update-parameter-locations parameters locations offset)
  "Generate the required code to update the parameter locations according to the register allocation"
  (let* [(initial            (parameter-locations parameters offset))
         (ordered-parameters (partial-sort parameters (cut need-to-copy-first initial locations <...>)))]
    (filter (compose not null?)
      (map (lambda (parameter)
             (move-variable-content parameter
                                    (assq-ref initial parameter)
                                    (assq-ref locations parameter)))
           ordered-parameters))))

(define (place-result-variable results locations code)
  "add code for placing result variable in register RAX if required"
  (filter (compose not null?)
          (attach (append (all-but-last code)
                          (map (lambda (result) (move-variable-content result (assq-ref locations result) RAX)) results))
                  (RET))))

; RSP is not included because it is used as a stack pointer
; RBP is not included because it may be used as a frame pointer
(define default-registers (list RAX RCX RDX RSI RDI R10 R11 R9 R8 R12 R13 R14 R15 RBX RBP))
(define callee-saved (list RBX RBP RSP R12 R13 R14 R15))
(define caller-saved (list RAX RCX RDX RSI RDI R10 R11 R9 R8))
(define parameter-registers (list RDI RSI RDX RCX R8 R9))

(define (used-callee-saved allocation)
   "Return the list of callee saved registers in use"
   (delete-duplicates (lset-intersection eq? (apply compact (map cdr allocation)) callee-saved)))

(define (backup-registers registers code)
  "Store register content on stack and restore it after executing the code"
  (append (map (cut PUSH <>) registers) (all-but-last code) (map (cut POP <>) (reverse registers)) (list (RET))))

(define* (linear-scan-allocate prog #:key (registers default-registers) (parameters '()) (blocked '()) (results '()))
  "Linear scan register allocation for a given program"
  (let* [(live                 (live-analysis prog results))
         (temp-vars            (temporary-variables prog))
         (intervals            (append (live-intervals live (variables prog))
                                       (unit-intervals temp-vars)))
         (predefined-registers (register-parameter-locations (register-parameters parameters)))
         (parameters-to-move   (blocked-predefined predefined-registers intervals blocked))
         (remaining-predefines (non-blocked-predefined predefined-registers parameters-to-move))
         (stack-parameters     (stack-parameters parameters))
         (colors               (linear-scan-coloring intervals registers remaining-predefines blocked))
         (callee-saved         (used-callee-saved colors))
         (stack-offset         (* 8 (1+ (number-spilled-variables colors stack-parameters))))
         (parameter-offset     (+ stack-offset (* 8 (length callee-saved))))
         (stack-locations      (stack-parameter-locations stack-parameters parameter-offset))
         (allocation           (add-stack-parameter-information colors stack-locations))
         (temporaries          (temporary-registers allocation temp-vars))
         (locations            (add-spill-information allocation 8 8))]
    (backup-registers callee-saved
      (adjust-stack-pointer stack-offset
        (place-result-variable results locations
          (append (update-parameter-locations parameters locations parameter-offset)
                  (append-map (cut replace-variables locations <...>) prog temporaries)))))))

(define (register-parameters parameters)
   "Return the parameters which are stored in registers according to the x86 ABI"
   (take-up-to parameters 6))

(define (stack-parameters parameters)
   "Return the parameters which are stored on the stack according to the x86 ABI"
   (drop-up-to parameters 6))

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

(define* (virtual-variables results parameters instructions #:key (registers default-registers))
  (linear-scan-allocate (flatten-code (relabel (filter-blocks instructions)))
                        #:registers registers
                        #:parameters parameters
                        #:results results
                        #:blocked (blocked-intervals instructions)))

(define (repeat n . body)
  (let [(i (var (typecode n)))]
    (list (MOV i 0) 'begin (CMP i n) (JE 'end) (INC i) body (JMP 'begin) 'end)))

(define-class <block> ()
  (reg  #:init-keyword #:reg  #:getter get-reg)
  (code #:init-keyword #:code #:getter get-code))
(define-method (blocked (reg <register>) . body) (make <block> #:reg reg #:code body))
(define-method (blocked (lst <null>) . body) body)
(define-method (blocked (lst <pair>) . body) (blocked (car lst) (apply blocked (cdr lst) body)))
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

(define (sign-extend-ax size) (case size ((1) (CBW)) ((2) (CWD)) ((4) (CDQ)) ((8) (CQO))))
(define (div/mod-prepare-signed r a)
  (list (MOV (to-type (typecode r) RAX) a) (sign-extend-ax (size-of r))))
(define (div/mod-prepare-unsigned r a)
  (if (eqv? 1 (size-of r)) (list (MOVZX AX a)) (list (MOV (to-type (typecode r) RAX) a) (MOV (to-type (typecode r) RDX) 0))))
(define (div/mod-signed r a b) (attach (div/mod-prepare-signed r a) (IDIV b)))
(define (div/mod-unsigned r a b) (attach (div/mod-prepare-unsigned r a) (DIV b)))
(define (div/mod-block-registers r . code) (blocked RAX (if (eqv? 1 (size-of r)) code (blocked RDX code))))
(define (div/mod r a b . finalise) (div/mod-block-registers r ((if (signed? r) div/mod-signed div/mod-unsigned) r a b) finalise))
(define (div r a b) (div/mod r a b (MOV r (to-type (typecode r) RAX))))
(define (mod r a b) (div/mod r a b (if (eqv? 1 (size-of r)) (list (MOV AL AH) (MOV r AL)) (MOV r DX))))

(define-method (signed? (x <var>)) (signed? (typecode x)))
(define-method (signed? (x <ptr>)) (signed? (typecode x)))
(define (shx r x shift-signed shift-unsigned)
  (blocked RCX (mov-unsigned CL x) ((if (signed? r) shift-signed shift-unsigned) r CL)))
(define (shl r x) (shx r x SAL SHL))
(define (shr r x) (shx r x SAR SHR))
(define-method (test (a <var>)) (list (TEST a a)))
(define-method (test (a <ptr>))
  (let [(intermediate (var (typecode a)))]
    (list (MOV intermediate a) (test intermediate))))
(define (test-zero r a) (attach (test a) (SETE r)))
(define (test-non-zero r a) (attach (test a) (SETNE r)))
(define ((binary-bool op) a b)
  (let [(intermediate (var <byte>))]
    (attach (append (test-non-zero a a) (test-non-zero intermediate b)) (op a intermediate))))
(define bool-and (binary-bool AND))
(define bool-or  (binary-bool OR))

(define-method (cmp a b) (list (CMP a b)))
(define-method (cmp (a <ptr>) (b <ptr>))
  (let [(intermediate (var (typecode a)))]
    (cons (MOV intermediate a) (cmp intermediate b))))
(define ((cmp-setxx set-signed set-unsigned) out a b)
  (let [(set (if (or (signed? a) (signed? b)) set-signed set-unsigned))]
    (attach (cmp a b) (set out))))
(define cmp-equal         (cmp-setxx SETE   SETE  ))
(define cmp-not-equal     (cmp-setxx SETNE  SETNE ))
(define cmp-lower-than    (cmp-setxx SETL   SETB  ))
(define cmp-lower-equal   (cmp-setxx SETLE  SETBE ))
(define cmp-greater-than  (cmp-setxx SETNLE SETNBE))
(define cmp-greater-equal (cmp-setxx SETNL  SETNB ))

(define ((cmp-cmovxx set-signed set-unsigned jmp-signed jmp-unsigned) r a b)
  (if (eqv? 1 (size-of r))
    (append (mov r a) (cmp r b) (list ((if (signed? r) jmp-signed jmp-unsigned) 'skip)) (mov r b) (list 'skip))
    (append (mov r a) (cmp r b) (list ((if (signed? r) set-signed set-unsigned) r b)))))
(define minor (cmp-cmovxx CMOVNLE CMOVNBE JL   JB  ))
(define major (cmp-cmovxx CMOVL   CMOVB   JNLE JNBE))

(define-method (skeleton (self <meta<element>>)) (make self #:value (var self)))
(define-method (skeleton (self <meta<sequence<>>>))
  (let [(slice (skeleton (project self)))]
    (make self
          #:value   (value slice)
          #:shape   (cons (var <long>) (shape   slice))
          #:strides (cons (var <long>) (strides slice)))))

(define-class <param> ()
  (delegate #:init-keyword #:delegate #:getter delegate))

(define-class <indexer> (<param>)
  (dimension #:init-keyword #:dimension #:getter dimension)
  (index     #:init-keyword #:index     #:getter index))
(define (indexer dimension index delegate)
  (make <indexer> #:dimension dimension #:index index #:delegate delegate))

(define-class <lookup> (<param>)
  (index    #:init-keyword #:index    #:getter index)
  (stride   #:init-keyword #:stride   #:getter stride)
  (iterator #:init-keyword #:iterator #:getter iterator)
  (step     #:init-keyword #:step     #:getter step))
(define-method (lookup index delegate stride iterator step)
  (make <lookup> #:index index #:delegate delegate #:stride stride #:iterator iterator #:step step))
(define-method (lookup idx (obj <indexer>) stride iterator step)
  (indexer (dimension obj) (index obj) (lookup idx (delegate obj) stride iterator step)))

(define-class <function> (<param>)
  (arguments #:init-keyword #:arguments #:getter arguments)
  (type      #:init-keyword #:type      #:getter type)
  (project   #:init-keyword #:project   #:getter project)
  (term      #:init-keyword #:term      #:getter term))

(define-method (type (self <param>)) (typecode (delegate self)))
(define-method (type (self <indexer>)) (sequence (type (delegate self))))
(define-method (type (self <lookup>)) (type (delegate self)))
(define-method (typecode (self <indexer>)) (typecode (type self)))
(define-method (shape (self <indexer>)) (attach (shape (delegate self)) (dimension self)))
(define-method (strides (self <indexer>)) (attach (strides (delegate self)) (stride (lookup self (index self)))))
(define-method (lookup (self <indexer>)) (lookup self (index self)))
(define-method (lookup (self <indexer>) (idx <var>)) (lookup (delegate self) idx))
(define-method (lookup (self <lookup>) (idx <var>)) (if (eq? (index self) idx) self (lookup (delegate self) idx)))
(define-method (stride (self <indexer>)) (stride (lookup self)))
(define-method (iterator (self <indexer>)) (iterator (lookup self)))
(define-method (step (self <indexer>)) (step (lookup self)))
(define-method (parameter (self <element>)) (make <param> #:delegate self))
(define-method (parameter (self <sequence<>>))
  (let [(idx (var <long>))]
    (indexer (parameter (make <long> #:value (dimension self)))
             idx
             (lookup idx
                     (parameter (project self))
                     (parameter (make <long> #:value (stride self)))
                     (var <long>)
                     (var <long>)))))
(define-method (parameter (self <meta<element>>)) (parameter (skeleton self)))
(define-method (subst self candidate replacement) self)
(define-method (subst (self <indexer>) candidate replacement)
  (indexer (dimension self) (index self) (subst (delegate self) candidate replacement)))
(define-method (subst (self <lookup>) candidate replacement)
  (lookup (if (eq? (index self) candidate) replacement (index self))
          (subst (delegate self) candidate replacement)
          (stride self)
          (iterator self)
          (step self)))
(define-method (value (self <param>)) (value (delegate self)))
(define-method (value (self <indexer>)) (value (delegate self)))
(define-method (value (self <lookup>)) (value (delegate self)))
(define-method (rebase value (self <param>)) (parameter (rebase value (delegate self))))
(define-method (rebase value (self <indexer>))
  (indexer (dimension self) (index self) (rebase value (delegate self))))
(define-method (rebase value (self <lookup>))
  (lookup (index self) (rebase value (delegate self)) (stride self) (iterator self) (step self)))
(define-method (project (self <indexer>)) (project (delegate self) (index self)))
(define-method (project (self <indexer>) (idx <var>))
  (indexer (dimension self) (index self) (project (delegate self) idx)))
(define-method (project (self <lookup>) (idx <var>))
  (if (eq? (index self) idx)
      (delegate self)
      (lookup (index self) (project (delegate self) idx) (stride self) (iterator self) (step self))))
(define-method (get (self <indexer>) idx) (subst (delegate self) (index self) idx))
(define-syntax-rule (tensor size index expr) (let [(index (var <long>))] (indexer size index expr)))

(define-method (size-of (self <param>))
  (apply * (native-const <long> (size-of (typecode (type self)))) (shape self)))

(define-method (setup self) '())
(define-method (setup (self <indexer>))
  (list (IMUL (step self) (get (delegate (stride self))) (size-of (typecode self)))
        (MOV (iterator self) (value self))))
(define-method (setup (self <function>)) (append-map setup (arguments self)))
(define-method (increment self) '())
(define-method (increment (self <indexer>)) (list (ADD (iterator self) (step self))))
(define-method (increment (self <function>)) (append-map increment (arguments self)))
(define-method (body self) self)
(define-method (body (self <indexer>)) (project (rebase (iterator self) self)))
(define-method (body (self <function>)) ((project self)))
(define-method (shape (self <function>)) (argmax length (map shape (arguments self))))

(define-method (operand (a <element>)) (get a))
(define-method (operand (a <pointer<>>))
  (if (pointer-offset a)
      (ptr (typecode a) (get a) (pointer-offset a))
      (ptr (typecode a) (get a))))
(define-method (operand (a <param>)) (operand (delegate a)))

(define (insert-intermediate value intermediate fun)
  (append (code intermediate value) (fun intermediate)))

(define-method (code (a <element>) (b <element>)) ((to-type (typecode a) (typecode b)) (parameter a) (list (parameter b))))
(define-method (code (a <element>) (b <integer>)) (list (MOV (operand a) b)))

(define-method (code (a <pointer<>>) (b <pointer<>>))
  (insert-intermediate b (skeleton (typecode a)) (cut code a <>)))
(define-method (code (a <param>) (b <param>)) (code (delegate a) (delegate b)))
(define-method (code (a <indexer>) (b <param>))
  (list (setup a)
        (setup b)
        (repeat (get (delegate (dimension a)))
                (append (code (body a) (body b))
                        (increment a)
                        (increment b)))))
(define-method (code (out <element>) (fun <function>))
  (if (need-conversion? (typecode out) (type fun))
    (insert-intermediate fun (skeleton (type fun)) (cut code out <>))
    ((term fun) (parameter out))))
(define-method (code (out <pointer<>>) (fun <function>))
  (insert-intermediate fun (skeleton (typecode out)) (cut code out <>)))
(define-method (code (out <param>) (fun <function>)) (code (delegate out) fun))
(define-method (code (out <param>) (value <integer>)) (code out (native-const (type out) value)))

; decompose parameters into elementary native types
(define-method (content (type <meta<element>>) (self <param>)) (map parameter (content type (delegate self))))
(define-method (content (type <meta<scalar>>) (self <function>)) (list self))
(define-method (content (type <meta<composite>>) (self <function>)) (arguments self))
(define-method (content (type <meta<sequence<>>>) (self <param>))
  (cons (dimension self) (cons (stride self) (content (project type) (project self)))))

(define (is-pointer? value) (and (delegate value) (is-a? (delegate value) <pointer<>>)))
(define-method (need-conversion? target type) (not (eq? target type)))
(define-method (need-conversion? (target <meta<int<>>>) (type <meta<int<>>>))
  (not (eqv? (size-of target) (size-of type))))
(define-method (need-conversion? (target <meta<bool>>) (type <meta<int<>>>))
  (not (eqv? (size-of target) (size-of type))))
(define-method (need-conversion? (target <meta<int<>>>) (type <meta<bool>>))
  (not (eqv? (size-of target) (size-of type))))
(define (code-needs-intermediate? t value) (or (is-a? value <function>) (need-conversion? t (type value))))
(define (call-needs-intermediate? t value) (or (is-pointer? value) (code-needs-intermediate? t value)))
(define-method (force-parameters (targets <list>) args predicate fun)
  (let* [(mask          (map predicate targets args))
         (intermediates (map-select mask (compose parameter car list) (compose cadr list) targets args))
         (preamble      (concatenate (map-select mask code (const '()) intermediates args)))]
    (attach preamble (apply fun intermediates))))
(define-method (force-parameters target args predicate fun)
  (force-parameters (make-list (length args) target) args predicate fun))

(define (operation-code target op out args)
  "Adapter for nested expressions"
  (force-parameters target args code-needs-intermediate?
    (lambda intermediates
      (apply op (operand out) (map operand intermediates)))))
(define ((functional-code op) out args)
  "Adapter for machine code without side effects on its arguments"
  (operation-code (reduce coerce #f (map type args)) op out args))
(define ((mutating-code op) out args)
  "Adapter for machine code overwriting its first argument"
  (insert-intermediate (car args) out (cut operation-code (type out) op <> (cdr args))))
(define ((unary-extract op) out args)
  "Adapter for machine code to extract part of a composite value"
  (code (delegate out) (apply op (map delegate args))))

(define-macro (define-operator-mapping name arity type fun)
  (let* [(args   (symbol-list arity))
         (header (typed-header args type))]
    `(define-method (,name . ,header) ,fun)))

(define-operator-mapping -   1 <meta<int<>>> (mutating-code   NEG              ))
(define-method (- (z <integer>) (a <meta<int<>>>)) (mutating-code NEG))
(define-operator-mapping ~   1 <meta<int<>>> (mutating-code   NOT              ))
(define-operator-mapping =0  1 <meta<int<>>> (functional-code test-zero        ))
(define-operator-mapping !=0 1 <meta<int<>>> (functional-code test-non-zero    ))
(define-operator-mapping !   1 <meta<bool>>  (functional-code test-zero        ))
(define-operator-mapping +   2 <meta<int<>>> (mutating-code   ADD              ))
(define-operator-mapping -   2 <meta<int<>>> (mutating-code   SUB              ))
(define-operator-mapping *   2 <meta<int<>>> (mutating-code   IMUL             ))
(define-operator-mapping /   2 <meta<int<>>> (functional-code div              ))
(define-operator-mapping %   2 <meta<int<>>> (functional-code mod              ))
(define-operator-mapping <<  2 <meta<int<>>> (mutating-code   shl              ))
(define-operator-mapping >>  2 <meta<int<>>> (mutating-code   shr              ))
(define-operator-mapping &   2 <meta<int<>>> (mutating-code   AND              ))
(define-operator-mapping |   2 <meta<int<>>> (mutating-code   OR               ))
(define-operator-mapping ^   2 <meta<int<>>> (mutating-code   XOR              ))
(define-operator-mapping &&  2 <meta<bool>>  (mutating-code   bool-and         ))
(define-operator-mapping ||  2 <meta<bool>>  (mutating-code   bool-or          ))
(define-operator-mapping =   2 <meta<int<>>> (functional-code cmp-equal        ))
(define-operator-mapping !=  2 <meta<int<>>> (functional-code cmp-not-equal    ))
(define-operator-mapping <   2 <meta<int<>>> (functional-code cmp-lower-than   ))
(define-operator-mapping <=  2 <meta<int<>>> (functional-code cmp-lower-equal  ))
(define-operator-mapping >   2 <meta<int<>>> (functional-code cmp-greater-than ))
(define-operator-mapping >=  2 <meta<int<>>> (functional-code cmp-greater-equal))
(define-operator-mapping min 2 <meta<int<>>> (functional-code minor            ))
(define-operator-mapping max 2 <meta<int<>>> (functional-code major            ))

(define-operator-mapping -   1 <meta<element>> (native-fun obj-negate    ))
(define-method (- (z <integer>) (a <meta<element>>)) (native-fun obj-negate))
(define-operator-mapping ~   1 <meta<element>> (native-fun scm-lognot    ))
(define-operator-mapping =0  1 <meta<element>> (native-fun obj-zero-p    ))
(define-operator-mapping !=0 1 <meta<element>> (native-fun obj-nonzero-p ))
(define-operator-mapping !   1 <meta<element>> (native-fun obj-not       ))
(define-operator-mapping +   2 <meta<element>> (native-fun scm-sum       ))
(define-operator-mapping -   2 <meta<element>> (native-fun scm-difference))
(define-operator-mapping *   2 <meta<element>> (native-fun scm-product   ))
(define-operator-mapping /   2 <meta<element>> (native-fun scm-divide    ))
(define-operator-mapping %   2 <meta<element>> (native-fun scm-remainder ))
(define-operator-mapping <<  2 <meta<element>> (native-fun scm-ash       ))
(define-operator-mapping >>  2 <meta<element>> (native-fun obj-shr       ))
(define-operator-mapping &   2 <meta<element>> (native-fun scm-logand    ))
(define-operator-mapping |   2 <meta<element>> (native-fun scm-logior    ))
(define-operator-mapping ^   2 <meta<element>> (native-fun scm-logxor    ))
(define-operator-mapping &&  2 <meta<element>> (native-fun obj-and       ))
(define-operator-mapping ||  2 <meta<element>> (native-fun obj-or        ))
(define-operator-mapping =   2 <meta<element>> (native-fun obj-equal-p   ))
(define-operator-mapping !=  2 <meta<element>> (native-fun obj-nequal-p  ))
(define-operator-mapping <   2 <meta<element>> (native-fun obj-less-p    ))
(define-operator-mapping <=  2 <meta<element>> (native-fun obj-leq-p     ))
(define-operator-mapping >   2 <meta<element>> (native-fun obj-gr-p      ))
(define-operator-mapping >=  2 <meta<element>> (native-fun obj-geq-p     ))
(define-operator-mapping min 2 <meta<element>> (native-fun scm-min       ))
(define-operator-mapping max 2 <meta<element>> (native-fun scm-max       ))

(define-method (decompose-value (target <meta<scalar>>) self) self)

(define-method (delegate-op (target <meta<scalar>>) (intermediate <meta<scalar>>) name out args)
  ((apply name (map type args)) out args))
(define-method (delegate-op (target <meta<sequence<>>>) (intermediate <meta<sequence<>>>) name out args)
  ((apply name (map type args)) out args))
(define-method (delegate-op target intermediate name out args)
  (let [(result (apply name (map (lambda (arg) (decompose-value (type arg) arg)) args)))]
    (append-map code (content (type out) out) (content (type result) result))))
(define (delegate-fun name)
  (lambda (out args) (delegate-op (type out) (reduce coerce #f (map type args)) name out args)))

(define (make-function name coercion fun args)
  (make <function> #:arguments args
                   #:type      (apply coercion (map type args))
                   #:project   (lambda ()  (apply name (map body args)))
                   #:delegate  #f
                   #:term      (lambda (out) (fun out args))))

(define-macro (n-ary-base name arity coercion fun)
  (let* [(args   (symbol-list arity))
         (header (typed-header args '<param>))]
    `(define-method (,name . ,header) (make-function ,name ,coercion ,fun (list . ,args)))))

(define (content-vars args) (map get (append-map content (map class-of args) args)))

(define (assemble return-args args instructions)
  "Determine result variables, argument variables, and instructions"
  (list (content-vars return-args) (content-vars args) (attach instructions (RET))))

(define (build-list . args)
  "Generate code to package ARGS in a Scheme list"
  (fold-right scm-cons scm-eol args))

(define (package-return-content value)
  "Generate code to package parameter VALUE in a Scheme list"
  (apply build-list (content (type value) value)))

(define-method (construct-value result-type retval expr) '())
(define-method (construct-value (result-type <meta<sequence<>>>) retval expr)
  (let [(malloc (if (pointerless? result-type) scm-gc-malloc-pointerless scm-gc-malloc))]
    (append (append-map code (shape retval) (shape expr))
            (code (last (content result-type retval)) (malloc (size-of retval)))
            (append-map code (strides retval) (default-strides (shape retval))))))

(define (generate-return-code args intermediate expr)
  (let [(retval (skeleton <obj>))]
    (list (list retval)
          args
          (append (construct-value (type intermediate) intermediate expr)
                  (code intermediate expr)
                  (code (parameter retval) (package-return-content intermediate))))))

(define (jit context classes proc)
  (let* [(vars         (map skeleton classes))
         (expr         (apply proc (map parameter vars)))
         (result-type  (type expr))
         (result       (parameter result-type))
         (types        (map class-of vars))
         (intermediate (generate-return-code vars result expr))
         (instructions (asm context
                            <ulong>
                            (map typecode (content-vars vars))
                            (apply virtual-variables (apply assemble intermediate))))
         (fun          (lambda header (apply instructions (append-map unbuild types header))))]
    (lambda args (build result-type (address->scm (apply fun args))))))

(define-macro (define-jit-dispatch name arity delegate)
  (let* [(args   (symbol-list arity))
         (header (typed-header args '<element>))]
    `(define-method (,name . ,header)
       (let [(f (jit ctx (map class-of (list . ,args)) ,delegate))]
         (add-method! ,name
                      (make <method>
                            #:specializers (map class-of (list . ,args))
                            #:procedure (lambda args (apply f (map get args))))))
       (,name . ,args))))

(define-macro (define-nary-collect name arity)
  (let* [(args   (symbol-list arity))
         (header (cons (list (car args) '<element>) (cdr args)))]; TODO: extract and test
    (cons 'begin
          (map
            (lambda (i)
              `(define-method (,name . ,(cycle-times header i))
                (apply ,name (map wrap (list . ,(cycle-times args i))))))
            (iota arity)))))

(define-syntax-rule (define-jit-method coercion name arity)
  (begin (n-ary-base name arity coercion (delegate-fun name))
         (define-nary-collect name arity)
         (define-jit-dispatch name arity name)))

; various type class conversions
(define-method (convert-type (target <meta<element>>) (self <meta<element>>)) target)
(define-method (convert-type (target <meta<element>>) (self <meta<sequence<>>>)) (multiarray target (dimensions self)))
(define-method (to-bool a) (convert-type <bool> a))
(define-method (to-bool a b) (coerce (to-bool a) (to-bool b)))

; define unary and binary operations
(define-method (+ (a <param>)) a)
(define-method (+ (a <element>)) a)
(define-method (* (a <param>)) a)
(define-method (* (a <element>)) a)
(define-jit-dispatch duplicate 1 identity)
(define-jit-method identity -   1)
(define-jit-method identity ~   1)
(define-jit-method to-bool  =0  1)
(define-jit-method to-bool  !=0 1)
(define-jit-method to-bool  !   1)
(define-jit-method coerce   +   2)
(define-jit-method coerce   -   2)
(define-jit-method coerce   *   2)
(define-jit-method coerce   /   2)
(define-jit-method coerce   %   2)
(define-jit-method coerce   <<  2)
(define-jit-method coerce   >>  2)
(define-jit-method coerce   &   2)
(define-jit-method coerce   |   2)
(define-jit-method coerce   ^   2)
(define-jit-method coerce   &&  2)
(define-jit-method coerce   ||  2)
(define-jit-method to-bool  =   2)
(define-jit-method to-bool  !=  2)
(define-jit-method to-bool  <   2)
(define-jit-method to-bool  <=  2)
(define-jit-method to-bool  >   2)
(define-jit-method to-bool  >=  2)
(define-jit-method coerce   min 2)
(define-jit-method coerce   max 2)

(define-method (to-type (target <meta<ubyte>>) (source <meta<obj>>  )) (native-fun scm-to-uint8   ))
(define-method (to-type (target <meta<byte>> ) (source <meta<obj>>  )) (native-fun scm-to-int8    ))
(define-method (to-type (target <meta<usint>>) (source <meta<obj>>  )) (native-fun scm-to-uint16  ))
(define-method (to-type (target <meta<sint>> ) (source <meta<obj>>  )) (native-fun scm-to-int16   ))
(define-method (to-type (target <meta<uint>> ) (source <meta<obj>>  )) (native-fun scm-to-uint32  ))
(define-method (to-type (target <meta<int>>  ) (source <meta<obj>>  )) (native-fun scm-to-int32   ))
(define-method (to-type (target <meta<ulong>>) (source <meta<obj>>  )) (native-fun scm-to-uint64  ))
(define-method (to-type (target <meta<long>> ) (source <meta<obj>>  )) (native-fun scm-to-int64   ))
(define-method (to-type (target <meta<int<>>>) (source <meta<int<>>>)) (functional-code mov       ))
(define-method (to-type (target <meta<int<>>>) (source <meta<bool>> )) (functional-code mov       ))
(define-method (to-type (target <meta<bool>> ) (source <meta<bool>> )) (functional-code mov       ))
(define-method (to-type (target <meta<bool>> ) (source <meta<int<>>>)) (functional-code mov       ))
(define-method (to-type (target <meta<bool>> ) (source <meta<obj>>  )) (native-fun scm-to-bool    ))
(define-method (to-type (target <meta<obj>>  ) (source <meta<obj>>  )) (functional-code mov       ))
(define-method (to-type (target <meta<obj>>  ) (source <meta<ubyte>>)) (native-fun scm-from-uint8 ))
(define-method (to-type (target <meta<obj>>  ) (source <meta<byte>> )) (native-fun scm-from-int8  ))
(define-method (to-type (target <meta<obj>>  ) (source <meta<usint>>)) (native-fun scm-from-uint16))
(define-method (to-type (target <meta<obj>>  ) (source <meta<sint>> )) (native-fun scm-from-int16 ))
(define-method (to-type (target <meta<obj>>  ) (source <meta<uint>> )) (native-fun scm-from-uint32))
(define-method (to-type (target <meta<obj>>  ) (source <meta<int>>  )) (native-fun scm-from-int32 ))
(define-method (to-type (target <meta<obj>>  ) (source <meta<ulong>>)) (native-fun scm-from-uint64))
(define-method (to-type (target <meta<obj>>  ) (source <meta<long>> )) (native-fun scm-from-int64 ))
(define-method (to-type (target <meta<obj>>  ) (source <meta<bool>> )) (native-fun obj-from-bool  ))
(define-method (to-type (target <meta<composite>>) (source <meta<composite>>))
  (lambda (out args)
    (append-map
      (lambda (channel) (code (channel (delegate out)) (channel (delegate (car args)))))
      (components source))))

(define-method (to-type (target <meta<element>>) (a <param>))
  (let [(to-target  (cut to-type target <>))
        (coercion   (cut convert-type target <>))]
    (make-function to-target coercion (delegate-fun to-target) (list a))))
(define-method (to-type (target <meta<element>>) (self <element>))
  (let [(f (jit ctx (list (class-of self)) (cut to-type target <>)))]
    (add-method! to-type
                 (make <method>
                       #:specializers (map class-of (list target self))
                       #:procedure (lambda (target self) (f (get self)))))
    (to-type target self)))

(define (ensure-default-strides img)
  "Create a duplicate of the array unless it is compact"
  (if (equal? (strides img) (default-strides (shape img))) img (duplicate img)))

(define-syntax-rule (pass-parameters parameters body ...)
  (let [(first-six-parameters (take-up-to parameters 6))
        (remaining-parameters (drop-up-to parameters 6))]
    (append (map (lambda (register parameter)
                   (MOV (to-type (native-equivalent (type parameter)) register) (get (delegate parameter))))
                 parameter-registers
                 first-six-parameters)
            (map (lambda (parameter) (PUSH (get (delegate parameter)))) remaining-parameters)
            (list body ...)
            (list (ADD RSP (* 8 (length remaining-parameters)))))))

(define* ((native-fun native) out args)
  (force-parameters (argument-types native) args call-needs-intermediate?
    (lambda intermediates
      (blocked caller-saved
        (pass-parameters intermediates
          (MOV RAX (function-pointer native))
          (CALL RAX)
          (MOV (get (delegate out)) (to-type (native-equivalent (return-type native)) RAX)))))))

(define (make-native-function native . args)
  (make-function make-native-function (const (return-type native)) (native-fun native) args))

(define (native-call return-type argument-types function-pointer)
  (cut make-native-function (make-native-method return-type argument-types function-pointer) <...>))

(define* ((native-data native) out args) (list (MOV (get (delegate out)) (get native))))

(define (make-constant-function native . args) (make-function make-constant-function (const (return-type native)) (native-data native) args))

(define (native-const type value) (make-constant-function (native-value type value)))

; Scheme list manipulation
(define main (dynamic-link))
(define scm-eol (native-const <obj> (scm->address '())))
(define scm-cons (native-call <obj> (list <obj> <obj>) (dynamic-func "scm_cons" main)))
(define scm-gc-malloc-pointerless (native-call <ulong> (list <ulong>) (dynamic-func "scm_gc_malloc_pointerless" main)))
(define scm-gc-malloc             (native-call <ulong> (list <ulong>) (dynamic-func "scm_gc_malloc"             main)))
