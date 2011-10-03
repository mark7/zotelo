;; zotexo.el --- synchronize zotero collections in emacs.
;;
;; Filename: zotero.el
;; Author: Spinu Vitalie
;; Maintainer: Spinu Vitalie
;; Copyright (C) 2011, Spinu Vitalie, all rights reserved.
;; Created: Oct 2 2011
;; Version: 0.1
;; URL: http://code.google.com/p/zotexo/
;; Keywords: zotero, emacs, reftex, bibtex, MozRepl
;;
;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file is *NOT* part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.
;;
;; Features that might be required by this library:
;; reftex
;;
;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; Commentary:
;; See http://code.google.com/p/zotexo/ and `zotexo-minor-mode' for more info.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;;; Change log:
;;;; Code:


(require 'moz)
(require 'reftex)

(defvar zotexo-minor-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-czu" 'zotexo-update-database)
    (define-key map "\C-czs" 'zotexo-set-collection)
    (define-key map "\C-czm" 'zotexo-mark-for-auto-update)
    map))

(defvar zotexo--check-timer nil
  "Global timer executed at `zotexo-check-interval' seconds. ")

(defvar zotexo-check-interval 2 
  "Seconds between checks for zotero database changes.")

(define-minor-mode zotexo-minor-mode
  "zotexo minor mode for interaction with Firefox.
With no argument, this command toggles the mode.
Non-null prefix argument turns on the mode.
Null prefix argument turns off the mode.

When this minor mode is enabled, `zotexo-set-collection' prompts
for zotero collection and stores it as file local variable . To
manually update the BibTeX data base call
`zotexo-update-database'. The \"file_name.bib\" file will be
created with the exported zotero items. To specify the file_name
just insert insert \bibliography{file_name} anywhere in the
buffer.

This mode is designed mainly for latex modes and works in
conjunction with RefTex, but it can be used in any other mode
such as org-mode.

The following keys are bound in this minor mode:

\\{zotexo-minor-mode-map}"
  nil
  " Zx"
  :keymap zotexo-minor-mode-map
  :group 'zotexo
  (if zotexo-minor-mode
      (progn
        (unless (timerp zotexo--check-timer)
          (setq zotexo--check-timer
                (run-with-idle-timer 1 zotexo-check-interval 'zotexo--check-and-update-all)))
        (setq zotexo--zotero-database-last-change nil) ;; reset the change tracker 
        )
    (unless 
        (loop for b in (buffer-list)
              for is-zotexo-mode = (buffer-local-value 'zotexo-minor-mode b)
              until is-zotexo-mode
              finally return is-zotexo-mode)
      ;; if no more active zotexo mode, cancel the timer
      (when (timerp zotexo--check-timer)
          (cancel-timer zotexo--check-timer)
          (setq zotexo--check-timer nil)
          )
      )
    )
  )
;; [nil 20104 24819 766111 1 zotexo--check-and-update-all nil nil]
(defun zotexo--check-and-update-all ()
  "Function run with `zotexo--check-timer'."
  (let ((last-change (zotexo--get-zotero-db-change-time))
        out id)
    (when last-change ;; if nil no change have been made and no new zotexo-minor-mode trigers 
      (dolist (b  (buffer-list))
        (when (and
               (buffer-local-value 'zotexo-minor-mode b)
               (assoc 'zotero-collection (buffer-local-value 'file-local-variables-alist b))
               (let ((auto-update
                      (assoc 'zotexo-auto-update (buffer-local-value 'file-local-variables-alist b))))
                 (if (and zotexo-auto-update-all (null auto-update))
                     (setq auto-update '(t . t)))
                 (cdr auto-update))
               )
          (with-current-buffer b
            (setq id (zotexo-update-database last-change)))
          (when id
            (append (cons (buffer-name b) id) out)
            )))
      (setq zotexo--zotero-database-last-change last-change) ; set it only if all updates are successful 
      (message "Zotexo: updated files %s " out)
      )
    ))

(defvar zotexo-zotero-database-location nil
  "Location of zotero sql database.
It is detected automatically. Usually you would not need
to set it manually.")

(defvar zotexo--get-zotero-database-js
  "var zotero = Components.classes['@zotero.org/Zotero;1'].getService(Components.interfaces.nsISupports).wrappedJSObject;
repl.print(zotero.getZoteroDatabase().path);")

(defvar zotexo--zotero-database-last-change nil
  "Internal, used to track zotero changes.")

(defun zotexo--get-zotero-db-change-time ()
  "Return the time of zotero last change if changed or nil otherwise."

  (unless zotexo-zotero-database-location
    (with-current-buffer (moz-command zotexo--get-zotero-database-js)
      (let ((file (buffer-substring-no-properties (point-min) (max (1- (point-max)) 0))))
        (if (file-exists-p file)
            (setq zotexo-zotero-database-location file)
          (error "MozRepl didn't return a valid database location. \nPlease try again or set it manually. \n %s" file) )
        )))
  (let ((zdb-last-mod (nth 5 (file-attributes zotexo-zotero-database-location))))
    (if zotexo--zotero-database-last-change ;; is set to nil each time new .tex buffer is opened. 
        (when (time-less-p zotexo--zotero-database-last-change zdb-last-mod)
           zdb-last-mod) ;; return nil otherwise
      zdb-last-mod))
  )
  

(defvar zotexo-use-ido t
  "If t will try to use ido interface")

(defvar zotexo-auto-update-all nil
  "If t zotexo checks for the change in zotero database
every `zotexo-check-interval' seconds and auto updates all
buffers with active `zotexo-minor-mode'.

If nil the only updated files are those with non-nil file local
variable `zotexo-auto-update'. See
`zotexo-mark-for-auto-update'. ")

(defvar zotexo--render-collection-js
   "var render_collection = function(coll, prefix) {
    if (!coll) {
        coll = null;
    };
    if (!prefix){
        prefix='';
    };
    var collections = zotero.getCollections(coll);
    for (c in collections) {
        full_name = prefix + '/' + collections[c].name;
        repl.print(collections[c].id + ' ' + full_name);
        if (collections[c].hasChildCollections) {
	    var name = render_collection(collections[c].id, full_name);
        };
    };
};
"
)


(defvar zotexo--export-collection-js
  "

var filename=('%s');
var prefs = Components.classes['@mozilla.org/preferences-service;1'].getService(Components.interfaces.nsIPrefService).getBranch('extensions.zotero.');
var recColl = prefs.getBoolPref('recursiveCollections');
prefs.setBoolPref('recursiveCollections', true);
var file = Components.classes['@mozilla.org/file/local;1'].createInstance(Components.interfaces.nsILocalFile);
file.initWithPath(filename);
var zotero = Components.classes['@zotero.org/Zotero;1'].getService(Components.interfaces.nsISupports).wrappedJSObject;
var collection = true;
var id = %s;
if (%s){
    var translator = new zotero.Translate('export');
    collection = zotero.Collections.get(id);
    translator.setCollection(collection);
};
if(collection){
    translator.setLocation(file);
    translator.setTranslator('9cb70025-a888-4a29-a210-93ec52da40d4');
    translator.translate();    
}else{
    repl.print('MozError: Collection with the id ' + id + ' does not exist.');
};
prefs.setBoolPref('recursiveCollections', recColl);
"

"Command is sent to zotero."
)

(defun zotexo-update-database(&optional last-change)
  "Prompt for collection if not found, but return nil in
non-interactive mode. Error if bibfile is not found. Error if
collection is not found by MozRepl. "
  (interactive)
  (let ((bibfile (car (zotexo--locate-bibliography-files default-directory)))
        (proc  (inferior-moz-process))
        (id (zotexo--get-local-collection-id))
        (buf (get-buffer-create "*moz-command-output*"))
        all-colls-p cstr bib-last-change)
    (if (null bibfile)
        (when (called-interactively-p)
            (message "Cannot find bibliography reference for file '%s' or it's included files." (buffer-name)))
      (setq bib-last-change (nth 5 (file-attributes bibfile))) ;; nil if bibfile does not exist yet
      (when (and (called-interactively-p) (null id))
        (zotexo-set-collection "Zotero collection is not set. Choose one: " t)
        (setq id (zotexo--get-local-collection-id)))
      (when (and id
                 (or (null last-change)
                     (null bib-last-change)
                     (time-less-p bib-last-change last-change)))
        (setq all-colls-p
              (if (equal id "0")
                  "false"
                "true"))
        (setq cstr (format zotexo--export-collection-js bibfile id all-colls-p))
        ;; (print cstr)
        (message "Updating '%s' ..." (file-name-nondirectory bibfile))
        (moz-command cstr buf) ;; moz-command stalls emacs
        (with-current-buffer buf
          (if (equal (buffer-string) "")
              (message "'%s' updated successfully" (file-name-nondirectory bibfile))
            (goto-char (point-min))
            (let ((mozerr (re-search-forward "MozError:" nil t)))
              (if mozerr
                  (signal 'MozError (buffer-substring-no-properties (point) (1- (point-max))))
                (message "Unexpected MozRepl output, this  might indicate an error:\n%s"
                         (buffer-substring-no-properties (point-min) (poinnt-max))))))
          id)
        ))))

(defun zotexo--locate-bibliography-files (master-dir)
  ;; Scan buffer for bibliography macro and return as a list.
  ;; Modeled after the corresponding reftex function
  
  (let ((files
         (save-excursion
           (goto-char (point-max))
           (if (re-search-backward
                (concat
                                        ;           "\\(\\`\\|[\n\r]\\)[^%]*\\\\\\("
                 "\\(^\\)[^%\n\r]*\\\\\\("
                 (mapconcat 'identity reftex-bibliography-commands "\\|")
                 "\\){[ \t]*\\([^}]+\\)") nil t)
               (setq files 
                     (split-string (reftex-match-string 3)
                                   "[ \t\n\r]*,[ \t\n\r]*"))))))
    (when files
      (setq files 
            (mapcar
             (lambda (x)
               (if (or (member x reftex-bibfile-ignore-list)
                       (delq nil (mapcar (lambda (re) (string-match re x))
                                         reftex-bibfile-ignore-regexps)))
                   ;; excluded file
                   nil
                 ;; find the file
                 (or (reftex-locate-file x "bib" master-dir)
                     (concat master-dir x ".bib"))))
             files))
       (delq nil files))
    ))

(defun zotexo-set-collection (&optional prompt not-update)
  "Ask for a zotero collection.
Ido interface is used by default. If you don't like it set `zotexo-use-ido' to nil.

In `ido-mode' use \"C-s\" and \"C-r\" for navigation. See
ido-mode emacs wiki for many more details.

If not-update is t, don't update after setting the collecton.
"
  (interactive)
  (let ((buf (get-buffer-create "*moz-command-output*"))
        reset-ido colls)
    (when  (and (not ido-mode)
                (featurep 'ido )
                zotexo-use-ido)
      ;; ido initialization
      (setq reset-ido t)
      (ido-init-completion-maps)
      (add-hook 'minibuffer-setup-hook 'ido-minibuffer-setup)
      (add-hook 'choose-completion-string-functions 'ido-choose-completion-string)
      (add-hook 'kill-emacs-hook 'ido-kill-emacs-hook)
      )
    (unwind-protect
        (progn
          ;; set up the collection list
          (moz-command zotexo--render-collection-js)
          (moz-command "render_collection()" buf)
          (with-current-buffer buf
            (goto-char (point-min))
            (let (name  id )
              (while (re-search-forward "^\\([0-9]+\\) /\\(.*\\)$" nil t)
                (setq id (match-string-no-properties 1)
                      name (match-string-no-properties 2))
                (setq colls (cons
                             (propertize name 'zotero-id id)
                             colls))))
            )
          (if (null colls)
              (message "No collections found")
            ;; (setq colls (mapcar 'remove-text-properties colls))
            (setq name (zotexo--read (nreverse colls) prompt))
            (save-excursion
              (add-file-local-variable 'zotero-collection
                                       (propertize (get-text-property 1 'zotero-id name)
                                                   'name (substring-no-properties name)))
              (hack-local-variables))
            (unless not-update
              (zotexo-update-database))
            )
          )
      ;; ido initialization
      (when reset-ido
        (remove-hook 'minibuffer-setup-hook 'ido-minibuffer-setup)
        (remove-hook 'choose-completion-string-functions 'ido-choose-completion-string)
        (removeq-hook 'kill-emacs-hook 'ido-kill-emacs-hook)
        )
      ))
  )


(defun zotexo-mark-for-auto-update (&optional unmark)
  "Mark current file for auto-update.

If the file is marked for auto-update zotexo runs
`zotexo-update-database' on it whenever the zotero data-base is
updated.

File is marked by adding file local variable
'zotexo-auto-update'. To un-mark the file call this function with
an argument or just delete or set to nil the local variable at
the end of the file.
"
  (interactive "P")
  (save-excursion
    (if unmark
        (progn
          (delete-file-local-variable 'zotexo-auto-update)
          (setq file-local-variables-alist
                (assq-delete-all 'zotexo-auto-update file-local-variables-alist)))
      (add-file-local-variable 'zotexo-auto-update t)
      (hack-local-variables)
      (setq zotexo--zotero-database-last-change nil) ;force recheck on next timer
      )
    )
  )


(defun zotexo--get-local-collection-id ()
   (cdr (assoc 'zotero-collection file-local-variables-alist)))

(defun zotexo--read (collections &optional prompt)
  "Read a choice from zotero collections via Ido."
  (ido-completing-read (or prompt "Collection : ")
                                   (cons (propertize "*ALL*" 'zotero-id "0")
                                                         collections)
                                   nil t nil nil))



;;;; Moz utilities
(defun moz-command (com &optional buf)
  "Send the moz-repl  process command COM and delete the output
from the MozRepl process buffer.  If an optional second argument BUF
exists, it must be a string or an existing buffer object. The
output is inserted in that buffer. BUF is erased before use.
"
  (if buf
      (setq buf (get-buffer-create buf))
    (setq buf (get-buffer-create "*moz-command-output*")))
  (let ((proc (inferior-moz-process)))
    (save-excursion
      ;; (set-buffer sbuffer)
      (when (process-get proc 'busy)
        (error
         "MozRepl process not ready. Finish your command before trying again."))
      (setq oldpf (process-filter proc))
      (setq oldpb (process-buffer proc))
      (setq oldpm (marker-position (process-mark proc)))
        ;; need the buffer-local values in result buffer "buf":
      (unwind-protect
          (progn
            (set-process-buffer proc buf)
            (set-process-filter proc 'moz-ordinary-insertion-filter)
            ;; Output is now going to BUF:
            (save-excursion
              (set-buffer buf)
              (erase-buffer)
              (set-marker (process-mark proc) (point-min))
              (process-put proc 'busy t)
              (process-send-string proc (concat com "\n"))
              (sleep-for 0.020); 0.1 is noticeable!
              (moz-wait-for-process proc)
              (delete-region (point-at-bol) (point-max))
              )
            (message "Moz-command finished")
            )
        ;; Restore old values for process filter
        (set-process-buffer proc oldpb)
        (set-process-filter proc oldpf)
        (set-marker (process-mark proc) oldpm oldpb) ;; need oldpb here!!! otherwise it is not set for some reason
        )
      )
    )
  buf
  )

(defun moz-wait-for-process (proc &optional sleep force-redisplay timeout)
  "Wait for TIMEOUT seconds the 'busy property of the process to become nil."
  (if sleep (sleep-for sleep)); we sleep here, *and* wait below
  (unless timeout
    (setq timeout 30))
  (let ((i 1)
        (elapsed 0.0))
    (accept-process-output proc 0.01) ;; enought for most of the short commands on my machine
    (while (and (process-get proc 'busy)
                (< elapsed timeout))
      (sleep-for (* .1 i)) ; if passed to accept-process-output
                                        ; does not work in emacs 23.2.1, very elusive bug, most likely on long outputs accept-process-output returns before teh timeout if output is receive
      (setq elapsed (* (/ (+ i 1) 2.0) .1 i))
      (setq i (1+ i))
      (accept-process-output proc 0)
      (if force-redisplay (redisplay t))
      (when (>= elapsed timeout)
        (message "Waited for %s seconds. Process is bussy or waits for the user's input." elapsed)
        ;; (process-put proc 'ready t) ;; unlikely to end here; :tothink
        )
      )))


(defun moz-ordinary-insertion-filter (proc string)
  "simple filter for command execution"
  ;; (with-current-buffer (process-buffer proc)
  (let (moving)
    (process-put proc 'busy (not (string-match "\\(\\w+\\)> \\'" string)))
    (setq moving (= (point) (process-mark proc)))
    (save-excursion
      ;; Insert the text, moving the process-marker.
      (goto-char (process-mark proc))
      (insert string)
      (set-marker (process-mark proc) (point)))
    (if moving (goto-char (process-mark proc))))
  )

(defun inferior-moz-track-proc-busy (comint-output)
  "track if process returned the '>' prompt and mark it as busy if not."
  (if (string-match "\\(\\w+\\)> \\'" comint-output)
      (process-put (get-buffer-process (current-buffer)) 'busy nil)
    (process-put (get-buffer-process (current-buffer)) 'busy t)))

(defun zotexo-insert-busy-hook ()
  "Add `inferior-moz-track-proc-busy' to comint-outbut-filter hook "
  (add-hook 'comint-output-filter-functions 'inferior-moz-track-proc-busy nil t)
  )

(add-hook 'inferior-moz-hook 'zotexo-insert-busy-hook)

(provide 'zotexo)
;;; zotexo.el ends here.
