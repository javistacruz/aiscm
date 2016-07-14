(use-modules (oop goops) (aiscm ffmpeg) (aiscm xorg) (aiscm pulse) (aiscm util) (aiscm element) (aiscm image))
(define video (open-input-video "av-sync.mp4"))
(define pulse (make <pulse-play> #:rate (rate video) #:channels (channels video) #:type (typecode video)))
(define (play-audio video)
  (let [(frame (read-audio/video video))]
    (if (or (not frame) (is-a? frame <image>)) frame (begin (write-samples frame pulse) (play-audio video)))))
(define time (clock))
(show (lambda (dsp)
  (synchronise (read-video video) time (video-pts video) (event-loop dsp))))
(drain pulse)
