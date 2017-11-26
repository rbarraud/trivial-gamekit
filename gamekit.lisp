(in-package :trivial-gamekit)


(declaim (special *font*))


(defvar +origin+ (vec2 0.0 0.0))


(defvar *exit-latch* nil)


(defvar *black* (vec4 0 0 0 1))


(defclass gamekit-system (enableable generic-system)
  ((keymap :initform nil)
   (cursor-action :initform nil)
   (resource-path :initarg :resource-path :initform nil)
   (resource-registry)
   (viewport-width :initarg :viewport-width :initform 640)
   (viewport-height :initarg :viewport-height :initform 480)
   (fullscreen-p :initarg :fullscreen-p :initform nil)
   (prepare-resources :initform t)
   (viewport-title :initarg :viewport-title :initform "Trivial Gamekit")
   (canvas :initform nil :reader canvas-of)
   (font :initform nil :reader font-of)
   (action-queue :initform (mt:make-guarded-reference nil)))
  (:default-initargs :depends-on '(graphics-system audio-system)))


(defgeneric configure-game (game)
  (:method ((this gamekit-system)) (declare (ignore this))))


(defun split-opts (opts)
  (loop for opt in opts
     if (member (first opt) '(:viewport-width
                              :viewport-height
                              :viewport-title
                              :fullscreen-p
                              :prepare-resources))
     collect opt into extended
     else
     collect opt into std
     finally (return (values std extended))))


(defmacro defgame (name (&rest classes) &body ((&rest slots) &rest opts))
  "Defines a game class that can be passed to [`#'start`](#gamekit-start) to run a game. `name` is
the name of a class generated. `classes` are names of superclasses, `slots` - standard class
slots and `opts` are class options. So, pretty much standard class definition except it does
configure a class in certain ways specifically for `gamekit` use and allows passing additional
options in `opts` apart from standard `:documentation`, `:default-initargs` and so others.

Additional options that can be passed in `opts` are:

* `:viewport-width` - width of the window and canvas
* `:viewport-height` - height of the window and canvas
* `:viewport-title` - title of the window
* `:prepare-resources` - boolean value that indicates whether `gamekit` should load resources
automatically on startup or if not, user prefers to load them dynamically on request. Defaults
to `t`.

Example:

```common_lisp
(gamekit:defgame notalone ()
  ;; some game related state
  ((world :initform (make-instance 'world))
   (game-state))
  ;; options
  (:viewport-width 800)
  (:viewport-height 600)
  (:viewport-title \"NOTALONE\")
  (:prepare-resources nil))
```"
  (multiple-value-bind (std-opts extended) (split-opts opts)
    `(progn
       (defclass ,name (gamekit-system ,@classes)
         ,slots
         ,@std-opts)
       ,(with-hash-entries ((viewport-width :viewport-width)
                            (viewport-height :viewport-height)
                            (viewport-title :viewport-title)
                            (fullscreen-p :fullscreen-p)
                            (prepare-resources :prepare-resources))
            (alist-hash-table extended)
          `(progn
             (defmethod configure-game ((this ,name))
               ,@(when viewport-width
                   `((setf (slot-value this 'viewport-width) ,@viewport-width)))
               ,@(when viewport-height
                   `((setf (slot-value this 'viewport-height) ,@viewport-height)))
               ,@(when viewport-title
                   `((setf (slot-value this 'viewport-title) ,@viewport-title)))
               ,@(when fullscreen-p
                   `((setf (slot-value this 'fullscreen-p) ,@fullscreen-p)))
               ,@(multiple-value-bind (value exist-p) prepare-resources
                   `((setf (slot-value this 'prepare-resources) ,(if exist-p
                                                                     (first value)
                                                                     t))))))))))


(defmethod initialize-instance :around ((this gamekit-system) &key)
  (when (null *gamekit-instance-class*)
    (error "Manual gamekit instance creation forbidden. Use #'gamekit:start"))
  (call-next-method))


(defun gamekit ()
  "Returns instance of a running game or `nil` if no game is started yet.

Example:
```common_lisp
(gamekit:gamekit)
```"
  (when *gamekit-instance-class*
    (ge.ng:engine-system *gamekit-instance-class*)))


(defgeneric act (system)
  (:method ((system gamekit-system)) (declare (ignore system))))


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
  (with-slots (canvas font) system
    (gl:clear :color-buffer :depth-buffer :stencil-buffer)
    (ge.vg:with-canvas (canvas)
      (let ((*font* font))
        (call-next-method)))))


(defmethod initialize-resources :around ((system gamekit-system))
  (with-slots (resource-registry) system
    (let ((*resource-registry* resource-registry))
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


(defun make-package-resource-table (resource-paths)
  (flet ((to-package-pair (pair)
           (cons (find-package (car pair)) (cdr pair))))
    (alist-hash-table (mapcar #'to-package-pair resource-paths))))


(defun push-action (game action)
  (with-slots (action-queue) game
    (mt:with-guarded-reference (action-queue)
      (push action action-queue))))


(defgeneric notice-resources (game &rest resource-names)
  (:method ((this gamekit-system) &rest resource-names)
    (declare (ignore this))
    (log:trace "Resources loaded: ~A" resource-names)))


(defun prepare-resources (game &rest resource-names)
  (log:trace "Preparing resources: ~A" resource-names)
  (with-slots (canvas resource-registry) game
    (flet ((get-canvas ()
             canvas)
           (notify-game ()
             (apply #'notice-resources game resource-names)))
      (run (>> (loading-flow resource-registry #'get-canvas resource-names)
               (instantly ()
                 (push-action game #'notify-game)))))))


(defmethod initialize-system :after ((this gamekit-system))
  (with-slots (keymap viewport-title viewport-width viewport-height fullscreen-p
                      canvas resource-registry resource-path
                      prepare-resources action-queue font)
      this
    (configure-game this)
    (setf keymap (make-hash-table)
          resource-registry (make-instance 'gamekit-resource-registry))
    (initialize-resources this)
    (unless (executablep)
      (when resource-path
        (register-resource-package :keyword resource-path)
        (%mount-packages :keyword))
      (when prepare-resources
        (apply #'%mount-resources (list-all-resources))))
    (flet ((%get-canvas ()
             canvas))
      (run (>> (-> ((host)) ()
                 (setf (viewport-title) viewport-title)
                 (setf (fullscreen-viewport-p) fullscreen-p)
                 (setf (viewport-size) (vec2 viewport-width viewport-height))
                 (initialize-host this))
               (-> ((audio)) ()
                 (initialize-audio this))
               (-> ((graphics)) ()
                 (gl:viewport 0 0 viewport-width viewport-height)
                 (setf canvas (ge.vg:make-canvas viewport-width
                                                 viewport-height
                                                 :antialiased t))
                 (ge.vg:with-canvas (canvas)
                   (let ((font-face (ge.vg:register-font-face +font-name+ (load-resource +font-name+))))
                     (setf font (ge.vg:make-font font-face 32))))
                 (setf (swap-interval (host)) 1)
                 (initialize-graphics this))
               (when prepare-resources (loading-flow resource-registry
                                                     #'%get-canvas
                                                     (list-all-resources)))
               (concurrently ()
                 (post-initialize this)
                 (let (looped-flow)
                   (setf looped-flow (>> (instantly ()
                                           (mt:with-guarded-reference (action-queue)
                                             (loop for action in action-queue
                                                do (funcall action)
                                                finally (setf action-queue nil)))
                                           (act this))
                                         (-> ((graphics)) ()
                                           (draw this)
                                           (swap-buffers (host)))
                                         (instantly ()
                                           (when (enabledp this)
                                             (run looped-flow)))))
                   (run looped-flow))))))))


(defun resource-by-id (id)
  (with-slots (resource-registry) (gamekit)
    (%get-resource resource-registry id)))


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


(defun play-sound (sound-id &key looped-p)
  (let ((source (resource-by-id sound-id)))
    (when looped-p
      (setf (ge.snd:audio-looped-p source) t))
    (ge.snd:play-audio source)))


(defun stop-sound (sound-id)
  (ge.snd:stop-audio (resource-by-id sound-id)))


(defun play (sound-id &key looped-p)
  "Deprecated. Use #'play-sound instead"
  (play-sound sound-id :looped-p looped-p))


(defun draw-image (position image-id &key origin width height)
  (when-let ((image (resource-by-id image-id)))
    (let* ((image-origin (or origin +origin+))
           (image-width (if width
                            width
                            (width-of image)))
           (image-height (if height
                             height
                             (height-of image))))
      (ge.vg:with-pushed-canvas ()
        (ge.vg:translate-canvas (- (x position) (x image-origin)) (- (y position) (y image-origin)))
        (draw-rect image-origin image-width image-height :fill-paint image)))))


(defun make-font (font-id size)
  (ge.vg:make-font (resource-by-id font-id) size))


(defun print-text (string x y &optional (color *black*))
  "Deprecated. Use #'draw-text instead"
  (draw-text string (vec2 x y) :fill-color color))


(defun draw-text (string origin &key (fill-color *black*) (font *font*))
  (ge.vg:with-font (font)
    (ge.vg:draw-text origin string :fill-color fill-color)))


;;;
;;; Startup routines
;;;
(defun start (classname &key (log-level :info) (opengl-version '(3 3)) blocking)
  "Bootsraps a game allocating a window and other system resources. Instantiates game object
defined with [`defgame`](#gamekit-defgame) which can be obtained via
[`#'gamekit`](#gamekit-gamekit). Cannot be called twice - [`#'stop`](#gamekit-stop) should be
called first before running `start` again.

Example:

```common_lisp
(gamekit:start 'notalone)
```"
  (when *gamekit-instance-class*
    (error "Only one active system of type 'gamekit-system is allowed"))
  (let ((exit-latch (mt:make-latch)))
    (setf *gamekit-instance-class* classname
          *exit-latch* exit-latch)
    (startup `(:engine (:systems (,classname) :log-level ,log-level)
                       :host (:opengl-version ,opengl-version)))
    (when blocking
      (mt:wait-for-latch exit-latch))))


(defun stop ()
  "Stops currently running game releasing acquired resources.

Example:
```common_lisp
(gamekit:stop)
```"
  (shutdown)
  (let ((latch *exit-latch*))
    (setf *gamekit-instance-class* nil
          *exit-latch* nil)
    (mt:open-latch latch)))


(define-event-handler on-exit ((ev viewport-hiding-event))
  (in-new-thread "exit-thread"
    (stop)))
