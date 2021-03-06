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
(use-modules (srfi srfi-1)
             (srfi srfi-26)
             (srfi srfi-64)
             (rnrs bytevectors)
             (oop goops)
             (aiscm util)
             (aiscm asm)
             (aiscm mem)
             (aiscm jit)
             (aiscm element)
             (aiscm int)
             (aiscm pointer)
             (aiscm sequence)
             (aiscm bool)
             (aiscm rgb)
             (aiscm complex))

(test-begin "aiscm jit3")

(define ctx (make <context>))
(test-equal "subtract 2D array from each other"
  '((1 1 2) (3 4 5)) (to-list (- (arr (2 3 5) (7 9 11)) (arr (1 2 3) (4 5 6)))))
(test-equal "negate 3D array"
  '(((-1 2 -3) (4 -5 6))) (to-list (- (arr ((1 -2 3) (-4 5 -6))))))
(test-equal "add 1D and 2D array"
  '((3 4 5) (7 8 9)) (to-list (+ (seq 0 1) (arr (3 4 5) (6 7 8)))))
(test-equal "add 2D and 1D array"
  '((3 4 5) (7 8 9)) (to-list (+ (arr (3 4 5) (6 7 8)) (seq 0 1))))

(test-begin "aiscm jit3")
