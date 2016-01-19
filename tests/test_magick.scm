(use-modules (aiscm magick)
             (aiscm element)
             (aiscm pointer)
             (aiscm rgb)
             (guile-tap))
(planned-tests 2)
(define dot (read-image "fixtures/dot.png"))
(ok (equal? '(6 4) (shape dot))
    "Check size of loaded image")
(skip (equal? (rgb 36 46 65) (get dot 2 1))
    "Check loaded image")
