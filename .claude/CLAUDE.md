# mozc-modeless.el 開発ガイド

mozc.el を利用した「モードレス」日本語入力を提供する Emacs Lisp パッケージ。

このファイルは開発用コンテキストとして、**現在の仕様**・**設計上の知見**・**開発ルール**をまとめる。
詳細な開発経緯は git 履歴と GitHub issue を参照すること（このファイルには時系列ログを蓄積しない）。

## コンセプト

通常は英数入力モードで動作し、必要な時だけ日本語変換を行う「モードレス」な入力方式。
IME の ON/OFF 切り替えが不要で、変換確定後は自動的に英数入力に戻る。

```
入力: "hello nihongo" + C-j
結果: "hello 日本語"   （自動的に英数モードに戻る）
```

## リポジトリ構成

| ファイル | 内容 |
|---------|------|
| `mozc-modeless.el` | 本体（単一ファイル） |
| `mozc-modeless-english-words.el` | 英単語辞書（SCOWL 由来・約3,679語・Public Domain）。アンビエント変換の英文検出用 |
| `mozc-modeless.recipe` | MELPA レシピ |
| `docs/mozc-el-internals.md` | mozc.el 内部構造の調査結果（ヘルパープロトコル・データ構造） |
| `docs/usage-flow.svg/.png` | 操作方法の図解（README に埋め込み） |
| `docs/reconvert-text-property.svg/.png` | 再変換の仕組み（text property）の図解 |

- 依存: mozc.el（`Package-Requires: ((emacs "29.0") (mozc "1.0"))`）
- 現在のバージョン: 0.10.0
- 有効化: `(global-mozc-modeless-mode 1)` またはバッファローカルに `(mozc-modeless-mode 1)`

## 現在の仕様

### 基本動作: 2段階 C-j（issue #34）

1. **新規変換**: ローマ字入力後に `C-j` → **第1候補で即確定**（候補ウィンドウは出ない）。
   確定テキストには読み（ローマ字）が text property `mozc-modeless-reading` として埋め込まれる。
2. **再変換**: 変換済みテキストの直後で `C-j` → 記録された読みを再生して mozc.el の候補ウィンドウを開く。
   `C-n`/`C-p` で候補選択、`RET` で確定、`C-g` で元のテキストを復元。
   確定後は新しいテキストに読みが付け直されるので、何度でも再変換できる。

`mozc-modeless-convert`（C-j）のディスパッチは4分岐:

1. `lisp-interaction-mode` で直前が `)` → `eval-print-last-sexp`（issue #10）
2. 変換中（候補ウィンドウ表示中） → 次候補へ
3. 直前が**非 ASCII 文字**かつ `mozc-modeless-reading` property あり → 再変換
4. それ以外 → 直前のローマ字を新規変換（即確定）

再変換の発火条件を「直前が非 ASCII（日本語）」に限定しているのは安全弁
（直前が英数字なら、property が継承されていても常に新規変換を優先する）。

### 変換対象の検出

`mozc-modeless--get-preceding-roman` がカーソル直前の変換対象を検出する:

- `mozc-modeless-skip-chars` に含まれる文字を後方スキャン（英数字＋一部記号）
- **行頭インデント**（空白・タブ）は変換対象から除外。全モードで有効（issue #6）
- **markdown 構文**（リスト記号 `-` `*` `+` `1.`、見出し `#`）を除外。
  markdown-mode では `markdown-regex-list` を利用、text-mode / fundamental-mode では独自正規表現（issue #5）
- **スラッシュフェンス**: 文字列に `/` が含まれる場合、最後の `/` より後だけを変換し、`/` 自体は削除する。
  例: `日本語/ga` + C-j → `日本語が`

### 変換中のキーバインド（`mozc-modeless--converting-map`）

| キー | 動作 | 実装方式 |
|------|------|---------|
| `C-j` / `SPC` | 次候補 | |
| `C-n` | 次候補 | **下矢印キーに変換して送信**（後述の知見参照） |
| `C-p` | 前候補 | 上矢印キーに変換して送信 |
| `C-f` | 次の文節へ | 右矢印キーに変換して送信 |
| `C-b` | 前の文節へ | 左矢印キーに変換して送信 |
| `RET` | 確定 | |
| `C-g` | キャンセル（元の文字列を復元） | |

このキーマップは `set-transient-map` で変換中のみ有効（issue #13）。
状態が壊れた場合の復旧用コマンドとして `mozc-modeless-reset` がある。

### アンビエント変換（issue #20）

助詞＋スペースや句読点の入力をトリガーに自動変換する。**デフォルトで有効**。

- **助詞トリガー**: `mozc-modeless-ambient-particles` の助詞（"wa" "ga" "ni" 等）で終わる
  ローマ字の後にスペースを打つと自動変換＋第1候補で自動確定
- **句読点トリガー**: `.` `,` `?` の入力で自動変換し、全角句読点（`。` `、` `？`）を挿入。
  `mozc-modeless-ambient-punctuation-delay`（デフォルト 0.5 秒）のタイマー遅延があり、
  その間に他のキー入力があると発火しない。
  `mozc-modeless-ambient-punctuation-auto-confirm` を nil にすると自動確定せず候補選択できる
- **英文検出**: 直前テキストの英単語率が `mozc-modeless-ambient-english-threshold`
  （デフォルト 0.8）以上ならスキップ。SCOWL 辞書＋短単語リスト＋固有名詞（大文字始まり）で判定
- **除外条件**: `mozc-modeless-ambient-exclude-modes`（shell-mode 等）、ミニバッファ、変換中
- トリガーは `post-self-insert-hook`（バッファローカル）の `mozc-modeless--check-ambient-trigger`

アンビエント変換で確定したテキストにも読みが付き、C-j で再変換できる。

### カスタマイズ変数

| 変数 | デフォルト | 意味 |
|------|-----------|------|
| `mozc-modeless-convert-key` | `C-j` | 変換トリガーキー |
| `mozc-modeless-ambient-enable` | `t` | アンビエント変換の有効/無効 |
| `mozc-modeless-ambient-particles` | wa/ha/ga/wo/ni/de/to/kara/made/he/mo/no/ya/desu | 助詞トリガー |
| `mozc-modeless-ambient-punctuation` | `("." "," "?")` | 句読点トリガー |
| `mozc-modeless-ambient-punctuation-delay` | `0.5` | 句読点トリガーの遅延秒数 |
| `mozc-modeless-ambient-punctuation-auto-confirm` | `t` | 句読点トリガーの自動確定 |
| `mozc-modeless-ambient-english-threshold` | `0.8` | 英文判定の閾値 |
| `mozc-modeless-ambient-exclude-modes` | shell/term/eshell | アンビエント除外モード |

## 開発コマンド

### リント／構文チェック

Emacs Lisp ファイルを編集した後は、**必ず**括弧バランスチェックツールを実行すること:

```bash
agent-lisp-paren-aid-linux mozc-modeless.el
```

### リリース前チェック

MELPA 品質基準を満たすため、以下をすべて警告なしで通すこと:

```bash
emacs --batch -f batch-byte-compile mozc-modeless.el   # バイトコンパイル
# checkdoc（docstring チェック）
# package-lint（パッケージ規約チェック）
```

- 関数名のクォートは `#'function-name`（sharp-quote）を使う
- docstring 内の Lisp シンボルは `` `symbol-name' `` 形式でクォートする
- `Package-Requires` の依存にはバージョンを明記する（日付ベースの snapshot version は警告になるため `"1.0"` 形式）

## 設計上の知見・制約

### mozc.el / mozc サーバーの構造（詳細: docs/mozc-el-internals.md）

- 3層構成: mozc.el ⇄ `mozc_emacs_helper`（S式⇔protobuf ブリッジ）⇄ `mozc_server`（変換エンジン）
- ヘルパーがサポートするコマンドは `CreateSession` / `DeleteSession` / `SendKey` の**3つのみ**。
  候補 id 直接選択（`SELECT_CANDIDATE`）や再変換（`CONVERT_REVERSE`）に必要な `SEND_COMMAND` は未実装
- サーバー応答 `Output` には候補リスト（`candidate-window`, `all-candidate-words`）が含まれるが、
  mozc.el は候補リストを永続保持しない
- → 候補リストの「取得」は SendKey だけで可能。id 直接選択・任意テキストの再変換にはヘルパー拡張が必要

### キーイベントの扱い

- mozc へのキー送信は `unread-command-events` 経由。mozc-mode-map は `[t]`（全キー）を
  `mozc-handle-event` にバインドし、サーバーが `consumed=false` を返したキーは Emacs 側にフォールバック
- **`C-n` は mozc サーバー側で特別な意味（確定動作）を持つ**。そのまま送ると
  C-p → C-n の操作で意図せず確定してしまうため、変換中の `C-n`/`C-p`/`C-f`/`C-b` は
  矢印キーのシンボル（`down`/`up`/`right`/`left`）に変換して送信する
- 新規変換の即確定は「ローマ字＋スペース＋Enter」を `unread-command-events` に送る方式
  （preedit 消失を `post-command-hook` で検知してクリーンアップ）

### text property による読みの記録

- `mozc-modeless--tag-reading` は `mozc-modeless-reading` と同時に **`rear-nonsticky` を必ず付与**する。
  text property はデフォルトで rear-sticky のため、これがないと変換確定テキストの直後に打った
  文字が読みを継承し、次の C-j で前の変換結果ごと巻き込まれるバグになる（実機で発生済み）
- 読み property はバッファ内のみで永続化されない（ファイル保存では消える）

### 失敗した実験（再挑戦しないこと）

- **リージョン選択した文字列を mozc に渡す再変換**（2025-12）:
  `listify-key-sequence` でリージョン文字列をイベント化して `unread-command-events` に送る方式は、
  マルチバイト文字（日本語）を正しく処理できず全ケース失敗。ロールバック済み。
  既存日本語の再変換を実現するなら `CONVERT_REVERSE`（`SEND_COMMAND`）対応のヘルパー拡張が必要

## 開発履歴（要約）

詳細は各 issue / PR と git 履歴を参照。

| Issue | 内容 |
|-------|------|
| #5 | markdown 構文（リスト記号・見出し）を変換対象から除外 |
| #6 | 行頭インデントを変換対象から除外（全モード） |
| #10 | lisp-interaction-mode で直前が `)` なら S式評価 |
| #13 | 変換中の `C-n`/`C-p`/`C-f`/`C-b` キーバインド（矢印キー変換方式） |
| #20 | アンビエント変換（助詞＋スペース / 句読点トリガー、英文検出） |
| #34 | 2段階 C-j: 即確定＋text property による再変換（PR #37） |

## MELPA

- 登録 PR: https://github.com/melpa/melpa/pull/9963 （2026-04-23 レビュー指摘対応済み、レビュー待ち）
- レシピはデフォルト形式: `(mozc-modeless :fetcher github :repo "kiyoka/mozc-modeless-emacs")`
  （`:fetcher` を `:repo` より前に書く。`:files` はデフォルトで `*.el` が入るため省略）

## 残課題

- README の C-j 挙動説明が旧仕様（C-j で即候補ウィンドウ）のまま。2段階 C-j に合わせて更新が必要
- 即確定の自動処理中（`mozc-modeless--ambient-in-progress`）の C-j 連打は未ガード
- 読み property のない既存日本語（ファイルから開いたテキスト等）の再変換は未対応
  （`CONVERT_REVERSE` ヘルパー拡張が必要。docs/mozc-el-internals.md 6.2/6.3 参照）
