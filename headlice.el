;;; headlice.el --- Automatically handle license headers -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2024 TEC
;;
;; Author: TEC <contact@tecosaur.net>
;; Maintainer: TEC <contact@tecosaur.net>
;; Created: September 29, 2024
;; Modified: September 29, 2024
;; Version: 0.1.0
;; Keywords: convenience docs files tools
;; Homepage: https://code.tecosaur.net/tec/headlice
;; Package-Requires: ((emacs "28.1"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;  Automatically handle license headers
;;
;;; Code:

(require 'cl-lib)

;;;; Customisation variables:

(defgroup headlice nil
  "Diff in-place."
  :link '(url-link :tag "Homepage" "https://code.tecosaur.net/tec/headlice")
  :link '(emacs-library-link :tag "Library Source" "headlice.el")
  :group 'convenience
  :prefix "headlice-")

(defcustom headlice-license-specs
  (let ((licenses-dir (expand-file-name "licenses" (file-name-directory load-file-name)))
        (headers-dir (expand-file-name "headers" (file-name-directory load-file-name))))
    `((unlicense
       :template ,(file-name-concat licenses-dir "unlicense.txt")
       :spdx "Unlicense")
      (mit
       :template ,(file-name-concat licenses-dir "mit.txt")
       :spdx "MIT")
      (bsd-2
       :template ,(file-name-concat licenses-dir "bsd-2.txt")
       :spdx "BSD-2-Clause")
      (bsd-3
       :template ,(file-name-concat licenses-dir "bsd-3.txt")
       :spdx "BSD-3-Clause")
      (apache-2
       :template ,(file-name-concat licenses-dir "apache-2.txt")
       :header ,(file-name-concat headers-dir "apache-2.txt")
       :spdx "Apache-2.0")
      (eupl-1_2-en
       :template ,(file-name-concat licenses-dir "eupl-1.2_en.txt")
       :spdx "EUPL-1.2")
      (mpl-2
       :template ,(file-name-concat licenses-dir "mpl-2.txt")
       :header ,(file-name-concat headers-dir "mpl-2.txt")
       :spdx "MPL-2.0")
      (lgpl-3
       :template ,(file-name-concat licenses-dir "lgpl-3.txt")
       :spdx "LGPL-2.0-or-later")
      (gpl-2
       :template ,(file-name-concat licenses-dir "gpl-2.txt")
       :spdx "GPL-2-or-later")
      (gpl-3
       :template ,(file-name-concat licenses-dir "gpl-3.txt")
       :header ,(file-name-concat headers-dir "gpl-3.txt")
       :spdx "GPL-3-or-later")
      (agpl-3
       :template ,(file-name-concat licenses-dir "agpl-3.txt")
       :spdx "AGPL-3.0-or-later")))
  "Template files for known licenses."
  :type '(alist :key-type symbol
          :value-type
          (list (const :template) file
                (const :header) (choice (const nil :tag "No header") file)
                (const :spdx) string)))

(defcustom headlice-license-fields-autofills
  (cl-eval-when (load)
    `(("year" . ,(format-time-string "%Y"))
      ("authors" . ,user-full-name)))
  "Fields that can be reliably guessed."
  :type '(alist :key-type string :value-type (choice string function)))

(defcustom headlice-license-filenames
  '("LICENSE" "LICENCE" "LICENSE.txt" "LICENSE.md" "LICENSE.rst"
    "LICENCE" "LICENCE" "LICENCE.txt" "LICENCE.md" "LICENCE.rst"
    "COPYING" "COPYING.txt" "COPYING.org" "COPYING.md" "COPYING.rst"
    "README" "README.txt" "README.org" "README.md" "README.rst")
  "List of possible license filenames to search for in the project root."
  :type '(repeat string))

(defcustom headlice-preferred-filename "LICENSE"
  "The license file name that's preferred when creating new projects."
  :type 'string)

(defcustom headlice-preferred-license nil
  "The license kind that's preferred when creating new projects."
  :type '(choice symbol (const nil)))

(defcustom headlice-use-spdx-headers nil
  "Whether SPDX headers should be used.
This can either be t/nil, or a list of licenses which SPDX should be used for."
  :type '(choice (const t :tag "Always") (const nil :tag "Never")
          (repeat symbol)))

(defcustom headlice-limit-licenses nil
  "When set, headers are only added for these licenses.
See `headlice-license-specs' for a list of known license."
  :type '(repeat symbol))

(defcustom headlice-ignored-licenses nil
  "Unless `headlice-limit-licenses' is set, these licenses are ignored.
See `headlice-license-specs' for a list of known license."
  :type '(repeat symbol))

(defcustom headlice-enabled-modes '(prog-mode)
  "Major modes that the minor mode affects."
  :type '(repeat symbol))

;;;; Internal variables:

(defvar headlice--cache (make-hash-table :test 'equal)
  "Cache of detected licenses. Maps project roots to cached results.")

;;;; Minor mode:

;;;###autoload
(define-minor-mode headlice-mode
  "Automatically add relevant license headers to created files."
  :global t
  :init-value nil
  (if headlice-mode
      (add-hook 'find-file-hook #'headlice-auto-insert)
    (remove-hook 'find-file-hook #'headlice-auto-insert)))

;;;; Functions:

(declare-function project-current "project")
(declare-function project-root "project")
(declare-function projectile-project-root "projectile")

(defun headlice--project-root (&optional dir)
  "Attempt to find the root project of DIR, defaulting to `default-directory'.
Returns nil if no root project could be identified."
  (or (and (featurep 'project)
           (project-current dir)
           (project-root (project-current dir)))
      (and (featurep 'projectile)
           (projectile-project-root))))

(defun headlice--project-license (&optional dir)
  "Attempt to determine the license governing DIR.
If a license could be identified, this result is cached."
  (let* ((dir (or dir default-directory))
         (root (or (headlice--project-root dir) dir)))
    (let (license)
      (while (and (not license)
                  (string-prefix-p root dir))
        (setq license (gethash dir headlice--cache))
        (unless license
          (setq license (headlice--project-license-1 dir))
          (when license (puthash dir license headlice--cache)))
        (unless license
          (setq dir (file-name-directory (directory-file-name dir)))))
      license)))

(defun headlice--project-license-1 (dir)
  "Look for a license directly under DIR."
  (let (license)
    (dolist (filename headlice-license-filenames)
      (when (and (not license)
                 (file-exists-p (file-name-concat dir filename)))
        (dolist (license-spec headlice-license-specs)
          (when-let (((not license))
                     (template (plist-get (cdr license-spec) :template))
                     (license-match
                      (headlice--match-contents
                       template
                       (file-name-concat dir filename))))
            (setq license (cons (car license-spec)
                                (cdr license-match)))
            ))))
    license))

(defun headlice--file-words (filepath &optional interpret-special-p)
  "Return a list of all words in FILEPATH.
The following special forms an interpreted when INTERPRET-SPECIAL-P is non-nil:
  {{placeholder}}
  ??optional content??"
  (with-temp-buffer
    (insert-file-contents filepath)
    (downcase-region (point-min) (point-max))
    (goto-char (point-min))
    (text-mode)
    (let ((pos (point)) words)
      (while (not (eobp))
        (let ((syntax (syntax-class (syntax-after (point)))))
          (cond
           ((and interpret-special-p
                 (eq (char-after) ?{)
                 (re-search-forward "{{\\([^\n]*?\\)}}" nil t))
            (push (cons 'placeholder (match-string 1)) words))
           ((and interpret-special-p
                 (eq (char-after) ??)
                 (re-search-forward "\\?\\?\\([^[^\n]*?\\)\\?\\?" nil t))
            (dolist (word (split-string (match-string 1) "\\Sw" t))
              (push (cons 'optional word) words)))
           ((memq syntax '(1 2))
            (skip-syntax-forward (string (syntax-class-to-char syntax)))
            (push (cons pos (buffer-substring-no-properties pos (point)))
                  words))
           (t
            (skip-syntax-forward (string (syntax-class-to-char syntax)))))
          (setq pos (point))))
      (nreverse words))))

(defun headlice--fill-template (&optional placeholders prompt-prefix)
  "Search for all placeholders in the current buffer, and fill them.
If there is no entry in PLACEHOLDERS, `headlice-license-fields-autofills' will
be used if possible, or the user explicitly prompted (starting with
PROMPT-PREFIX)."
  (let (extra-placeholders)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "{{\\([^\n]*?\\)}}" nil t)
        (let* ((placeholder (match-string 1))
               (replacement
                (or (cdr (assoc placeholder placeholders))
                    (cdr (assoc placeholder extra-placeholders))
                    (when-let ((auto (cdr (assoc placeholder headlice-license-fields-autofills))))
                      (cond
                       ((stringp auto) auto)
                       ((functionp auto)
                        (cdar (push (cons placeholder (save-match-data (funcall auto)))
                                    extra-placeholders)))))
                    (cdar (push (cons placeholder
                                      (read-string (format "%s%s: " (or prompt-prefix "") placeholder)))
                                extra-placeholders)))))
          (replace-match replacement))))))

;;;###autoload
(defun headlice-auto-insert (&optional force)
  "Automatically insert a license header, as appropriate.
With \\[universal-argument] FORCE, ignore suitability.
With \\[universal-argument] \\[universal-argument] FORCE, insert at point."
  (interactive "P")
  (when-let (((or force (headlice--suitable-buffer-p)))
             (license (headlice--project-license))
             ((or force
                  (if headlice-limit-licenses
                      (memq (car license) headlice-limit-licenses)
                    (not (memq (car license) headlice-ignored-licenses)))))
             (spec (alist-get (car license) headlice-license-specs)))
    (save-excursion
      (unless (and (consp force) (> (car force) 4))
        (goto-char (point-min)))
      (cond
       ((and (or (eq headlice-use-spdx-headers t)
                 (and (consp headlice-use-spdx-headers)
                      (memq (car license) headlice-use-spdx-headers)))
             (plist-get spec :spdx))
        (insert (string-trim-right (or comment-start "") " ")
                (and comment-start)
                "SPDX-License-Identifier: "
                (plist-get spec :spdx) "\n"))
       ((plist-get spec :header)
        (let ((header-lines
               (with-temp-buffer
                 (insert-file-contents (plist-get spec :header))
                 (headlice--fill-template (cdr license))
                 (split-string (buffer-string) "\n" t)))
              (comment-prefix
               (string-trim-right (or comment-start "") " ")))
          (dolist (line header-lines)
            (insert comment-prefix (and comment-start " ") line "\n"))))))))

;;;###autoload
(defun headlice-create-license (&optional explicit-choice)
  "Create a license for the current project.
If called while in an empty file of name `headlice-preferred-filename', license
content is inserted into the current buffer. Otherwise, a file with the name
`headlice-preferred-filename' is created in `headlice--project-root'.

When set, a `headlice-preferred-license' license will be used.

With \\[universal-argument] prefix EXPLICIT-CHOICE, ask for the license kind
regardless of `headlice-preferred-license'.
With \\[universal-argument] \\[universal-argument] prefix EXPLICIT-CHOICE, ask
for the target directory regardless of the detected project root."
  (interactive "P")
  (message "EC: %S" explicit-choice)
  (when-let ((license-buf
              (if (and buffer-file-name
                       (not buffer-read-only)
                       (not (memq (aref (buffer-name) 0) '(?* ?\s)))
                       (member (file-name-base buffer-file-name)
                               (mapcar #'file-name-base
                                       headlice-license-filenames))
                       (member (file-name-extension buffer-file-name)
                               '(nil "txt"))
                       (or (and (bobp) (eobp)
                                (not (file-exists-p buffer-file-name))
                                (not (buffer-modified-p))
                                (null (buffer-base-buffer)))
                           (yes-or-no-p "Replace the current content? ")))
                  (current-buffer)
                (let ((filepath
                       (expand-file-name
                        headlice-preferred-filename
                        (or (and (or (not (consp explicit-choice))
                                     (< (car explicit-choice) 16))
                                 (headlice--project-root))
                            (read-directory-name "Project root: ")))))
                  (and (or (not (file-exists-p filepath))
                           (yes-or-no-p (format "Replace existing %s? " filepath)))
                           (find-file-noselect filepath)))))
             (selected-license
              (or (and (not explicit-choice)
                       headlice-preferred-license)
                  (let ((license-entries
                         (mapcar
                          (lambda (s) (cons (plist-get (cdr s) :spdx) (car s)))
                          headlice-license-specs)))
                    (cdr (assoc (completing-read "License: " license-entries nil t)
                                license-entries)))))
             (template-file
              (plist-get (cdr (assoc selected-license headlice-license-specs)) :template)))
    (with-current-buffer license-buf
      (insert-file-contents template-file)
      (headlice--fill-template nil (format "(%s) " selected-license))
      (basic-save-buffer))))

(defun headlice--suitable-buffer-p ()
  "Whether the current buffer is a suitable target for license insertion."
  (and buffer-file-name
       (not buffer-read-only)
       (bobp) (eobp) ; Is empty
       (not (memq (aref (buffer-name) 0) '(?* ?\s))) ; Isn't a "special" buffer
       (not (bound-and-true-p org-capture-current-plist)) ; Isn't an org-capture buffer
       (not (file-exists-p buffer-file-name)) ; Is a new file
       (not (buffer-modified-p)) ; Hasn't been modified
       (null (buffer-base-buffer)) ; Isn't an indirect clone
       (apply #'derived-mode-p headlice-enabled-modes)
       t))

(defun headlice--sequence-run (aseq apos bseq bpos &optional max-run)
  "Find the run of equivalent items in ASEQ and BSEQ, starting from APOS and BPOS.

If MAX-RUN is provided, comparison will stop when this many items are seen.

Items of ASEQ and BSEQ are assumed to be cons cells, and we check that:
- The `car's of each item are of the same type
- The `cdr's of each item are `equal'"
  (let ((run 0)
        (run-stop (min (or max-run most-positive-fixnum)
                       (- (length aseq) apos)
                       (- (length bseq) bpos)))
        (continue t))
    (while (and (< run run-stop)
                continue)
      (let ((aelt (elt aseq (+ apos run)))
            (belt (elt bseq (+ bpos run))))
        (if (and (eq (type-of (car aelt)) (type-of (car belt)))
                 (equal (cdr aelt) (cdr belt)))
            (cl-incf run)
          (setq continue nil))))
    run))

(defun headlice--sequence-first-match (seq needle &optional start)
  "Find the first instance where the subseqence NEEDLE occurs in SEQ, after START."
  (let ((offset (or start 0))
        (max-offset (- (length seq) (length needle)))
        (nlen (length needle))
        result)
    (while (and (not result)
                (<= offset max-offset))
      (if (eq (headlice--sequence-run seq offset needle 0) nlen)
          (setq result offset)
        (cl-incf offset)))
    result))

(defconst headlice--match-placeholder-scan-ahead 5
  "The number of words to scan ahead when matching a placeholder.")

(defun headlice--match-contents-1 (ref-words-vec seen-words-vec &optional seen-start)
  "Attempt to match REF-WORDS-VEC against SEEN-WORDS-VEC starting from SEEN-START.
Returns a cons cell giving the match proportion and placeholders,
or nil if no match."
  (let ((ref-pos 0)
        (ref-len (length ref-words-vec))
        (seen-pos (or seen-start 0))
        (seen-len (length seen-words-vec))
        (ref-skipped 0)
        (placeholder-words 0)
        placeholders)
    (let ((nrun (headlice--sequence-run ref-words-vec ref-pos seen-words-vec seen-pos)))
      (setq ref-pos (+ ref-pos nrun)
            seen-pos (+ seen-pos nrun)))
    (while (and (< seen-pos seen-len)
                (< ref-pos ref-len))
      (let ((this-ref (elt ref-words-vec ref-pos))
            (scan-ahead 0)
            match-cont)
        (cond
         ((eq (car this-ref) 'optional)
          (setq ref-pos (1+ ref-pos)
                ref-skipped (1+ ref-skipped)))
         ((eq (car this-ref) 'placeholder)
          (push (cons (cdr this-ref) (cons (car (elt seen-words-vec seen-pos)) nil))
                placeholders)
          (while (and (< scan-ahead headlice--match-placeholder-scan-ahead)
                      (< (+ ref-pos scan-ahead 1) ref-len)
                      (not (symbolp (car (elt ref-words-vec (+ ref-pos scan-ahead 1))))))
            (cl-incf scan-ahead))
          (setq match-cont
                (if (and (= scan-ahead 0)
                         (symbolp (car (elt ref-words-vec (1+ ref-pos)))))
                    (1+ seen-pos)
                  (headlice--sequence-first-match
                   seen-words-vec
                   (cl-subseq ref-words-vec (1+ ref-pos) (+ ref-pos 1 scan-ahead))
                   seen-pos)))
          (if (not match-cont)
              (setq seen-pos seen-len) ; Early exit
            (cl-incf placeholder-words (- match-cont seen-pos 1))
            (setq ref-pos (1+ ref-pos)
                  seen-pos match-cont)
            (setcdr (cdar placeholders) (1- (car (elt seen-words-vec seen-pos))))))
         (t ; Early exit
          (setq seen-pos seen-len)))
        (unless (= seen-pos seen-len)
          (let ((nrun (headlice--sequence-run ref-words-vec ref-pos seen-words-vec seen-pos)))
            (setq ref-pos (+ ref-pos nrun)
                  seen-pos (+ seen-pos nrun))))))
    (and (= ref-pos ref-len)
         (cons (/ (float (- ref-pos ref-skipped))
                  (- seen-len placeholder-words))
               placeholders))))

(defun headlice--match-contents (ref-file test-file)
  "Match TEST-FILE against REF-FILE.
Returns the match proportion and all identified placeholders, or nil."
  (let ((ref-words-vec (vconcat (headlice--file-words ref-file t)))
        (seen-words-vec (vconcat (headlice--file-words test-file)))
        (seen-start -1)
        result)
    (while (and (not result) seen-start)
      (setq seen-start (headlice--sequence-first-match seen-words-vec (list (elt ref-words-vec 0)) (1+ seen-start))
            result (headlice--match-contents-1 ref-words-vec seen-words-vec seen-start)))
    (and result
         (cons (car result)
               (headlice--extract-placeholder-values test-file (cdr result))))))

(defun headlice--extract-placeholder-values (file placeholder-positions)
  "Extract placeholders from FILE according to PLACEHOLDER-POSITIONS."
  (with-temp-buffer
    (insert-file-contents file)
    (let (placeholders)
      (dolist (name-position placeholder-positions)
        (push (cons (car name-position)
                    (string-trim
                     (buffer-substring (cadr name-position) (cddr name-position))))
              placeholders))
      (nreverse placeholders))))

(defun headlice-clear-cache ()
  "Clear the project license cache."
  (interactive)
  (setq headlice--cache (make-hash-table :test 'equal)))

(provide 'headlice)
;;; headlice.el ends here
