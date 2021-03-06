(define-module (aiscm samples)
  #:use-module (oop goops)
  #:use-module (ice-9 optargs)
  #:use-module (srfi srfi-1)
  #:use-module (aiscm mem)
  #:use-module (aiscm util)
  #:use-module (aiscm element)
  #:use-module (aiscm int)
  #:use-module (aiscm float)
  #:use-module (aiscm sequence)
  #:use-module (aiscm jit)
  #:export (<samples> <meta<samples>>
            AV_SAMPLE_FMT_U8 AV_SAMPLE_FMT_S16 AV_SAMPLE_FMT_S32 AV_SAMPLE_FMT_FLT AV_SAMPLE_FMT_DBL
            AV_SAMPLE_FMT_U8P AV_SAMPLE_FMT_S16P AV_SAMPLE_FMT_S32P AV_SAMPLE_FMT_FLTP AV_SAMPLE_FMT_DBLP
            planar? to-samples convert-samples convert-samples-from! type+planar->sample-format
            sample-format->type sample-format->planar)
  #:re-export (typecode shape channels rate to-array size-of))

(load-extension "libguile-aiscm-samples" "init_samples")

(define-class* <samples> <object> <meta<samples>> <class>
              (typecode #:init-keyword #:typecode #:getter typecode)
              (shape    #:init-keyword #:shape    #:getter shape   )
              (rate     #:init-keyword #:rate     #:getter rate    )
              (offsets  #:init-keyword #:offsets  #:getter offsets )
              (planar   #:init-keyword #:planar   #:getter planar? )
              (mem      #:init-keyword #:mem                       ))

(define-method (initialize (self <samples>) initargs)
  "Convert for images"
  (let-keywords initargs #f (typecode shape rate offsets planar mem)
    (let [(offsets (or offsets (if planar (iota (car shape) 0 (* (size-of typecode) (cadr shape))) '(0))))
          (mem     (or mem (make <mem> #:size (apply * (size-of typecode) shape) #:pointerless #t)))]
      (next-method self (list #:typecode typecode
                              #:shape    shape
                              #:rate     rate
                              #:offsets  offsets
                              #:planar   planar
                              #:mem      mem)))))

(define-method (channels (self <samples>))
  "Get number of audio channels of audio samples"
  (car (shape self)))

(define-method (size-of (self <samples>))
  "Memory size of audio samples in bytes"
  (apply * (size-of (typecode self)) (shape self)))

(define-method (to-array (self <samples>))
  "Convert audio samples to a numerical array"
  (if (planar? self)
      (to-array (convert-samples self (typecode self) #f))
      (make (multiarray (typecode self) 2) #:shape (shape self) #:value (slot-ref self 'mem))))

(define (to-samples self rate)
  "Convert numerical array to audio samples"
  (let [(shape     (if (eqv? (dimensions self) 1) (cons 1 (shape self)) (shape self)))
        (compacted (ensure-default-strides self))]
    (make <samples> #:typecode (typecode self) #:shape shape #:planar #f #:rate rate #:mem (slot-ref compacted 'value))))

(define typemap-packed
  (list (cons <ubyte>  AV_SAMPLE_FMT_U8  )
        (cons <sint>   AV_SAMPLE_FMT_S16 )
        (cons <int>    AV_SAMPLE_FMT_S32 )
        (cons <float>  AV_SAMPLE_FMT_FLT )
        (cons <double> AV_SAMPLE_FMT_DBL )))

(define typemap-planar
  (list (cons <ubyte>  AV_SAMPLE_FMT_U8P )
        (cons <sint>   AV_SAMPLE_FMT_S16P)
        (cons <int>    AV_SAMPLE_FMT_S32P)
        (cons <float>  AV_SAMPLE_FMT_FLTP)
        (cons <double> AV_SAMPLE_FMT_DBLP)))

(define inverse-typemap
  (append (alist-invert typemap-packed) (alist-invert typemap-planar)))

(define (type+planar->sample-format type planar)
  "Convert type and planar/packed information to type tag"
  (or (assq-ref (if planar typemap-planar typemap-packed) type)
      (aiscm-error 'type+planar->sample-format "Type ~a not supported by FFmpeg audio" type)))

(define (sample-format->type sample-format)
  "Get type information for type tag"
  (assq-ref inverse-typemap sample-format))

(define (sample-format->planar sample-format)
  "Check whether a sample format is planar"
  (not (memv sample-format (map cdr typemap-packed))))

(define (descriptor self)
  (list (type+planar->sample-format (typecode self) (planar? self)) (shape self) (rate self) (offsets self)))

(define (convert-samples-from! destination source)
  "Convert audio samples from source to destination format"
  (let [(source-type (descriptor source))
        (dest-type   (descriptor destination))]
    (samples-convert (get-memory (slot-ref source 'mem)) source-type (get-memory (slot-ref  destination 'mem)) dest-type)))

(define (convert-samples self typecode planar)
  "Convert audio samples using the specified attributes"
  (let* [(size        (apply * (size-of typecode) (shape self)))
         (destination (make <samples>
                            #:typecode typecode
                            #:shape (shape self)
                            #:rate (rate self)
                            #:planar planar
                            #:mem (make <mem> #:size size #:pointerless #t)))]
    (convert-samples-from! destination self)
    destination))
