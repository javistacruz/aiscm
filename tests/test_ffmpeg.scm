(use-modules (oop goops)
             (srfi srfi-1)
             (aiscm ffmpeg)
             (aiscm element)
             (aiscm int)
             (aiscm rgb)
             (aiscm image)
             (aiscm pointer)
             (aiscm sequence)
             (guile-tap))
(define video (open-input-video "fixtures/camera.avi"))
(define audio (open-input-audio "fixtures/test.mp3"))
(define image (open-input-video "fixtures/fubk.png"))
(define video-pts0 (video-pts video))
(define video-frame (read-video video))
(define video-pts1 (video-pts video))
(define audio-mono-frame (read-audio audio))
(define audio-stereo-frame (read-audio video))
(ok (equal? '(320 240) (shape video))
    "Check frame size of input video")
(ok (throws? (open-input-video "fixtures/no-such-file.avi"))
    "Throw error if file does not exist")
(ok (throws? (shape audio))
    "Audio file does not have width and height")
(ok (throws? (video-pts audio))
    "Audio file does not have a video presentation time stamp")
(ok (equal? '(320 240) (shape video-frame))
    "Check shape of video frame")
(ok (is-a? video-frame <image>)
    "Check that video frame is an image object")
(ok (eqv? 5 (frame-rate video))
    "Get frame rate of video")
(ok (throws? (frame-rate audio))
    "Audio file does not have a frame rate")
(ok (not (cadr (list (read-video image) (read-video image))))
    "Image has only one video frame")
(ok (equal? (rgb 195 179 137) (get (to-array video-frame) 100 200))
    "Check a pixel in the first video frame of the video")
(ok (equal? (list 0 (/ 1 5)) (list video-pts0 video-pts1))
    "Check first two video frame time stamps")
(define full-run (open-input-video "fixtures/camera.avi"))
(define images (map (lambda (i) (read-video full-run)) (iota 157)))
(ok (last images)
    "Check last image of video was read")
(ok (not (read-video full-run))
    "Check 'read-video' returns false after last frame")
(ok (eqv? 1 (channels audio))
    "Detect mono audio stream")
(ok (eqv? 2 (channels video))
    "Detect stereo audio stream")
(ok (throws? (channels image))
    "Image does not have audio channels")
(ok (eqv? 8000 (rate audio))
    "Get sampling rate of audio stream")
(ok (throws? (rate image))
    "Image does not have an audio sampling rate")
(ok (eq? <sint> (typecode audio))
    "Get type of audio samples")
(ok (throws? (typecode image))
    "Image does not have an audio sample type")
(ok (is-a? audio-mono-frame <sequence<>>)
    "Check that audio frame is an array")
(ok (eqv? 2 (dimensions audio-mono-frame))
    "Audio frame should have two dimensions")
(ok (eq? <sint> (typecode audio-mono-frame))
    "Audio frame should have samples of correct type")
(ok (eqv? 1 (car (shape audio-mono-frame)))
    "Mono audio frame should have 1 as first dimension")
(ok (eqv? 2 (car (shape audio-stereo-frame)))
    "Stereo audio frame should have 2 as first dimension")
(run-tests)
