(define-module (aiscm xorg)
  #:use-module (oop goops)
  #:use-module (ice-9 optargs)
  #:use-module (aiscm util)
  #:use-module (aiscm element)
  #:use-module (aiscm image)
  #:export (<xdisplay> <meta<xdisplay>>
            <xwindow> <meta<xwindow>>
            process-events event-loop quit? quit=
            show hide title= resize IO-XIMAGE IO-OPENGL IO-XVIDEO))
(load-extension "libguile-xorg" "init_xorg")
(define-class* <xdisplay> <object> <meta<xdisplay>> <class>
  (display #:init-keyword #:display #:getter get-display))
(define-method (initialize (self <xdisplay>) initargs)
  (let-keywords initargs #f (name)
    (let [(name (or name ":0.0"))]
      (next-method self (list #:display (make-display name))))))
(define-method (shape (self <xdisplay>)) (display-shape (get-display self)))
(define-method (process-events (self <xdisplay>)) (display-process-events (get-display self)))
(define-method (event-loop (self <xdisplay>) (timeout <real>))
  (display-event-loop (get-display self) timeout))
(define-method (event-loop (self <xdisplay>)) (display-event-loop (get-display self) -1))
(define-method (destroy (self <xdisplay>)) (display-destroy (get-display self)))
(define-method (quit? (self <xdisplay>)) (display-quit? (get-display self)))
(define-method (quit= (self <xdisplay>) (value <boolean>)) (display-quit= (get-display self) value))
(define-class* <xwindow> <object> <meta<xwindow>> <class>
              (window #:init-keyword #:window #:getter get-window))
(define-method (initialize (self <xwindow>) initargs)
  (let-keywords initargs #f (display shape io)
    (let [(io (or io IO-XIMAGE))]
      (next-method self (list #:window (make-window (get-display display) (car shape) (cadr shape) io))))))
(define-method (show (self <xwindow>)) (window-show (get-window self)))
(define-method (show (self <image>))
  (let* [(display (make <xdisplay>))
         (window  (make <xwindow> #:display display #:shape (shape self) #:io IO-XIMAGE))]
    (title= window "AIscm")
    (write window self)
    (show window)
    (event-loop display)
    (hide window)
    (destroy display)))
(define-method (show (self <procedure>))
  (let* [(img     (self))
         (display (make <xdisplay>))
         (window  (make <xwindow> #:display display #:shape (shape img) #:io IO-XVIDEO))]
    (title= window "AIscm")
    (write window img)
    (show window)
    (do () ((quit? display)) (write window (self)) (process-events display))
    (hide window)
    (destroy display)))
(define-method (hide (self <xwindow>)) (window-hide (get-window self)))
(define-method (destroy (self <xwindow>)) (window-destroy (get-window self)))
(define-method (title= (self <xwindow>) (title <string>)) (window-title= (get-window self) title))
(define-method (resize (self <xwindow>) (shape <list>))
  (window-resize (get-window self) (car shape) (cadr shape)))
(define-method (show (self <xwindow>) (image <image>))
  (window-write (get-window self) image))
