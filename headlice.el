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
;; Package-Requires: ((emacs "29.1"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;  Automatically handle license headers
;;
;;; Code:

(require 'cl-lib)

(eval-when-compile
  (require 'subr-x))

(defconst headlice--data-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory holding the bundled license and header templates.")

;;;; Customisation variables:

(defgroup headlice nil
  "Automatically handle license headers."
  :link '(url-link :tag "Homepage" "https://code.tecosaur.net/tec/headlice")
  :link '(emacs-library-link :tag "Library Source" "headlice.el")
  :group 'convenience
  :prefix "headlice-")

(defcustom headlice-license-specs
  (let ((licenses-dir (expand-file-name "licenses" headlice--data-directory))
        (headers-dir (expand-file-name "headers" headlice--data-directory)))
    `((unlicense
       :template ,(file-name-concat licenses-dir "unlicense.txt")
       :needle (["free" "and" "unencumbered" "software"] ["unlicense" "org"])
       :spdx "Unlicense")
      (mit
       :template ,(file-name-concat licenses-dir "mit.txt")
       :needle (["mit" "license"] ["permission" "is" "hereby" "granted"])
       :spdx "MIT")
      (bsd-2
       :template ,(file-name-concat licenses-dir "bsd-2.txt")
       :needle ["redistribution" "and" "use" "in" "source"]
       :spdx "BSD-2-Clause")
      (bsd-3
       :template ,(file-name-concat licenses-dir "bsd-3.txt")
       :needle ["redistribution" "and" "use" "in" "source"]
       :spdx "BSD-3-Clause")
      (apache
       :template ,(file-name-concat licenses-dir "apache-2.txt")
       :header ,(file-name-concat headers-dir "apache-2.txt")
       :needle ["apache" "license"]
       :spdx "Apache-2.0")
      (eupl
       :template ,(file-name-concat licenses-dir "eupl-1.2_en.txt")
       :needle ["european" "union" "public" "licence"]
       :spdx "EUPL-1.2")
      (mpl
       :template ,(file-name-concat licenses-dir "mpl-2.txt")
       :header ,(file-name-concat headers-dir "mpl-2.txt")
       :needle ["mozilla" "public" "license"]
       :spdx "MPL-2.0")
      (lgpl-3
       :template ,(file-name-concat licenses-dir "lgpl-3.txt")
       :needle ["gnu" "lesser" "general" "public" "license"]
       :spdx "LGPL-3.0-or-later")
      (gpl-2
       :template ,(file-name-concat licenses-dir "gpl-2.txt")
       :needle ["gnu" "general" "public" "license" "version" "2"]
       :spdx "GPL-2.0-or-later")
      (gpl-3
       :template ,(file-name-concat licenses-dir "gpl-3.txt")
       :header ,(file-name-concat headers-dir "gpl-3.txt")
       :needle ["gnu" "general" "public" "license"]
       :spdx "GPL-3.0-or-later")
      (agpl-3
       :template ,(file-name-concat licenses-dir "agpl-3.txt")
       :needle ["gnu" "affero" "general" "public" "license"]
       :spdx "AGPL-3.0-or-later")
      (cc0
       :template ,(file-name-concat licenses-dir "cc-zero.txt")
       :needle ["cc0" "1" "0"]
       :spdx "CC0-1.0")
      (cc-by
       :template ,(file-name-concat licenses-dir "cc-by-4.txt")
       :needle ["creative" "commons" "attribution" "4" "0" "international"]
       :spdx "CC-BY-4.0")
      (cc-by-sa
       :template ,(file-name-concat licenses-dir "cc-by-sa-4.txt")
       :needle ["creative" "commons" "attribution" "sharealike" "4" "0" "international"]
       :spdx "CC-BY-SA-4.0")))
  "Template files for known licenses.

Each spec should be a cons cell of the form (NAME . SPEC),
where the NAME is a symbol for the license and SPEC is a plist.

The SPEC recognises these properties:
- :template (mandatory), a path to a template license file
- :spdx (mandatory), the SPDX license identifier
- :header (optional), a path to a license header sample
- :needle (optional but recommended), a distinctive sequence of words that
  occurs in the license but rules out most random documents.  This is either
  a vector of words, or a list of such vectors giving alternatives.
  Each word is matched separately and in order, so that intervening
  whitespace and comment prefixes are ignored.  Consequently a needle also
  matches the :header form, when applicable.
  When unset, this defaults to [\"copyright\"]."
  :type '(alist :key-type symbol
          :value-type (plist :options ((:template file)
                                       (:spdx string)
                                       (:header file)
                                       (:needle sexp)))))

(defcustom headlice-header-search-limit 2000
  "Number of bytes searched at the start of a file for a license header."
  :type 'natnum)

(defcustom headlice-license-fields-autofills
  `(("year" . ,(format-time-string "%Y"))
    ("authors" . ,user-full-name))
  "Fields that can be reliably guessed.
Each entry is (FIELD . VALUE), where VALUE is a string or a function of no
arguments returning one.  An \"authors\" value has `headlice-user-email'
appended, unless it already gives an email."
  :type '(alist :key-type string :value-type (choice string function)))

(defcustom headlice-license-filenames
  '("LICENSE" "LICENSE.txt" "LICENSE.md" "LICENSE.rst"
    "LICENCE" "LICENCE.txt" "LICENCE.md" "LICENCE.rst"
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
  :type '(choice (const :tag "Always" t) (const :tag "Never" nil)
          (repeat symbol)))

(defcustom headlice-state-copyright-holder t
  "Whether to (re)state the copyright holder in headers."
  :type 'boolean)

(defcustom headlice-blank-line-after-header t
  "Whether to insert a blank line after a license header."
  :type 'boolean)

(defcustom headlice-user-email nil
  "The default email to use when setting copyright information."
  :type '(choice string (const nil)))

(defcustom headlice-limit-licenses nil
  "When set, headers are only added for these licenses.
See `headlice-license-specs' for a list of known license."
  :type '(repeat symbol))

(defcustom headlice-ignored-licenses '(cc0 cc-by cc-by-sa)
  "Unless `headlice-limit-licenses' is set, these licenses are ignored.
By default, licenses which are appropriate for documentation only are ignored.
See `headlice-license-specs' for a list of known license."
  :type '(repeat symbol))

(defcustom headlice-enabled-modes '(prog-mode)
  "Major modes that the minor mode affects."
  :type '(repeat symbol))

;;;; File search variables:

(defcustom headlice-ignored-directories '(".src" ".svn" ".git" ".hg" ".bzr")
  "Directory names should not be descended into when looking for files."
  :type '(repeat string))

;;;; Internal variables:

(defconst headlice--copyright-regexp
  ;; The ©/(C) sigil is optional (Apache omits it), so the year must lead with a
  ;; digit to keep prose like "copyright holder" from matching.
  "[Cc]opyright:?\\s *\\(?:\\(?:©\\|([Cc])\\)\\s *\\)?\\([0-9][0-9-, ]*\\)\\s *\\([^\n]+\\)")

(defconst headlice--spdx-text-regexp
  "SPDX-FileCopyrightText:\\s *©? *\\([0-9-, ]+\\)\\s *\\([^\n]+\\)")

(defconst headlice--spdx-license-regexp
  "SPDX-License-Identifier: \\([^ \t\n]+\\)")

(defvar headlice--cache (make-hash-table :test 'equal)
  "Cache of detected licenses. Maps project roots to cached results.")

(defconst headlice--comment-variables
  '(uncomment-region-function comment-start comment-add comment-end
    comment-padding comment-continue comment-end-skip comment-multi-line
    comment-start-skip comment-use-syntax comment-quote-nested
    comment-inline-offset)
  "Buffer-local variables that determine how comments are recognised.")

(defvar headlice--mode-comment-syntaxes nil
  "Alist of (MODE SYNTAX-TABLE . BINDINGS) for each major mode probed so far.
BINDINGS is an alist giving MODE's values of `headlice--comment-variables'.")

(defconst headlice--unrecognised-license 'unrecognised
  "Symbol indicating the a license not known in `headlice-license-specs'.")

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

(defun headlice--needle-match-p (needle)
  "Whether NEEDLE occurs in the current buffer.
NEEDLE is a vector of words, or a list of such vectors giving alternatives,
as described in `headlice-license-specs'.  The words of a vector must occur
consecutively, but may be separated by any non-word characters, so that
line wrapping and comment prefixes are ignored."
  (let ((case-fold-search t))
    (save-excursion
      (cl-loop
       for words in (ensure-list (or needle ["copyright"]))
       thereis (progn
                 (goto-char (point-min))
                 (cl-loop
                  while (search-forward (aref words 0) nil t)
                  thereis (save-excursion
                            (cl-loop
                             for i from 1 below (length words)
                             always (progn
                                      (skip-syntax-forward "^w")
                                      (let ((start (point)))
                                        (skip-syntax-forward "w")
                                        (string-equal-ignore-case
                                         (aref words i)
                                         (buffer-substring-no-properties
                                          start (point)))))))))))))

(defun headlice--project-root (&optional dir)
  "Attempt to find the root project of DIR, defaulting to `default-directory'.
Returns nil if no root project could be identified."
  (or (and (featurep 'project)
           (project-current nil dir)
           (project-root (project-current nil dir)))
      (and (featurep 'projectile)
           (projectile-project-root))))

(defun headlice--project-license (&optional dir)
  "Attempt to determine the license governing DIR.
If a license could be identified, this result is cached."
  (let* ((dir (directory-file-name (or dir default-directory)))
         (root (directory-file-name (or (headlice--project-root dir) dir))))
    (let (license)
      (while (and (not license)
                  dir
                  (string-prefix-p root dir))
        (setq license (gethash dir headlice--cache))
        (unless license
          (setq license (headlice--project-license-1 dir))
          (when license (puthash dir license headlice--cache)))
        (unless license
          (let ((parent (directory-file-name (file-name-directory dir))))
            (setq dir (and (not (equal parent dir)) parent)))))
      license)))

(defun headlice--project-license-1 (dir)
  "Look for a license directly under DIR."
  (let (license non-readme-licensefile)
    (dolist (filename headlice-license-filenames)
      (when (and (not license)
                 (file-exists-p (file-name-concat dir filename)))
        (unless (string-equal-ignore-case (file-name-base filename) "README")
          (setq non-readme-licensefile t))
        (with-temp-buffer
          (insert-file-contents (file-name-concat dir filename))
          (dolist (license-spec headlice-license-specs)
            (unless license
              (when-let* ((template (plist-get (cdr license-spec) :template))
                          ((headlice--needle-match-p
                            (plist-get (cdr license-spec) :needle)))
                          (match (headlice--match-contents template (current-buffer))))
                (setq license (cons (car license-spec)
                                    (cdr match)))))))))
    (or license
        (and non-readme-licensefile
             (cons headlice--unrecognised-license nil)))))

(defun headlice--file-license (&optional file mode-cache)
  "Get the license of FILE, defaulting to the current buffer's file.
If MODE-CACHE is provided, it may speed up the guessing of FILE's mode."
  (if file
      (if-let* ((buf (if (equal file buffer-file-name)
                        (current-buffer)
                      (get-file-buffer file))))
          (with-current-buffer buf
            (headlice--file-license))
        (with-temp-buffer
          (insert-file-contents file nil nil headlice-header-search-limit)
          (setq buffer-file-name file)
          (headlice--set-comment-syntax
           (or (and (not (save-excursion (re-search-forward "mode:" nil t)))
                    (headlice--prog-file-kind file mode-cache))
               (headlice--guess-mode)
               'text-mode))
          (prog1 (headlice--file-license)
            (set-buffer-modified-p nil))))
    (let (license)
      (save-excursion
        (goto-char (point-min))
        (dolist (license-spec headlice-license-specs)
          (when-let* (((not license))
                     (header (plist-get (cdr license-spec) :header))
                     ((headlice--needle-match-p
                       (plist-get (cdr license-spec) :needle)))
                     (license-match
                      (headlice--match-contents header (current-buffer))))
            (setq license (cons (car license-spec)
                                (cdr license-match)))))
        (unless license
          (when-let* ((license-spdx
                      (and (re-search-forward headlice--spdx-license-regexp nil t)
                           (match-string-no-properties 1))))
            (dolist (spec headlice-license-specs)
              (unless license
                (when (equal license-spdx (plist-get (cdr spec) :spdx))
                  (setq license (cons (car spec) nil)))))
            (when license
              (goto-char (point-min))
              (when-let* (((re-search-forward headlice--spdx-text-regexp nil t))
                         (year (match-string-no-properties 1))
                         (authors (match-string-no-properties 2))
                         ((progn
                            (beginning-of-line)
                            (and comment-start-skip
                                 (re-search-forward comment-start-skip (match-beginning 0) t)))))
                (setcdr license (list (cons "year" year) (cons "authors" authors))))))))
      license)))

(defun headlice--file-copyright (&optional file)
  "Identify the copyright parameters relevant to FILE."
  (if file
      (if-let* ((buf (get-file-buffer file)))
          (with-current-buffer buf
            (headlice--file-copyright))
        (with-temp-buffer
          (insert-file-contents file nil nil headlice-header-search-limit)
          (setq buffer-file-name file)
          (headlice--set-comment-syntax (or (headlice--guess-mode) 'text-mode))
          (prog1
              (headlice--file-copyright)
            (set-buffer-modified-p nil))))
    (save-excursion
      (goto-char (point-min))
      (when-let* ((match (or
                         (re-search-forward headlice--spdx-text-regexp nil t)
                         (re-search-forward headlice--copyright-regexp nil t)))
                 (year (match-string-no-properties 1))
                 (authors (match-string-no-properties 2))
                 (is-comment
                  (progn
                    (beginning-of-line)
                    (and comment-start-skip
                         (re-search-forward comment-start-skip (match-beginning 0) t)))))
        (list (cons "year" year)
              (cons "authors" authors))))))

(defun headlice--set-comment-syntax (mode)
  "Make the current buffer recognise comments as MODE does, without running it."
  (let ((syntax
         (or (alist-get mode headlice--mode-comment-syntaxes)
             (cdar (push (with-temp-buffer
                           (delay-mode-hooks (funcall mode))
                           (comment-normalize-vars t)
                           (cons mode
                                 (cons (syntax-table)
                                       (mapcar (lambda (var) (cons var (symbol-value var)))
                                               headlice--comment-variables))))
                         headlice--mode-comment-syntaxes)))))
    (set-syntax-table (car syntax))
    (pcase-dolist (`(,var . ,value) (cdr syntax))
      (set (make-local-variable var) value))))

(defun headlice--guess-mode ()
  "Guess the appropriate major mode for the current file.
Largely copied from `set-auto-mode'."
  (let (mode end)
    (save-excursion
      (goto-char (point-min))
      (skip-chars-forward " \t\n")
      (and enable-local-variables
           (not (inhibit-local-variables-p))
           (setq end (set-auto-mode-1))
           (if (save-excursion (search-forward ":" end t))
               ;; Find all specifications for the `mode:' variable
               ;; and execute them left to right.
               (while (let ((case-fold-search t))
                        (or (and (looking-at "mode:")
                                 (goto-char (match-end 0)))
                            (re-search-forward "[ \t;]mode:" end t)))
                 (skip-chars-forward " \t")
                 (let ((beg (point)))
                   (if (search-forward ";" end t)
                       (forward-char -1)
                     (goto-char end))
                   (skip-chars-backward " \t")
                   (push (intern-soft (concat (downcase (buffer-substring beg (point))) "-mode"))
                         mode)))
             ;; Simple -*-MODE-*- case.
             (push (intern-soft (concat (downcase (buffer-substring (point) end))
                                        "-mode"))
                   mode)))
      (setq mode (car (cl-remove-if-not #'functionp mode)))
      (unless mode
        (let ((name (file-name-sans-versions buffer-file-name))
              (remote-id (file-remote-p buffer-file-name)))
          (when (and (stringp remote-id)
                     (string-match (regexp-quote remote-id) name))
            (setq name (substring name (match-end 0))))
          (while name
            ;; Find first matching alist entry.
            (setq mode (assoc-default name auto-mode-alist 'string-match))
            (if (and mode
                     (not (functionp mode))
                     (consp mode)
                     (cadr mode))
                (setq mode (car mode)
                      name (substring name 0 (match-beginning 0)))
              (setq name nil)))))
      mode)))

(defun headlice--file-authors (&optional file)
  "Attempt to identify the relevant authors of FILE."
  (cdr (or (assoc "authors" (headlice--file-copyright file))
           (assoc "authors" (headlice--file-license file)))))

(defvar headlice--files-to-sample 10)

(defun headlice--sample-dir-files (fn dir)
  "Apply FN to a sample of the code files under DIR.
Returns all unique return values of FN."
  (let* ((code-files (headlice--find-code-files dir))
         (nfiles (length code-files))
         results)
    (if (< nfiles 100)
        (let ((seq (vconcat (number-sequence 0 (1- nfiles)))))
          (let ((n (length seq)))
            (dotimes (i n)
              (cl-rotatef (elt seq i) (elt seq (+ i (random (- n i)))))))
          (cl-loop
           for i in (append seq nil)
           while (< (length results) headlice--files-to-sample)
           for result = (funcall fn (car (elt code-files i)))
           when result
           do (push result results))
          results)
      (dotimes (_ headlice--files-to-sample)
        (when-let* ((result (funcall fn (car (elt code-files (random nfiles))))))
          (push result results))))
    (setq results (delete-dups results))
    results))

(defun headlice--project-authors (&optional dir)
  "List the authors known to be responsible for the project under DIR."
  (or (cdr (assoc "authors" (cdr (headlice--project-license dir))))
      (let ((authors (headlice--sample-dir-files #'headlice--file-authors (or dir default-directory))))
        (and (= (length (delete-dups authors)) 1)
             (car authors)))))

(defun headlice--call-as-plain-text (source fn)
  "Call FN in an uncommented copy of SOURCE, a buffer or file path.
The copy uses `text-mode-syntax-table', with point at its start.
Returns FN's value."
  (with-temp-buffer
    (if (stringp source)
        (insert-file-contents source)
      (insert-buffer-substring source)
      (dolist (var headlice--comment-variables)
        (set (make-local-variable var) (buffer-local-value var source)))
      (when comment-start
        (with-syntax-table (with-current-buffer source (syntax-table))
          (uncomment-region (point-min) (point-max)))))
    (set-syntax-table text-mode-syntax-table)
    (goto-char (point-min))
    (funcall fn)))

(defun headlice--get-words (&optional interpret-special-p)
  "Return a list of all words in the current buffer after point.
Each word is a cons cell (POSITION . WORD), with WORD downcased.  The buffer
should use `text-mode-syntax-table'.

When INTERPRET-SPECIAL-P is non-nil, these special forms are recognised:
  {{name}}      giving (placeholder . NAME)
  ??content??   giving (optional . WORD) for each word of CONTENT"
  (let ((pos (point))
        words)
    (save-excursion
      (while (not (eobp))
        (let ((syntax (syntax-class (syntax-after (point)))))
          (cond
           ;; Anchored, so a stray "{" or "?" is read as ordinary text
           ;; instead of consuming everything up to a distant special form.
           ((and interpret-special-p (looking-at "{{\\([^\n]*?\\)}}"))
            (push (cons 'placeholder (match-string 1)) words)
            (goto-char (match-end 0)))
           ((and interpret-special-p (looking-at "\\?\\?\\([^?\n]*?\\)\\?\\?"))
            ;; Move first: `split-string' clobbers the match data.
            (let ((contents (match-string 1)))
              (goto-char (match-end 0))
              (dolist (word (split-string (downcase contents) "\\Sw" t))
                (push (cons 'optional word) words))))
           ((memq syntax '(1 2))
            (skip-syntax-forward (string (syntax-class-to-char syntax)))
            (push (cons pos (downcase (buffer-substring-no-properties pos (point))))
                  words))
           (t
            (skip-syntax-forward (string (syntax-class-to-char syntax)))))
          (setq pos (point)))))
    (nreverse words)))

(defun headlice--autofill-values ()
  "Return `headlice-license-fields-autofills' with all values as strings."
  (mapcar
   (pcase-lambda (`(,field . ,value))
     (let ((value (if (functionp value) (funcall value) value)))
       (cons field
             (if (and (equal field "authors")
                      headlice-user-email
                      (not (string-search "<" value)))
                 (format "%s <%s>" value headlice-user-email)
               value))))
   headlice-license-fields-autofills))

(defun headlice--fill-template (&optional placeholders prompt-prefix)
  "Search for all placeholders in the current buffer, and fill them.
Each placeholder takes its value from the PLACEHOLDERS alist, else
`headlice-license-fields-autofills', else the user is prompted (starting
with PROMPT-PREFIX).

Optional \"??text??\" segments are retained, with their markers removed.

Returns the value of every placeholder filled, as an alist."
  (let ((autofills (headlice--autofill-values))
        filled-placeholders)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "\\?\\?\\([^?\n]*\\)\\?\\?" nil t)
        (replace-match (match-string 1) t t))
      (goto-char (point-min))
      (while (re-search-forward "{{\\([^\n]*?\\)}}" nil t)
        (let* ((placeholder (match-string 1))
               (replacement
                (or (cdr (assoc placeholder filled-placeholders))
                    (cdar (push (cons placeholder
                                      (or (cdr (assoc placeholder placeholders))
                                          (cdr (assoc placeholder autofills))
                                          (save-match-data
                                            (read-string (format "%s%s: " (or prompt-prefix "") placeholder)))))
                                filled-placeholders)))))
          (replace-match replacement t t))))
    filled-placeholders))

;;;###autoload
(defun headlice-auto-insert (&optional license force)
  "Automatically insert a header for LICENSE, as appropriate.
When unset, LICENSE is guessed or interactively asked for.

With FORCE, insert regardless of whether the buffer seems suitable.
With \\[universal-argument] FORCE, ask for the license type if ambiguous.
With \\[universal-argument] \\[universal-argument] FORCE, insert at point."
  (interactive (list nil (or current-prefix-arg (list 1))))
  (when-let* (((or force (headlice--suitable-buffer-p)))
             (license (or license
                          (headlice--project-license)
                          (and (consp force)
                               (cons (or (and (> (car force) 1)
                                              headlice-preferred-license)
                                         (headlice--pick-license))
                                     (headlice--autofill-values)))))
             ((or force
                  (if headlice-limit-licenses
                      (memq (car license) headlice-limit-licenses)
                    (not (memq (car license) headlice-ignored-licenses)))))
             (spec (alist-get (car license) headlice-license-specs)))
    (unless (and (consp force) (> (car force) 4))
      (goto-char (point-min)))
    (cond
     ((and (or (eq headlice-use-spdx-headers t)
               (and (consp headlice-use-spdx-headers)
                    (memq (car license) headlice-use-spdx-headers)))
           (plist-get spec :spdx))
      (let ((insert-start (point)))
        (when headlice-state-copyright-holder
          (insert "SPDX-FileCopyrightText: © "
                  (headlice--get-year license)
                  " "
                  (headlice--get-authors license default-directory)
                  "\n"))
        (insert "SPDX-License-Identifier: " (plist-get spec :spdx) "\n")
        (comment-region insert-start (point))
        (when headlice-blank-line-after-header
          (insert "\n"))))
     ((plist-get spec :header)
      (let ((insert-start (point))
            (target-buffer (current-buffer))
            (comment-empty-lines t))
        (with-temp-buffer
          (insert-file-contents (plist-get spec :header))
          (headlice--fill-template (cdr license))
          (goto-char (point-min))
          (when (and headlice-state-copyright-holder
                     (not (re-search-forward headlice--copyright-regexp nil t)))
            (insert "Copyright © "
                    (headlice--get-year license)
                    " "
                    (headlice--get-authors license default-directory)
                    "\n"))
          (insert-into-buffer target-buffer))
        (comment-region insert-start (point))
        (when headlice-blank-line-after-header
          (insert "\n")))))))

(defun headlice--buffer-insert-if-absent ()
  "Call `headlice-auto-insert' if the current buffer has no file license.
Returns t when `headlice-auto-insert' has been run, nil otherwise."
  (when-let* (((headlice--suitable-buffer-p t))
             (license (headlice--project-license))
             ((not (headlice--file-license))))
    (headlice-auto-insert license 1)
    t))

(defun headlice--file-insert-if-absent (file &optional mode-cache)
  "Call `headlice-auto-insert' within FILE if it has no license header.
Returns t when `headlice-auto-insert' has been run, nil otherwise.
MODE-CACHE may be provided to speed up this operation when run repeatedly on
similar files."
  (when-let* (((not (headlice--file-license file mode-cache)))
             (license (headlice--project-license (file-name-directory file))))
    (with-temp-buffer
      (insert-file-contents file)
      (rename-buffer (file-name-nondirectory file))
      (setq buffer-file-name file)
      (let ((delay-mode-hooks t))
        (normal-mode))
      (comment-normalize-vars)
      (headlice-auto-insert license 1)
      (save-buffer))
    t))

;;;###autoload
(defun headlice-infest (&optional dir create-license-p)
  "Add license headers to all files in the current project (under DIR).
When the CREATE-LICENSE-P argument is set, a license file will be created before
adding headers if the project is currently unlicensed.

When called interactively, DIR is the current working directory and
CREATE-LICENSE-P is set."
  (interactive (list nil t))
  (let* ((root (or dir (headlice--project-root)))
         (license (headlice--project-license root))
         (mode-cache (list nil)))
    (when (and (not license) create-license-p)
      (headlice-create-licensefile root)
      (setq license (headlice--project-license root)))
    (if license
        (let* ((files (mapcar #'car (headlice--find-code-files root mode-cache)))
               (nfiles (length files))
               (nchecked 0)
               (ninserted 0))
          (dolist (file files)
            (message "Checking %s... [%s/%s]" file (cl-incf nchecked) nfiles)
            (if-let* ((buf (get-file-buffer file)))
                (with-current-buffer buf
                  (when (headlice--buffer-insert-if-absent)
                    (save-buffer)
                    (cl-incf ninserted)))
              (when (headlice--file-insert-if-absent file)
                (cl-incf ninserted))))
          (message "Checked %s files, inserted %s headers" (length files) ninserted))
      (message "Cannot infest %s, as it is not under any known license" root))))

;;;###autoload
(defun headlice-status (&optional dir)
  "Report on the licensing status of the files in DIR (the current project).

With \\[universal-argument] prefix, ask for the directory to report on."
  (interactive
   (list (when current-prefix-arg
           (read-directory-name "Report on directory: "))))
  (let* ((status (headlice-project-status dir))
         (files (plist-get status :files))
         (authors (plist-get status :authors))
         (num-files (plist-get status :total-files))
         (num-unlicensed (plist-get status :unlicensed))
         (license-names
          (mapconcat
           (lambda (license)
             (if (eq (car license) headlice--unrecognised-license)
                 (propertize "Unrecognised" 'face 'warning)
               (propertize (upcase (symbol-name (car license)))
                           'face 'font-lock-keyword-face)))
           files
           "/"))
         (author-info
          (cond
           ((null authors)
            (propertize "unknown" 'face 'shadow))
           ((<= 1 (length authors) 4)
            (let* ((rev-authors (reverse authors))
                   (last-author (car rev-authors))
                   (most-authors (nreverse (cdr rev-authors)))
                   (n-authors (length authors))
                   (max-len (/ 36 n-authors)))
              (concat
               (mapconcat
                (lambda (author)
                  (propertize (truncate-string-to-width author max-len nil nil t)
                              'face 'font-lock-string-face))
                most-authors
                ", ")
               (pcase n-authors
                 (1 nil)
                 (2 " and ")
                 (_ ", and "))
               (propertize (truncate-string-to-width last-author max-len nil nil t)
                           'face 'font-lock-string-face))))
           (t ; >4 authors
            (propertize (format "%s and %s other authors"
                                (car authors)
                                (1- (length authors)))
                        'face 'font-lock-string-face))))
         (unlicensed-info
          (if (> num-unlicensed 0)
              (propertize (format " (%s unlicensed)" num-unlicensed) 'face 'error)
            "")))
    (if files
        (message "%s is a %s licensed project by %s encompassing %s file%s%s"
                 (propertize (file-name-nondirectory (directory-file-name (or dir default-directory)))
                             'face 'font-lock-constant-face)
                 license-names
                 author-info
                 (propertize (number-to-string num-files) 'face 'font-lock-number-face)
                 (if (= num-files 1) "" "s")
                 unlicensed-info)
      (message "Unlicensed project"))))

(defun headlice-project-status (&optional dir)
  "Collect information on the license of files under DIR."
  (let* ((root (file-truename (or dir default-directory)))
         project-license
         (authors-table (make-hash-table :test #'equal))
         (unlicensed-count 0)
         (file-count 0)
         file-licenses
         last-dir-license
         (mode-cache (list nil))
         (scan-update 0.0)
         code-files)
    (with-temp-message (format "Scanning %s…" (directory-file-name root))
      (redisplay)
      (setq project-license (headlice--project-license root)
            code-files (headlice--find-code-files dir mode-cache))
      (dolist (code-file code-files)
        (cl-incf file-count)
        (when (> (- (float-time) scan-update) 0.2)
          (message "[%s/%s] Scanning %s…" file-count (length code-files) (car code-file))
          (redisplay)
          (setq scan-update (float-time)))
        (let* ((parent-dir (file-name-directory (car code-file)))
               (parent-license
                (if (equal (car last-dir-license) parent-dir)
                    (cdr last-dir-license)
                  (cdr
                   (setq last-dir-license
                         (cons parent-dir (headlice--project-license parent-dir))))))
               (license
                (or (headlice--file-license (car code-file) mode-cache)
                    parent-license))
               (kind (car license))
               (authors (cdr (assoc "authors" (cdr license)))))
          (if kind
              (if-let* ((count (assoc kind file-licenses)))
                  (cl-incf (cdr count))
                (push (cons kind 1) file-licenses))
            (cl-incf unlicensed-count))
          (when authors
            (dolist (author (split-string authors "[ \t]*,[ \t]*\\|[ \t]+and[ \t]+"))
              (puthash author t authors-table))))))
    (list :project (car project-license)
          :files (cl-sort file-licenses #'> :key #'cdr)
          :authors (sort (hash-table-keys authors-table) #'string<)
          :unlicensed unlicensed-count
          :total-files file-count)))

(defun headlice--get-year (license)
  "Get or set the year in LICENSE."
  (cdr (or (assoc "year" (cdr license))
           (car (push
                 (cons "year"
                       (format-time-string "%Y"))
                 (cdr license))))))

(defun headlice--get-authors (license &optional dir)
  "Get or set the authors in LICENSE.
When LICENSE gives none, they are guessed from the files of the project under
DIR, or else asked for, starting from `headlice-license-fields-autofills'."
  (or (cdr (assoc "authors" (cdr license)))
      (let ((authors
             (or
              (and dir (or (headlice--project-authors dir)
                           (let ((root (headlice--project-root dir)))
                             (and (not (equal root dir))
                                  (headlice--project-authors root)))))
              (read-string "Copyright holder: "
                           (cdr (assoc "authors" (headlice--autofill-values)))))))
        (cdar (push (cons "authors" authors) (cdr license))))))

;;;###autoload
(defun headlice-create-licensefile (&optional dir license-kind)
  "Create a license for the current project.
If called while in an empty file of name `headlice-preferred-filename', license
content is inserted into the current buffer. Otherwise, a file with the name
`headlice-preferred-filename' is created in `headlice--project-root'.

When set, a `headlice-preferred-license' license will be used.

With \\[universal-argument] prefix, ask for the license kind
regardless of `headlice-preferred-license'.
With \\[universal-argument] \\[universal-argument] prefix, ask
for the target directory as well regardless of the detected project root.

When called non-interactively, DIR and LICENSE-KIND may be used to set where the
license is created, and what kind of license is used."
  (interactive
   (list (or (and (or (not (consp current-prefix-arg))
                      (< (car current-prefix-arg) 16))
                  (headlice--project-root))
             (read-directory-name "Project root: "))
         (if current-prefix-arg
             (headlice--pick-license)
           headlice-preferred-license)))
  (let* ((license-buf
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
            (let ((filepath (expand-file-name headlice-preferred-filename dir)))
              (and (or (not (file-exists-p filepath))
                       (yes-or-no-p (format "Replace existing %s? " filepath)))
                   (find-file-noselect filepath)))))
         (selected-license
          (or license-kind headlice-preferred-license (headlice--pick-license)))
         (template-file
          (plist-get (cdr (assoc selected-license headlice-license-specs)) :template)))
    (if template-file
        (with-current-buffer license-buf
          (erase-buffer)
          (insert-file-contents template-file)
          (let ((filled-specs (headlice--fill-template nil (format "(%s) " selected-license))))
            (basic-save-buffer)
            (let ((license-dir (file-name-directory buffer-file-name)))
              (maphash
               (lambda (file _)
                 (when (string-prefix-p license-dir file)
                   (remhash file headlice--cache)))
               headlice--cache)
              ;; Keyed as `headlice--project-license' looks it up, sans slash.
              (puthash (directory-file-name license-dir)
                       (cons selected-license filled-specs)
                       headlice--cache)))
          (message "Created license file %s" (propertize (buffer-file-name) 'face 'font-lock-builtin-face)))
      (unless (eq (current-buffer) license-buf)
        (kill-buffer license-buf))
      (user-error "Could not create license, no template for `%s' could be located" selected-license))))

(defun headlice--pick-license ()
  "Select a license name from `headlice-license-specs'."
  (let ((license-entries
         (mapcar
          (lambda (s) (cons (plist-get (cdr s) :spdx) (car s)))
          headlice-license-specs)))
    (cdr (assoc (completing-read "License: " license-entries nil t)
                license-entries))))

(defun headlice--find-code-files (&optional dir mode-cache)
  "List all files under DIR that seem licensable.
MODE-CACHE may be provided to speed up or record file mode identification."
  (let ((root (file-truename (expand-file-name (or dir default-directory))))
        (ignored-dirnames (append headlice-ignored-directories '("." "..")))
        path-queue
        (paths-seen (make-hash-table :test #'equal))
        (prog-cache (or mode-cache (list nil)))
        files kind)
    (push (cons (file-name-as-directory root) 'directory) path-queue)
    (while path-queue
      (let* ((file (pop path-queue))
             (path (car file)))
        (unless (gethash path paths-seen)
          (cond
           ((or (not (cdr file)) ; Skip
                (not (file-readable-p path))))
           ((file-symlink-p path) ; Follow all symlinks exactly once
            (let ((realpath (file-truename path)))
              (when (and (not (gethash realpath paths-seen))
                         (string-prefix-p root realpath))
                (push (cons realpath (cdr file)) path-queue))))
           ((directory-name-p path) ; Find code files under directory
            (dolist (subpath (directory-files path t))
              (cond
               ((file-directory-p subpath)
                (unless (member (file-name-nondirectory subpath) ignored-dirnames)
                  (push (cons (file-name-as-directory subpath) 'directory) path-queue)))
               ((setq kind (headlice--prog-file-kind subpath prog-cache))
                (push (cons subpath kind) path-queue)))))
           ((file-regular-p path)
            (push file files)))
          (puthash path t paths-seen))))
    files))

(defun headlice--prog-file-kind (file &optional cache)
  "Return the `prog-mode' derived mode for FILE according to `auto-mode-alist'.
Should FILE not match any `prog-mode'-derived entry, return nil.

If querying many files in the same project, this can often be sped up
by providing a CACHE list, which should be initialised as list of nil."
  (or (and (car cache)
           (string-match-p (caar cache) file)
           (cdar cache))
      (and (cadr cache)
           (let ((cache-slice (cdr cache))
                 matched-entry)
             (while cache-slice
               (if (and (car cache-slice)
                        (string-match-p (caar cache-slice) file))
                   (setq matched-entry (car cache-slice)
                         cache-slice nil)
                 (setq cache-slice (cdr cache-slice))))
             (when matched-entry
               (setcdr cache (cons (car cache) (delq matched-entry (cdr cache))))
               (setcar cache matched-entry)
               (cdr matched-entry))))
      (let ((mode-list auto-mode-alist))
        (while (consp mode-list)
          (when (headlice--file-is-prog-mode-p file (cdar mode-list) (caar mode-list))
            (when cache
              (let ((cache-copy (cons (car cache) (cdr cache))))
                (setcar cache (car mode-list))
                (setcdr cache cache-copy)))
            (setq mode-list (car mode-list)))
          (setq mode-list (cdr mode-list)))
        mode-list)))

(defun headlice--file-is-prog-mode-p (file mode regexp)
  "Return MODE if FILE matches REGEXP and MODE is a decedent of `prog-mode'.
A riff on `provided-mode-derived-p'."
  (when (symbolp mode)
    (when (and (autoloadp (symbol-function mode))
               (string-match-p regexp file))
      (autoload-do-load (symbol-function mode)))
    (while (and mode (not (eq mode 'prog-mode)))
      (setq mode (get mode 'derived-mode-parent))))
  (and (eq mode 'prog-mode) (string-match-p regexp file) t))

;;; Fuzzy license matching

(defun headlice--suitable-buffer-p (&optional allow-existing)
  "Whether the current buffer is a suitable target for license insertion.
When ALLOW-EXISTING is set, this will also match a buffer that represents an
existing file."
  (and buffer-file-name
       (not buffer-read-only)
       (or allow-existing
           (and (bobp) (eobp)))
       (not (memq (aref (buffer-name) 0) '(?* ?\s))) ; Isn't a "special" buffer
       (not (bound-and-true-p org-capture-current-plist)) ; Isn't an org-capture buffer
       (or allow-existing
           (and (not (file-exists-p buffer-file-name)) ; Is a new file
                (not (buffer-modified-p)) ; Hasn't been modified
                (null (buffer-base-buffer)))) ; Isn't an indirect clone
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
          (if (equal (cdr this-ref) (cdr (elt seen-words-vec seen-pos)))
              (cl-incf seen-pos)
            (cl-incf ref-skipped))
          (cl-incf ref-pos))
         ((eq (car this-ref) 'placeholder)
          (push (cons (cdr this-ref) (cons (car (elt seen-words-vec seen-pos)) nil))
                placeholders)
          (while (and (< scan-ahead headlice--match-placeholder-scan-ahead)
                      (< (+ ref-pos scan-ahead 1) ref-len)
                      (not (symbolp (car (elt ref-words-vec (+ ref-pos scan-ahead 1))))))
            (cl-incf scan-ahead))
          (setq match-cont
                (if (and (= scan-ahead 0)
                         (or (= (1+ ref-pos) ref-len)
                             (symbolp (car (elt ref-words-vec (1+ ref-pos))))))
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
            (let* ((last (and (> seen-pos 0) (elt seen-words-vec (1- seen-pos))))
                   (word-end (if last (+ (car last) (length (cdr last))) 0)))
              (setcdr (cdar placeholders)
                      (if (< seen-pos seen-len)
                          (max word-end (1- (car (elt seen-words-vec seen-pos))))
                        word-end)))))
         (t ; Early exit
          (setq seen-pos seen-len)))
        (unless (= seen-pos seen-len)
          (let ((nrun (headlice--sequence-run ref-words-vec ref-pos seen-words-vec seen-pos)))
            (setq ref-pos (+ ref-pos nrun)
                  seen-pos (+ seen-pos nrun))))))
    (and (= ref-pos ref-len)
         (> (- seen-len placeholder-words) 0)
         (cons (/ (float (- ref-pos ref-skipped))
                  (- seen-len placeholder-words))
               placeholders))))

(defun headlice--match-contents (reference test)
  "Match TEST against REFERENCE.
REFERENCE and TEST are each a buffer or a file path, and comments in TEST are
disregarded.  Returns (PROPORTION . PLACEHOLDERS), where PLACEHOLDERS is an
alist of each placeholder in REFERENCE to its text in TEST, or nil when TEST
does not contain REFERENCE."
  (let ((ref-words-vec
         (vconcat (headlice--call-as-plain-text
                   reference (lambda () (headlice--get-words t))))))
    (headlice--call-as-plain-text
     test
     (lambda ()
       (let ((seen-words-vec (vconcat (headlice--get-words)))
             (seen-start -1)
             result)
         (while (and (not result) seen-start (> (length ref-words-vec) 0))
           (setq seen-start (headlice--sequence-first-match seen-words-vec (list (elt ref-words-vec 0)) (1+ seen-start))
                 result (headlice--match-contents-1 ref-words-vec seen-words-vec seen-start)))
         (and result
              (cons (car result)
                    (headlice--extract-placeholder-values (cdr result)))))))))

(defun headlice--extract-placeholder-values (placeholder-positions)
  "Extract placeholders at PLACEHOLDER-POSITIONS in the current buffer.
PLACEHOLDER-POSITIONS is a list of (NAME START . END).
Returns an alist of (NAME . VALUE)."
  (let (placeholders)
    (pcase-dolist (`(,name ,start . ,end) placeholder-positions)
      (push (cons name (string-trim (buffer-substring-no-properties start end)))
            placeholders))
    (nreverse placeholders)))

(defun headlice-clear-cache ()
  "Clear the project license cache."
  (interactive)
  (setq headlice--cache (make-hash-table :test 'equal)))

(provide 'headlice)
;;; headlice.el ends here
