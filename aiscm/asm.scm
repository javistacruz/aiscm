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
(define-module (aiscm asm)
  #:use-module (oop goops)
  #:use-module (system foreign)
  #:use-module (ice-9 binary-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-26)
  #:use-module (aiscm util)
  #:use-module (aiscm mem)
  #:use-module (aiscm element)
  #:use-module (aiscm int)
  #:export (<context> <operand> <register> <address> <jcc>
            reg get-code xmm
            AL CL DL BL SPL BPL SIL DIL AH CH DH BH
            R8L R9L R10L R11L R12L R13L R14L R15L
            AX CX DX BX SP BP SI DI
            R8W R9W R10W R11W R12W R13W R14W R15W
            EAX ECX EDX EBX ESP EBP ESI EDI
            R8D R9D R10D R11D R12D R13D R14D R15D
            RAX RCX RDX RBX RSP RBP RSI RDI
            R8 R9 R10 R11 R12 R13 R14 R15
            XMM0 XMM1 XMM2 XMM3 XMM4 XMM5 XMM6 XMM7
            XMM8 XMM9 XMM10 XMM11 XMM12 XMM13 XMM14 XMM15
            resolve-jumps get-target retarget
            asm obj ptr get-reg get-disp get-index
            ADD MOV MOVSX MOVZX LEA NOP RET PUSH POP SAL SAR SHL SHR NOT NEG INC SUB IMUL IDIV DIV
            AND OR XOR CBW CWDE CDQE CWD CDQ CQO CMP TEST
            SETB SETNB SETE SETNE SETBE SETNBE SETL SETNL SETLE SETNLE
            JMP JB JNB JE JNE JBE JNBE JL JNL JLE JNLE conditional?
            CMOVB CMOVNB CMOVE CMOVNE CMOVBE CMOVNBE CMOVL CMOVNL CMOVLE CMOVNLE
            CALL))
; http://www.drpaulcarter.com/pcasm/
; http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html
(load-extension "libguile-aiscm-jit" "init_jit")
(define-class <context> () (binaries #:init-value '()))

(define-class <operand> ())

(define-class <register> (<operand>)
  (size   #:init-keyword #:size #:getter size-of)
  (code   #:init-keyword #:code #:getter get-code)
  (symbol #:init-keyword #:symbol))
(define-method (write (self <register>) port) (format port "~a" (slot-ref self 'symbol)))
(define reg-symbols
  '((1 AL  CL  DL  BL  SPL BPL SIL DIL R8L R9L R10L R11L R12L R13L R14L R15L)
    (2 AX  CX  DX  BX  SP  BP  SI  DI  R8W R9W R10W R11W R12W R13W R14W R15W)
    (4 EAX ECX EDX EBX ESP EBP ESI EDI R8D R9D R10D R11D R12D R13D R14D R15D)
    (8 RAX RCX RDX RBX RSP RBP RSI RDI R8  R9  R10  R11  R12  R13  R14  R15)))
(define (reg-list bytes lst)
  (map (lambda (sym code) (make <register> #:size bytes #:code code #:symbol sym)) lst (iota #x10)))
(define regs (map (lambda (pair) (cons (car pair) (reg-list (car pair) (cdr pair)))) reg-symbols))
(define-method (reg (size <integer>) (code <integer>)) (list-ref (assq-ref regs size) code))
(define-method (reg (type <meta<int<>>>) (code <integer>)) (reg (size-of type) code))
(for-each
  (lambda (pair)
    (for-each
      (lambda (sym code) (toplevel-define! sym (reg (car pair) code))) (cdr pair) (iota #x10)))
  reg-symbols)
(define AH (make <register> #:size 1 #:code 4 #:symbol 'AH))
(define CH (make <register> #:size 1 #:code 5 #:symbol 'CH))
(define DH (make <register> #:size 1 #:code 6 #:symbol 'DH))
(define BH (make <register> #:size 1 #:code 7 #:symbol 'BH))
(define-method (to-type (typecode <meta<int<>>>) (self <register>)) (reg (size-of typecode) (get-code self)))

(define-class <xmm> (<operand>)
  (code   #:init-keyword #:code #:getter get-code)
  (symbol #:init-keyword #:symbol))
(define-method (write (self <xmm>) port) (format port "~a" (slot-ref self 'symbol)))
(define xmm-symbols
  '(XMM0 XMM1 XMM2 XMM3 XMM4 XMM5 XMM6 XMM7 XMM8 XMM9 XMM10 XMM11 XMM12 XMM13 XMM14 XMM15))
(define xmms (map (lambda (sym code) (make <xmm> #:code code #:symbol sym)) xmm-symbols (iota #x10)))
(define (xmm code) (list-ref xmms code))
(for-each (lambda (sym code) (toplevel-define! sym (xmm code))) xmm-symbols (iota #x10))

(define-class <address> (<operand>)
  (type  #:init-keyword #:type  #:getter get-type)
  (reg   #:init-keyword #:reg   #:getter get-reg)
  (disp  #:init-keyword #:disp  #:getter get-disp  #:init-value #f)
  (index #:init-keyword #:index #:getter get-index #:init-value #f))
(define-method (write (self <address>) port)
  (format port "~a"
          (compact 'ptr (class-name (get-type self)) (get-reg self) (get-index self) (get-disp self))))
(define-method (equal? (a <address>) (b <address>)) (equal? (object-slots a) (object-slots b)))
(define-method (size-of (self <address>)) (size-of (get-type self)))
(define-method (ptr (type <meta<element>>) (reg <register>))
  (make <address> #:type type #:reg reg))
(define-method (ptr (type <meta<element>>) (reg <register>) (disp <integer>))
  (make <address> #:type type #:reg reg #:disp disp))
(define-method (ptr (type <meta<element>>) (reg <register>) (index <register>))
  (make <address> #:type type #:reg reg #:index index))
(define-method (ptr (type <meta<element>>) (reg <register>) (index <register>) (disp <integer>))
  (make <address> #:type type #:reg reg #:index index #:disp disp))
(define-method (to-type (typecode <meta<int<>>>) (self <address>))
  (make <address> #:type typecode #:reg (get-reg self) #:disp (get-disp self) #:index (get-index self)))

(define-method (raw64 (imm <boolean>) (size <integer>)) '())
(define-method (raw64 (imm <integer>) (size <integer>))
  (bytevector->u8-list (pack (make (integer (* 8 size) (if (negative? imm) signed unsigned)) #:value imm))))
(define-method (raw64 (imm <mem>) (size <integer>))
  (raw64 (pointer-address (get-memory imm)) size))
(define (raw32 imm size) (raw64 imm (min 4 size)))

(define-method (bits3 (x <integer>)) (logand x #b111))
(define-method (bits3 (x <register>)) (bits3 (get-code x)))
(define-method (bits3 (x <address>)) (bits3 (get-reg x)))

(define-method (get-reg   (x <register>)) #f)
(define-method (get-index (x <register>)) #f)
(define-method (get-disp  (x <register>)) #f)

(define-method (bit4 (x <boolean>)) 0)
(define-method (bit4 (x <integer>)) (logand x #b1))
(define-method (bit4 (x <register>)) (bit4 (ash (get-code x) -3)))
(define-method (bit4 (x <address>)) (bit4 (get-reg x)))

(define-method (disp-value (x <register>)) #f)
(define-method (disp-value (x <address>))
  (or (get-disp x) (if (memv (get-reg x) (list RBP R13)) 0 #f)))

(define (opcode code reg) (list (logior code (bits3 reg))))
(define (if8 reg a b) (list (if (= (size-of reg) 1) a b)))
(define (opcode-if8 reg code1 code2) (opcode (car (if8 reg code1 code2)) reg))
(define-method (op16 (x <integer>)) (if (= x 2) (list #x66) '()))
(define-method (op16 (x <operand>)) (op16 (size-of x)))

(define-method (disp8? (disp <boolean>)) #f)
(define-method (disp8? (disp <integer>)) (and (>= disp -128) (< disp 128)))

(define-method (mod (r/m <boolean>)) #b00)
(define-method (mod (r/m <integer>)) (if (disp8? r/m) #b01 #b10))
(define-method (mod (r/m <register>)) #b11)
(define-method (mod (r/m <address>)) (mod (disp-value r/m)))

(define-method (ModR/M mod reg/opcode r/m)
  (list (logior (ash mod 6) (ash (bits3 reg/opcode) 3) (bits3 r/m))))
(define-method (ModR/M reg/opcode (r/m <register>))
  (ModR/M (mod r/m) reg/opcode r/m))
(define-method (ModR/M reg/opcode (r/m <address>))
  (if (get-index r/m)
    (ModR/M (mod r/m) reg/opcode #b100)
    (ModR/M (mod r/m) reg/opcode (get-reg r/m))))

(define (need-rex? r) (member r (list SPL BPL SIL DIL))); need REX to differentiate from AH, CH, DH, and BH
(define (REX W r r/m)
  (let [(flags (logior (ash (if (= (size-of W) 8) 1 0) 3)
                       (ash (bit4 r) 2)
                       (ash (bit4 (get-index r/m)) 1)
                       (bit4 r/m)))]
    (if (or (not (zero? flags)) (need-rex? r) (need-rex? r/m))
      (list (logior (ash #b0100 4) flags)) '())))

(define (scale s) (index-of s '(1 2 4 8)))

(define (SIB r/m)
  (if (get-index r/m)
    (list (logior (ash (scale (size-of (get-type r/m))) 6)
                  (ash (bits3 (get-index r/m)) 3)
                  (bits3 (get-reg r/m))))
    (if (memv (get-reg r/m) (list RSP R12))
      (list #b00100100)
      '())))

(define-method (prefixes (r/m <operand>))
  (append (op16 r/m) (REX r/m 0 r/m)))
(define-method (prefixes (r <register>) (r/m <operand>))
  (append (op16 r) (REX r r r/m)))

(define (postfixes reg/opcode r/m)
  (append (ModR/M reg/opcode r/m) (SIB r/m) (raw32 (disp-value r/m) (if (disp8? (disp-value r/m)) 1 4))))

(define (NOP) '(#x90))
(define (RET) '(#xc3))

(define-method (MOV (m <address>) (r <register>))
  (append (prefixes r m) (if8 r #x88 #x89) (postfixes r m)))
(define-method (MOV (r <register>) (imm <integer>))
  (append (prefixes r) (opcode-if8 r #xb0 #xb8) (raw64 imm (size-of r))))
(define-method (MOV (m <address>) (imm <integer>))
  (append (prefixes m) (if8 m #xc6 #xc7) (postfixes 0 m) (raw32 imm (size-of m))))
(define-method (MOV (r <register>) (imm <mem>))
  (append (prefixes r) (opcode-if8 r #xb0 #xb8) (raw64 imm (size-of r))))
(define-method (MOV (m <address>) (imm <mem>))
  (append (prefixes m) (if8 m #xc6 #xc7) (postfixes 0 m) (raw32 imm (size-of m))))
(define-method (MOV (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r #x8a #x8b) (postfixes r r/m)))
(define-method (MOV (r <register>) (imm <foreign>))
  (MOV r (pointer-address imm)))

(define-method (MOVSX (r <register>) (r/m <operand>))
  (let* [(size   (size-of r/m))
         (opcode (case size ((1) (list #x0f #xbe))
                            ((2) (list #x0f #xbf))
                            ((4) (list #x63))))]
    (append (prefixes r r/m) opcode (postfixes r r/m))))
(define-method (MOVZX (r <register>) (r/m <operand>))
  (let* [(size   (size-of r/m))
         (opcode (case size ((1) (list #x0f #xb6))
                            ((2) (list #x0f #xb7))
                            ((4) (aiscm-error 'MOVZX "MOVZX does not support 32-bit input"))))]
    (append (prefixes r r/m) opcode (postfixes r r/m))))

(define (CBW) '(#x66 #x98))
(define (CWDE) '(#x98))
(define (CDQE) '(#x48 #x98))

(define (CWD) '(#x66 #x99))
(define (CDQ) '(#x99))
(define (CQO) '(#x48 #x99))

(define-method (LEA (r <register>) (m <address>))
  (append (prefixes r m) (list #x8d) (postfixes r m)))

(define-method (SHL (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xd0 #xd1) (postfixes 4 r/m)))
(define-method (SHL (r/m <operand>) (r <register>))
  (append (prefixes r/m) (if8 r/m #xd2 #xd3) (postfixes 4 r/m)))
(define-method (SHR (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xd0 #xd1) (postfixes 5 r/m)))
(define-method (SHR (r/m <operand>) (r <register>))
  (append (prefixes r/m) (if8 r/m #xd2 #xd3) (postfixes 5 r/m)))
(define-method (SAL (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xd0 #xd1) (postfixes 4 r/m)))
(define-method (SAL (r/m <operand>) (r <register>))
  (append (prefixes r/m) (if8 r/m #xd2 #xd3) (postfixes 4 r/m)))
(define-method (SAR (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xd0 #xd1) (postfixes 7 r/m)))
(define-method (SAR (r/m <operand>) (r <register>))
  (append (prefixes r/m) (if8 r/m #xd2 #xd3) (postfixes 7 r/m)))

(define-method (ADD (m <address>) (r <register>))
  (append (prefixes r m) (if8 m #x00 #x01) (postfixes r m)))
(define-method (ADD (r <register>) (imm <integer>))
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #x04 #x05) (raw32 imm (size-of r)))
    (next-method)))
(define-method (ADD (r/m <operand>) (imm <integer>))
  (append (prefixes r/m) (if8 r/m #x80 #x81) (postfixes 0 r/m) (raw32 imm (size-of r/m))))
(define-method (ADD (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r #x02 #x03) (postfixes r r/m)))

(define-method (PUSH (r <register>))
  (append (prefixes r) (opcode #x50 r)))
(define-method (POP (r <register>))
  (append (prefixes r) (opcode #x58 r)))

(define-method (NOT (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xf6 #xf7) (postfixes 2 r/m)))

(define-method (NEG (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xf6 #xf7) (postfixes 3 r/m)))

(define-method (INC (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xfe #xff) (postfixes 0 r/m)))

(define-method (SUB (m <address>) (r <register>))
  (append (prefixes r m) (if8 m #x28 #x29) (postfixes r m)))
(define-method (SUB (r <register>) (imm <integer>))
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #x2c #x2d) (raw32 imm (size-of r)))
    (next-method)))
(define-method (SUB (r/m <operand>) (imm <integer>))
  (append (prefixes r/m) (if8 r/m #x80 #x81) (postfixes 5 r/m) (raw32 imm (size-of r/m))))
(define-method (SUB (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r/m #x2a #x2b) (postfixes r r/m)))

(define-method (IMUL (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (list #x0f #xaf) (postfixes r r/m)))
(define-method (IMUL (r <register>) (r/m <operand>) (imm <integer>))
  (if (and (< imm 128) (>= imm -128))
    (append (prefixes r r/m) (list #x6b) (postfixes r r/m) (raw32 imm 1))
    (append (prefixes r r/m) (list #x69) (postfixes r r/m) (raw32 imm (size-of r/m)))))

(define-method (IDIV (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xf6 #xf7) (postfixes 7 r/m)))
(define-method (DIV (r/m <operand>))
  (append (prefixes r/m) (if8 r/m #xf6 #xf7) (postfixes 6 r/m)))

(define-method (AND (m <address>) (r <register>))
  (append (prefixes r m) (if8 m #x20 #x21) (postfixes r m)))
(define-method (AND (r <register>) (imm <integer>))
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #x24 #x25) (raw32 imm (size-of r)))
    (next-method)))
(define-method (AND (r/m <operand>) (imm <integer>))
  (append (prefixes r/m) (if8 r/m #x80 #x81) (postfixes 4 r/m) (raw32 imm (size-of r/m))))
(define-method (AND (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r #x22 #x23) (postfixes r r/m)))

(define-method (OR (m <address>) (r <register>))
  (append (prefixes r m) (if8 m #x08 #x09) (postfixes r m)))
(define-method (OR (r <register>) (imm <integer>))
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #x0c #x0d) (raw32 imm (size-of r)))
    (next-method)))
(define-method (OR (r/m <operand>) (imm <integer>))
  (append (prefixes r/m) (if8 r/m #x80 #x81) (postfixes 1 r/m) (raw32 imm (size-of r/m))))
(define-method (OR (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r #x0a #x0b) (postfixes r r/m)))

(define-method (XOR (m <address>) (r <register>))
  (append (prefixes r m) (if8 m #x30 #x31) (postfixes r m)))
(define-method (XOR (r <register>) (imm <integer>))
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #x34 #x35) (raw32 imm (size-of r)))
    (next-method)))
(define-method (XOR (r/m <operand>) (imm <integer>))
  (append (prefixes r/m) (if8 r/m #x80 #x81) (postfixes 6 r/m) (raw32 imm (size-of r/m))))
(define-method (XOR (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r #x32 #x33) (postfixes r r/m)))

(define-method (CMP (m <address>) (r <register>))
  (append (prefixes r m) (if8 m #x38 #x39) (postfixes r m)))
(define-method (CMP (r <register>) (imm <integer>))
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #x3c #x3d) (raw32 imm (size-of r)))
    (next-method)))
(define-method (CMP (r/m <operand>) (imm <integer>))
  (append (prefixes r/m) (if8 r/m #x80 #x81) (postfixes 7 r/m) (raw32 imm (size-of r/m))))
(define-method (CMP (r <register>) (r/m <operand>))
  (append (prefixes r r/m) (if8 r/m #x3a #x3b) (postfixes r r/m)))

(define-method (TEST (r <register>) (imm <integer>))
  (if (equal? (get-code r) 0)
    (append (prefixes r) (if8 r #xa8 #xa9) (raw32 imm (size-of r)))
    (next-method)))
(define-method (TEST (r/m <operand>) (imm <integer>))
  (append (prefixes r/m) (if8 r/m #xf6 #xf7) (postfixes 0 r/m) (raw32 imm (size-of r/m))))
(define-method (TEST (r/m <operand>) (r <register>))
  (append (prefixes r r/m) (if8 r/m #x84 #x85) (postfixes r r/m)))

(define-class <jcc> ()
  (target #:init-keyword #:target #:getter get-target)
  (code8 #:init-keyword #:code8 #:getter get-code8)
  (code32 #:init-keyword #:code32 #:getter get-code32))
(define-method (write (self <jcc>) port) (format port "(Jcc ~a)" (get-target self)))
(define-method (instruction-length self) 0)
(define-method (instruction-length (self <list>)) (length self))
(define-method (Jcc target code8 code32)
  (make <jcc> #:target target #:code8 code8 #:code32 code32))
(define (conditional? self) (not (= #xeb (get-code8 self))))
(define-method (Jcc (target <integer>) code8 code32)
  (append (if (disp8? target) (list code8) code32) (raw32 target (if (disp8? target) 1 4))))
(define (retarget jcc target) (Jcc target (get-code8 jcc) (get-code32 jcc)))
(define-method (apply-offset self offsets) self)
(define-method (apply-offset (self <jcc>) offsets)
  (let [(pos    (assq-ref offsets self))
        (target (assq-ref offsets (get-target self)))]
    (retarget self (if target (- target pos) 0))))
(define (apply-offsets commands offsets) (map (cut apply-offset <> offsets) commands))
(define (stabilize-jumps commands guess)
  (let* [(applied  (apply-offsets commands guess))
         (sizes    (map instruction-length applied))
         (offsets  (map cons commands (integral sizes)))]
    (if (equal? offsets guess)
      (filter (compose not symbol?) applied)
      (stabilize-jumps commands offsets))))
(define (resolve-jumps commands) (stabilize-jumps commands '()))

(define (JMP  target) (Jcc target #xeb (list #xe9)))
(define (JB   target) (Jcc target #x72 (list #x0f #x82)))
(define (JNB  target) (Jcc target #x73 (list #x0f #x83)))
(define (JE   target) (Jcc target #x74 (list #x0f #x84)))
(define (JNE  target) (Jcc target #x75 (list #x0f #x85)))
(define (JBE  target) (Jcc target #x76 (list #x0f #x86)))
(define (JNBE target) (Jcc target #x77 (list #x0f #x87)))
(define (JL   target) (Jcc target #x7c (list #x0f #x8c)))
(define (JNL  target) (Jcc target #x7d (list #x0f #x8d)))
(define (JLE  target) (Jcc target #x7e (list #x0f #x8e)))
(define (JNLE target) (Jcc target #x7f (list #x0f #x8f)))

(define (obj commands) (u8-list->bytevector (flatten (resolve-jumps commands))))
(define (asm ctx return-type arg-types commands)
  (let* [(code   (obj commands))
         (mapped (make-mmap code))]
    (if (equal? "YES" (getenv "DEBUG")) (objdump (bytevector->u8-list code)))
    (slot-set! ctx 'binaries (cons mapped (slot-ref ctx 'binaries)))
    (pointer->procedure (foreign-type return-type)
                        (make-pointer (mmap-address mapped))
                        (map foreign-type arg-types))))

(define (SETcc code r/m)
  (append (prefixes r/m) (list #x0f code) (postfixes 0 r/m)))
(define-method (SETB   (r/m <operand>)) (SETcc #x92 r/m))
(define-method (SETNB  (r/m <operand>)) (SETcc #x93 r/m))
(define-method (SETE   (r/m <operand>)) (SETcc #x94 r/m))
(define-method (SETNE  (r/m <operand>)) (SETcc #x95 r/m))
(define-method (SETBE  (r/m <operand>)) (SETcc #x96 r/m))
(define-method (SETNBE (r/m <operand>)) (SETcc #x97 r/m))
(define-method (SETL   (r/m <operand>)) (SETcc #x9c r/m))
(define-method (SETNL  (r/m <operand>)) (SETcc #x9d r/m))
(define-method (SETLE  (r/m <operand>)) (SETcc #x9e r/m))
(define-method (SETNLE (r/m <operand>)) (SETcc #x9f r/m))

(define (CMOVcc code r r/m)
  (append (prefixes r r/m) (list #x0f code) (postfixes r r/m)))
(define-method (CMOVB   (r <register>) (r/m <operand>)) (CMOVcc #x42 r r/m))
(define-method (CMOVNB  (r <register>) (r/m <operand>)) (CMOVcc #x43 r r/m))
(define-method (CMOVE   (r <register>) (r/m <operand>)) (CMOVcc #x44 r r/m))
(define-method (CMOVNE  (r <register>) (r/m <operand>)) (CMOVcc #x45 r r/m))
(define-method (CMOVBE  (r <register>) (r/m <operand>)) (CMOVcc #x46 r r/m))
(define-method (CMOVNBE (r <register>) (r/m <operand>)) (CMOVcc #x47 r r/m))
(define-method (CMOVL   (r <register>) (r/m <operand>)) (CMOVcc #x4c r r/m))
(define-method (CMOVNL  (r <register>) (r/m <operand>)) (CMOVcc #x4d r r/m))
(define-method (CMOVLE  (r <register>) (r/m <operand>)) (CMOVcc #x4e r r/m))
(define-method (CMOVNLE (r <register>) (r/m <operand>)) (CMOVcc #x4f r r/m))

(define-method (CALL (r/m <operand>))
  (append (prefixes r/m) (list #xff) (postfixes 2 r/m)))
