;;; glosbe.el --- Interface to glosbe.com -*- lexical-binding: t; coding: utf-8 -*-

;; Copyright (C)  7 February 2026
;;

;; Author: Sébastien Le Maguer <sebastien.lemaguer@helsinki.fi>

;; Package-Requires: ((emacs "25.2"))
;; Keywords: convenience, translate, wp, dictionary
;; Homepage: https://github.com/seblemaguer/glosbe.el

;; glosbe is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; glosbe is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with glosbe.  If not, see http://www.gnu.org/licenses.

;;; Commentary:
;;
;; An interface betwen emacs and glosbe.com

;;; Code:

(require 'cl-lib)


(require 'url)
(require 'dom)
(require 'xml)
(require 'subr-x)
(require 'json)
(require 'thingatpt)
(require 'magit-section)

(defgroup glosbe nil
  "Glosbe dictionary integration."
  :group 'applications)


(defcustom glosbe-default-from "en"
  "Default source language."
  :type 'string
  :group 'glosbe)

(defcustom glosbe-default-to "fi"
  "Default target language."
  :type 'string
  :group 'glosbe)


(defface glosbe-translation-entry-face
  '((t :inherit outline-1 :weight ultra-bold :height 150))
  "Face for the header of a section in glosbe."
  :group 'glosbe)

(defface glosbe-entry-pos-face
  '((t :inherit outline-1 :weight bold :height 100))
  "Face for the header of a section in glosbe."
  :group 'glosbe)

(defface glosbe-entry-category-header-face
  '((t :inherit outline-2 :weight bold))
  "Face for the name of a project in glosbe."
  :group 'glosbe)

(cl-defstruct glosbe--details)

(defvar glosbe--fragment-cache (make-hash-table :test 'equal))
(defvar glosbe--query-cache (make-hash-table :test 'equal))

(defvar glosbe-buffer-name "*Glosbe*")

;;; Utilities


(defun glosbe--url (word src tgt)
  (format "https://glosbe.com/%s/%s/%s"
          src tgt (url-hexify-string word)))

(defun glosbe--fetch-dom (url)
  (with-current-buffer (url-retrieve-synchronously url t t)
    (goto-char (point-min))
    (re-search-forward "\n\n" nil t)
    (libxml-parse-html-region (point) (point-max))))

;;; Entry point

;;;###autoload
(defun glosbe-translate-word (src tgt word)
  (interactive
   (list
    (read-string (format "From language [%s]: " glosbe-default-from) glosbe-default-from)
    (read-string (format "To language [%s]: " glosbe-default-to) glosbe-default-to)
    (read-string (format "Word [%s]: " (thing-at-point 'word)) (thing-at-point 'word))))

  (let* ((key (list word src tgt)))
    (with-current-buffer (get-buffer-create glosbe-buffer-name)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (glosbe-mode)
        (insert (propertize (format "%s (%s → %s)\n" word src tgt) 'face '(:height 1.4 :weight bold)) "\n"))

      (display-buffer glosbe-buffer-name)

      (if-let ((cached (gethash key glosbe--query-cache)))
          (glosbe--render word cached)
        (let ((dom (glosbe--fetch-dom (glosbe--url word src tgt))))
          (puthash key dom glosbe--query-cache)
          (glosbe--render word dom))))))

;;; Rendering

(defun glosbe--render (word dom)
  (with-current-buffer glosbe-buffer-name
    (let ((inhibit-read-only t))
      (magit-insert-section (root)
        (dolist (li (dom-by-class dom "translation__item"))
          (when (string= (dom-tag li) "li")
            (glosbe--insert-translation li)))))))

(defun glosbe--insert-translation (li)
  (let* ((word-node (car (dom-by-class li "translation__item__pharse")))
         (word (and word-node (string-trim (dom-texts word-node))))
         (pos-nodes (dom-by-class li "inline-block dir-aware-pr-1"))
         (pos (and pos-nodes (mapconcat (lambda (pos-node) (string-trim (dom-texts pos-node))) pos-nodes ", ")))
         (frag (dom-attr li 'data-fragment-url))
         (definition (string-trim (dom-texts (car (dom-by-tag (dom-by-class li "translation__definition") 'span)))))
         (freq (dom-attr li 'data-frequency)))

    (magit-insert-section (translation word)
      (magit-insert-heading
        (propertize word 'face 'glosbe-translation-entry-face)
        " "
        (propertize (format "[%s]" pos) 'face 'glosbe-entry-pos-face))

      (when definition
        (magit-insert-section (definition word)
          (magit-insert-heading (propertize "Definition" 'face 'glosbe-entry-category-header-face))
          (insert "  " definition)
          (insert "\n\n")))

      (when frag
        (glosbe--insert-details-section frag))

      (glosbe--insert-examples li))
    (insert "\n")))

;;; Details

(defun glosbe--fragment-details (frag)
  (let* ((dom (glosbe--fetch-dom (concat "https://glosbe.com" frag))))
    (list
     ;; Possible translation parts
     (propertize "Translation" 'face 'font-lock-keyword-face)
     ;; (string-trim (format "%S" (dom-texts (dom-by-class dom "grammar-tables"))))
     ""

     ;; Grammar part
     (propertize "Grammar" 'face 'font-lock-keyword-face)
     ;; (string-trim (format "%S" (dom-texts (dom-by-class dom "grammar-tables"))))
     )))

(defun glosbe--insert-details-section (frag)
  (magit-insert-section (glosbe--details frag)
    (magit-insert-heading (propertize "Details" 'face 'glosbe-entry-category-header-face))

    (dolist (d (glosbe--fragment-details frag))
      (insert "  " d "\n"))
    (insert "\n")))


;;; Examples

(defun glosbe--insert-examples (li)
  (when-let ((examples (dom-by-class li "translation__example")))
    (magit-insert-section (examples)
      (magit-insert-heading (propertize "Examples" 'face 'glosbe-entry-category-header-face))
      (dolist (ex examples)
        (glosbe--insert-example ex)))))

(defun glosbe--insert-example (ex)
  (let ((ps (dom-by-tag ex 'p)))
    (when (= (length ps) 2)
      (insert "  "
              (propertize (string-trim (dom-texts (nth 0 ps))) 'face 'font-lock-keyword-face)
              "\n  "
              (propertize (string-trim (dom-texts (nth 1 ps))) 'face 'font-lock-string-face)
              "\n"))))

;;; Major mode

(define-derived-mode glosbe-mode magit-section-mode "Glosbe"
  "Major mode for Glosbe dictionary buffers."
  (setq-local font-lock-defaults nil) ;; take into account the change in magit-section introduced in commit 7de0f13
  )

(provide 'glosbe)
;;; glosbe.el ends here
