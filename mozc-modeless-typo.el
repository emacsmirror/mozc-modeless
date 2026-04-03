;;; mozc-modeless-typo.el --- Typo detection and correction for romaji input  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Kiyoka Nishiyama
;; Keywords: i18n
;; License: GPL-3.0-or-later

;;; Commentary:
;; This file provides typo detection and correction for romaji input.
;; It uses a romaji syllable trie to parse input, detects invalid sequences,
;; and suggests corrections using QWERTY keyboard proximity.
;;
;; The correction flow:
;; 1. Try to parse the input as valid romaji syllables
;; 2. If parsing fails, identify the error position
;; 3. Generate correction candidates around the error position
;; 4. Validate candidates: must be parseable AND in the dictionary
;; 5. Return the best candidate

;;; Code:

(require 'mozc-modeless-romaji-words)

;;; Romaji syllable table (valid patterns for mozc default)

(defconst mozc-modeless-typo--romaji-syllables
  '(;; Vowels
    "a" "i" "u" "e" "o"
    ;; K-row
    "ka" "ki" "ku" "ke" "ko" "kya" "kyu" "kyo"
    ;; S-row
    "sa" "si" "shi" "su" "se" "so" "sha" "shu" "sho"
    ;; T-row
    "ta" "ti" "chi" "tu" "tsu" "te" "to" "cha" "chu" "cho"
    ;; N-row
    "na" "ni" "nu" "ne" "no" "nya" "nyu" "nyo"
    ;; H-row
    "ha" "hi" "hu" "fu" "he" "ho" "hya" "hyu" "hyo"
    ;; M-row
    "ma" "mi" "mu" "me" "mo" "mya" "myu" "myo"
    ;; Y-row
    "ya" "yu" "yo"
    ;; R-row
    "ra" "ri" "ru" "re" "ro" "rya" "ryu" "ryo"
    ;; W-row
    "wa" "wi" "we" "wo"
    ;; N (syllabic)
    "n" "nn" "xn"
    ;; G-row
    "ga" "gi" "gu" "ge" "go" "gya" "gyu" "gyo"
    ;; Z-row
    "za" "zi" "ji" "zu" "ze" "zo" "ja" "ju" "jo"
    ;; D-row
    "da" "di" "du" "de" "do"
    ;; B-row
    "ba" "bi" "bu" "be" "bo" "bya" "byu" "byo"
    ;; P-row
    "pa" "pi" "pu" "pe" "po" "pya" "pyu" "pyo"
    ;; Small kana
    "xa" "xi" "xu" "xe" "xo" "xya" "xyu" "xyo" "xtu"
    ;; Special
    "fa" "fi" "fe" "fo"
    "dya" "dyu" "dyo"
    "thi" "thu"
    "la" "li" "lu" "le" "lo"
    "lya" "lyu" "lyo" "ltu")
  "List of valid romaji syllable patterns (mozc default table).")

;;; Trie data structure

(defvar mozc-modeless-typo--trie nil
  "Trie for valid romaji syllable lookup.")

(defun mozc-modeless-typo--build-trie ()
  "Build the romaji syllable trie from `mozc-modeless-typo--romaji-syllables'."
  (let ((trie (list nil)))
    (dolist (syllable mozc-modeless-typo--romaji-syllables)
      (let ((node trie))
        (dotimes (i (length syllable))
          (let* ((ch (aref syllable i))
                 (child (assq ch (cdr node))))
            (unless child
              (setq child (cons ch (list nil)))
              (setcdr node (cons child (cdr node))))
            (setq node (cdr child))))
        (setcar node t)))
    trie))

(defun mozc-modeless-typo--get-trie ()
  "Get the romaji syllable trie, building it if necessary."
  (unless mozc-modeless-typo--trie
    (setq mozc-modeless-typo--trie (mozc-modeless-typo--build-trie)))
  mozc-modeless-typo--trie)

;;; Romaji parser

(defconst mozc-modeless-typo--vowels '(?a ?i ?u ?e ?o)
  "List of vowel characters.")

(defun mozc-modeless-typo--parse-romaji (str)
  "Parse STR as a sequence of romaji syllables.
Returns a list of syllable strings if successful, or nil if parsing fails.
Uses greedy longest-match strategy.
Handles sokuon (っ) by detecting doubled consonants."
  (car (mozc-modeless-typo--parse-romaji-internal str)))

(defun mozc-modeless-typo--parse-romaji-internal (str)
  "Parse STR and return (SYLLABLES . ERROR-POS).
SYLLABLES is a list of syllable strings if successful, nil on failure.
ERROR-POS is the position where parsing failed, or nil on success."
  (let ((trie (mozc-modeless-typo--get-trie))
        (pos 0)
        (len (length str))
        (result (list)))
    (catch 'done
      (while (< pos len)
        (let ((ch (aref str pos)))
          ;; Handle sokuon: doubled consonant (but not nn which is ん)
          (if (and (< (1+ pos) len)
                   (eq ch (aref str (1+ pos)))
                   (not (memq ch mozc-modeless-typo--vowels))
                   (not (eq ch ?n)))
              (progn
                (push (char-to-string ch) result)
                (setq pos (1+ pos)))
            ;; Try longest match in trie
            (let ((node trie)
                  (best-end nil)
                  (j pos))
              (while (and (< j len)
                          (let ((child (assq (aref str j) (cdr node))))
                            (when child
                              (setq node (cdr child))
                              (when (car node)
                                (setq best-end (1+ j)))
                              t)))
                (setq j (1+ j)))
              ;; Special: 'n' before consonant or end-of-string = ん
              (when (and (null best-end)
                         (eq ch ?n)
                         (or (= (1+ pos) len)
                             (not (memq (aref str (1+ pos))
                                        '(?a ?i ?u ?e ?o ?y ?n)))))
                (setq best-end (1+ pos)))
              (if best-end
                  (progn
                    (push (substring str pos best-end) result)
                    (setq pos best-end))
                ;; Parse failed at pos
                (throw 'done (cons nil pos)))))))
      (cons (nreverse result) nil))))

(defun mozc-modeless-typo--error-position (str)
  "Return the position where romaji parsing fails in STR, or nil if valid."
  (cdr (mozc-modeless-typo--parse-romaji-internal str)))

;;; QWERTY keyboard proximity map

(defconst mozc-modeless-typo--qwerty-neighbors
  '((?a . "qwsz")
    (?b . "vghn")
    (?c . "xdfv")
    (?d . "sfcxer")
    (?e . "wrsdf")
    (?f . "dgvcrt")
    (?g . "fhbvty")
    (?h . "gjbnyu")
    (?i . "ujkol")
    (?j . "hknmui")
    (?k . "jlmio")
    (?l . "kop")
    (?m . "njk")
    (?n . "bhjm")
    (?o . "iklp")
    (?p . "ol")
    (?q . "wa")
    (?r . "edft")
    (?s . "awedxz")
    (?t . "rfgy")
    (?u . "yhji")
    (?v . "cfgb")
    (?w . "qase")
    (?x . "zsdc")
    (?y . "tghu")
    (?z . "asx"))
  "QWERTY keyboard neighbor map.")

(defun mozc-modeless-typo--neighbors (ch)
  "Return a string of QWERTY-neighboring characters for CH."
  (or (cdr (assq (downcase ch) mozc-modeless-typo--qwerty-neighbors))
      ""))

;;; Candidate generation (focused around error position)

(defconst mozc-modeless-typo--all-romaji-chars "aiueokstnhmyrwgzdbp"
  "Characters commonly used in romaji input.")

(defun mozc-modeless-typo--generate-candidates (str error-pos)
  "Generate typo correction candidates for STR around ERROR-POS.
Candidates are generated in order of likelihood:
1. QWERTY neighbor substitution at error-pos and nearby positions
2. Deletion at error-pos and nearby positions
3. Transposition around error-pos
4. Insertion at error-pos and nearby positions"
  (let ((candidates nil)
        (len (length str))
        ;; Generate candidates in a window around the error position
        (start (max 0 (- error-pos 2)))
        (end (min (length str) (+ error-pos 3))))
    ;; 1. Substitution with QWERTY neighbors (near error position)
    (let ((i start))
      (while (< i end)
        (let ((neighbors (mozc-modeless-typo--neighbors (aref str i))))
          (dotimes (j (length neighbors))
            (push (concat (substring str 0 i)
                          (char-to-string (aref neighbors j))
                          (substring str (1+ i)))
                  candidates)))
        (setq i (1+ i))))
    ;; Also try all romaji characters at error position itself
    (dotimes (j (length mozc-modeless-typo--all-romaji-chars))
      (let ((ch (aref mozc-modeless-typo--all-romaji-chars j)))
        (unless (eq ch (aref str error-pos))
          (push (concat (substring str 0 error-pos)
                        (char-to-string ch)
                        (substring str (1+ error-pos)))
                candidates))))
    ;; 2. Deletion near error position
    (let ((i start))
      (while (< i end)
        (push (concat (substring str 0 i) (substring str (1+ i))) candidates)
        (setq i (1+ i))))
    ;; 3. Transposition around error position
    (let ((i (max 0 (1- error-pos))))
      (while (< i (min (1- len) (+ error-pos 2)))
        (push (concat (substring str 0 i)
                      (char-to-string (aref str (1+ i)))
                      (char-to-string (aref str i))
                      (substring str (+ i 2)))
              candidates)
        (setq i (1+ i))))
    ;; 4. Insertion near error position
    (let ((i (max 0 (1- error-pos))))
      (while (<= i (min len (+ error-pos 2)))
        (dotimes (j (length mozc-modeless-typo--all-romaji-chars))
          (push (concat (substring str 0 i)
                        (char-to-string (aref mozc-modeless-typo--all-romaji-chars j))
                        (substring str i))
                candidates))
        (setq i (1+ i))))
    (nreverse candidates)))

;;; Main API

(defun mozc-modeless-typo--generate-all-candidates (str)
  "Generate correction candidates for STR by trying edits at every position.
Used when STR is parseable but not in the dictionary.
Only QWERTY neighbor substitution is used to avoid false corrections
\(e.g., deletion turning a valid word into a shorter different word)."
  (let ((candidates nil)
        (len (length str)))
    ;; Substitution with QWERTY neighbors at every position
    (dotimes (i len)
      (let ((neighbors (mozc-modeless-typo--neighbors (aref str i))))
        (dotimes (j (length neighbors))
          (push (concat (substring str 0 i)
                        (char-to-string (aref neighbors j))
                        (substring str (1+ i)))
                candidates))))
    (nreverse candidates)))

(defun mozc-modeless-typo--correct-word (str-down)
  "Try to correct a single romaji word STR-DOWN (already downcased).
Returns the corrected string, or nil if no correction needed/found.
Strings that contain no alphabetic characters are skipped."
  ;; Skip non-alphabetic strings (punctuation, numbers, etc.)
  (unless (string-match-p "[a-z]" str-down)
    (setq str-down nil))
  (when str-down
    (let* ((parse-result (mozc-modeless-typo--parse-romaji-internal str-down))
           (syllables (car parse-result))
           (error-pos (cdr parse-result)))
      (cond
       ;; Case 1: Parse failed - invalid romaji sequence
       (error-pos
        (let ((candidates (mozc-modeless-typo--generate-candidates str-down error-pos))
              (first-parseable nil))
          (catch 'found
            (dolist (candidate candidates)
              (when (mozc-modeless-typo--parse-romaji candidate)
                (unless first-parseable
                  (setq first-parseable candidate))
                (when (mozc-modeless--romaji-word-p candidate)
                  (throw 'found candidate))))
            ;; No dictionary match; return first parseable candidate
            first-parseable)))
       ;; Case 2/3: Parse succeeded - no correction
       ;; Valid romaji sequences are passed through to mozc as-is.
       ;; (SKK dictionary does not cover all conjugation forms,
       ;; so correcting valid romaji causes false positives like
       ;; shimasu -> shinasu)
       (t nil)))))

(defun mozc-modeless-typo-correct (str)
  "Try to correct typos in romaji string STR.
If STR contains spaces, each word is checked independently.
Returns the corrected string if any word was corrected, or nil if
no corrections were needed.

The correction process per word:
1. Parse as romaji syllables
2. If parse fails: generate candidates near error, find parseable+dict match
3. If parse succeeds: no correction (pass through to mozc as-is)"
  (let* ((words (split-string str " "))
         (any-corrected nil)
         (result-words
          (mapcar (lambda (word)
                    (let ((corrected (mozc-modeless-typo--correct-word
                                     (downcase word))))
                      (when corrected
                        (setq any-corrected t))
                      (or corrected word)))
                  words)))
    (when any-corrected
      (mapconcat #'identity result-words " "))))

(provide 'mozc-modeless-typo)
;;; mozc-modeless-typo.el ends here
