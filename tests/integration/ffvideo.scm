(use-modules (aiscm ffmpeg) (aiscm xorg) (aiscm util))
(define video (open-input-video "av-sync.mp4"))
(define time (clock))
(show (lambda (dsp) (synchronise (read-video video) time (video-pts video) (event-loop dsp))))
