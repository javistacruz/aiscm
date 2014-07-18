(define-module (aiscm jit)
  #:use-module (oop goops)
  #:use-module (ice-9 optargs)
  #:use-module (system foreign)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (aiscm element)
  #:use-module (aiscm util)
  #:use-module (aiscm int)
  #:use-module (aiscm mem)
  #:export (<jit-context> <pool>
            get-type get-reg get-code get-name asm label-offsets get-target resolve
            resolve-jumps len get-bits ptr get-disp get-index
            ADD MOV MOVSX MOVZX LEA NOP RET PUSH POP SAL SAR SHL SHR NEG SUB CMP
            SETB SETNB SETE SETNE SETBE SETNBE SETL SETNL SETLE SETNLE
            JMP JB JNB JE JNE JBE JNBE JL JNL JLE JNLE
            AL CL DL BL SPL BPL SIL DIL
            R8L R9L R10L R11L R12L R13L R14L R15L
            AX CX DX BX SP BP SI DI
            R8W R9W R10W R11W R12W R13W R14W R15W
            EAX ECX EDX EBX ESP EBP ESI EDI
            R8D R9D R10D R11D R12D R13D R14D R15D
            RAX RCX RDX RBX RSP RBP RSI RDI
            R8 R9 R10 R11 R12 R13 R14 R15
            reg arg)
  #:export-syntax (env))
; http://www.drpaulcarter.com/pcasm/
; http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html
(load-extension "libguile-jit" "init_jit")
(define-class <jit-context> () (binaries #:init-value '()))

(define-class <jcc> ()
  (target #:init-keyword #:target #:getter get-target)
  (code #:init-keyword #:code #:getter get-code))
(define-method (len (self <jcc>)) 2)
(define-method (Jcc (target <symbol>) (code <integer>))
  (make <jcc> #:target target #:code code))
(define-method (Jcc (target <integer>) (code <integer>))
  (append (list code) (raw target 8)))
(define-method (resolve (self <jcc>) (offset <integer>) offsets)
  (let [(target (- (assq-ref offsets (get-target self)) offset))]
    (Jcc target (get-code self))))

(define (label-offsets commands)
  (define (iterate cmd acc)
    (let [(offsets (car acc))
          (offset  (cdr acc))]
      (if (is-a? cmd <symbol>)
        (cons (acons cmd offset offsets) offset)
        (let [(len-cmd (if (is-a? cmd <jcc>) (len cmd) (length cmd)))]
          (cons offsets (+ offset len-cmd))))))
  (car (fold iterate (cons '() 0) commands)))

(define (resolve-jumps commands offsets)
  (define (iterate cmd acc)
    (let [(tail   (car acc))
          (offset (cdr acc))]
      (cond
        ((is-a? cmd <jcc>)    (cons (cons (resolve cmd (+ offset (len cmd)) offsets) tail)
                                    (+ offset (len cmd))))
        ((is-a? cmd <symbol>) (cons tail offset))
        (else                 (cons (cons cmd tail) (+ offset (length cmd)))))))
  (reverse (car (fold iterate (cons '() 0) commands))))

(define (JMP  target) (Jcc target #xeb))
(define (JB   target) (Jcc target #x72))
(define (JNB  target) (Jcc target #x73))
(define (JE   target) (Jcc target #x74))
(define (JNE  target) (Jcc target #x75))
(define (JBE  target) (Jcc target #x76))
(define (JNBE target) (Jcc target #x77))
(define (JL   target) (Jcc target #x7c))
(define (JNL  target) (Jcc target #x7d))
(define (JLE  target) (Jcc target #x7e))
(define (JNLE target) (Jcc target #x7f))

(define (asm ctx return-type commands arg-types)
  (let* [(offsets     (label-offsets commands))
         (resolved    (resolve-jumps commands offsets))
         (with-return (append resolved (list (RET))))
         (code        (make-mmap (u8-list->bytevector (apply append with-return))))]
    (slot-set! ctx 'binaries (cons code (slot-ref ctx 'binaries)))
    (pointer->procedure (foreign-type return-type)
                        (make-pointer (mmap-address code))
                        (map foreign-type arg-types))))

(define-class <operand> ())

(define-class <register> (<operand>)
  (bits #:init-keyword #:bits #:getter get-bits)
  (code #:init-keyword #:code #:getter get-code))

(define hex (upto #x0 #xf))
(define register-sizes '(1 2 4 8))
(define (each-hex proc arg) (for-each proc arg hex))
(define (reg-list bits) (map (cut make <register> #:bits bits #:code <>) hex))
(define regs (map (compose reg-list (cut * <> 8)) register-sizes)); TODO: use bytes instead of bits
(define-method (reg (type <meta<int<>>>) (code <integer>))
  (list-ref (list-ref regs (index (size-of type) register-sizes)) code))

(each-hex (lambda (sym val) (toplevel-define! sym (reg <byte> val)))
          '(AL CL DL BL SPL BPL SIL DIL R8L R9L R10L R11L R12L R13L R14L R15L))

(each-hex (lambda (sym val) (toplevel-define! sym (reg <sint> val)))
          '(AX CX DX BX SP BP SI DI R8W R9W R10W R11W R12W R13W R14W R15W))

(each-hex (lambda (sym val) (toplevel-define! sym (reg <int> val)))
          '(EAX ECX EDX EBX ESP EBP ESI EDI R8D R9D R10D R11D R12D R13D R14D R15D))

(each-hex (lambda (sym val) (toplevel-define! sym (reg <long> val)))
          '(RAX RCX RDX RBX RSP RBP RSI RDI R8 R9 R10 R11 R12 R13 R14 R15))

(define (scale s) (index s register-sizes))

(define-class <pointer> (<operand>)
  (type  #:init-keyword #:type  #:getter get-type)
  (reg   #:init-keyword #:reg   #:getter get-reg)
  (disp  #:init-keyword #:disp  #:getter get-disp  #:init-value #f)
  (index #:init-keyword #:index #:getter get-index #:init-value #f))

(define-method (get-bits (self <pointer>)) (* 8 (size-of (get-type self))))

(define-method (ptr (type <meta<int<>>>) (reg <register>))
  (make <pointer> #:type type #:reg reg))
(define-method (ptr (type <meta<int<>>>) (reg <register>) (disp <integer>))
  (make <pointer> #:type type #:reg reg #:disp disp))
(define-method (ptr (type <meta<int<>>>) (reg <register>) (index <register>))
  (make <pointer> #:type type #:reg reg #:index index))
(define-method (ptr (type <meta<int<>>>) (reg <register>) (index <register>) (disp <integer>))
  (make <pointer> #:type type #:reg reg #:index index #:disp disp))

(define-method (raw (imm <boolean>) (bits <integer>)) '())
(define-method (raw (imm <integer>) (bits <integer>))
  (bytevector->u8-list (pack (make (integer bits unsigned) #:value imm))))
(define-method (raw (imm <mem>) (bits <integer>))
  (raw (pointer-address (get-memory imm)) bits))

(define-method (bits3 (x <integer>)) (logand x #b111))
(define-method (bits3 (x <register>)) (bits3 (get-code x)))
(define-method (bits3 (x <pointer>)) (bits3 (get-reg x)))

(define-method (get-reg (x <register>)) #f)
(define-method (get-index (x <register>)) #f)
(define-method (get-disp (x <register>)) #f)

(define-method (bit4 (x <boolean>)) 0)
(define-method (bit4 (x <integer>)) (logand x #b1))
(define-method (bit4 (x <register>)) (bit4 (ash (get-code x) -3)))
(define-method (bit4 (x <pointer>)) (bit4 (get-reg x)))

(define (opcode code reg) (list (logior code (bits3 reg))))
(define (if8 reg a b) (list (if (eqv? (get-bits reg) 8) a b)))
(define (opcode-if8 reg code1 code2) (opcode (car (if8 reg code1 code2)) reg))
(define-method (op16 (x <integer>)) (if (eqv? x 16) (list #x66) '()))
(define-method (op16 (x <operand>)) (op16 (get-bits x)))

(define-method (disp8? (disp <boolean>)) 8)
(define-method (disp8? (disp <integer>)) (and (>= disp -128) (< disp 128)))

(define-method (mod (r/m <boolean>)) #b00)
(define-method (mod (r/m <integer>)) (if (disp8? r/m) #b01 #b10))
(define-method (mod (r/m <register>)) #b11)
(define-method (mod (r/m <pointer>)) (mod (get-disp r/m)))

(define-method (ModR/M mod reg/opcode r/m)
  (list (logior (ash mod 6) (ash (bits3 reg/opcode) 3) (bits3 r/m))))
(define-method (ModR/M reg/opcode (r/m <register>))
  (ModR/M (mod r/m) reg/opcode r/m))
(define-method (ModR/M reg/opcode (r/m <pointer>))
  (if (get-index r/m)
    (ModR/M (mod r/m) reg/opcode #b100)
    (ModR/M (mod r/m) reg/opcode (get-reg r/m))))

(define (need-rex? r) (member r (list SPL BPL SIL DIL)))
(define (REX W r r/m)
  (let [(flags (logior (ash (if (eqv? (get-bits W) 64) 1 0) 3)
                       (ash (bit4 r) 2)
                       (ash (bit4 (get-index r/m)) 1)
                       (bit4 r/m)))]
    (if (or (not (zero? flags)) (need-rex? r) (need-rex? (get-index r/m)) (need-rex? r/m))
      (list (logior (ash #b0100 4) flags)) '())))

(define (SIB r/m)
  (if (get-index r/m)
    (list (logior (ash (scale (size-of (get-type r/m))) 6)
                  (ash (bits3 (get-index r/m)) 3)
                  (bits3 (get-reg r/m))))
    (if (equal? (get-reg r/m) RSP)
      (list #b00100100)
      '())))

(define-method (prefixes (r/m <operand>))
  (append (op16 r/m) (REX r/m 0 r/m)))
(define-method (prefixes (r <register>) (r/m <operand>))
  (append (op16 r) (REX r r r/m)))

(define (postfixes reg/opcode r/m)
  (append (ModR/M reg/opcode r/m) (SIB r/m) (raw (get-disp r/m) (if (disp8? (get-disp r/m)) 8 32))))

(define (NOP) '(#x90))
(define (RET) '(#xc3))

(define-method (MOV (m <pointer>) (r <register>))
  (append (prefixes r m) (if8 r #x88 #x89) (postfixes r m)))
(define-method (MOV (r <register>) imm)
  (append (prefixes r) (opcode-if8 r #xb0 #xb8) (raw imm (get-bits r))))
(define-method (MOV (m <pointer>) imm)
  (append (prefixes m) (if8 m #xc6 #xc7) (postfixes 0 m) (raw imm (min 32 (get-bits m)))))
(define-method (MOV (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r #x8a #x8b) (postfixes r r/m)))

(define-method (MOVSX (r <register>) (r/m <operand>))
  (let* [(bits   (get-bits r/m))
         (opcode (cond ((eqv? bits  8) (list #x0f #xbe))
                       ((eqv? bits 16) (list #x0f #xbf))
                       ((eqv? bits 32) (list #x63))))]
    (append (prefixes r r/m) opcode (postfixes r r/m))))

(define-method (MOVZX (r <register>) (r/m <operand>))
  (let* [(bits   (get-bits r/m))
         (opcode (cond ((eqv? bits  8) (list #x0f #xb6))
                       ((eqv? bits 16) (list #x0f #xb7))))]
    (append (prefixes r r/m) opcode (postfixes r r/m))))

(define-method (LEA (r <register>) (m <pointer>))
  (append (prefixes r m) (list #x8d) (postfixes r m)))

(define-method (SHL (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xd0 #xd1) (postfixes 4 r/m)))
(define-method (SHR (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xd0 #xd1) (postfixes 5 r/m)))
(define-method (SAL (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xd0 #xd1) (postfixes 4 r/m)))
(define-method (SAR (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xd0 #xd1) (postfixes 7 r/m)))

(define-method (ADD (m <pointer>) (r <register>))
  (append (prefixes r m) (if8 m #x00 #x01) (postfixes r m)))
(define-method (ADD (r <register>) imm)
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #x04 #x05) (raw imm (min 32 (get-bits r))))
    (next-method)))
(define-method (ADD (r/m <operand>) imm)
  (append (prefixes r/m) (if8 r/m #x80 #x81) (postfixes 0 r/m) (raw imm (min 32 (get-bits r/m)))))
(define-method (ADD (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r #x02 #x03) (postfixes r r/m)))

(define-method (PUSH (r <register>)); TODO: PUSH r/m, PUSH imm
  (append (prefixes r) (opcode #x50 r)))
(define-method (POP (r <register>))
  (append (prefixes r) (opcode #x58 r)))

(define-method (NEG (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xf6 #xf7) (postfixes 3 r/m)))

(define-method (SUB (m <pointer>) (r <register>))
  (append (prefixes r m) (if8 m #x28 #x29) (postfixes r m)))
(define-method (SUB (r <register>) imm)
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #x2c #x2d) (raw imm (min 32 (get-bits r))))
    (next-method)))
(define-method (SUB (r/m <operand>) imm)
  (append (prefixes r/m) (if8 r/m #x80 #x81) (postfixes 5 r/m) (raw imm (min 32 (get-bits r/m)))))
(define-method (SUB (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r/m #x2a #x2b) (postfixes r r/m)))

(define-method (CMP (m <pointer>) (r <register>))
  (append (prefixes r m) (if8 m #x38 #x39) (postfixes r m)))
(define-method (CMP (r <register>) (imm <integer>))
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #x3c #x3d) (raw imm (min 32 (get-bits r))))
    (next-method)))
(define-method (CMP (r/m <operand>) (imm <integer>))
  (append (prefixes r/m) (if8 r/m #x80 #x81) (postfixes 7 r/m) (raw imm (min 32 (get-bits r/m)))))
(define-method (CMP (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r/m #x3a #x3b) (postfixes r r/m)))

(define (SETcc code r/m)
  (append (prefixes r/m) (list #x0f code) (postfixes 0 r/m)))
(define (SETB   r/m) (SETcc #x92 r/m))
(define (SETNB  r/m) (SETcc #x93 r/m))
(define (SETE   r/m) (SETcc #x94 r/m))
(define (SETNE  r/m) (SETcc #x95 r/m))
(define (SETBE  r/m) (SETcc #x96 r/m))
(define (SETNBE r/m) (SETcc #x97 r/m))
(define (SETL   r/m) (SETcc #x9c r/m))
(define (SETNL  r/m) (SETcc #x9d r/m))
(define (SETLE  r/m) (SETcc #x9e r/m))
(define (SETNLE r/m) (SETcc #x9f r/m))

(define default-codes
  (map get-code (list RAX RCX RDX RSI RDI R10 R11 R9 R8 RBX RBP R12 R13 R14 R15)))
(define callee-saved-codes (map get-code (list RBX RSP RBP R12 R13 R14 R15)))
(define args (map get-code (list RDI RSI RDX RCX R8 R9)))
(define-class <pool> ()
  (codes  #:init-value default-codes #:init-keyword #:codes #:getter get-codes)
  (live   #:init-value '() #:getter get-live   #:setter set-live)
  (before #:init-value '() #:getter get-before #:setter set-before)
  (after  #:init-value '() #:getter get-after  #:setter set-after)
  (offset #:init-value   0 #:getter get-offset #:setter set-offset)
  (argc   #:init-value   0 #:getter get-argc   #:setter set-argc))
(define (get-free pool)
  (let [(live-codes (map get-code (get-live pool)))]
    (find (compose not (cut member <> live-codes)) (get-codes pool))))
(define (clear-before pool) (let [(retval (get-before pool))] (set-before pool '()) retval))
(define (clear-after pool) (let [(retval (get-after pool))] (set-after pool '()) retval))
(define (push-stack pool reg)
  (set-offset pool (1+ (get-offset pool)))
  (set-before pool (append (get-before pool) (list (PUSH reg))))
  (set-after pool (cons (POP reg) (get-after pool))))
(define (spill pool type)
  (let* [(target (last (get-live pool)))
         (retval (reg type (get-code target)))]
    (push-stack pool target)
    (set-live pool (cons retval (all-but-last (get-live pool))))
    retval))
(define (allocate pool type)
  (let* [(code (get-free pool))
         (retval (if code (reg type code) #f))]
    (if retval (set-live pool (cons retval (get-live pool))))
    (if (member code callee-saved-codes) (push-stack pool (reg <long> code)))
    retval))
(define-method (reg (type <meta<int<>>>) (pool <pool>))
  (or (allocate pool type) (spill pool type)))
(define-method (arg (type <meta<int<>>>) (pool <pool>))
  (let* [(n       (get-argc pool))
         (is-reg? (< n (length args)))
         (retval  (if is-reg?
                    (reg type (list-ref args n))
                    (ptr type RSP (ash (+ (- n (length args)) 1) 3))))]
    (if is-reg? (set-live pool (cons retval (get-live pool))))
    (set-argc pool (1+ (get-argc pool)))
    retval))
(define-method (reg (value <register>) (pool <pool>)) value)
(define-method (reg (value <pointer>) (pool <pool>))
  (let* [(retval (reg (get-type value) pool))
         (disp   (+ (get-disp value) (ash (get-offset pool) 3)))
         (setup  (MOV retval (ptr (get-type value) RSP disp)))]
    (set-before pool (append (get-before pool) (list setup)))
    retval))
(define-syntax-rule (env pool vars . body)
  (let* [(live   (get-live pool))
         (before (clear-before pool))
         (after  (clear-after pool))
         (offset (get-offset pool))
         (middle (let* vars (list . body)))
         (start  (get-before pool))
         (end    (get-after pool))]
    (set-live pool live)
    (set-before pool before)
    (set-after pool after)
    (set-offset pool offset)
    (flatten-n (append start middle end) 2)))
