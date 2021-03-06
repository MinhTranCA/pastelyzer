(in-package #:pastelyzer)

(defgeneric histogram (source))
(defgeneric alphabet (source))

(defmethod histogram ((source string))
  (let ((table (make-hash-table :test 'eql :size 67)))
    (loop for char across source
          do (incf (gethash (char-code char) table 0)))
    table))

(defmethod histogram ((source vector))
  (let ((table (make-hash-table :test 'eql :size 67)))
    (loop for byte across source
          do (incf (gethash byte table 0)))
    table))

(defmethod histogram ((source stream))
  (let ((table (make-hash-table :test 'eql :size 67)))
    (etypecase (stream-element-type source)
      (character
       (loop for char = (read-char source nil nil)
             while char
             do (incf (gethash (char-code char) table 0))))
      ((vector (unsigned-byte 8))
       (loop for byte = (read-byte source nil nil)
             while byte
             do (incf (gethash byte table 0)))))
    table))

(defmethod histogram ((source pathname))
  (with-open-file (in source :direction :input :element-type 'character)
    (histogram in)))

;;; XXX: Would be nice if we could make this into a function that can
;;; be used with FORMAT.
(defun bar (stream width n max &optional (graphics "▏▎▍▌▋▊▉█"))
  "Draw an N/MAX bar no wider than WIDTH using charecters from GRAPHICS."
  (declare (type number width n max)
           (type string graphics))
  (assert (<= 1 (length graphics))
          (graphics)
          "Invalid graphics provided: ~S" graphics)
  (let* ((nchars (length graphics))
         (inc (/ 1 nchars 2)))
    (multiple-value-bind (full part)
        (truncate (* width (/ n max)))
      (loop with char = (char graphics (1- nchars))
            repeat full
            do (write-char char stream))
      (multiple-value-bind (index rem)
          (truncate (* nchars (- part inc)))
        (when (<= 0 rem)
          (write-char (char graphics index) stream)))))
  nil)

(defmethod show-histogram ((table cons)
                           &key (stream *standard-output*)
                                (width (or *print-right-margin* 80))
                                (sort #'<)
                                (key-base 10)
                                (graphics "▏▎▍▌▋▊▉█")
                                ignore-keys)
  ;; Alterantive graphics: "⠆⡇⡷⣿", "⣀⣄⣤⣦⣶⣷⣿".
  (let* ((entries (cond (ignore-keys
                         (remove-if (lambda (item)
                                      (find item ignore-keys))
                                    table
                                    :key #'car))
                        (t
                         (copy-list table))))
         (max-key (reduce #'max entries :key #'car :initial-value 0))
         (max-count (reduce #'max entries :key #'cdr :initial-value 0)))

    (when entries
      (setf entries (sort entries sort :key #'car))

      (fresh-line stream)
      (loop with count-width = (ceiling (log (1+ max-count) 10))
            with key-width = (ceiling (log (1+ max-key) key-base))
            with room = (max 1 (- width key-width 3 count-width 1))
            with fmt = (ecase key-base
                         (2 (formatter "~V,'0B ~:[~* ~;~C~] ~VD "))
                         (8 (formatter "~V,'0O ~:[~* ~;~C~] ~VD "))
                         (10 (formatter "~V,' D ~:[~* ~;~C~] ~VD "))
                         (16 (formatter "~V,'0X ~:[~* ~;~C~] ~VD ")))
            for (key . count) in entries
            for char = (code-char key)
            do (funcall fmt stream
                        key-width key
                        (graphic-char-p char) char
                        count-width count)
               (bar stream room count max-count graphics)
               (terpri stream)))
    entries))

(defmethod show-histogram ((table hash-table)
                           &rest keys
                           &key stream width sort key-base ignore-keys graphics)
  (declare (ignorable stream width sort key-base ignore-keys graphics))
  (apply #'show-histogram
         (alexandria:hash-table-alist table)
         keys))

(defmethod alphabet ((source string))
  (alphabet (histogram source)))

(defmethod alphabet ((source hash-table))
  (let ((result (make-string (hash-table-count source))))
    (loop for key being each hash-key of source
          for i upfrom 0
          do (setf (schar result i) (code-char key)))
    (sort result #'char<)))

(defun sub-alphabet-p (string1 string2 &aux (len1 (length string1))
                                            (len2 (length string2)))
  "Returns T if STRING1 is a sub-alphabet of STRING2.  The strings are
assumed to be sorted."
  (declare (type string string1 string2))
  (let ((i 0)
        (j 0))
    (declare (type array-length i j))
    (loop
      (cond ((= i len1)
             (return t))
            ((= j len2)
             (return nil))
            ((char= (char string1 i)
                    (char string2 j))
             (incf i)))
      (incf j))))

(defun entropy (string &aux (length (length string)))
  (declare (type string string))
  (let ((table (make-hash-table)))
    (loop for char across string
          do (incf (gethash char table 0)))
    (- (loop for freq being each hash-value in table
             for freq/length = (/ freq length)
             sum (* freq/length (log freq/length 2))))))

(defun group (list &key ((:key key-fn) #'identity)
                        ((:test test-fn) #'eql))
  (declare (type (or symbol function) key-fn test-fn))
  (let ((result ()))
    (dolist (item list result)
      (let* ((key (funcall key-fn item))
             (cons (assoc key result :test test-fn)))
        (cond (cons
               (push item (cdr cons)))
              (t
               (setf result (acons key (list item) result))))))))

(defun partition (list fn)
  (loop for item in list
        when (funcall fn item)
          collect item into a
        else
          collect item into b
        finally (return (values a b))))

(defparameter *whitespace-chars*
  (coerce '(#\space #\linefeed #\tab #\return #\page) 'base-string))

(defun whitespace-char-p (char)
  (find char *whitespace-chars*))

(defun trim-space (string side &optional (chars *whitespace-chars*))
  (ecase side
    (:both (string-trim chars string))
    (:left (string-left-trim chars string))
    (:right (string-right-trim chars string))))

(defun visible-char-p (char)
  (and (graphic-char-p char)
       (case char
         ((#\tab #\linefeed #\return #\page)
          nil)
         (otherwise
          t))))

(defun one-line (string &key (start 0)
                             (end nil)
                             (limit 24)
                             (replace-invisible #\.)
                             (continuation "...")
                             (mode :shorten))
  (declare (type string string)
           (type (and fixnum unsigned-byte) start limit)
           (type (or null character) replace-invisible))
  (when (null end)
    (setq end (length string)))
  (flet ((clean (start end)
           (let ((result (subseq string start end)))
             (if replace-invisible
                 (nsubstitute-if-not replace-invisible #'visible-char-p result)
                 result))))
    (if (<= (- end start) limit)
        (clean start end)
        (ecase mode
          (:shorten
           (concatenate 'string
                        (clean start (+ start limit))
                        continuation))
          (:squeeze
           (let ((half (truncate limit 2)))
             (concatenate 'string
                          (clean start (+ start half (if (oddp limit) 1 0)))
                          continuation
                          (clean (- end half) end))))))))

(defun string-context-before (string position &key (after 0)
                                                   (limit 50)
                                                   (bol nil)
                                                   (trim-space t))
  (let ((start (if limit
                   (max after (- position limit))
                   after)))
    (when bol
      (when-let (pos (position #\newline string :start start :end position
                                                :from-end t))
        (setq start (1+ pos))))
    (when trim-space
      (when-let (pos (position-if-not #'whitespace-char-p string
                                      :start start :end position))
        (setq start pos)))
    (subseq string start position)))

(defun string-context-after (string position &key (before nil)
                                                  (limit 50)
                                                  (eol nil)
                                                  (trim-space t))
  (let* ((before (if before before (length string)))
         (end  (if limit
                   (min before (+ position limit))
                   before)))
    (when eol
      (when-let (pos (position #\newline string :start position :end end))
        (setq end pos)))
    (when trim-space
      (when-let (pos (position-if-not #'whitespace-char-p string
                                      :start position :end end
                                      :from-end t))
        (setq end (1+ pos))))
    (subseq string position end)))

(defun dsubseq (array start end)
  (declare (type array-index start end))
  (make-array (- end start)
              :element-type (array-element-type array)
              :displaced-to array
              :displaced-index-offset start))

(defgeneric map-lines (input function &key trim-space ignore-comment-lines))

(defmethod map-lines ((input pathname) function &rest args)
  (with-open-file (stream input :direction :input)
    (apply #'map-lines stream function args)))

(defmethod map-lines ((input string) function &rest args)
  (with-input-from-string (stream input)
    (apply #'map-lines stream function args)))

(defmethod map-lines ((input stream) function
                      &key trim-space ignore-comment-lines)
  (loop for line = (read-line input nil nil)
        while line
        when (and (< 0 (length line))
                  (or (not ignore-comment-lines)
                      (char/= #\# (schar line 0))))
          do (funcall function
                      (if trim-space
                          (trim-space line :both)
                          line))))

(defun starts-with-subseq (prefix sequence &rest keys)
  (let ((mismatch (apply #'mismatch prefix sequence keys)))
    (or (null mismatch)
        (= (length prefix) mismatch))))

(defun ends-with-subseq (suffix sequence &rest keys)
  (let ((mismatch (apply #'mismatch suffix sequence :from-end t keys)))
    (or (null mismatch)
        (zerop mismatch))))
