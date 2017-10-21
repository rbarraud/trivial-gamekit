(in-package :trivial-gamekit)


(defvar +origin+ (vec2 0.0 0.0))


(declaim (special *text-renderer*))


(define-constant +assets-directory+
    (merge-pathnames "assets/" (asdf:component-pathname (asdf:find-system :trivial-gamekit)))
  :test #'equal)


(defun asset-path (file)
  (merge-pathnames file +assets-directory+))


(defvar *gamekit-instance-class* nil)


(defclass gamekit-system (enableable generic-system)
  ((keymap :initform nil)
   (cursor-action :initform nil)
   (resource-path :initform #p"~/" :initarg :resource-path)
   (resource-loader :initform nil)
   (viewport-width :initarg :viewport-width :initform 640)
   (viewport-height :initarg :viewport-height :initform 480)
   (fullscreen-p :initarg :fullscreen-p :initform nil)
   (viewport-title :initarg :viewport-title :initform "Trivial Gamekit")
   (canvas :initform nil :reader canvas-of)
   (text-renderer :initform nil))
  (:default-initargs :depends-on '(graphics-system audio-system)))


(defmethod initialize-instance :around ((this gamekit-system) &key)
  (when (null *gamekit-instance-class*)
    (error "Manual gamekit instance creation forbidden. Use #'gamekit:start"))
  (call-next-method))


(definline gamekit ()
  (ge.ng:engine-system *gamekit-instance-class*))


(defgeneric draw (system)
  (:method ((system gamekit-system)) (declare (ignore system))))


(defgeneric initialize-resources (system)
  (:method ((system gamekit-system)) (declare (ignore system))))


(defgeneric initialize-audio (system)
  (:method ((system gamekit-system)) (declare (ignore system))))


(defgeneric initialize-graphics (system)
  (:method ((system gamekit-system)) (declare (ignore system))))


(defgeneric initialize-host (system)
  (:method ((system gamekit-system)) (declare (ignore system))))


(defgeneric post-initialize (system)
  (:method ((system gamekit-system)) (declare (ignore system))))


(defmethod draw :around ((system gamekit-system))
  (with-slots (canvas text-renderer) system
    (with-canvas (canvas)
      (let ((*text-renderer* text-renderer))
        (gl:clear :color-buffer :depth-buffer :stencil-buffer)
        (call-next-method)))))


(defmethod initialize-resources :around ((system gamekit-system))
  (with-slots (resource-loader) system
    (let ((*resource-loader* resource-loader))
      (call-next-method))))


(define-event-handler on-keyboard-event ((ev keyboard-event) key state)
  (with-slots (keymap) (gamekit)
    (when-let ((action (getf (gethash key keymap) state)))
      (funcall action))))


(defun bodge-mouse-button->gamekit (bodge-button)
  (case bodge-button
    (:left :mouse-left)
    (:right :mouse-right)
    (:middle :mouse-middle)
    (t bodge-button)))


(define-event-handler on-mouse-event ((ev mouse-event) button state)
  (with-slots (keymap) (gamekit)
    (when-let ((action (getf (gethash (bodge-mouse-button->gamekit button) keymap) state)))
      (funcall action))))


(define-event-handler on-cursor-event ((ev cursor-event) x y)
  (with-slots (cursor-action) (gamekit)
    (when cursor-action
      (funcall cursor-action x y))))


(defmethod initialize-system :after ((this gamekit-system))
  (with-slots (keymap viewport-title viewport-width viewport-height fullscreen-p
                      text-renderer canvas resource-loader resource-path)
      this
    (register-resource-loader (make-resource-loader (asset-path "font.brf")))
    (setf keymap (make-hash-table)
          resource-loader (make-instance 'gamekit-resource-loader))
    (initialize-resources this)
    (flet ((%get-canvas ()
             canvas))
      (run (>> (-> ((host)) ()
                 (setf (viewport-title) viewport-title)
                 (setf (fullscreen-viewport-p) fullscreen-p)
                 (setf (viewport-size) (vec2 viewport-width viewport-height))
                 (initialize-host this))
               (-> ((audio)) ()
                 (initialize-audio this))
               (resource-flow (font-resource-name "NotoSansUI-Regular.ttf"))
               (-> ((graphics)) (font)
                 (gl:viewport 0 0 viewport-width viewport-height)
                 (setf text-renderer (make-text-renderer viewport-width
                                                         viewport-height
                                                         font 32.0)
                       canvas (make-canvas viewport-width
                                           viewport-height
                                           :antialiased t))
                 (setf (swap-interval (host)) 1)
                 (initialize-graphics this))
               (preloading-flow resource-loader #'%get-canvas resource-path)
               (concurrently ()
                 (post-initialize this)
                 (let (looped-flow)
                   (setf looped-flow (>> (-> ((graphics)) ()
                                           (draw this)
                                           (swap-buffers (host)))
                                         (instantly ()
                                           (when (enabledp this)
                                             (run looped-flow)))))
                   (run looped-flow))))))))


(defun resource-by-id (id)
  (with-slots (resource-loader) (gamekit)
    (%get-resource resource-loader id)))


(defun bind-button (key state action)
  (let ((gamekit (gamekit)))
    (with-slots (keymap) gamekit
      (with-system-lock-held (gamekit)
        (setf (getf (gethash key keymap) state) action)))))


(defun bind-cursor (action)
  (let ((gamekit (gamekit)))
    (with-slots (cursor-action) gamekit
      (with-system-lock-held (gamekit)
        (setf cursor-action action)))))


(defun play (sound-id)
  (run (-> ((audio)) ()
         (ge.snd:play-audio (resource-by-id sound-id)))))


(defun draw-image (origin image-id &key image-origin image-end)
  (when-let ((image (resource-by-id image-id)))
    (let* ((image-origin (or image-origin +origin+))
           (image-width (if image-end
                            (- (x image-end) (x image-origin))
                            (width-of image)))
           (image-height (if image-end
                             (- (y image-end) (y image-origin))
                             (height-of image))))
      (with-pushed-canvas ()
        (translate-canvas (- (x origin) (x image-origin)) (- (y origin) (y image-origin)))
        (draw-rect image-origin image-width image-height :fill-paint image)))))


(defun print-text (string x y &optional color)
  (draw-text *text-renderer* string :position (vec2 x y) :color color))


(defun start (classname &key (log-level :info) (opengl-version '(3 3)))
  (when *gamekit-instance-class*
    (error "Only one active system of type 'gamekit-system is allowed"))
  (setf *gamekit-instance-class* classname)
  (startup `(:engine (:systems (,classname) :log-level ,log-level)
             :host (:opengl-version ,opengl-version))))


(defun stop ()
  (shutdown)
  (setf *gamekit-instance-class* nil))


(define-event-handler on-exit ((ev viewport-hiding-event))
  (in-new-thread "exit-thread"
    (stop)))
