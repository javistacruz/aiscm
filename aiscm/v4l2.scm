(define-module (aiscm v4l2)
  #:use-module (oop goops)
  #:use-module (aiscm util)
  #:use-module (aiscm mem)
  #:use-module (aiscm int)
  #:use-module (aiscm image)
  #:use-module (aiscm sequence)
  #:use-module (system foreign)
  #:export (make-v4l2 v4l2-close v4l2-read))
(load-extension "libguile-v4l2" "init_v4l2")
(define formats
  (list (cons 'RGB  V4L2_PIX_FMT_RGB24)
        (cons 'BGR  V4L2_PIX_FMT_BGR24)
        (cons 'I420 V4L2_PIX_FMT_YUV420)
        (cons 'UYVY V4L2_PIX_FMT_UYVY)
        (cons 'YUY2 V4L2_PIX_FMT_YUYV)
        (cons 'GRAY V4L2_PIX_FMT_GREY)))
(define symbols (assoc-invert formats))
(define (sym->fmt sym) (assq-ref formats sym))
(define (fmt->sym fmt) (assq-ref symbols fmt))
(define format-order (map car formats))
(define (format< x y)
  (let [(ord-x (index (car x) format-order))
        (ord-y (index (car y) format-order))
        (size-x (apply * (cdr x)))
        (size-y (apply * (cdr y)))]
    (or (< ord-x ord-y) (and (eqv? ord-x ord-y) (< size-x size-y)))))
(define (make-v4l2 device channel select)
  (let [(decode (lambda (f) (cons (fmt->sym (car f)) (cdr f))))
        (encode (lambda (f) (cons (sym->fmt (car f)) (cdr f))))]
    (make-v4l2-orig device
                    channel
                    (lambda (formats) (encode (select (sort (map decode formats) format<)))))))
(define (v4l2-read self)
  (let [(picture (v4l2-read-orig self))]
    (make <image>
          #:format (fmt->sym (car picture))
          #:width  (cadr picture)
          #:height (caddr picture)
          #:data   (cadddr picture))))
