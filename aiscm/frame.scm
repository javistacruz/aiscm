(define-module (aiscm frame)
  #:use-module (oop goops)
  #:use-module (aiscm util)
  #:export (<frame> <meta<frame>>
            get-format get-width get-height get-data convert
            PIX_FMT_YUYV422 PIX_FMT_GRAY8 PIX_FMT_BGRA))
(load-extension "libguile-frame" "init_frame")
(define-class <meta<frame>> (<class>))
(define-class <frame> ()
              (format #:init-keyword #:format #:getter get-format)
              (width #:init-keyword #:width #:getter get-width)
              (height #:init-keyword #:height #:getter get-height)
              (data #:init-keyword #:data #:getter get-data)
              #:metaclass <meta<frame>>)
(define formats
  (list (cons 'RGB  PIX_FMT_RGB24)
        (cons 'BGR  PIX_FMT_BGR24)
        (cons 'BGRA PIX_FMT_BGRA)
        (cons 'GRAY PIX_FMT_GRAY8)
        (cons 'I420 PIX_FMT_YUV420P)
        (cons 'UYVY PIX_FMT_UYVY422)
        (cons 'YUY2 PIX_FMT_YUYV422)))
(define symbols (assoc-invert formats))
(define (sym->fmt sym) (assq-ref formats sym))
(define (fmt->sym fmt) (assq-ref symbols fmt))
(define-method (convert (self <frame>) (format <symbol>) (width <integer>) (height <integer>))
  (let [(data (frame-convert (sym->fmt (get-format self))
                             (get-width self)
                             (get-height self)
                             (get-data self)
                             (sym->fmt format)
                             width
                             height))]
    (make <frame>
          #:format format
          #:width width
          #:height height
          #:data data)))
(define-method (convert (self <frame>) (format <symbol>))
  (convert self format (get-width self) (get-height self)))
(define-method (write (self <frame>) port)
  (format port "#<<frame> ~a ~a ~a>" (get-format self) (get-width self) (get-height self)))
(define-method (display (self <frame>) port)
  (format port "#<<frame> ~a ~a ~a>" (get-format self) (get-width self) (get-height self)))