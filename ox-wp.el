;;; ox-wp.el --- Org mode exporter for WordPress. -*- lexical-binding: t; -*-

;; Copyright (C) 2014 Puneeth Chaganti <punchagan@muse-amuse.in>

;; Author: Puneeth Chaganti <punchagan+org2blog@gmail.com>
;; Maintainer: Grant Rettke <grant@wisdomandwonder.com>
;; Version: 1.0.4
;; Keywords: comm, files
;; Homepage: https://github.com/org2blog/org2blog/wiki

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Read about how this exporter works here URL ‘https://orgmode.org/manual/Adding-export-back_002dends.html/’

;;; Code:



;;; Require

(eval-when-compile (require 'cl))
(require 'ox-html)
(require 's)



;;; Group

(defgroup org-export-wp nil
  "WordPress specific export options."
  :tag "Org WordPress"
  :group 'org-export
  :version "26.0"
  :package-version '(Org . "9.2"))



;;; Fun - Public

;;;###autoload
(defun org-wp-export-as-wordpress (&optional async subtreep ext-plist)
  "Export current buffer to a text buffer delegating ASYNC, SUTREEP, and EXT-PLIST.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting buffer should be accessible
through the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When `org-export-show-temporary-export-buffer' is non-nil
display a buffer with the export value."
  (interactive)
  (org-export-to-buffer 'wp "*Org WordPress Export*"
    async subtreep nil t ext-plist (lambda () (html-mode))))

(defun org-wp-export-as-string (&optional async subtreep ext-plist)
  "Get exported buffer text as a string delegating ASYNC, SUBTREEP, and EXT-PLIST.

Delegateswork to `org-wp-export-as-wordpress'."
  (interactive)
  (with-current-buffer (org-wp-export-as-wordpress async subtreep ext-plist)
    (let ((text (buffer-string)))
      (kill-buffer)
      text)))



;;;; Fun - Private



;;; Back-End

(org-export-define-derived-backend 'wp 'html
  :translate-alist '((src-block . org-wp-src-block)
                     (example-block . org-wp-src-block)
                     (latex-environment . org-wp-latex-environment)
                     (latex-fragment . org-wp-latex-fragment))
  :filters-alist '((:filter-paragraph . org-wp-filter-paragraph)))




;;; Filters

;; TODO Retain newlines for shortcode, maybe more
(defun org-wp-filter-paragraph (paragraph _backend info)
  "When INFO, filter newlines from PARAGRAPH."
  (let* ((keep-new-lines (plist-get info :wp-keep-new-lines))
         (result (if keep-new-lines paragraph
                   (format "%s\n\n"
                           (org-trim (replace-regexp-in-string "\s*\n" " "
                                                               paragraph))))))
    result))

(defun org-wp-src-block (src-block contents info)
  "Delegate transcoding of SRC-BLOCK, CONTENTS, and INFO."
  (let ((sc (plist-get info :wp-shortcode)))
    (if sc
        (org-wp-src-block-shortcode src-block contents info)
      (org-wp-src-block-html src-block contents info))))

(defun org-wp-src-block-shortcode (src-block _contents info)
  "Create the SyntaxHighlighter Evolved sourceblock with SRC-BLOCK, CONTENTS, and INFO.

Here is how this function maps an Org mode source block to
a SyntaxHighlighter Evolved (SHE) source block. The list items,
the part before the colon, are the SHE field names. The list
defintions (the part after the ‘:’) refer to the Org mode source
block and its properties:

- ‘language’: If non-nil use ‘language’, otherwise default to \"text\"
- ‘title’: Try to get both the ‘name’ and ‘caption’. Prepare a title
           using both elements, one element, or default to an
           empty string.
- ‘syntaxhl’: When an “#+attr_wp: :syntaxhl ...” document property appears
            directly above a source block, then everything after
            “:syntaxhl” is inserted directly into the shortcode."
  (let* ((langval (org-element-property :language src-block))
         (langs (plist-get info :wp-shortcode-langs-map))
         (lang (or (cdr (assoc langval langs))
                  (when langval (downcase langval))
                  "text"))
         (name (or (org-element-property :name src-block)
                  ""))
         (cap (or (and (org-export-get-caption src-block)
                    (org-trim (org-export-data
                               (org-export-get-caption src-block)
                               info)))
                 ""))
         (title-separator (if (and (s-present? name) (s-present? cap)) ": " ""))
         (title (format "%s%s%s" name title-separator cap))
         (syntaxhl (or (org-export-read-attribute :attr_wp src-block :syntaxhl)
                      ""))
         (srccode (org-export-format-code-default src-block info))
         (result
          (format
           "[sourcecode language=\"%s\" title=\"%s\" %s]\n%s[/sourcecode]"
           lang
           title
           syntaxhl
           srccode)))
    result))

(defun org-wp-src-block-html (src-block _contents info)
  "Create the HTML sourceblock with SRC-BLOCK, CONTENTS, and INFO."
  (catch 'return
    (when (org-export-read-attribute :attr_html src-block :textarea)
      (let (result (org-html--textarea-block src-block))
        (throw 'return result)))
    (let* ((lang (org-element-property :language src-block))
           (code (org-html-format-code src-block info))
           (name (let ((lbl (or (org-element-property :name src-block)
                               (org-export-get-reference src-block info))))
                   (if lbl (format " id=\"%s\"" lbl) ""))))
      (when (not lang)
        (let ((result (format "<pre class=\"example\"%s>\n%s</pre>" name code)))
          (throw 'return result)))
      (let* ((fmtcontent
              (format "<pre class=\"src src-%s\"%s>%s</pre>"
                      lang name code))
             (caption (org-export-get-caption src-block))
             (fmtcaption
              (if (not caption) ""
                (let* ((fmtlisting (format
                                    (org-html--translate "Listing %d:" info)
                                    (org-export-get-ordinal
                                     src-block info nil #'org-html--has-caption-p)))
                       (listing-number
                        (format
                         "<span class=\"listing-number\">%s </span>"
                         fmtlisting))
                       (classlabel
                        (format "<label class=\"org-src-name\">%s%s</label>"
                                listing-number
                                (org-trim (org-export-data caption info)))))
                  classlabel)))
             (result (format "<div class=\"org-src-container\">\n%s%s\n</div>"
                             fmtcaption
                             fmtcontent)))
        result))))

(defun org-wp-latex-environment (latex-environment contents info)
  "Transcode a LATEX-ENVIRONMENT element from Org to WP HTML.
CONTENTS holds the contents of the item.  INFO is a plist holding
contextual information."
  (if (not (plist-get info :wp-latex))
      (org-html-latex-environment latex-environment contents info)
    (let ((latex-env (org-element-property :value latex-environment)))
      (org-wp-latex-to-wp latex-env))))

(defun org-wp-latex-fragment (latex-fragment contents info)
  "Transcode a LATEX-FRAGMENT element from Org to WP HTML.
CONTENTS holds the contents of the item.  INFO is a plist holding
contextual information."
  (if (not (plist-get info :wp-latex))
      (org-html-latex-fragment latex-fragment contents info)
    (let ((latex-frag (org-element-property :value latex-fragment)))
      (org-wp-latex-to-wp latex-frag))))



;; Misc

(defun org-wp-latex-to-wp (text)
  "Convert latex fragments or environments in TEXT to WP LaTeX blocks."
  (let* ((matchers (plist-get org-format-latex-options :matchers))
         (re-list org-latex-regexps)
         re e m)
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (setq e (pop re-list))
        (setq m (car e)
              re (nth 1 e))
        (when (member m matchers)
          (save-match-data
            (when (re-search-forward re nil t)
              (cond
               ((equal m "$")
                (replace-match (concat (match-string 1) "$latex "
                                       (match-string 4) "$"
                                       (match-string 6))
                               nil t))
               ((equal m "$1")
                (replace-match (concat (match-string 1) "$latex "
                                       (substring (match-string 2) 1 -1)
                                       "$" (match-string 3))
                               nil t))
               ((equal m "\\(")
                (replace-match (concat "$latex "
                                       (substring (match-string 0) 2 -2)
                                       "$") nil t))
               ((equal m "\\[")
                (replace-match (concat "<p style=\"text-align:center\"> $latex "
                                       (substring (match-string 0) 2 -2)
                                       "$ </p>") nil t))
               ((equal m "$$")
                (replace-match (concat "<p style=\"text-align:center\"> $latex "
                                       (substring (match-string 0) 2 -2)
                                       "$ </p>") nil t))
               ((equal m )
                (if (equal (match-string 2) "equation")
                    (replace-match (concat "<p style=\"text-align:center\"> $latex "
                                           (substring (match-string 1) 16 -14)
                                           "$ </p>") nil t))))))))
      (replace-regexp-in-string "\s*\n" " " (buffer-string)))))

(provide 'ox-wp)

;;; ox-wp.el ends here
