;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: SIMPLE-NODEPORT-SERVICE; Base: 10 -*-
;;;
;;; Copyright (C) 2023  Anthony Green <green@redhat.com>
;;;
;;; This program is free software: you can redistribute it and/or
;;; modify it under the terms of the GNU Affero General Public License
;;; as published by the Free Software Foundation, either version 3 of
;;; the License, or (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Affero General Public License for more details.
;;;
;;; You should have received a copy of the GNU Affero General Public
;;; License along with this program.  If not, see
;;; <http://www.gnu.org/licenses/>.

;; Top level for simple-nodeport-service

(in-package :simple-nodeport-service)

;; ----------------------------------------------------------------------------
;; Machinery for managing the execution of the server.

(defvar *shutdown-cv* (bt:make-condition-variable))
(defvar *server-lock* (bt:make-lock))

;; ----------------------------------------------------------------------------

(defvar *config* nil)
(defvar *max-nodes* 0)
(defvar *name-template* "EMPTY-")
(defvar *resource-group* nil)

;; ----------------------------------------------------------------------------
;; The port of the server.  Define this in your config.ini files.

(defvar *server-port* nil)

;; ----------------------------------------------------------------------------
;; API routes

;; Readiness probe.
(easy-routes:defroute health ("/health") ()
  "ready")

(defvar *etcd* nil)

(easy-routes:defroute index ("/") ()
  (with-output-to-string (stream)
    (loop for p from *min-port* upto *max-port*
          when (cl-etcd:get-etcd (format nil "~A" p) *etcd*)
            do (format stream "~A~%" p))))

(defmacro run-with-retry (fmtstring &rest args)
  `(%run-with-retry (format nil ,fmtstring ,@args)))

(easy-routes:defroute get-nodeport ("/get-nodeport") (target)
  (tmpdir:with-tmpdir (tmpdir)
    (let* ((port (block find-port
                 (loop for p from *min-port* upto *max-port*
                       do (handler-case
                              (return-from find-port
                                (setf (cl-etcd:get-etcd (format nil "~A" p) *etcd* :key-must-not-exist t) "1"))
                            (cl-etcd:key-already-exists (e)
                              nil)))))
           (svcfile (str:concat (namestring tmpdir) "/service.yml")))
      (with-open-file (stream svcfile
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (format stream "---
apiVersion: v1
kind: Service
metadata:
  name: yarn-port-~A
  labels:
    name: yarn-port-~A
spec:
  type: NodePort
  ports:
    - port: 8000
      nodePort: ~A
      name: yarn
  selector:
    name: notebook-~A
" port port port target))
      (run-with-retry "bash -c 'KUBECONFIG=/etc/simple-nodeport-service/kubeconfig oc create -f ~A" svcfile))))

;; ----------------------------------------------------------------------------
;; HTTP server control

(defparameter *handler* nil)

(defmacro stop-server (&key (handler '*handler*))
  "Shutdown the HTTP handler"
  `(hunchentoot:stop ,handler))

(defvar *leader?* nil)

(defun %run-with-retry (cmd)
  "Try running CMD up to 5 times, waiting longer between each retry,
to account for intermittent network problems."
  (log:info cmd)
  (flet ((%%run-with-retry (cmd)
           (handler-case
               (inferior-shell:run cmd)
             (error (c)
               (progn
                 (log:info "error> ~A" c)
                 t)))))
    (loop for i from 1 upto 5
          until (not (%%run-with-retry cmd))
          do (progn (log:info "retry #~A" i) (sleep (* i 2)))
          finally (when (eq i 6) (log:error "failed cmd: ~A" cmd)))))

;; This method is called when I become leader.
(defun become-leader (etcd)
  (log:info t "**** I AM THE LEADER ***********")
  (setf *leader?* t))

;; This method is called when I become a follower.
(defun become-follower (etcd)
  (log:info "**** I AM A FOLLOWER ***********")
  (setf *leader?* nil))

(defun start-server (&optional (config-ini "/etc/simple-nodeport-service/config.ini"))

  (bt:with-lock-held (*server-lock*)

    (setf hunchentoot:*catch-errors-p* t)
    (setf hunchentoot:*show-lisp-errors-p* t)
    (setf hunchentoot:*show-lisp-backtraces-p* t)

    (log:info "Starting simple-nodeport-service.")

    ;; Read the user configuration settings.
    (setf *config*
  	  (if (fad:file-exists-p config-ini)
	      (cl-toml:parse
	       (alexandria:read-file-into-string config-ini
					         :external-format :latin-1))
	      (make-hash-table)))

    (flet ((get-config-value (key)
	     (let ((value (or (gethash key *config*)
			      (error "config does not contain key '~A'" key))))
	       ;; Some of the users of these values are very strict
	       ;; when it comes to string types... I'm looking at you,
	       ;; SB-BSD-SOCKETS:GET-HOST-BY-NAME.
	       (if (subtypep (type-of value) 'vector)
		   (coerce value 'simple-string)
		   value))))

      ;; Extract any config.ini settings here.
      (setf *server-port* (get-config-value "server-port"))
      (setf *min-port* (get-config-value "min-port"))
      (setf *max-port* (get-config-value "max-port"))

      (log:info "Starting server")

      (setf *print-pretty* nil)
      (setf *handler* (hunchentoot:start (make-instance 'easy-routes:routes-acceptor :port *server-port*)))

      (cl-etcd:with-etcd (etcd (gethash "etcd" *config*)
                               :on-leader #'become-leader
                               :on-follower #'become-follower)
        (setf *etcd* etcd)
        (bt:condition-wait *shutdown-cv* *server-lock*)))))
