;;; mozc-modeless.el --- Modeless Japanese input with Mozc  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Kiyoka Nishiyama

;; Author: Kiyoka Nishiyama <kiyokap@gmail.com>
;; Maintainer: Kiyoka Nishiyama <kiyokap@gmail.com>
;; Keywords: i18n, input-method
;; Version: 0.10.0
;; Package-Requires: ((emacs "29.0") (mozc "1.0"))
;; URL: https://github.com/kiyoka/mozc-modeless-emacs

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

;; mozc-modeless.el provides a modeless Japanese input interface using Mozc.
;;
;; Usage:
;;   (require 'mozc-modeless)
;;   (global-mozc-modeless-mode 1)
;;
;; By default, you type in alphanumeric mode.  When you want to convert
;; the preceding romaji to Japanese, press C-j.  The first candidate is
;; committed immediately and you stay in alphanumeric input (no candidate
;; window is shown).  If the first candidate is not what you wanted, press
;; C-j again on the just-converted text to reopen Mozc's candidate window
;; and select another candidate.  Text converted by mozc-modeless remembers
;; its reading (stored as a text property), so any such text can be
;; reconverted later in the same way, as long as the property is in memory.

;;; Code:

(require 'mozc)
(require 'mozc-modeless-english-words)

;;; Customization

(defgroup mozc-modeless nil
  "Modeless Japanese input with Mozc."
  :group 'mozc
  :prefix "mozc-modeless-")

(defcustom mozc-modeless-convert-key (kbd "C-j")
  "Key sequence to trigger conversion."
  :type 'key-sequence
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-enable t
  "Non-nil to enable ambient (automatic) conversion.
When enabled, typing a particle followed by space or punctuation
automatically triggers Mozc conversion.
Set this to nil to disable ambient conversion and rely solely on
the explicit conversion key (see `mozc-modeless-convert-key')."
  :type 'boolean
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-particles
  '("wa" "ha" "ga" "wo" "ni" "de" "to" "kara" "made" "he" "mo" "no" "ya" "desu")
  "List of romaji particles that trigger ambient conversion when followed by space."
  :type '(repeat string)
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-punctuation '("." "," "?")
  "List of punctuation characters that trigger ambient conversion."
  :type '(repeat string)
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-punctuation-delay 0.5
  "Delay in seconds before punctuation-triggered ambient conversion fires.
If any command is issued during this delay (e.g. the user keeps typing),
the pending conversion is cancelled.  Set to 0 to convert immediately
without any delay."
  :type 'number
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-punctuation-auto-confirm t
  "Non-nil means punctuation-triggered conversion auto-confirms.
The first candidate is used automatically.
When nil, punctuation-triggered conversion leaves Mozc in conversion
state, allowing the user to select candidates before confirming."
  :type 'boolean
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-english-threshold 0.8
  "Threshold for English text detection.
If the ratio of English words in the preceding text is greater than
or equal to this value, ambient conversion is skipped."
  :type 'float
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-exclude-modes '(shell-mode term-mode eshell-mode)
  "List of major modes where ambient conversion is disabled."
  :type '(repeat symbol)
  :group 'mozc-modeless)

(defvar mozc-modeless-skip-chars "a-zA-Z0-9.,@:`\\-+!/\\[\\]?;' \t"
  "Characters to be included in the preceding string for conversion.
Includes slash (/) as a delimiter for partial conversion.")

;;; Internal variables

(defvar mozc-modeless--active nil
  "Non-nil when Mozc conversion mode is active.")

(defvar mozc-modeless--start-pos nil
  "Buffer position where the romaji string started.")

(defvar mozc-modeless--original-string nil
  "Original romaji string before conversion.
This is used to restore the text when conversion is cancelled.")

(defvar mozc-modeless--reading nil
  "Reading (romaji) used to re-tag the committed text on finish.
For reconversion this differs from `mozc-modeless--original-string',
which holds the text to restore when the conversion is cancelled.")

(defvar mozc-modeless--skip-check-count 0
  "Number of `post-command-hook' calls to skip before checking finish.")

(defvar mozc-modeless--ambient-punctuation-pending nil
  "Punctuation character to insert after conversion confirmation.
Set by ambient conversion in interactive mode.")

(defvar mozc-modeless--converting-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-g") 'mozc-modeless-cancel)
    (define-key map (kbd "C-n") 'mozc-modeless-next-candidate)
    (define-key map (kbd "C-p") 'mozc-modeless-previous-candidate)
    (define-key map (kbd "C-f") 'mozc-modeless-next-segment)
    (define-key map (kbd "C-b") 'mozc-modeless-previous-segment)
    map)
  "Keymap active only during conversion.")

;;; Utility functions

(defun mozc-modeless--get-preceding-roman ()
  "Get the preceding romaji string before the cursor.
Returns a cons cell (START . STRING) where START is the beginning
position of the romaji string, or nil if no romaji is found.
Leading indentation (spaces and tabs) at the beginning of the line
are excluded from the conversion target.
In `markdown-mode', markdown syntax (list markers, headings) are
excluded.  In `text-mode' and `fundamental-mode', markdown syntax
is also recognized using built-in regex patterns."
  (save-excursion
    (let* ((end (point))
           (line-start (line-beginning-position))
           (search-start line-start))
      ;; Skip leading indentation (spaces and tabs)
      (goto-char line-start)
      (skip-chars-forward " \t")
      (setq search-start (point))
      ;; Skip markdown syntax in markdown-mode, text-mode, and fundamental-mode
      (cond
       ;; In markdown-mode, use markdown-regex-list if available
       ((and (derived-mode-p 'markdown-mode)
             (boundp 'markdown-regex-list))
        (save-excursion
          (goto-char search-start)
          ;; Check for list markers (-, *, +, 1., etc.)
          (when (looking-at markdown-regex-list)
            (setq search-start (match-end 0)))
          ;; Check for ATX headings (#, ##, etc.)
          (goto-char search-start)
          (when (looking-at "^\\(#+\\)[ \t]+")
            (setq search-start (max search-start (match-end 0))))))
       ;; In text-mode or fundamental-mode, use our own regex
       ((or (derived-mode-p 'text-mode)
            (derived-mode-p 'fundamental-mode))
        (save-excursion
          (goto-char search-start)
          ;; Check for list markers (-, *, +, 1., etc.)
          (when (looking-at "\\([-*+]\\|[0-9]+\\.\\)[ \t]+")
            (setq search-start (match-end 0)))
          ;; Check for ATX headings (#, ##, etc.)
          (goto-char search-start)
          (when (looking-at "\\(#+\\)[ \t]+")
            (setq search-start (match-end 0))))))
      ;; Skip backward over characters defined in mozc-modeless-skip-chars
      (goto-char end)
      (skip-chars-backward mozc-modeless-skip-chars search-start)
      (when (< (point) end)
        (cons (point) (buffer-substring-no-properties (point) end))))))

(defun mozc-modeless--apply-fence (roman-data)
  "Apply fence (slash) processing to ROMAN-DATA.
ROMAN-DATA is (START . STRING) from `mozc-modeless--get-preceding-roman'.
If the string contains a slash, return a new cons cell with only the part
after the last slash.  The start position is adjusted accordingly, and the
slash itself is deleted from the buffer.
Returns nil if nothing remains after the slash."
  (let* ((start (car roman-data))
         (full-string (cdr roman-data))
         (slash-pos (string-match-p "/[^/]*$" full-string)))
    (if slash-pos
        (let* ((roman-string (substring full-string (1+ slash-pos)))
               (delete-start (+ start slash-pos)))
          (if (string-empty-p roman-string)
              nil
            ;; Delete the slash from the buffer
            (delete-region delete-start (1+ delete-start))
            (cons delete-start roman-string)))
      roman-data)))

(defun mozc-modeless--tag-reading (beg end reading)
  "Tag the buffer text between BEG and END with READING.
READING is stored in the `mozc-modeless-reading' text property so the
text can later be reconverted by `mozc-modeless-convert'.  Does nothing
unless READING is a non-empty string and BEG is before END."
  (when (and (stringp reading) (> (length reading) 0) (< beg end))
    (put-text-property beg end 'mozc-modeless-reading reading)
    ;; Make the property non-rear-sticky so text typed right after the tagged
    ;; region does not inherit the reading.  Without this, characters typed
    ;; after a converted word would be swallowed into it on reconversion.
    (put-text-property beg end 'rear-nonsticky '(mozc-modeless-reading))))

(defun mozc-modeless--reconvertible-region-at-point ()
  "Return (BEG END READING) if point is at or within a reconvertible region.
A reconvertible region is text previously converted by mozc-modeless and
tagged with the `mozc-modeless-reading' text property.  The region is the
maximal run of that property covering the character before point.

Returns nil when the character before point carries no such property, or
when that character is an ASCII character (code < 128: romaji, digits or
symbols); in that case a new conversion is preferred over reconversion
even if a reading is present.  Reconversion fires only when a non-ASCII
\(Japanese) character precedes point."
  (let ((before (char-before)))
    (when (and before
               ;; Reconvert only when a non-ASCII (Japanese) char precedes
               ;; point.  Any ASCII char (romaji/digit/symbol) means a new
               ;; conversion is intended.
               (>= before 128))
      (let ((reading (get-text-property (1- (point)) 'mozc-modeless-reading)))
        (when reading
          (let ((beg (or (previous-single-property-change
                          (point) 'mozc-modeless-reading)
                         (point-min)))
                (end (or (next-single-property-change
                          (1- (point)) 'mozc-modeless-reading)
                         (point-max))))
            (list beg end reading)))))))

;;; Main functions

(defun mozc-modeless--reset-state ()
  "Reset all internal state variables and remove hooks."
  (setq mozc-modeless--active nil
        mozc-modeless--start-pos nil
        mozc-modeless--original-string nil
        mozc-modeless--reading nil
        mozc-modeless--skip-check-count 0
        mozc-modeless--ambient-punctuation-pending nil)
  (remove-hook 'post-command-hook #'mozc-modeless--check-finish t))

(defun mozc-modeless--deactivate-ime ()
  "Deactivate mozc input method if it's currently active."
  (when (and current-input-method
             (string= current-input-method "japanese-mozc"))
    (deactivate-input-method)))

(defun mozc-modeless-convert ()
  "Convert Japanese using Mozc, keeping a modeless interface.

This command is bound to \\[mozc-modeless-convert] and behaves
differently depending on what precedes point:

- Preceding romaji: convert it and commit the first candidate
  immediately, then return to alphanumeric input.  No candidate window is
  shown.  If the string contains a slash (/), only the part after the last
  slash is converted and the slash is deleted.
- Preceding text previously converted by mozc-modeless: reconvert it,
  opening Mozc's candidate window so another candidate can be selected.
- While the candidate window is open: switch to the next candidate.
- In `lisp-interaction-mode', when the preceding character is \\='),
  evaluate the expression instead of converting."
  (interactive)
  (let ((region (and (not mozc-modeless--active)
                     (mozc-modeless--reconvertible-region-at-point))))
    (cond
     ;; In lisp-interaction-mode, evaluate the expression if preceding char is ')'
     ((and (derived-mode-p 'lisp-interaction-mode)
           (eq (char-before) 41))
      (call-interactively #'eval-print-last-sexp))

     ;; Already in conversion mode, send space to get next candidate
     (mozc-modeless--active
      (setq unread-command-events (cons ?\s unread-command-events)))

     ;; Preceding text was previously converted: reconvert it (show candidates)
     (region
      (mozc-modeless--reconvert region))

     ;; Otherwise convert the preceding romaji and commit the first candidate
     (t
      (mozc-modeless--convert-preceding-romaji)))))

(defun mozc-modeless--convert-preceding-romaji ()
  "Convert the romaji preceding point and commit the first candidate.
No candidate window is shown; point returns to direct input.  The
committed text is tagged with its reading so it can be reconverted later
with `mozc-modeless-convert'."
  (let ((roman-data (mozc-modeless--get-preceding-roman)))
    (if (not roman-data)
        (message "No romaji found before cursor")
      ;; Apply fence (slash) processing
      (setq roman-data (mozc-modeless--apply-fence roman-data))
      (if (not roman-data)
          (message "No romaji found after slash")
        (undo-boundary)
        (let ((saved-undo buffer-undo-list))
          ;; Reuse the auto-confirm path: send romaji + space + Enter.
          (mozc-modeless--ambient-convert roman-data nil saved-undo))))))

(defun mozc-modeless--reconvert (region)
  "Reconvert a previously converted REGION using Mozc.
REGION is (BEG END READING) from
`mozc-modeless--reconvertible-region-at-point'.  The region's text is
removed and its stored READING is sent to Mozc with the candidate window
shown, so the user can pick a different candidate.
\\[mozc-modeless-cancel] restores the original text (with its reading)."
  (let* ((beg (nth 0 region))
         (end (nth 1 region))
         (reading (nth 2 region))
         ;; Keep the original text (with its reading property) so C-g can
         ;; restore it intact.
         (original (buffer-substring beg end)))
    (undo-boundary)
    (delete-region beg end)
    (goto-char beg)
    (mozc-modeless--start-conversion beg reading original)))

(defun mozc-modeless--start-conversion (start reading &optional restore-string
                                              send-string)
  "Begin interactive Mozc conversion of READING at buffer position START.
The caller must have already removed the source text from the buffer so
START is the insertion point.  READING is the romaji recorded on the
committed text for later reconversion.  RESTORE-STRING is what
`mozc-modeless-cancel' restores (defaults to READING); for
reconversion it is the original Japanese text.  SEND-STRING is the exact
string fed to Mozc (defaults to READING followed by a space); it may embed
punctuation.  Mozc's candidate window is shown via mozc.el."
  (let ((send (or send-string (concat reading " "))))
    (setq mozc-modeless--active t
          mozc-modeless--start-pos start
          mozc-modeless--reading reading
          mozc-modeless--original-string (or restore-string reading)
          ;; Skip checking finish until the queued keys have been processed.
          mozc-modeless--skip-check-count (length send))
    (unless current-input-method
      (activate-input-method "japanese-mozc"))
    (add-hook 'post-command-hook #'mozc-modeless--check-finish nil t)
    (set-transient-map mozc-modeless--converting-map
                       (lambda () mozc-modeless--active))
    (mozc-modeless--insert-string send)))

(defun mozc-modeless--insert-string (str)
  "Insert string STR through Mozc input method.
Queue characters to be processed by the active input method."
  (setq unread-command-events
        (append (listify-key-sequence str) unread-command-events)))

(defun mozc-modeless--preedit-active-p ()
  "Return non-nil if mozc has an active preedit session."
  (or (bound-and-true-p mozc-preedit-in-session-flag)
      (bound-and-true-p mozc-preedit-overlay)))

(defun mozc-modeless--check-finish ()
  "Check if conversion is finished and clean up if necessary.
This is called from `post-command-hook'."
  (when mozc-modeless--active
    (if (> mozc-modeless--skip-check-count 0)
        ;; Still processing initial romaji input
        (setq mozc-modeless--skip-check-count (1- mozc-modeless--skip-check-count))
      ;; Check if mozc is no longer in preedit/conversion state
      (unless (mozc-modeless--preedit-active-p)
        (mozc-modeless--finish)))))

(defun mozc-modeless--finish ()
  "Finish conversion mode and return to normal mode.
Tag the committed Japanese with its reading so it can be reconverted."
  (when mozc-modeless--active
    (let ((pending-punct mozc-modeless--ambient-punctuation-pending)
          (start mozc-modeless--start-pos)
          (reading mozc-modeless--reading))
      ;; Deactivate mozc input method
      (mozc-modeless--deactivate-ime)
      ;; Tag the committed text (between START and point) with its reading.
      (when (and start reading (> (point) start))
        (mozc-modeless--tag-reading start (point) reading))
      ;; Clean up state
      (mozc-modeless--reset-state)
      ;; Insert pending punctuation from ambient conversion
      (when pending-punct
        (insert (mozc-modeless--to-fullwidth-punctuation pending-punct))))))

(defun mozc-modeless-cancel ()
  "Cancel the current conversion and restore the original romaji string."
  (interactive)
  (when mozc-modeless--active
    ;; Cancel mozc conversion by deactivating input method
    (mozc-modeless--deactivate-ime)
    ;; Delete any preedit text that mozc may have inserted
    (when (bound-and-true-p mozc-preedit-overlay)
      (delete-overlay mozc-preedit-overlay))
    ;; Clear preedit flag if it exists
    (when (boundp 'mozc-preedit-in-session-flag)
      (setq mozc-preedit-in-session-flag nil))
    ;; Restore original string
    (when (and mozc-modeless--start-pos mozc-modeless--original-string)
      (goto-char mozc-modeless--start-pos)
      (insert mozc-modeless--original-string))
    ;; Clean up state
    (mozc-modeless--reset-state)))

(defun mozc-modeless-previous-candidate ()
  "Select the previous candidate during conversion.
This function simulates the up arrow key."
  (interactive)
  (setq unread-command-events (cons 'up unread-command-events)))

(defun mozc-modeless-next-candidate ()
  "Select the next candidate during conversion.
This function simulates the down arrow key."
  (interactive)
  (setq unread-command-events (cons 'down unread-command-events)))

(defun mozc-modeless-next-segment ()
  "Move to the next segment during conversion.
This function simulates the right arrow key."
  (interactive)
  (setq unread-command-events (cons 'right unread-command-events)))

(defun mozc-modeless-previous-segment ()
  "Move to the previous segment during conversion.
This function simulates the left arrow key."
  (interactive)
  (setq unread-command-events (cons 'left unread-command-events)))

(defun mozc-modeless-reset ()
  "Reset mozc-modeless state.
Use this if the mode gets stuck in an inconsistent state."
  (interactive)
  (mozc-modeless--deactivate-ime)
  (mozc-modeless--reset-state)
  (message "mozc-modeless state reset"))

;;; Ambient conversion

(defvar mozc-modeless--short-english-words
  '("I" "a" "an" "am" "as" "at" "be" "by" "do" "go" "he" "if" "in"
    "is" "it" "me" "my" "no" "of" "on" "or" "so" "to" "up" "us" "we")
  "List of common short English words (1-2 letters) not in the dictionary.")

(defun mozc-modeless--normalize-word (word)
  "Remove trailing punctuation from WORD for dictionary lookup."
  (replace-regexp-in-string "[.,?!;:]+$" "" word))

(defun mozc-modeless--english-text-p (text)
  "Return non-nil if TEXT appears to be English text.
Splits TEXT by whitespace, checks each word against the English
dictionary and short word list.  If the ratio of English words
is >= `mozc-modeless-ambient-english-threshold', return non-nil."
  (let* ((words (split-string text "[ \t]+" t))
         (total (length words))
         (english-count 0))
    (when (> total 0)
      (dolist (raw-word words)
        (let ((word (mozc-modeless--normalize-word raw-word)))
          (when (or (mozc-modeless--english-word-p word)
                    (member word mozc-modeless--short-english-words)
                    ;; Capitalized word (likely proper noun)
                    (and (> (length word) 0)
                         (let ((first-char (aref word 0)))
                           (and (>= first-char ?A) (<= first-char ?Z)))))
            (setq english-count (1+ english-count)))))
      (>= (/ (float english-count) total)
          mozc-modeless-ambient-english-threshold))))

(defun mozc-modeless--ambient-excluded-p ()
  "Return non-nil if ambient conversion should be skipped in the current context."
  (or mozc-modeless--active
      (minibufferp)
      (apply #'derived-mode-p mozc-modeless-ambient-exclude-modes)))

(defun mozc-modeless--get-preceding-text-on-line ()
  "Return the text from the beginning of the line to the cursor.
Leading indentation is excluded."
  (save-excursion
    (let ((end (point)))
      (beginning-of-line)
      (skip-chars-forward " \t")
      (buffer-substring-no-properties (point) end))))

(defun mozc-modeless--ends-with-particle-p (text)
  "Return the particle string if TEXT ends with a romaji particle, nil otherwise.
Only matches when the particle is preceded by another romaji character
so isolated particles are not triggered."
  (let ((result nil))
    (dolist (particle mozc-modeless-ambient-particles result)
      (when (and (>= (length text) (1+ (length particle)))
                 (string-suffix-p particle text)
                 ;; The character before the particle must be a letter
                 (let ((preceding-char (aref text (- (length text) (length particle) 1))))
                   (or (and (>= preceding-char ?a) (<= preceding-char ?z))
                       (and (>= preceding-char ?A) (<= preceding-char ?Z)))))
        (setq result particle)))))

(defvar mozc-modeless--ambient-in-progress nil
  "Non-nil when ambient conversion is in progress.")

(defvar mozc-modeless--ambient-punctuation-timer nil
  "Pending timer for punctuation-triggered ambient conversion, or nil.")

(defun mozc-modeless--cancel-ambient-punctuation-timer ()
  "Cancel the pending ambient punctuation timer, if any."
  (when (timerp mozc-modeless--ambient-punctuation-timer)
    (cancel-timer mozc-modeless--ambient-punctuation-timer))
  (setq mozc-modeless--ambient-punctuation-timer nil)
  (remove-hook 'pre-command-hook
               #'mozc-modeless--ambient-punctuation-pre-command t))

(defun mozc-modeless--ambient-punctuation-pre-command ()
  "Cancel the pending ambient punctuation timer when any command is run."
  (mozc-modeless--cancel-ambient-punctuation-timer))

(defun mozc-modeless--ambient-punctuation-timer-fire (buffer pos punct-char)
  "Fire ambient punctuation conversion for PUNCT-CHAR in BUFFER at POS.
Runs only if the buffer, point, and character at point-1 are unchanged."
  (setq mozc-modeless--ambient-punctuation-timer nil)
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (remove-hook 'pre-command-hook
                   #'mozc-modeless--ambient-punctuation-pre-command t)
      (when (and (eq buffer (current-buffer))
                 (= (point) pos)
                 (eq (char-before) punct-char)
                 mozc-modeless-ambient-enable
                 (not mozc-modeless--active)
                 (not mozc-modeless--ambient-in-progress)
                 (not (mozc-modeless--ambient-excluded-p)))
        (mozc-modeless--run-ambient-punctuation-conversion punct-char)))))

(defun mozc-modeless--run-ambient-punctuation-conversion (punct-char)
  "Run punctuation-triggered ambient conversion for PUNCT-CHAR.
Assumes PUNCT-CHAR has just been inserted so `char-before' is PUNCT-CHAR."
  (let ((char-before-punct (char-before (1- (point)))))
    ;; Skip if preceding character is a digit (e.g., "0.1" decimals, "$1,000" amounts)
    (unless (and char-before-punct
                 (>= char-before-punct ?0)
                 (<= char-before-punct ?9))
      (save-excursion
        (backward-char 1)
        (let* ((text-on-line (mozc-modeless--get-preceding-text-on-line))
               (roman-data (mozc-modeless--get-preceding-roman)))
          (when (and roman-data
                     (not (mozc-modeless--english-text-p text-on-line)))
            (setq roman-data (mozc-modeless--apply-fence roman-data))
            (when roman-data
              (undo-boundary)
              (let ((saved-undo buffer-undo-list))
                (forward-char 1)
                (delete-char -1)
                (mozc-modeless--ambient-convert roman-data punct-char saved-undo)))))))))

(defun mozc-modeless--check-ambient-trigger ()
  "Check if the last inserted character should trigger ambient conversion.
This function is added to `post-self-insert-hook'."
  (when (and mozc-modeless-ambient-enable
             (not mozc-modeless--active)
             (not mozc-modeless--ambient-in-progress)
             (not (mozc-modeless--ambient-excluded-p)))
    (let ((last-char (char-before)))
      (cond
       ;; Space trigger: check if preceding text ends with a particle
       ((eq last-char ?\s)
        (let* ((text-before-space
                (save-excursion
                  (backward-char 1)
                  (mozc-modeless--get-preceding-text-on-line)))
               (particle (mozc-modeless--ends-with-particle-p text-before-space)))
          (when (and particle
                     (not (mozc-modeless--english-text-p text-before-space)))
            ;; Save undo state before any modifications
            (undo-boundary)
            (let ((saved-undo buffer-undo-list))
              ;; Delete the space we just typed
              (delete-char -1)
              ;; Get romaji info and apply fence (slash) processing
              (let ((roman-data (mozc-modeless--get-preceding-roman)))
                (when roman-data
                  (setq roman-data (mozc-modeless--apply-fence roman-data))
                  (when roman-data
                    (mozc-modeless--ambient-convert roman-data nil saved-undo))))))))
       ;; Punctuation trigger
       ((member (char-to-string last-char) mozc-modeless-ambient-punctuation)
        (if (and (numberp mozc-modeless-ambient-punctuation-delay)
                 (> mozc-modeless-ambient-punctuation-delay 0))
            ;; Defer: schedule a timer; any subsequent command cancels it.
            (progn
              (mozc-modeless--cancel-ambient-punctuation-timer)
              (add-hook 'pre-command-hook
                        #'mozc-modeless--ambient-punctuation-pre-command nil t)
              (setq mozc-modeless--ambient-punctuation-timer
                    (run-with-timer
                     mozc-modeless-ambient-punctuation-delay nil
                     #'mozc-modeless--ambient-punctuation-timer-fire
                     (current-buffer) (point) last-char)))
          ;; Immediate: fire conversion now.
          (mozc-modeless--run-ambient-punctuation-conversion last-char)))))))

(defun mozc-modeless--ambient-convert (romaji-info punct-char saved-undo-list)
  "Perform ambient conversion on ROMAJI-INFO.
ROMAJI-INFO is (START . STRING) from `mozc-modeless--get-preceding-roman'.
PUNCT-CHAR is the punctuation character that triggered conversion,
or nil for space trigger.
SAVED-UNDO-LIST is the `buffer-undo-list' saved before any modifications,
used to merge all changes into a single undo group.
When PUNCT-CHAR is non-nil and `mozc-modeless-ambient-punctuation-auto-confirm'
is nil, the conversion stays in Mozc candidate selection mode."
  (let* ((start (car romaji-info))
         (roman-string (cdr romaji-info))
         (skip-count (1+ (length roman-string)))
         (auto-confirm (or (null punct-char)
                           mozc-modeless-ambient-punctuation-auto-confirm)))
    ;; Delete the romaji from the buffer
    (delete-region start (point))
    (if auto-confirm
        ;; Auto-confirm mode: convert and confirm immediately
        (progn
          (setq mozc-modeless--ambient-in-progress t)
          (unless current-input-method
            (activate-input-method "japanese-mozc"))
          ;; Set up hook to detect conversion completion and clean up
          (let ((cleanup-count skip-count))
            (letrec ((ambient-finish
                      (lambda ()
                        (if (> cleanup-count 0)
                            (setq cleanup-count (1- cleanup-count))
                          (unless (mozc-modeless--preedit-active-p)
                            (mozc-modeless--deactivate-ime)
                            ;; Tag the committed Japanese (before any
                            ;; punctuation) with its reading for reconversion.
                            (let ((jpn-end (point)))
                              (when punct-char
                                (insert (mozc-modeless--to-fullwidth-punctuation punct-char)))
                              (mozc-modeless--tag-reading start jpn-end roman-string))
                            ;; Merge all undo entries into a single group
                            (mozc-modeless--merge-undo-entries saved-undo-list)
                            (setq mozc-modeless--ambient-in-progress nil)
                            (remove-hook 'post-command-hook ambient-finish t))))))
              (add-hook 'post-command-hook ambient-finish nil t)))
          ;; Send romaji + space + Enter (auto-confirm first candidate)
          (mozc-modeless--insert-string (concat roman-string " \r")))
      ;; Interactive mode: enter conversion state, let the user select candidates.
      ;; Send romaji + punctuation + space to Mozc; record the reading (without
      ;; punctuation) so the committed result can be reconverted later.
      (mozc-modeless--start-conversion
       start roman-string roman-string
       (concat roman-string (char-to-string punct-char) " ")))))

(defun mozc-modeless--merge-undo-entries (saved-undo-list)
  "Merge all undo entries since SAVED-UNDO-LIST into a single undo group.
Remove intermediate undo boundaries so that a single undo operation
reverses all changes made during ambient conversion."
  (when (listp buffer-undo-list)
    (let ((result nil)
          (tail buffer-undo-list))
      ;; Collect all non-boundary entries added since saved point
      (while (not (eq tail saved-undo-list))
        (when (car tail)
          (push (car tail) result))
        (setq tail (cdr tail)))
      ;; Rebuild: boundary + merged entries (no intermediate boundaries) + saved
      (setq buffer-undo-list
            (nconc (nreverse result) saved-undo-list)))))

(defun mozc-modeless--to-fullwidth-punctuation (char)
  "Convert ASCII punctuation CHAR to its fullwidth Japanese equivalent."
  (pcase char
    (?. "。")
    (?, "、")
    (?? "？")
    (_ (char-to-string char))))

;;; Minor mode definition

(defvar mozc-modeless-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map mozc-modeless-convert-key 'mozc-modeless-convert)
    map)
  "Keymap for `mozc-modeless-mode'.")

(defvar mozc-modeless--original-mozc-keymap-entry nil
  "Original binding in `mozc-mode-map' for `mozc-modeless-convert-key'.
Saved for restoration when the mode is disabled.")

(defun mozc-modeless--setup-mozc-keymap ()
  "Set up binding in `mozc-mode-map' for next candidate selection."
  (when (boundp 'mozc-mode-map)
    ;; Save original binding
    (setq mozc-modeless--original-mozc-keymap-entry
          (lookup-key mozc-mode-map mozc-modeless-convert-key))
    ;; Set our binding
    (define-key mozc-mode-map mozc-modeless-convert-key 'mozc-modeless-convert)))

(defun mozc-modeless--restore-mozc-keymap ()
  "Restore original binding for `mozc-modeless-convert-key' in `mozc-mode-map'."
  (when (boundp 'mozc-mode-map)
    (if mozc-modeless--original-mozc-keymap-entry
        (define-key mozc-mode-map mozc-modeless-convert-key mozc-modeless--original-mozc-keymap-entry)
      (define-key mozc-mode-map mozc-modeless-convert-key nil))))

;;;###autoload
(define-minor-mode mozc-modeless-mode
  "Toggle modeless Japanese input with Mozc.

When enabled, you can type in alphanumeric mode normally.  Press
\\[mozc-modeless-convert] to convert the preceding romaji string to
Japanese.  After conversion is confirmed, the mode automatically
returns to alphanumeric input.

Key bindings:
\\{mozc-modeless-mode-map}"
  :lighter " Mozc-ML"
  :keymap mozc-modeless-mode-map
  :group 'mozc-modeless
  (if mozc-modeless-mode
      (progn
        ;; Enable mode
        (unless (fboundp 'mozc-mode)
          (error "Mozc is not available.  Please install mozc.el"))
        ;; Set up convert key in mozc-mode-map
        (mozc-modeless--setup-mozc-keymap)
        ;; Set up ambient conversion hook
        (add-hook 'post-self-insert-hook #'mozc-modeless--check-ambient-trigger nil t))
    ;; Disable mode
    (mozc-modeless--restore-mozc-keymap)
    (remove-hook 'post-self-insert-hook #'mozc-modeless--check-ambient-trigger t)
    (mozc-modeless--cancel-ambient-punctuation-timer)
    (when mozc-modeless--active
      (mozc-modeless--finish))))

;;;###autoload
(define-globalized-minor-mode global-mozc-modeless-mode
  mozc-modeless-mode
  (lambda () (mozc-modeless-mode 1))
  :group 'mozc-modeless)

(provide 'mozc-modeless)
;;; mozc-modeless.el ends here
