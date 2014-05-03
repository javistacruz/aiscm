(define-module (aiscm jit)
  #:use-module (oop goops)
  #:use-module (system foreign)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (aiscm element)
  #:use-module (aiscm int)
  #:use-module (aiscm mem)
  #:export (<jit-context>
            <addr>    <meta<addr>>
            <reg<>>   <meta<reg<>>>
            <reg<8>>  <meta<reg<8>>>
            <reg<16>> <meta<reg<16>>>
            <reg<32>> <meta<reg<32>>>
            <reg<64>> <meta<reg<64>>>
            <jcc>
            addr get-reg get-name asm label-offsets get-target resolve resolve-jumps len get-bits
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
            *1 *2 *4 *8))
; http://www.drpaulcarter.com/pcasm/
; http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html
(load-extension "libguile-jit" "init_jit")
(define-class <jit-context> ()
  (binaries #:init-value '()))

(define-class <jcc> ()
  (target #:init-keyword #:target #:getter get-target)
  (code #:init-keyword #:code #:getter get-code))
(define-method (len (self <jcc>)) 2)
(define-method (Jcc (target <symbol>) (code <integer>))
  (make <jcc> #:target target #:code code))
(define-method (Jcc (target <integer>) (code <integer>))
  (append (list code) (raw target 8)))
(define-method (resolve (self <jcc>) (offset <integer>) offsets)
  (let ((target (- (assq-ref offsets (get-target self)) offset)))
    (Jcc target (get-code self))))

(define (label-offsets commands)
  (define (iterate cmd acc)
    (let ((offsets (car acc))
          (offset  (cdr acc)))
      (if (is-a? cmd <symbol>)
        (cons (acons cmd offset offsets) offset)
        (let ((len-cmd (if (is-a? cmd <jcc>) (len cmd) (length cmd))))
          (cons offsets (+ offset len-cmd))))))
  (car (fold iterate (cons '() 0) commands)))

(define (resolve-jumps commands offsets)
  (define (iterate cmd acc)
    (let ((tail   (car acc))
          (offset (cdr acc)))
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

(define (asm ctx return_type commands . args)
  (let* ((offsets  (label-offsets commands))
         (resolved (resolve-jumps commands offsets))
         (code     (make-mmap (u8-list->bytevector (apply append resolved)))))
    (slot-set! ctx 'binaries (cons code (slot-ref ctx 'binaries)))
    (pointer->procedure return_type (make-pointer (mmap-address code)) args)))

(define-class <meta<operand>> (<class>))
(define-class <operand> ()
              #:metaclass <meta<operand>>)

(define-class <meta<reg<>>> (<meta<operand>>))
(define-class <reg<>> (<operand>)
              (code #:init-keyword #:code #:getter get-code)
              #:metaclass <meta<reg<>>>)
(define-class <meta<reg<8>>> (<meta<reg<>>>))
(define-method (get-bits (self <meta<reg<8>>>)) 8)
(define-class <reg<8>> (<reg<>>) #:metaclass <meta<reg<8>>>)
(define   AL (make <reg<8>> #:code #b0000))
(define   CL (make <reg<8>> #:code #b0001))
(define   DL (make <reg<8>> #:code #b0010))
(define   BL (make <reg<8>> #:code #b0011))
(define  SPL (make <reg<8>> #:code #b0100))
(define  BPL (make <reg<8>> #:code #b0101))
(define  SIL (make <reg<8>> #:code #b0110))
(define  DIL (make <reg<8>> #:code #b0111))
(define  R8L (make <reg<8>> #:code #b1000))
(define  R9L (make <reg<8>> #:code #b1001))
(define R10L (make <reg<8>> #:code #b1010))
(define R11L (make <reg<8>> #:code #b1011))
(define R12L (make <reg<8>> #:code #b1100))
(define R13L (make <reg<8>> #:code #b1101))
(define R14L (make <reg<8>> #:code #b1110))
(define R15L (make <reg<8>> #:code #b1111))
(define-class <meta<reg<16>>> (<meta<reg<>>>))
(define-method (get-bits (self <meta<reg<16>>>)) 16)
(define-class <reg<16>> (<reg<>>) #:metaclass <meta<reg<16>>>)
(define   AX (make <reg<16>> #:code #b0000))
(define   CX (make <reg<16>> #:code #b0001))
(define   DX (make <reg<16>> #:code #b0010))
(define   BX (make <reg<16>> #:code #b0011))
(define   SP (make <reg<16>> #:code #b0100))
(define   BP (make <reg<16>> #:code #b0101))
(define   SI (make <reg<16>> #:code #b0110))
(define   DI (make <reg<16>> #:code #b0111))
(define  R8W (make <reg<16>> #:code #b1000))
(define  R9W (make <reg<16>> #:code #b1001))
(define R10W (make <reg<16>> #:code #b1010))
(define R11W (make <reg<16>> #:code #b1011))
(define R12W (make <reg<16>> #:code #b1100))
(define R13W (make <reg<16>> #:code #b1101))
(define R14W (make <reg<16>> #:code #b1110))
(define R15W (make <reg<16>> #:code #b1111))
(define-class <meta<reg<32>>> (<meta<reg<>>>))
(define-method (get-bits (self <meta<reg<32>>>)) 32)
(define-class <reg<32>> (<reg<>>) #:metaclass <meta<reg<32>>>)
(define  EAX (make <reg<32>> #:code #b0000))
(define  ECX (make <reg<32>> #:code #b0001))
(define  EDX (make <reg<32>> #:code #b0010))
(define  EBX (make <reg<32>> #:code #b0011))
(define  ESP (make <reg<32>> #:code #b0100))
(define  EBP (make <reg<32>> #:code #b0101))
(define  ESI (make <reg<32>> #:code #b0110))
(define  EDI (make <reg<32>> #:code #b0111))
(define  R8D (make <reg<32>> #:code #b1000))
(define  R9D (make <reg<32>> #:code #b1001))
(define R10D (make <reg<32>> #:code #b1010))
(define R11D (make <reg<32>> #:code #b1011))
(define R12D (make <reg<32>> #:code #b1100))
(define R13D (make <reg<32>> #:code #b1101))
(define R14D (make <reg<32>> #:code #b1110))
(define R15D (make <reg<32>> #:code #b1111))
(define-class <meta<reg<64>>> (<meta<reg<>>>))
(define-method (get-bits (self <meta<reg<64>>>)) 64)
(define-class <reg<64>> (<reg<>>) #:metaclass <meta<reg<64>>>)
(define RAX (make <reg<64>> #:code #b0000))
(define RCX (make <reg<64>> #:code #b0001))
(define RDX (make <reg<64>> #:code #b0010))
(define RBX (make <reg<64>> #:code #b0011))
(define RSP (make <reg<64>> #:code #b0100))
(define RBP (make <reg<64>> #:code #b0101))
(define RSI (make <reg<64>> #:code #b0110))
(define RDI (make <reg<64>> #:code #b0111))
(define  R8 (make <reg<64>> #:code #b1000))
(define  R9 (make <reg<64>> #:code #b1001))
(define R10 (make <reg<64>> #:code #b1010))
(define R11 (make <reg<64>> #:code #b1011))
(define R12 (make <reg<64>> #:code #b1100))
(define R13 (make <reg<64>> #:code #b1101))
(define R14 (make <reg<64>> #:code #b1110))
(define R15 (make <reg<64>> #:code #b1111))

(define *1 #b00)
(define *2 #b01)
(define *4 #b10)
(define *8 #b11)

(define-class <meta<addr>> (<meta<operand>>))
(define-class <addr> (<operand>)
              (reg #:init-keyword #:reg #:getter get-reg)
              (disp #:init-keyword #:disp #:init-form #f #:getter get-disp)
              (scale #:init-keyword #:scale #:init-form *1 #:getter get-scale)
              (index #:init-keyword #:index #:init-form #f #:getter get-index)
              #:metaclass <meta<addr>>)
(define-method (addr (reg <reg<64>>)); TODO: specify one of: byte, word, dword, qword
  (make <addr> #:reg reg))
(define-method (addr (reg <reg<64>>) (disp <integer>))
  (make <addr> #:reg reg #:disp disp))
(define-method (addr (reg <reg<64>>) (index <reg<64>>) (scale <integer>))
  (make <addr> #:reg reg #:index index #:scale scale))
(define-method (addr (reg <reg<64>>) (index <reg<64>>) (scale <integer>) (disp <integer>))
  (make <addr> #:reg reg #:index index #:scale scale #:disp disp))

(define-method (raw (imm <boolean>) (bits <integer>)) '())
(define-method (raw (imm <integer>) (bits <integer>))
  (bytevector->u8-list (pack (make (integer bits unsigned) #:value imm))))
(define-method (raw (imm <mem>) (bits <integer>))
  (raw (pointer-address (get-memory imm)) bits))

(define-method (bits3 (x <integer>)) (logand x #b111))
(define-method (bits3 (x <reg<>>)) (bits3 (get-code x)))

(define-method (get-reg (x <reg<>>)) #f)
(define-method (get-index (x <reg<>>)) #f)
(define-method (get-disp (x <reg<>>)) #f)

(define-method (bit4 (x <boolean>)) 0)
(define-method (bit4 (x <integer>)) (logand x #b1))
(define-method (bit4 (x <reg<>>)) (bit4 (ash (get-code x) -3)))
(define-method (bit4 (x <addr>)) (bit4 (get-reg x)))

(define (opcode code reg) (list (logior code (bits3 reg))))
(define (if8 reg a b) (list (if (is-a? reg <reg<8>>) a b)))
(define (opcode-if8 reg code1 code2) (opcode (car (if8 reg code1 code2)) reg))
(define (op16 reg) (if (is-a? reg <reg<16>>) (list #x66) '()))

(define-method (mod (r/m <reg<>>)) #b11)
(define-method (mod (r/m <addr>)) (if (get-disp r/m) #b01 #b00)); TODO: #b10 
(define-method (ModR/M mod reg/opcode r/m)
  (list (logior (ash mod 6) (ash (bits3 reg/opcode) 3) (bits3 r/m))))
(define-method (ModR/M reg/opcode (r/m <reg<>>))
  (ModR/M (mod r/m) reg/opcode r/m))
(define-method (ModR/M reg/opcode (r/m <addr>))
  (if (get-index r/m)
    (ModR/M (mod r/m) reg/opcode #b100)
    (ModR/M (mod r/m) reg/opcode (get-reg r/m))))

(define (need-rex? r) (member r (list SPL BPL SIL DIL)))
(define (REX W r r/m)
  (let ((flags (logior (ash (if (is-a? W <reg<64>>) 1 0) 3)
                       (ash (bit4 r) 2)
                       (ash (bit4 (get-index r/m)) 1)
                       (bit4 r/m))))
    (if (or (not (zero? flags)) (need-rex? r) (need-rex? (get-index r/m)) (need-rex? r/m))
      (list (logior (ash #b0100 4) flags)) '())))

(define (SIB r/m)
  (if (get-index r/m)
    (list (logior (ash (get-scale r/m) 6)
                  (ash (bits3 (get-index r/m)) 3)
                  (bits3 (get-reg r/m))))
    (if (equal? (get-reg r/m) RSP)
      (list #b00100100)
      '())))

(define (NOP) '(#x90))
(define (RET) '(#xc3))

(define-method (MOV (r/m <operand>) (r <reg<>>))
  (append (op16 r) (REX r r r/m) (if8 r #x88 #x89) (ModR/M r r/m) (SIB r/m) (raw (get-disp r/m) 8)))
(define-method (MOV (r <reg<>>) (imm <mem>))
  (append (op16 r) (REX r 0 r) (opcode-if8 r #xb0 #xb8) (raw imm (get-bits (class-of r)))))
(define-method (MOV (r <reg<>>) (imm <integer>))
  (append (op16 r) (REX r 0 r) (opcode-if8 r #xb0 #xb8) (raw imm (get-bits (class-of r)))))
(define-method (MOV (r <reg<>>) (r/m <addr>))
  (append (op16 r) (REX r r r/m) (if8 r #x8a #x8b) (ModR/M r r/m) (SIB r/m) (raw (get-disp r/m) 8)))

(define-method (MOVSX (r <reg<>>) (r/m <reg<8>>))
  (append (op16 r) (REX r r r/m) (list #x0f #xbe) (ModR/M r r/m)))
(define-method (MOVSX (r <reg<>>) (r/m <reg<16>>))
  (append (op16 r) (REX r r r/m) (list #x0f #xbf) (ModR/M r r/m)))
(define-method (MOVSX (r <reg<>>) (r/m <reg<32>>))
  (append (op16 r) (REX r r r/m) (list #x63) (ModR/M r r/m)))
(define-method (MOVZX (r <reg<>>) (r/m <reg<8>>))
  (append (op16 r) (REX r r r/m) (list #x0f #xb6) (ModR/M r r/m)))
(define-method (MOVZX (r <reg<>>) (r/m <reg<16>>))
  (append (op16 r) (REX r r r/m) (list #x0f #xb7) (ModR/M r r/m)))

(define-method (LEA (r <reg<64>>) (r/m <addr>))
  (append (REX r r r/m) (list #x8d) (ModR/M r r/m) (SIB r/m) (raw (get-disp r/m) 8)))

(define-method (SHL (r/m <operand>))
  (append (op16 r/m) (REX r/m 0 r/m) (if8 r/m #xd0 #xd1) (ModR/M 4 r/m) (SIB r/m) (raw (get-disp r/m) 8)))
(define-method (SHR (r/m <operand>))
  (append (op16 r/m) (REX r/m 0 r/m) (if8 r/m #xd0 #xd1) (ModR/M 5 r/m) (SIB r/m) (raw (get-disp r/m) 8)))
(define-method (SAL (r/m <operand>))
  (append (op16 r/m) (REX r/m 0 r/m) (if8 r/m #xd0 #xd1) (ModR/M 4 r/m) (SIB r/m) (raw (get-disp r/m) 8)))
(define-method (SAR (r/m <operand>))
  (append (op16 r/m) (REX r/m 0 r/m) (if8 r/m #xd0 #xd1) (ModR/M 7 r/m) (SIB r/m) (raw (get-disp r/m) 8)))

(define-method (ADD (r/m <operand>) (r <reg<>>))
  (append (op16 r/m) (REX r r r/m) (if8 r/m #x00 #x01) (ModR/M r r/m) (SIB r/m) (raw (get-disp r/m) 8)))
(define-method (ADD (r/m <reg<>>) (imm <integer>))
  (if (equal? (get-code r/m) 0)
    (append (op16 r/m) (REX r/m 0 r/m) (if8 r/m #x04 #x05) (raw imm (min 32 (get-bits (class-of r/m)))))
    (append (op16 r/m) (REX r/m 0 r/m) (if8 r/m #x80 #x81) (ModR/M 0 r/m) (raw imm (min 32 (get-bits (class-of r/m)))))))
(define-method (ADD (r <reg<>>) (r/m <addr>))
  (append (op16 r) (REX r r r/m) (if8 r #x02 #x03) (ModR/M r r/m) (SIB r/m) (raw (get-disp r/m) 8)))

(define-method (PUSH (r <reg<64>>))
  (opcode #x50 r))
(define-method (POP (r <reg<64>>))
  (opcode #x58 r))

(define-method (NEG (r/m <operand>))
  (append (op16 r/m) (REX r/m 0 r/m) (if8 r/m #xf6 #xf7) (ModR/M 3 r/m) (SIB r/m) (raw (get-disp r/m) 8)))

(define-method (SUB (r/m <operand>) (r <reg<>>))
  (append (REX r r r/m) (list #x29) (ModR/M r r/m) (SIB r/m) (raw (get-disp r/m) 8)))
(define-method (SUB (r/m <reg<>>) (imm32 <integer>))
  (if (equal? (get-code r/m) 0)
    (append (REX r/m 0 r/m) (list #x2d) (raw imm32 32))
    (append (REX r/m 0 r/m) (list #x81) (ModR/M 5 r/m) (raw imm32 32))))

(define-method (CMP (r/m <reg<>>) (imm32 <integer>))
  (if (equal? (get-code r/m) 0)
    (append (REX r/m 0 r/m) (list #x3d) (raw imm32 32))
    (append (REX r/m 0 r/m) (list #x81) (ModR/M 7 r/m) (raw imm32 32))))
(define-method (CMP (r/m <operand>) (r <reg<>>))
  (append (REX r r r/m) (list #x39) (ModR/M r r/m) (SIB r/m) (raw (get-disp r/m) 8)))

(define (SETcc code r/m)
  (append (REX r/m 0 r/m) (list #x0f code) (opcode #xc0 r/m)))
(define-method (SETB   (r/m <reg<8>>)) (SETcc #x92 r/m))
(define-method (SETNB  (r/m <reg<8>>)) (SETcc #x93 r/m))
(define-method (SETE   (r/m <reg<8>>)) (SETcc #x94 r/m))
(define-method (SETNE  (r/m <reg<8>>)) (SETcc #x95 r/m))
(define-method (SETBE  (r/m <reg<8>>)) (SETcc #x96 r/m))
(define-method (SETNBE (r/m <reg<8>>)) (SETcc #x97 r/m))
(define-method (SETL   (r/m <reg<8>>)) (SETcc #x9c r/m))
(define-method (SETNL  (r/m <reg<8>>)) (SETcc #x9d r/m))
(define-method (SETLE  (r/m <reg<8>>)) (SETcc #x9e r/m))
(define-method (SETNLE (r/m <reg<8>>)) (SETcc #x9f r/m))
