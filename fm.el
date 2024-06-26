;;; fm.el --- follow mode for compilation/output buffers

;; Copyright (C) 1997 Stephen Eglen

;; Author: Stephen Eglen <stephen@anc.ed.ac.uk>
;; Maintainer: Stephen Eglen <stephen@anc.ed.ac.uk>, Joe Bloggs <vapniks@yahoo.com>
;; Created: 03 Jul 1997
;; Version: 20130612.1
;; Keywords: outlines
;; location: https://github.com/vapniks/fm
 
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; As you move through the lines of an output buffer (such as from
;; `grep' or `occur'), another window highlights the corresponding
;; line of the source buffer.

;; This is inspired by the table of contents code from reftex.el.
;; http://www.strw.leidenuniv.nl/~dominik/Tools/

;; To use the mode, do M-x fm-start in the output buffer.  Or just add
;; it to the mode hooks, e.g.:
;; (add-hook 'occur-mode-hook 'fm-start)
;; (add-hook 'compilation-mode-hook 'fm-start)
;; 

;;; Examples:
;;  
;; Do an occur for the word `package' in the NEWS file:
;; C-h n
;; M-x occur RTN package RTN

;; or test it on the current file:
;; (grep "grep -n 'def' fm.el")
;; (occur "def")

;; Once following is activated in a buffer, it can be toggled with the
;; "C-c C-f" key in that buffer. The key can be changed with the `fm-key' option.

;; To extend this code to handle other types of output buffer, you
;; need to add an entry to the alist `fm-modes', e.g:
;; (add-to-list 'fm-modes '(my-mode my-mode-goto-item))
;; where my-mode-goto-item is a function that opens the source buffer
;; at the place appropriate for the current item.
;; You can set the number of lines to display in the items buffer when
;; in fm-mode by setting the buffer local variable `fm-window-lines'. 


;; If you want to use fm in a buffer that doesn't have a useful major
;; mode, you can always set the value of fm-defun yourself.  For
;; example, the cscope buffer is in fundamental mode, so in this case
;; we set fm-defun as a local variable to be the defun to use for
;; visiting the corresponding line of the source buffer.

(add-hook 'cscope-query-hook 'cscope-run-fm)

(defun cscope-run-fm ()
  "Run cscope in the fm buffer."
  (set (make-local-variable 'fm-defun) '(cscope-interpret-output-line))
  ;; You can set the number of lines to show to 10 by uncommenting the following line.  
  ;;  (setq fm-window-lines 10)
  (fm-start))

;; If you are using this in the compile mode, you may find it easier
;; to use the key M-p to go to the previous error.  Otherwise, you may
;; find that if you go up one line, and this line doesn't have an
;; error on it, it goes down one line again, taking you back where you
;; started!

;;; Installation:
;;
;; Put fm.el in a directory in your load-path, e.g. ~/.emacs.d/
;; You can add a directory to your load-path with the following line in ~/.emacs
;; (add-to-list 'load-path (expand-file-name "~/elisp"))
;; where ~/elisp is the directory you want to add 
;; (you don't need to do this for ~/.emacs.d - it's added by default).
;;
;; Add the following to your ~/.emacs startup file.
;;
;; (require 'fm)


;;; TODO
;; ??

;;; Code:

;; fm-highlight is currently used to highlight the regions of both
;; the source(0) and output(1) buffers.

(defgroup fm nil
  "Customization for `fm'.")

(defcustom fm-modes
  '((compilation-mode . compile-goto-error)
    (occur-mode . occur-mode-goto-occurrence)
    (outlines-mode . outlines-goto-line) ;; sje hack
    (grep-mode . compile-goto-error)
    ;;(fundamental-mode cscope-interpret-output-line) ;;todo big time
    )
  "Alist of modes and the corresponding defun to visit source buffer."
  :type '(alist :key-type symbol :value-type function)
  :group 'fm)

(defcustom fm-stop-on-error nil
  "Whether to throw an error and stop if `fm-start' cannot be run."
  :type 'boolean
  :group 'fm)

(defcustom fm-key "C-c C-f"
  "Keybinding (as a string for `kbd') to toggle follow mode."
  :type 'string
  :group 'fm)

;; toggles...
(defvar fm-working t)
(defvar fm-window-lines nil
  "If non-nil then set the output buffer to this many lines in height when follow mode is on.")
(make-variable-buffer-local 'fm-window-lines)

(defun fm-start ()
  "Set up `follow-mode' to run on the current buffer.
This should be added to buffers through hooks, such as
`occur-mode-hook'."
  (interactive)
  (let ((l))
    ;; first check to see if it is worth running fm in this mode.
    (if (not (boundp 'fm-defun))
	(progn
	  (setq f (cdr (assoc major-mode fm-modes)))
	  (if f
	      (set (make-local-variable 'fm-defun) f))))
    
    (if (boundp 'fm-defun)
	(progn
	  (add-hook 'post-command-hook 'fm-post-command-hook nil 'local)
	  (add-hook 'pre-command-hook  'fm-pre-command-hook  nil 'local)
	  (local-set-key (kbd fm-key) 'fm-toggle))
      ;; else
      (if fm-stop-on-error
	  (error "Cannot use fm in this mode")
	(message "Cannot use fm in this mode")))))

(defun fm-pre-command-hook ()
  "Remove highlighing in both source and output buffers."
  ;; used as pre command hook in *toc* buffer
  (if fm-working
      (progn
	(fm-unhighlight 0)
	(fm-unhighlight 1))))

(defun fm-post-command-hook (&optional lines)
  "Add the highlighting if possible to both source and output buffers."
  ;;(message (format "run post in %s" (buffer-name)) )
  (if fm-working
      (let (ret)
	(progn
	  (let ((buf (buffer-name))
		(f nil))
	    
	    
	    ;; select current line.
	    (if (not (boundp 'fm-defun))
		(error "Cannot use fm in this buffer."))

	    (setq ret
		  (condition-case nil
		      (funcall fm-defun)
		    (error 'failed)))
	    ;;(message "ret is %s" ret)

	    (if (not (eq ret 'failed))
		(progn
		  ;; make the highlight in the source buffer.
		  (save-excursion
		    (fm-highlight 0
				  (progn (beginning-of-line) (point))
				  (progn (end-of-line) (point))))
		  
		  
		  ;; make the highlight in the output buffer.    
		  (pop-to-buffer buf)

		  (and (> (point) 1) 
		       (save-excursion
			 (fm-highlight 1 
				       (progn (beginning-of-line) (point))
				       (progn (end-of-line) (point)))))
                  (if fm-window-lines
                      (shrink-window (- (window-body-height) fm-window-lines))))
	      ;; else there was an error 
	      (progn
		;; make sure we stay in output buffer.
		(pop-to-buffer buf)
		(message "couldn't find line..."))))))))

(defun fm-toggle ()
  "Toggle the fm behaviour on and off."
  (interactive)
  (setq fm-working (not fm-working)))

;;; Highlighting (copied from reftex.el -- cheers Carsten!)

;; Highlighting uses overlays.  If this is for XEmacs, we need to load
;; the overlay library, available in version 19.15
(and (not (fboundp 'make-overlay))
     (condition-case nil
         (require 'overlay)
       ('error 
        (error "Fm needs overlay emulation (available in XEmacs 19.15)"))))

;; We keep a vector with several different overlays to do our highlighting.
(defvar fm-highlight-overlays [nil nil])

;; Initialize the overlays
(aset fm-highlight-overlays 0 (make-overlay 1 1))
(overlay-put (aref fm-highlight-overlays 0) 'face 'highlight)
(aset fm-highlight-overlays 1 (make-overlay 1 1))
(overlay-put (aref fm-highlight-overlays 1) 'face 'highlight)

;; Two functions for activating and deactivation highlight overlays
(defun fm-highlight (index begin end &optional buffer)
  "Highlight a region with overlay INDEX."
  (move-overlay (aref fm-highlight-overlays index)
                begin end (or buffer (current-buffer))))
(defun fm-unhighlight (index)
  "Detatch overlay INDEX."
  (delete-overlay (aref fm-highlight-overlays index)))

(provide 'fm)
;;; fm.el ends here
