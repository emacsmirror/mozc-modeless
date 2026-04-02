;;; test-mozc-modeless-typo.el --- Tests for mozc-modeless-typo  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for typo detection and correction.
;; Run with:
;;   emacs --batch -L . -l test-mozc-modeless-typo.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'mozc-modeless-romaji-words)
(require 'mozc-modeless-typo)

;; ============================================================
;; 1. Romaji parser: valid syllable sequences
;; ============================================================

(ert-deftest typo-parse-vowels ()
  "Single vowels parse correctly."
  (should (equal (mozc-modeless-typo--parse-romaji "a") '("a")))
  (should (equal (mozc-modeless-typo--parse-romaji "i") '("i")))
  (should (equal (mozc-modeless-typo--parse-romaji "u") '("u")))
  (should (equal (mozc-modeless-typo--parse-romaji "e") '("e")))
  (should (equal (mozc-modeless-typo--parse-romaji "o") '("o"))))

(ert-deftest typo-parse-basic-syllables ()
  "Basic consonant+vowel syllables parse correctly."
  (should (equal (mozc-modeless-typo--parse-romaji "ka") '("ka")))
  (should (equal (mozc-modeless-typo--parse-romaji "shi") '("shi")))
  (should (equal (mozc-modeless-typo--parse-romaji "tsu") '("tsu")))
  (should (equal (mozc-modeless-typo--parse-romaji "chi") '("chi")))
  (should (equal (mozc-modeless-typo--parse-romaji "fu") '("fu"))))

(ert-deftest typo-parse-youon ()
  "拗音 (combination syllables) parse correctly."
  (should (equal (mozc-modeless-typo--parse-romaji "kya") '("kya")))
  (should (equal (mozc-modeless-typo--parse-romaji "sha") '("sha")))
  (should (equal (mozc-modeless-typo--parse-romaji "cha") '("cha")))
  (should (equal (mozc-modeless-typo--parse-romaji "nya") '("nya")))
  (should (equal (mozc-modeless-typo--parse-romaji "ryo") '("ryo")))
  (should (equal (mozc-modeless-typo--parse-romaji "gyu") '("gyu")))
  (should (equal (mozc-modeless-typo--parse-romaji "byo") '("byo")))
  (should (equal (mozc-modeless-typo--parse-romaji "pya") '("pya"))))

(ert-deftest typo-parse-nn ()
  "ん (nn) parses correctly."
  (should (equal (mozc-modeless-typo--parse-romaji "nn") '("nn")))
  (should (equal (mozc-modeless-typo--parse-romaji "xn") '("xn"))))

(ert-deftest typo-parse-n-before-consonant ()
  "ん (n before consonant) parses correctly."
  ;; nk: n is ん before k, but k alone fails -> parse fails
  (should-not (mozc-modeless-typo--parse-romaji "nk"))
  ;; n at end of string
  (should (equal (mozc-modeless-typo--parse-romaji "kan") '("ka" "n")))
  ;; n before consonant+vowel
  (should (equal (mozc-modeless-typo--parse-romaji "kanka") '("ka" "n" "ka")))
  (should (equal (mozc-modeless-typo--parse-romaji "sanka") '("sa" "n" "ka")))
  (should (equal (mozc-modeless-typo--parse-romaji "honki") '("ho" "n" "ki"))))

(ert-deftest typo-parse-n-before-vowel ()
  "n before vowel should NOT be treated as ん."
  ;; na, ni, nu, ne, no are syllables
  (should (equal (mozc-modeless-typo--parse-romaji "na") '("na")))
  (should (equal (mozc-modeless-typo--parse-romaji "ni") '("ni")))
  ;; n before y is ny- syllable
  (should (equal (mozc-modeless-typo--parse-romaji "nya") '("nya"))))

(ert-deftest typo-parse-sokuon ()
  "促音 (っ, doubled consonant) parses correctly."
  (should (equal (mozc-modeless-typo--parse-romaji "kka") '("k" "ka")))
  (should (equal (mozc-modeless-typo--parse-romaji "tte") '("t" "te")))
  (should (equal (mozc-modeless-typo--parse-romaji "ppa") '("p" "pa")))
  (should (equal (mozc-modeless-typo--parse-romaji "sshi") '("s" "shi")))
  (should (equal (mozc-modeless-typo--parse-romaji "cchi") '("c" "chi"))))

(ert-deftest typo-parse-sokuon-not-vowels ()
  "Doubled vowels are NOT sokuon."
  ;; aa = a + a (two vowels, not sokuon)
  (should (equal (mozc-modeless-typo--parse-romaji "aa") '("a" "a")))
  (should (equal (mozc-modeless-typo--parse-romaji "ii") '("i" "i")))
  (should (equal (mozc-modeless-typo--parse-romaji "uu") '("u" "u")))
  (should (equal (mozc-modeless-typo--parse-romaji "oo") '("o" "o"))))

(ert-deftest typo-parse-multi-syllable-words ()
  "Multi-syllable words parse correctly."
  (should (equal (mozc-modeless-typo--parse-romaji "nihongo")
                 '("ni" "ho" "n" "go")))
  (should (equal (mozc-modeless-typo--parse-romaji "taberu")
                 '("ta" "be" "ru")))
  (should (equal (mozc-modeless-typo--parse-romaji "konnnichiha")
                 '("ko" "nn" "ni" "chi" "ha")))
  (should (equal (mozc-modeless-typo--parse-romaji "arigatou")
                 '("a" "ri" "ga" "to" "u")))
  (should (equal (mozc-modeless-typo--parse-romaji "wakaru")
                 '("wa" "ka" "ru")))
  (should (equal (mozc-modeless-typo--parse-romaji "tsumari")
                 '("tsu" "ma" "ri")))
  (should (equal (mozc-modeless-typo--parse-romaji "hashiru")
                 '("ha" "shi" "ru")))
  (should (equal (mozc-modeless-typo--parse-romaji "yomu")
                 '("yo" "mu")))
  (should (equal (mozc-modeless-typo--parse-romaji "hanasu")
                 '("ha" "na" "su"))))

(ert-deftest typo-parse-words-with-sokuon ()
  "Words containing sokuon parse correctly."
  (should (equal (mozc-modeless-typo--parse-romaji "kitte")
                 '("ki" "t" "te")))
  (should (equal (mozc-modeless-typo--parse-romaji "zasshi")
                 '("za" "s" "shi")))
  (should (equal (mozc-modeless-typo--parse-romaji "nippon")
                 '("ni" "p" "po" "n")))
  (should (equal (mozc-modeless-typo--parse-romaji "gakkari")
                 '("ga" "k" "ka" "ri")))
  (should (equal (mozc-modeless-typo--parse-romaji "mattaku")
                 '("ma" "t" "ta" "ku"))))

(ert-deftest typo-parse-small-kana ()
  "Small kana (x-prefix) parses correctly."
  (should (equal (mozc-modeless-typo--parse-romaji "xa") '("xa")))
  (should (equal (mozc-modeless-typo--parse-romaji "xtu") '("xtu")))
  (should (equal (mozc-modeless-typo--parse-romaji "xya") '("xya"))))

(ert-deftest typo-parse-special-syllables ()
  "Special syllables (fa, fi, etc.) parse correctly."
  (should (equal (mozc-modeless-typo--parse-romaji "fa") '("fa")))
  (should (equal (mozc-modeless-typo--parse-romaji "fi") '("fi")))
  (should (equal (mozc-modeless-typo--parse-romaji "fe") '("fe")))
  (should (equal (mozc-modeless-typo--parse-romaji "fo") '("fo")))
  (should (equal (mozc-modeless-typo--parse-romaji "thi") '("thi"))))

(ert-deftest typo-parse-empty-string ()
  "Empty string parses as empty list."
  (should (equal (mozc-modeless-typo--parse-romaji "") '())))

;; ============================================================
;; 2. Romaji parser: invalid sequences (parse failure)
;; ============================================================

(ert-deftest typo-parse-fail-invalid-char ()
  "Strings with non-romaji characters fail to parse."
  (should-not (mozc-modeless-typo--parse-romaji "ni1go"))
  (should-not (mozc-modeless-typo--parse-romaji "abc@def"))
  (should-not (mozc-modeless-typo--parse-romaji "hello!")))

(ert-deftest typo-parse-fail-invalid-sequence ()
  "Invalid consonant clusters fail to parse."
  (should-not (mozc-modeless-typo--parse-romaji "vgo"))
  (should-not (mozc-modeless-typo--parse-romaji "qka"))
  (should-not (mozc-modeless-typo--parse-romaji "xf")))

(ert-deftest typo-parse-fail-single-consonant ()
  "Single consonants (except n) fail to parse."
  (should-not (mozc-modeless-typo--parse-romaji "k"))
  (should-not (mozc-modeless-typo--parse-romaji "s"))
  (should-not (mozc-modeless-typo--parse-romaji "t"))
  ;; But n alone is valid (ん at end of string)
  (should (equal (mozc-modeless-typo--parse-romaji "n") '("n"))))

;; ============================================================
;; 3. Error position detection
;; ============================================================

(ert-deftest typo-error-pos-valid ()
  "Valid romaji returns nil error position."
  (should-not (mozc-modeless-typo--error-position "nihongo"))
  (should-not (mozc-modeless-typo--error-position "taberu"))
  (should-not (mozc-modeless-typo--error-position "")))

(ert-deftest typo-error-pos-at-start ()
  "Error at start position."
  (should (equal (mozc-modeless-typo--error-position "qka") 0))
  (should (equal (mozc-modeless-typo--error-position "vgo") 0)))

(ert-deftest typo-error-pos-in-middle ()
  "Error in the middle of the string."
  (should (equal (mozc-modeless-typo--error-position "nihovgo") 4))
  ;; tsu-m parsed, then mq fails at position 3
  (should (equal (mozc-modeless-typo--error-position "tsumqri") 3)))

(ert-deftest typo-error-pos-at-end ()
  "Error near the end of the string."
  ;; ma parsed, then tq fails at position 2
  (should (equal (mozc-modeless-typo--error-position "matq") 2))
  ;; ka parsed, then kj fails at position 2
  (should (equal (mozc-modeless-typo--error-position "kakj") 2)))

;; ============================================================
;; 4. QWERTY neighbor map
;; ============================================================

(ert-deftest typo-neighbors-basic ()
  "QWERTY neighbors return correct values."
  (should (stringp (mozc-modeless-typo--neighbors ?a)))
  (should (string-match-p "s" (mozc-modeless-typo--neighbors ?a)))
  (should (string-match-p "w" (mozc-modeless-typo--neighbors ?a)))
  (should (string-match-p "z" (mozc-modeless-typo--neighbors ?a))))

(ert-deftest typo-neighbors-all-alpha ()
  "All lowercase alpha characters have neighbors defined."
  (dotimes (i 26)
    (let ((ch (+ ?a i)))
      (should (> (length (mozc-modeless-typo--neighbors ch)) 0)))))

(ert-deftest typo-neighbors-case-insensitive ()
  "Neighbors lookup is case-insensitive."
  (should (equal (mozc-modeless-typo--neighbors ?A)
                 (mozc-modeless-typo--neighbors ?a))))

(ert-deftest typo-neighbors-unknown-char ()
  "Unknown characters return empty string."
  (should (equal (mozc-modeless-typo--neighbors ?1) ""))
  (should (equal (mozc-modeless-typo--neighbors ?@) "")))

;; ============================================================
;; 5. Typo correction: Case 1 - Parse failure (invalid romaji)
;; ============================================================

(ert-deftest typo-correct-invalid-qwerty-substitution ()
  "QWERTY neighbor substitution fixes common typos."
  ;; q is near a on QWERTY
  (should (equal (mozc-modeless-typo-correct "matq") "mata"))
  (should (equal (mozc-modeless-typo-correct "tsumqri") "tsumari"))
  (should (equal (mozc-modeless-typo-correct "wakqru") "wakaru")))

(ert-deftest typo-correct-invalid-middle-error ()
  "Errors in the middle of the word are corrected."
  (should (equal (mozc-modeless-typo-correct "nihovgo") "nihongo"))
  (should (equal (mozc-modeless-typo-correct "kakj") "kaku")))

(ert-deftest typo-correct-invalid-start-error ()
  "Errors at the start of the word are corrected."
  ;; q -> a (neighbor), qru -> aru
  (should (equal (mozc-modeless-typo-correct "qru") "aru")))

(ert-deftest typo-correct-invalid-returns-parseable-fallback ()
  "When no dict match, returns first parseable candidate."
  ;; Fabricate something that can be fixed to parseable but maybe not in dict
  (let ((result (mozc-modeless-typo-correct "xvq")))
    ;; Should return something (parseable) or nil, but not crash
    (should (or (null result) (stringp result)))))

;; ============================================================
;; 6. Typo correction: Case 2 - Valid romaji, not in dictionary
;; ============================================================

(ert-deftest typo-correct-valid-not-in-dict ()
  "Valid romaji not in dictionary is corrected via neighbor substitution."
  ;; taheru: ta-he-ru is valid romaji, but not a word; taberu is
  (should (equal (mozc-modeless-typo-correct "taheru") "taberu"))
  ;; h and b are QWERTY neighbors
  )

(ert-deftest typo-correct-valid-not-in-dict-deletion ()
  "Valid romaji not in dict, correctable by deletion."
  ;; mataa: ma-ta-a, valid romaji, not in dict; mata is
  (let ((result (mozc-modeless-typo-correct "mataa")))
    (should (or (null result) (equal result "mata")))))

(ert-deftest typo-correct-valid-not-in-dict-transposition ()
  "Valid romaji not in dict, correctable by transposition."
  ;; amta: a-m-ta, if parseable -> check if swap gives mata
  (let ((result (mozc-modeless-typo-correct "maata")))
    (should (or (null result) (equal result "mata")))))

;; ============================================================
;; 7. Typo correction: Case 3 - Valid and in dictionary (no correction)
;; ============================================================

(ert-deftest typo-correct-nil-when-valid ()
  "Valid romaji in dictionary returns nil (no correction needed)."
  (should-not (mozc-modeless-typo-correct "nihongo"))
  (should-not (mozc-modeless-typo-correct "taberu"))
  (should-not (mozc-modeless-typo-correct "mata"))
  (should-not (mozc-modeless-typo-correct "aru"))
  (should-not (mozc-modeless-typo-correct "iku"))
  (should-not (mozc-modeless-typo-correct "kaku"))
  (should-not (mozc-modeless-typo-correct "yomu"))
  (should-not (mozc-modeless-typo-correct "hanasu"))
  (should-not (mozc-modeless-typo-correct "hashiru"))
  (should-not (mozc-modeless-typo-correct "aruku"))
  (should-not (mozc-modeless-typo-correct "tsumari"))
  (should-not (mozc-modeless-typo-correct "wakaru"))
  (should-not (mozc-modeless-typo-correct "arigatou")))

(ert-deftest typo-correct-nil-short-words ()
  "Short valid words return nil."
  (should-not (mozc-modeless-typo-correct "a"))
  (should-not (mozc-modeless-typo-correct "e"))
  (should-not (mozc-modeless-typo-correct "ka")))

(ert-deftest typo-correct-nil-empty ()
  "Empty string returns nil."
  (should-not (mozc-modeless-typo-correct "")))

;; ============================================================
;; 8. Case insensitivity
;; ============================================================

(ert-deftest typo-correct-case-insensitive ()
  "Correction is case-insensitive."
  (should-not (mozc-modeless-typo-correct "Nihongo"))
  (should-not (mozc-modeless-typo-correct "TABERU"))
  (should (equal (mozc-modeless-typo-correct "MATQ") "mata"))
  (should (equal (mozc-modeless-typo-correct "Nihovgo") "nihongo")))

;; ============================================================
;; 9. Correction returns valid romaji (parseable)
;; ============================================================

(ert-deftest typo-correct-result-is-parseable ()
  "All correction results must be parseable as valid romaji."
  (let ((typos '("matq" "tsumqri" "nihovgo" "wakqru" "kakj" "taheru")))
    (dolist (typo typos)
      (let ((result (mozc-modeless-typo-correct typo)))
        (when result
          (should (mozc-modeless-typo--parse-romaji result)))))))

;; ============================================================
;; 10. Correction does NOT return the same string
;; ============================================================

(ert-deftest typo-correct-result-differs-from-input ()
  "Correction result is never the same as input."
  (let ((typos '("matq" "tsumqri" "nihovgo" "wakqru" "kakj" "taheru")))
    (dolist (typo typos)
      (let ((result (mozc-modeless-typo-correct typo)))
        (when result
          (should-not (equal (downcase typo) result)))))))

;; ============================================================
;; 11. Dictionary lookup
;; ============================================================

(ert-deftest typo-dict-common-words-exist ()
  "Common Japanese words exist in the romaji dictionary."
  (should (mozc-modeless--romaji-word-p "nihongo"))
  (should (mozc-modeless--romaji-word-p "taberu"))
  (should (mozc-modeless--romaji-word-p "mata"))
  (should (mozc-modeless--romaji-word-p "aru"))
  (should (mozc-modeless--romaji-word-p "iku"))
  (should (mozc-modeless--romaji-word-p "kaku"))
  (should (mozc-modeless--romaji-word-p "yomu"))
  (should (mozc-modeless--romaji-word-p "hanasu"))
  (should (mozc-modeless--romaji-word-p "hashiru"))
  (should (mozc-modeless--romaji-word-p "aruku"))
  (should (mozc-modeless--romaji-word-p "tsumari"))
  (should (mozc-modeless--romaji-word-p "wakaru"))
  (should (mozc-modeless--romaji-word-p "arigatou"))
  (should (mozc-modeless--romaji-word-p "konnnichiha")))

(ert-deftest typo-dict-case-insensitive ()
  "Dictionary lookup is case-insensitive (via downcase)."
  (should (mozc-modeless--romaji-word-p "nihongo"))
  ;; The function uses downcase internally
  (should (gethash "nihongo" mozc-modeless--romaji-words-hash)))

(ert-deftest typo-dict-nonsense-not-found ()
  "Nonsense strings are not in the dictionary."
  (should-not (mozc-modeless--romaji-word-p "xyzxyz"))
  (should-not (mozc-modeless--romaji-word-p "qqqqq"))
  (should-not (mozc-modeless--romaji-word-p "bbbbb")))

;; ============================================================
;; 12. Trie structure
;; ============================================================

(ert-deftest typo-trie-builds ()
  "Trie is built without error."
  (let ((mozc-modeless-typo--trie nil))
    (should (mozc-modeless-typo--get-trie))
    (should (listp (mozc-modeless-typo--get-trie)))))

(ert-deftest typo-trie-cached ()
  "Trie is cached after first build."
  (let ((mozc-modeless-typo--trie nil))
    (let ((trie1 (mozc-modeless-typo--get-trie))
          (trie2 (mozc-modeless-typo--get-trie)))
      (should (eq trie1 trie2)))))

;; ============================================================
;; 13. Candidate generation
;; ============================================================

(ert-deftest typo-candidates-not-empty ()
  "Candidate generation produces non-empty list."
  (should (> (length (mozc-modeless-typo--generate-candidates "matq" 3)) 0))
  (should (> (length (mozc-modeless-typo--generate-candidates "nihovgo" 4)) 0)))

(ert-deftest typo-candidates-all-different-length ()
  "Candidates include both same-length and different-length strings."
  (let* ((candidates (mozc-modeless-typo--generate-candidates "matq" 3))
         (same-len (seq-filter (lambda (c) (= (length c) 4)) candidates))
         (diff-len (seq-filter (lambda (c) (/= (length c) 4)) candidates)))
    ;; Should have both substitution (same length) and deletion/insertion (different)
    (should (> (length same-len) 0))
    (should (> (length diff-len) 0))))

(ert-deftest typo-all-candidates-not-empty ()
  "All-candidates generation produces non-empty list."
  (should (> (length (mozc-modeless-typo--generate-all-candidates "taheru")) 0)))

(ert-deftest typo-all-candidates-includes-neighbor-substitution ()
  "All-candidates includes QWERTY neighbor substitutions."
  (let ((candidates (mozc-modeless-typo--generate-all-candidates "taheru")))
    ;; taberu should be in candidates (h->b substitution)
    (should (member "taberu" candidates))))

;; ============================================================
;; 14. Realistic typo scenarios
;; ============================================================

(ert-deftest typo-scenario-adjacent-key-right ()
  "Right-neighbor key typo is corrected."
  ;; o -> p (right neighbor)
  (let ((result (mozc-modeless-typo-correct "nihpngo")))
    ;; Should not crash, may or may not find correction
    (should (or (null result) (stringp result)))))

(ert-deftest typo-scenario-extra-char ()
  "Extra character in the middle."
  ;; matxa -> mata (extra x)
  (let ((result (mozc-modeless-typo-correct "matxa")))
    ;; x is valid (xa = small あ), so this may parse
    (should (or (null result) (stringp result)))))

(ert-deftest typo-scenario-missing-vowel ()
  "Missing vowel at end."
  ;; kak -> should fail parse at end (k alone)
  (let ((result (mozc-modeless-typo-correct "kak")))
    (should (or (null result) (stringp result)))))

(ert-deftest typo-scenario-swapped-chars ()
  "Swapped adjacent characters."
  ;; amta: parse fails at mt -> corrected to a dict word
  (let ((result (mozc-modeless-typo-correct "amta")))
    (should (or (null result) (stringp result)))))

;; ============================================================
;; 15. Performance / robustness
;; ============================================================

(ert-deftest typo-no-crash-on-long-input ()
  "Long input does not crash."
  (let ((long-str (make-string 100 ?a)))
    (should (or (null (mozc-modeless-typo-correct long-str))
                (stringp (mozc-modeless-typo-correct long-str))))))

(ert-deftest typo-no-crash-on-all-consonants ()
  "All-consonant input does not crash."
  (should (or (null (mozc-modeless-typo-correct "bcdfg"))
              (stringp (mozc-modeless-typo-correct "bcdfg")))))

(ert-deftest typo-no-crash-on-single-invalid ()
  "Single invalid character does not crash."
  (should (or (null (mozc-modeless-typo-correct "q"))
              (stringp (mozc-modeless-typo-correct "q")))))

(ert-deftest typo-performance-reasonable ()
  "100 corrections complete in under 1 second."
  (let ((start (float-time)))
    (dotimes (_ 100)
      (mozc-modeless-typo-correct "nihovgo")
      (mozc-modeless-typo-correct "matq")
      (mozc-modeless-typo-correct "taheru")
      (mozc-modeless-typo-correct "nihongo"))
    (should (< (- (float-time) start) 1.0))))

;; ============================================================
;; 16. Parse-romaji-internal returns correct structure
;; ============================================================

(ert-deftest typo-parse-internal-success-structure ()
  "On success, internal parse returns (SYLLABLES . nil)."
  (let ((result (mozc-modeless-typo--parse-romaji-internal "nihongo")))
    (should (consp result))
    (should (listp (car result)))
    (should (null (cdr result)))))

(ert-deftest typo-parse-internal-failure-structure ()
  "On failure, internal parse returns (nil . ERROR-POS)."
  (let ((result (mozc-modeless-typo--parse-romaji-internal "nihovgo")))
    (should (consp result))
    (should (null (car result)))
    (should (numberp (cdr result)))))

;; ============================================================
;; 17. Longest match behavior
;; ============================================================

(ert-deftest typo-parse-longest-match-shi-vs-si ()
  "Parser prefers longest match: shi over s+i."
  (should (equal (mozc-modeless-typo--parse-romaji "shi") '("shi")))
  ;; si is also valid
  (should (equal (mozc-modeless-typo--parse-romaji "si") '("si"))))

(ert-deftest typo-parse-longest-match-chi-vs-c ()
  "Parser prefers longest match: chi over c+hi."
  (should (equal (mozc-modeless-typo--parse-romaji "chi") '("chi"))))

(ert-deftest typo-parse-longest-match-tsu-vs-t ()
  "Parser prefers longest match: tsu over t+su."
  (should (equal (mozc-modeless-typo--parse-romaji "tsu") '("tsu"))))

(ert-deftest typo-parse-longest-match-sha-vs-s ()
  "Parser prefers longest match: sha over s+ha."
  (should (equal (mozc-modeless-typo--parse-romaji "sha") '("sha"))))

(ert-deftest typo-parse-longest-match-kya-vs-ki ()
  "Parser prefers kya over ki+a."
  (should (equal (mozc-modeless-typo--parse-romaji "kya") '("kya"))))

;;; test-mozc-modeless-typo.el ends here
