#!/usr/bin/env python3
"""Convert SKK dictionary hiragana keys to romaji and generate an Elisp hash table.

Usage:
    python3 tools/skk-to-romaji.py SKK-JISYO.S > mozc-modeless-romaji-words.el

Input: SKK dictionary file (EUC-JP encoded)
Output: Elisp file with hash table of romaji words
"""

import sys
import codecs

# Hiragana to romaji conversion table (mozc default)
HIRAGANA_TO_ROMAJI = {
    'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
    'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
    'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
    'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
    'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
    'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
    'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
    'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
    'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
    'わ': 'wa', 'ゐ': 'wi', 'ゑ': 'we', 'を': 'wo',
    'ん': 'n',
    'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
    'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
    'だ': 'da', 'ぢ': 'di', 'づ': 'du', 'で': 'de', 'ど': 'do',
    'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
    'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
    # 拗音
    'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
    'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
    'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
    'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
    'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
    'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
    'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
    'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
    'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
    'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
    'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
    # 促音
    'っ': 'xtu',  # placeholder, handled specially
    # 小文字
    'ぁ': 'xa', 'ぃ': 'xi', 'ぅ': 'xu', 'ぇ': 'xe', 'ぉ': 'xo',
    'ゃ': 'xya', 'ゅ': 'xyu', 'ょ': 'xyo',
    'ー': '-',
}


def hiragana_to_romaji_variants(hiragana):
    """Convert a hiragana string to romaji variants (mozc default table).

    Returns a list of romaji strings (multiple variants for ん: n/nn),
    or empty list if conversion fails.
    """
    # Build list of segments, where each segment is a list of variants
    # e.g., へんかん -> [["he"], ["n", "nn"], ["ka"], ["n", "nn"]]
    segments = []
    i = 0
    while i < len(hiragana):
        # Try 2-char match first (拗音)
        if i + 1 < len(hiragana):
            two_char = hiragana[i:i+2]
            if two_char in HIRAGANA_TO_ROMAJI:
                segments.append([HIRAGANA_TO_ROMAJI[two_char]])
                i += 2
                continue

        # Handle 促音 (っ): double the next consonant
        if hiragana[i] == 'っ':
            if i + 1 < len(hiragana):
                next_romaji = None
                if i + 2 < len(hiragana):
                    two_char = hiragana[i+1:i+3]
                    if two_char in HIRAGANA_TO_ROMAJI:
                        next_romaji = HIRAGANA_TO_ROMAJI[two_char]
                if next_romaji is None and hiragana[i+1] in HIRAGANA_TO_ROMAJI:
                    next_romaji = HIRAGANA_TO_ROMAJI[hiragana[i+1]]
                if next_romaji and next_romaji[0].isalpha():
                    segments.append([next_romaji[0]])
                    i += 1
                    continue
            return []

        # Single char match
        one_char = hiragana[i]
        if one_char in HIRAGANA_TO_ROMAJI:
            romaji = HIRAGANA_TO_ROMAJI[one_char]
            if one_char == 'ん':
                # ん always has both n and nn variants
                segments.append(['n', 'nn'])
            else:
                segments.append([romaji])
            i += 1
        else:
            return []

    # Expand all combinations of segments
    if not segments:
        return ['']
    results = ['']
    for seg_variants in segments:
        new_results = []
        for prefix in results:
            for variant in seg_variants:
                new_results.append(prefix + variant)
        results = new_results
    return results


def hiragana_to_romaji(hiragana):
    """Convert a hiragana string to romaji (mozc default table).

    Returns the primary romaji string, or None if conversion fails.
    """
    variants = hiragana_to_romaji_variants(hiragana)
    return variants[0] if variants else None


def expand_okuri_ari(hiragana_stem, okurigana_consonant):
    """Expand an okuri-ari entry into full hiragana forms.

    For example: stem='つま' + consonant='r' -> ['つまら', 'つまり', 'つまる', 'つまれ', 'つまろ']
    """
    # Map consonant to possible hiragana endings
    CONSONANT_TO_HIRAGANA = {
        'k': ['か', 'き', 'く', 'け', 'こ'],
        's': ['さ', 'し', 'す', 'せ', 'そ'],
        't': ['た', 'ち', 'つ', 'て', 'と'],
        'n': ['な', 'に', 'ぬ', 'ね', 'の'],
        'h': ['は', 'ひ', 'ふ', 'へ', 'ほ'],
        'm': ['ま', 'み', 'む', 'め', 'も'],
        'r': ['ら', 'り', 'る', 'れ', 'ろ'],
        'g': ['が', 'ぎ', 'ぐ', 'げ', 'ご'],
        'z': ['ざ', 'じ', 'ず', 'ぜ', 'ぞ'],
        'd': ['だ', 'ぢ', 'づ', 'で', 'ど'],
        'b': ['ば', 'び', 'ぶ', 'べ', 'ぼ'],
        'p': ['ぱ', 'ぴ', 'ぷ', 'ぺ', 'ぽ'],
        'w': ['わ', 'ゐ', 'う', 'ゑ', 'を'],
        'y': ['や', 'ゆ', 'よ'],
        # Vowel okurigana (e.g., あu -> あう)
        'a': ['あ'], 'i': ['い'], 'u': ['う'], 'e': ['え'], 'o': ['お'],
    }
    endings = CONSONANT_TO_HIRAGANA.get(okurigana_consonant, [])
    return [hiragana_stem + ending for ending in endings]


def parse_skk_dict(filepath):
    """Parse SKK dictionary and extract hiragana keys from both sections."""
    in_okuri_ari = False
    in_okuri_nasi = False
    entries = []

    with codecs.open(filepath, 'r', 'euc-jp', errors='replace') as f:
        for line in f:
            line = line.strip()
            if line == ';; okuri-ari entries.':
                in_okuri_ari = True
                in_okuri_nasi = False
                continue
            if line == ';; okuri-nasi entries.':
                in_okuri_ari = False
                in_okuri_nasi = True
                continue
            if line.startswith(';;') or not line:
                continue

            # Extract the key (before the first space)
            parts = line.split(' ', 1)
            if not parts:
                continue
            key = parts[0]

            if in_okuri_nasi:
                # Only process pure hiragana keys
                if all('\u3041' <= c <= '\u309f' or c == 'ー' for c in key):
                    entries.append(key)
            elif in_okuri_ari:
                # Okuri-ari: key ends with a consonant letter (e.g., つまr)
                if len(key) >= 2 and key[-1].isascii() and key[-1].isalpha():
                    stem = key[:-1]
                    consonant = key[-1]
                    if all('\u3041' <= c <= '\u309f' or c == 'ー' for c in stem):
                        expanded = expand_okuri_ari(stem, consonant)
                        entries.extend(expanded)

    return entries


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} SKK-JISYO.S", file=sys.stderr)
        sys.exit(1)

    skk_file = sys.argv[1]
    entries = parse_skk_dict(skk_file)

    # Convert to romaji (including nn variants for ん)
    romaji_words = set()
    failed = 0
    for hiragana in entries:
        variants = hiragana_to_romaji_variants(hiragana)
        if variants:
            for v in variants:
                romaji_words.add(v)
        else:
            failed += 1

    print(f";; Converted {len(romaji_words)} words, {failed} skipped", file=sys.stderr)

    # Sort for deterministic output
    sorted_words = sorted(romaji_words)

    # Generate Elisp
    print(';;; mozc-modeless-romaji-words.el --- Japanese romaji words dictionary  -*- lexical-binding: t; -*-')
    print()
    print(';; This file is generated from SKK dictionary (SKK-JISYO.S).')
    print(';; Source: https://github.com/skk-dev/dict')
    print(';; SKK License: GPL-2.0-or-later')
    print(';; ')
    print(';; To regenerate:')
    print(f';;   python3 tools/skk-to-romaji.py SKK-JISYO.S > mozc-modeless-romaji-words.el')
    print()
    print(';;; Commentary:')
    print(';; This file contains a hash table of common Japanese words in romaji form,')
    print(';; used by mozc-modeless to validate romaji input and detect typos.')
    print(';;')
    print(f';; Total words: {len(sorted_words)}')
    print()
    print(';;; Code:')
    print()
    size = int(len(sorted_words) * 1.1)  # ~10% overhead for hash table
    print(f'(defconst mozc-modeless--romaji-words-hash')
    print(f'  (let ((ht (make-hash-table :test \'equal :size {size})))')
    for word in sorted_words:
        print(f'    (puthash "{word}" t ht)')
    print('    ht)')
    print('  "Hash table of Japanese words in romaji form for typo detection.")')
    print()
    print('(defun mozc-modeless--romaji-word-p (word)')
    print('  "Return non-nil if WORD is a known Japanese romaji word."')
    print('  (gethash (downcase word) mozc-modeless--romaji-words-hash))')
    print()
    print('(provide \'mozc-modeless-romaji-words)')
    print(';;; mozc-modeless-romaji-words.el ends here')


if __name__ == '__main__':
    main()
