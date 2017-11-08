(cl:in-package :cl-user)


(declaim (special *gamekit-game-class*))


(defun %find-game-class ()
  (let ((package (find-package (first *gamekit-game-class*))))
    (find-symbol (symbol-name (second *gamekit-game-class*)) package)))


(defun trivial-gamekit::main (args)
  (declare (ignore args))
  (let ((game-class (%find-game-class)))
    (gamekit:start game-class :blocking t :log-level :trace)))


(defun mount-containers ()
  (ge.as:mount-container "/_gamekit/"
                         (ge.ng:merge-working-pathname "assets/gamekit.brf")
                         "/_gamekit/")
  (ge.as:mount-container "/_asset/"
                         (ge.ng:merge-working-pathname "assets/assets.brf")
                         "/_asset/"))

(pushnew #'mount-containers ge.ng:*engine-startup-hooks*)