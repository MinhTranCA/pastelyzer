(in-package #:pastelyzer)

;;; System release version.
(defvar *release* "0.8")

;;; Set by build script.
(defvar *build-id* nil)

(defvar *circl-zmq-address*)

(defvar *interesting-networks* nil)

(defvar *interesting-tlds* '()
  "A list of TLDs that should be treated as noteworthy.")

(defvar *valid-tlds* nil
  "Table of all valid TLDs.")

(defvar *log-artefacts-threshold* 3
  "Include artefacts in the log output if there are fewer than this
  number of them")

(defvar *interesting-b64-size-threshold* 500
  "Create artefacts for Base64 fragments at least this big.")

(defvar *acceptor* nil)

(defvar *web-server-external-uri*
  (make-instance 'puri:uri :scheme :http :host "localhost"))

;; XXX: This is a hack to avoid resolving same domains over and over
;; again (in the scope of a single paste for now; see PROCESS generic
;; function).  Until we have our own resolver in place.
(defvar *seen-hostnames* nil)

(defvar *big-fragment-bytes* (* 1024 1024)
  "Size of a fragment that is considered big and is processed in a
  separate queue.")

(defvar *huge-fragment-bytes* (* 16 1024 1024)
  "Size of a fragment that is considered too big to process.")

(defvar *bank-card-extractors* nil
  "A list of functions that recognises bank card numbers.")

(defvar *announcers*
  '(log-hit)
  "A list of functions that are called with the results of paste analysis.")

(defvar *ignored-paste-sites*
  '()
  "Paste sites to ignore when re-fetching broken pastes.")

(defvar *default-http-user-agent* nil)
