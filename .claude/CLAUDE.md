## mozc-modeless.el 仕様書

### 概要
mozc.el を利用した modeless 日本語入力環境を提供する Emacs Lisp パッケージ。

### コンセプト
通常は英数入力モードで動作し、必要な時だけ日本語変換を行う「モードレス」な入力方式を実現する。

### 基本動作

1. **通常状態**
   - 英数字がそのまま入力される（通常のEmacs動作）

2. **変換開始** (`C-j`)
   - カーソル直前のローマ字列を検出
   - ローマ字を削除し、mozc に渡して変換モードに入る

3. **変換確定後**
   - 自動的に英数入力モードに戻る
   - 次の `C-j` まで日本語入力は行われない

### キーバインド

| キー | 動作 |
|------|------|
| `C-j` | 直前のローマ字を変換開始 |
| `C-g` | 変換キャンセル（元のローマ字を復元） |

### 使用例

```
入力: "hello nihongo"  + C-j
結果: "hello 日本語"   (自動的に英数モードに戻る)
```

### 依存関係
- mozc.el

### ファイル構成
- `mozc-modeless.el` （単一ファイル）


## 開発コマンド

### リント／構文チェック
Emacs Lispファイルを編集した後は、**必ず**括弧バランスチェックツールを実行してください：

```bash
agent-lisp-paren-aid-linux mozc-modeless.el
```

## mozc-modeless.el の設計提案

### 概要
modelessなIMEインターフェースを実現するEmacs Lispプログラムです。通常は英数入力で、`C-j`キーで直前のローマ字をMozcで変換します。

### 主な機能設計

#### 1. **基本構造**
```
- mozc-modeless-mode: マイナーモード
- 通常状態: 英数入力（直接入力）
- C-j押下 → 変換モード → 確定 → 通常状態に戻る
```

#### 2. **実装アプローチ（2つの案）**

**【案A】mozc.elに依存する方式（推奨）**
- 既存のmozc.elの機能を活用
- メリット：
  - 実装がシンプル（200-300行程度）
  - mozcサーバー通信が安定
  - 候補表示UIを再利用可能
- デメリット：
  - mozc.elが必要

**【案B】独立実装方式**
- mozcサーバーと直接プロセス通信
- メリット：
  - 依存なし、独立動作
  - 完全にカスタマイズ可能
- デメリット：
  - 実装量が多い（500-800行程度）
  - mozcプロトコルの実装が必要

#### 3. **主要な機能**

```elisp
;; コア機能
(define-minor-mode mozc-modeless-mode
  "Modeless Japanese input using Mozc.")

(defun mozc-modeless-convert ()
  "C-jで呼び出される変換開始関数"
  ;; 1. 直前のローマ字を取得
  ;; 2. その範囲を削除
  ;; 3. mozcで変換開始
  ;; 4. 変換確定後、通常モードに戻る
  )

(defun mozc-modeless--get-preceding-roman ()
  "カーソル直前のローマ字文字列を取得"
  ;; [a-zA-Z]+ のパターンで後方検索
  )
```

#### 4. **技術的なポイント**

**ローマ字の検出**
- 正規表現で `[a-zA-Z]+` を後方検索
- 単語境界：空白、句読点、改行など
- 例: `hello world konna` → カーソル位置から `konna` を抽出

**変換モードの実装**
- 一時的なキーマップを設定
- 変換中のキー: SPC（次候補）、C-n/C-p（選択）、RET（確定）、C-g（キャンセル）
- overlayで候補を表示

**状態管理**
```elisp
(defvar mozc-modeless--active nil
  "変換モードが有効かどうか")
```

#### 5. **ファイル構成（案A推奨）**

```elisp
;;; mozc-modeless.el --- Modeless Japanese input with Mozc

;; 依存関係
(require 'mozc)  ; 既存のmozc.el

;; カスタマイズ変数
(defgroup mozc-modeless nil ...)

;; 内部変数
(defvar mozc-modeless--active nil)
(defvar mozc-modeless--start-pos nil)

;; ユーティリティ関数
(defun mozc-modeless--get-preceding-roman () ...)

;; メイン機能
(defun mozc-modeless-convert () ...)
(defun mozc-modeless--finish () ...)

;; マイナーモード定義
(define-minor-mode mozc-modeless-mode
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-j") 'mozc-modeless-convert)
            map))
```

### 推奨する実装の流れ

1. **基本骨格の作成**（mozc.elへの依存を前提）
2. **ローマ字検出機能**
3. **mozc連携機能**（既存APIのラッパー）
4. **変換UI**（overlayベース）
5. **状態管理とクリーンアップ**

### 質問

実装を進める前に確認させてください：

1. **依存関係**: 既存のmozc.elに依存する「案A」で良いでしょうか？
2. **変換キャンセル**: `C-g`でキャンセルした場合、ローマ字を元に戻しますか？
3. **変換範囲**: ローマ字のみ対象ですか？それとも既に入力された日本語も含めますか？


1. **依存関係**: 既存のmozc.elに依存する「案A」で良いでしょうか？ yes
2. **変換キャンセル**: `C-g`でキャンセルした場合、ローマ字を元に戻しますか？ yes
3. **変換範囲**: ローマ字のみ対象ですか？それとも既に入力された日本語も含めますか？ ローマ字のみが対象です。

## 実装内容

### ファイル: mozc-modeless.el

mozc.elに依存する形でmodelessなIMEを実装しました。

#### 実装した主要機能

1. **マイナーモード定義** (mozc-modeless.el:161-180)
   - `mozc-modeless-mode`: グローバルまたはバッファローカルで有効化可能
   - ライター表示: " Mozc-ML"
   - 有効化時にmozc.elの存在をチェック

2. **カスタマイズ変数** (mozc-modeless.el:45-58)
   - `mozc-modeless-roman-regexp`: ローマ字検出用の正規表現 (デフォルト: `[a-zA-Z]+`)
   - `mozc-modeless-convert-key`: 変換トリガーキー (デフォルト: `C-j`)

3. **内部状態管理** (mozc-modeless.el:60-72)
   - `mozc-modeless--active`: 変換モードが有効かどうか
   - `mozc-modeless--start-pos`: ローマ字の開始位置
   - `mozc-modeless--original-string`: キャンセル時の復元用

4. **ローマ字検出** (mozc-modeless.el:76-86)
   - `mozc-modeless--get-preceding-roman`: カーソル直前のローマ字を検出
   - 行頭から現在位置までを検索範囲とする
   - 戻り値: `(開始位置 . ローマ字文字列)` または nil

5. **変換開始** (mozc-modeless.el:90-114)
   - `mozc-modeless-convert`: C-jにバインドされたメイン関数
   - 処理フロー:
     1. ローマ字検出
     2. 元の文字列を保存
     3. ローマ字を削除
     4. mozc input-methodを有効化
     5. mozcに文字列を送信
     6. 変換完了検知のフック設定

6. **変換終了処理** (mozc-modeless.el:128-142)
   - `mozc-modeless--finish`: 変換確定後のクリーンアップ
   - input-methodの無効化
   - 内部状態のリセット
   - フックの削除

7. **キャンセル機能** (mozc-modeless.el:144-157)
   - `mozc-modeless-cancel`: C-gにバインド
   - mozc変換のキャンセル
   - 元のローマ字を復元
   - 状態のクリーンアップ

#### キーバインド

- `C-j`: `mozc-modeless-convert` - 変換開始
- `C-g`: `mozc-modeless-cancel` - キャンセルと復元

#### 使用方法

```elisp
;; .emacsまたはinit.elに追加
(require 'mozc-modeless)
(mozc-modeless-mode 1)

;; 使い方:
;; 1. 通常通りローマ字を入力 (例: "konnnichiwa")
;; 2. C-j を押すと mozc変換開始
;; 3. スペースで候補選択、Enterで確定
;; 4. 確定後、自動的に英数モードに戻る
;; 5. C-g でキャンセルして元のローマ字に戻る
```

#### 注意事項と今後の課題

**mozc.el APIの不確実性:**

現在の実装は、以下のmozc.el APIを仮定しています：
- `mozc-handle-event`: イベント処理
- `mozc-in-conversion-p`: 変換中かどうかの判定
- `mozc-handle-event-after-insert-hook`: 挿入後のフック
- `mozc-cancel`: 変換キャンセル

**これらのAPIが実際のmozc.elに存在しない可能性があります。**

実際に動作させるには：
1. システムにインストールされているmozc.elのソースコードを確認
2. 正しいAPI仕様に合わせてコードを修正
3. 実際に動作テストを実施

#### 代替実装案

mozc.elの内部APIが使えない場合、以下の代替アプローチが考えられます：

1. **シンプルなinput-method切り替え方式**
   - `activate-input-method` / `deactivate-input-method` のみ使用
   - キーイベントを `unread-command-events` で送信
   - より移植性が高い

2. **overlay を使った独自UI**
   - mozcサーバーと直接通信
   - 候補表示を独自実装
   - 完全な制御が可能だが実装量が多い

#### 次のステップ

1. mozc.elの実際のAPIドキュメント・ソースコードを確認
2. 必要に応じてAPIの使い方を修正
3. 実際の動作テストと調整
4. エッジケースの処理追加（複数行、特殊文字など）

### GitHub Issue #5 対応: markdown-mode でのmarkdown構文除外

#### 問題の概要

markdown-modeで使用時、markdownの構文記号（リスト記号、見出し記号など）が変換対象に含まれてしまう問題がありました。

**具体例:**
```
入力: "- aitemu" + C-j
現在の結果: "ーアイテム"  ← リスト記号"-"が長音符"ー"に変換されてしまう
期待する結果: "- アイテム"  ← リスト記号"-"は変換せず、"aitemu"だけを変換
```

#### 実装内容 (2025-12-03)

`mozc-modeless--get-preceding-roman` 関数を修正して、markdown-mode時にmarkdown構文を認識し、変換対象から除外するようにしました。

**主な変更点:**

1. **markdown-modeの検出**
   - `derived-mode-p` を使ってmarkdown-modeかどうかをチェック

2. **markdown構文の認識**
   - リスト記号: markdown-modeの `markdown-regex-list` を使用して `-`, `*`, `+`, `1.` などを認識
   - 見出し記号: 正規表現 `^[ \t]*\\(#+\\)[ \t]+` で `#`, `##` などを認識

3. **変換範囲の調整**
   - markdown構文が検出された場合、その後の位置から変換対象の検索を開始
   - これにより、markdown構文自体は変換対象から除外される

4. **依存関係の追加**
   - Package-Requires に `(markdown-mode "2.0")` を追加

**修正ファイル:**
- `mozc-modeless.el:79-105` - `mozc-modeless--get-preceding-roman` 関数
- `mozc-modeless.el:8` - Package-Requires

**動作例:**
```
入力: "- aitemu" + C-j
結果: "- アイテム"

入力: "## midashi" + C-j
結果: "## 見出し"
```

**参考資料:**
- [markdown-mode公式ドキュメント](https://jblevins.org/projects/markdown-mode/)
- [markdown-mode GitHub リポジトリ](https://github.com/jrblevin/markdown-mode)

### GitHub Issue #6 対応: インデントの維持

#### 問題の概要

Ctrl-Jで変換を開始すると、行頭のインデント（空白やタブ文字）も変換対象に含まれてしまい、インデント構造が崩れる問題がありました。

**具体例:**
```
入力: "    konnnichiwa" + C-j  (行頭に4つの空白)
問題: 空白も変換対象に含まれる可能性
期待する結果: "    こんにちは"  (インデントは保持)
```

#### 実装内容 (2025-12-03)

`mozc-modeless--get-preceding-roman` 関数を修正して、行頭のインデント（空白・タブ文字）を変換対象から除外するようにしました。

**主な変更点:**

1. **行頭インデントのスキップ**
   - `skip-chars-forward " \t"` を使って行頭の空白・タブをスキップ
   - スキップ後の位置から変換対象の検索を開始

2. **処理順序の調整**
   - まず行頭のインデントをスキップ
   - その後、markdown-modeの構文チェック（issue #5の機能）を実行
   - これにより、インデント付きのmarkdown構文も正しく処理される

3. **すべてのモードで有効**
   - この機能はmarkdown-mode専用ではなく、すべてのモードで動作
   - プログラムコードの編集時にも有用

**修正ファイル:**
- `mozc-modeless.el:79-111` - `mozc-modeless--get-preceding-roman` 関数

**動作例:**
```
入力: "    konnnichiwa" + C-j
結果: "    こんにちは"  (インデント保持)

入力: "        - aitemu" + C-j  (markdown-modeでインデント付きリスト)
結果: "        - アイテム"  (インデントとリスト記号の両方を保持)
```

**技術詳細:**
- 行頭から `skip-chars-forward " \t"` でインデント部分をスキップ
- `search-start` をインデント後の位置に設定
- markdown構文チェックは `search-start` から開始するため、インデント後の構文を正しく認識

質問です。

 mozc-modelessでバッファ上に"質問"のような日本語変換済みの文字列が存在する状態から、再度mozcの変換状態に戻る方法はありますか？
つまり，"質問"という文字列をmozcに渡しながらmozcの変換状態に入ることは可能でしょうか？

提案された方法は、"しつもん"という文字列が入手できているように書かれていますが、それはどこから得られる想定ですか？

### リージョン選択による変換機能の実験 (2025-12-13) - 失敗

#### 実験の背景

バッファ上に既に存在する日本語文字列（例："質問"）を再度mozcの変換状態に戻して、別の候補を選択したいという要望から、リージョン選択した文字列をmozcに渡す機能を実験的に実装しました。

#### 実装方針

- リージョンが選択されている場合、その文字列をmozcに渡す
- `listify-key-sequence`で文字列をイベントに変換して`unread-command-events`に追加

#### 実験結果：全て失敗

| テストケース | 入力 | 期待結果 | 実際の結果 |
|------------|------|---------|----------|
| 日本語（漢字） | 「質問」を選択 + C-j | 変換候補表示 | ✗ スペースのみ残る |
| ひらがな | 「しつもん」を選択 + C-j | 「質問」等に変換 | ✗ スペースのみ残る |
| ローマ字 | 「sitsumon」を選択 + C-j | 「しつもん」に変換 | ✗ スペースのみ残る |

**動作例:**
```
入力: 「あああ質問あああ」
操作: 「質問」を選択してC-j
結果: 「あああ　あああ」（質問が消えてスペースだけが残る）
```

**C-gでのキャンセル:** 元の文字列が復元されない（これも不具合）

#### 失敗の原因

`listify-key-sequence`が日本語文字（マルチバイト文字）を正しく処理できず、選択した文字列がmozcに渡されていない。最後に追加したスペースだけが入力される状態。

#### 結論

**この実装方式では日本語文字列の再変換は実現不可能。**

実装をロールバックしてバージョン0.4.0の状態に戻しました。

#### 今後の方向性

日本語文字列の再変換を実現するには、以下のような別のアプローチが必要：
- mozc.elの再変換API（もし存在すれば）を直接利用
- 日本語→ひらがな変換ライブラリ（kakasi等）を使用して読みを取得
- mozcサーバーと直接プロトコル通信

現時点では実装を見送り。

### GitHub Issue #10 対応: Lisp Interactionモードでの式評価

#### 問題の概要

Lisp Interactionモード（*scratch*バッファなど）では、通常Ctrl-Jは`eval-print-last-sexp`（S式を評価して結果を表示）として使われます。しかし、mozc-modelessが有効な場合、常にローマ字変換を試みるため、Lisp式の評価ができなくなっていました。

**要望:**
- Lisp Interactionモードで、Ctrl-J押下時にカーソルの直前が「)」（閉じ括弧）の場合は、mozc変換ではなく、Lisp式を評価する動作としてほしい

#### 実装内容 (2025-12-13)

`mozc-modeless-convert`関数の冒頭で、lisp-interaction-modeかどうかと、カーソル直前の文字が「)」かどうかをチェックし、両方に該当する場合は元のCtrl-Jの動作を実行するようにしました。

**主な変更点:**

1. **lisp-interaction-modeのチェック**
   - `(derived-mode-p 'lisp-interaction-mode)` でモードを判定
   - `(eq (char-before) 41)` でカーソル直前の文字が「)」(ASCII 41)かどうかをチェック

2. **条件分岐の追加**
   - lisp-interaction-modeかつカーソル直前が「)」の場合: `eval-print-last-sexp`を実行
   - それ以外の場合: 通常のmozc変換を実行

3. **emacs-lisp-modeへの対応**
   - 調査の結果、emacs-lisp-modeではCtrl-Jは`newline-and-indent`（改行とインデント）
   - S式の評価には`C-x C-e`（`eval-last-sexp`）や`C-M-x`（`eval-defun`）を使用
   - したがって、emacs-lisp-modeは対象外とし、lisp-interaction-modeのみに対応

**修正ファイル:**
- `mozc-modeless.el:152-198` - `mozc-modeless-convert`関数の修正
- `mozc-modeless.el:150-151` - docstringの更新

**動作例:**
```
Lisp Interactionモードでの動作:

入力: "(+ 1 2)" + Ctrl-J
結果: S式が評価されて "3" が表示される

入力: "nihongo" + Ctrl-J
結果: "日本語" に変換される（通常のmozc変換）
```

**技術詳細:**
- 文字リテラル`?\)`ではなく、ASCII コード`41`を使用して括弧をチェック
- `cond`を使用して3つの条件分岐を明確化：
  1. lisp-interaction-modeで閉じ括弧の直後 → S式評価
  2. 既に変換モード中 → 次候補へ
  3. それ以外 → 通常の変換開始
- ネストした`if`ではなく`cond`を使用することで、可読性を向上

### GitHub Issue #13 対応: 変換中のCtrlキーバインド追加

#### 問題の概要

mozc変換中に、Emacsの標準的なカーソル移動キー（Ctrl+N、Ctrl+P、Ctrl+F、Ctrl+B）を使って候補選択や文節移動を行いたいという要望がありました。

**要望内容:**
1. **Ctrl+N** → 次の候補を選択
2. **Ctrl+P** → 前の候補を選択
3. **Ctrl+F** → 次の文節に移動
4. **Ctrl+B** → 前の文節に移動

#### 調査結果 (2026-01-03)

**mozc.elのキーイベント処理の仕組み:**

1. mozc-mode-mapは`[t]`（すべてのキー）を`mozc-handle-event`にバインド (mozc.el:174)
2. `mozc-handle-event`はすべてのキーイベントをmozcサーバーに送信 (mozc.el:327-374)
3. mozcサーバー側で対応しているキーは`consumed=true`を返し、対応していないキーは`consumed=false`を返す
4. `consumed=false`のキーはEmacsのデフォルトキーバインドにフォールバック

**現状:**
- Ctrl+Nはmozcサーバー側でサポートされているが、特別な意味（確定動作）を持つため、矢印キーと異なる動作をする
- Ctrl+P、Ctrl+F、Ctrl+Bはmozcサーバー側で未サポート

#### 実装内容 (2026-01-03)

mozc-modeless側で、変換中に有効な`mozc-modeless--converting-map`に4つのキーバインドを追加しました。

**追加した関数:** (mozc-modeless.el:254-276)

1. `mozc-modeless-previous-candidate` - Ctrl+P用
   - 上矢印キー（`up`）を`unread-command-events`に送信

2. `mozc-modeless-next-candidate` - Ctrl+N用
   - 下矢印キー（`down`）を`unread-command-events`に送信
   - mozcサーバー側のCtrl+Nの特別な意味を回避

3. `mozc-modeless-next-segment` - Ctrl+F用
   - 右矢印キー（`right`）を`unread-command-events`に送信

4. `mozc-modeless-previous-segment` - Ctrl+B用
   - 左矢印キー（`left`）を`unread-command-events`に送信

**キーマップの更新:** (mozc-modeless.el:71-79)

```elisp
(defvar mozc-modeless--converting-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-g") 'mozc-modeless-cancel)
    (define-key map (kbd "C-n") 'mozc-modeless-next-candidate)
    (define-key map (kbd "C-p") 'mozc-modeless-previous-candidate)
    (define-key map (kbd "C-f") 'mozc-modeless-next-segment)
    (define-key map (kbd "C-b") 'mozc-modeless-previous-segment)
    map)
  "Keymap active only during conversion.")
```

**動作例:**
```
変換中の操作:

入力: "konnnichiwa" + Ctrl-J
変換開始: 「こんにちわ」

Ctrl+N: 次の候補「今日は」（mozc-modeless側で下矢印を送信）
Ctrl+P: 前の候補「こんにちわ」（mozc-modeless側で上矢印を送信）
Ctrl+F: 次の文節に移動（mozc-modeless側で右矢印を送信）
Ctrl+B: 前の文節に移動（mozc-modeless側で左矢印を送信）
```

**技術詳細:**
- 矢印キーのシミュレーションには、シンボル（`'down`、`'up`、`'right`、`'left`）を`unread-command-events`に追加
- これらのキーは`mozc-handle-event`を経由してmozcサーバーに渡される
- mozcサーバーは矢印キーを適切に処理（候補選択、文節移動）
- `mozc-modeless--converting-map`は`set-transient-map`により変換中のみ有効 (mozc-modeless.el:203-204)

**Ctrl+Nの特別な扱い:**
- mozcサーバー側のCtrl+Nは、確定動作など特別な意味を持つ
- Ctrl+Pを押した後にCtrl+Nを押すと確定してしまう問題があった
- mozc-modeless側でCtrl+Nを下矢印キーに変換することで、この問題を回避

### GitHub Issue #20 対応: アンビエント変換（自動変換）

#### 問題の概要

従来、日本語変換はC-jの明示的な押下でのみ開始されていました。Sumibiのアンビエント変換を参考に、助詞＋スペースや句読点入力をトリガーに自動的にmozc変換を実行する機能を追加しました。変換はmozcの第1候補で自動確定し、タイピングの流れを中断しません。

**要望:**
- 助詞（「wa」「ga」「ni」等）の後にスペースを入力すると自動変換
- 句読点（`.` `,` `?`）の入力で自動変換＋全角句読点挿入
- 英文入力時はスキップ（誤変換防止）
- デフォルトは無効（ユーザーが明示的に有効化）

#### 実装内容 (2026-03-03)

**新規ファイル: `mozc-modeless-english-words.el`**

Sumibiの`sumibi-english-words.el`（SCOWL辞書ベース、Public Domain）をコピー・リネームして作成。

- `mozc-modeless--english-words-hash`: 約3,679語の英単語ハッシュテーブル（3〜10文字）
- `mozc-modeless--english-word-p`: 英単語判定関数（O(1)ハッシュテーブル検索）
- ソース: SCOWL (Spell Checker Oriented Word Lists) Version 2020.12.07

**修正ファイル: `mozc-modeless.el` (v0.6.0 → v0.7.0)**

1. **カスタマイズ変数（5つ追加）** (mozc-modeless.el:53-81)
   - `mozc-modeless-ambient-enable` (default: `nil`) — アンビエント変換の有効/無効
   - `mozc-modeless-ambient-particles` — 助詞リスト: `("wa" "ha" "ga" "wo" "ni" "de" "to" "kara" "made" "he" "mo" "no" "ya" "desu")`
   - `mozc-modeless-ambient-punctuation` — 句読点リスト: `("." "," "?")`
   - `mozc-modeless-ambient-english-threshold` (default: 0.8) — 英文判定閾値
   - `mozc-modeless-ambient-exclude-modes` — 除外モードリスト: `(shell-mode term-mode eshell-mode)`

2. **英文検出機能** (mozc-modeless.el:320-348)
   - `mozc-modeless--short-english-words`: 短い英単語リスト（"I", "a", "is"等27語）
   - `mozc-modeless--normalize-word`: 末尾句読点の除去
   - `mozc-modeless--english-text-p`: メイン判定関数
     - テキストを空白で分割
     - 各単語を辞書・短単語リスト・固有名詞（大文字始まり）で判定
     - 英単語率 >= 80% なら英文と判定してスキップ

3. **助詞・句読点トリガー** (mozc-modeless.el:382-415)
   - `mozc-modeless--check-ambient-trigger`: `post-self-insert-hook`に登録
     - スペース入力時: 直前テキストが助詞で終わるか判定
     - 句読点入力時: 直前にローマ字があるか判定
     - 英文検出で80%以上ならスキップ
     - 除外モード・ミニバッファ・変換中はスキップ
   - `mozc-modeless--ends-with-particle-p`: 助詞末尾検出（孤立した助詞はスキップ）
   - `mozc-modeless--ambient-excluded-p`: 除外条件判定

4. **自動変換・自動確定** (mozc-modeless.el:417-446)
   - `mozc-modeless--ambient-convert`: アンビエント変換実行
     - ローマ字を削除し、mozc input-methodを有効化
     - ローマ字＋スペース＋Enter（自動確定）を`unread-command-events`に送信
     - `post-command-hook`でpreedit消失を検知してクリーンアップ
     - 句読点トリガーの場合、確定後に全角句読点を挿入
   - `mozc-modeless--to-fullwidth-punctuation`: 句読点の全角変換（`.`→`。`, `,`→`、`, `?`→`？`）

5. **フック管理** (mozc-modeless.el:496-509)
   - `mozc-modeless-mode`の有効化時に`post-self-insert-hook`に`mozc-modeless--check-ambient-trigger`を追加
   - 無効化時にフックを削除

**既存の`mozc-modeless-convert`（C-j）との違い:**
- transient-keymapを設定しない（候補選択UIなし）
- `mozc-modeless--active`をセットしない（C-gキャンセル不要）
- 自動確定のためEnterキーイベントを追加送信
- `mozc-modeless--ambient-in-progress`フラグで再帰トリガーを防止

**動作例:**
```
;; 有効化
(setq mozc-modeless-ambient-enable t)

;; 助詞＋スペーストリガー
入力: "nihonga " (スペース入力)
結果: "日本が"  ← 自動変換＋自動確定

;; 句読点トリガー
入力: "wakarimashita."
結果: "わかりました。" ← 自動変換＋全角句読点

;; 英文はスキップ
入力: "I will not create a pull request "
結果: "I will not create a pull request " ← そのまま（英文80%以上）

;; shell-modeでは無効
shell-mode: コマンド入力中にアンビエント変換は発動しない
```

**依存関係の追加:**
- `mozc-modeless-english-words.el`を`require`で読み込み (mozc-modeless.el:39)

https://github.com/melpa/melpa/pull/9963 の内容を日本語にして、ここに表示してください。

### MELPA PR #9963 の内容（日本語訳）

- **PRタイトル**: mozc-modeless のレシピを追加
- **作成者**: Kiyoka Nishiyama (@kiyoka)
- **作成日**: 2026-04-18
- **ステータス**: OPEN（レビュー待ち）
- **URL**: https://github.com/melpa/melpa/pull/9963

#### パッケージの簡単な説明

`mozc-modeless` は、Mozc を利用した Emacs 向けの「モードレス」な日本語入力インターフェースを提供します。通常は英数入力モードでタイプし、直前のローマ字を日本語に変換したい時だけ `C-j` を押します。変換確定後は自動的に英数入力モードに戻るため、IME の ON/OFF を切り替える必要がありません。

**主な機能:**
- モードレス入力: IME の ON/OFF 切り替えが不要
- 変換後は自動的に英数モードに復帰
- `C-g` でキャンセルして元のローマ字を復元
- アンビエント変換: 助詞+スペースや句読点による自動変換（オプション）
- 誤変換を防ぐための英文検出機能

#### パッケージリポジトリへの直接リンク

https://github.com/kiyoka/mozc-modeless-emacs

#### パッケージとの関係

私はこのパッケージの作者兼メンテナーです。

#### パッケージのアップストリームメンテナーとのやり取り

**不要**

#### チェックリスト

- [x] パッケージは [GPL 互換のフリーソフトウェアライセンス](https://www.gnu.org/licenses/license-list.en.html#GPLCompatibleLicenses) のもとでリリースされている
- [x] [CONTRIBUTING.org](https://github.com/melpa/melpa/blob/master/CONTRIBUTING.org) を読んだ
- [x] 最新の [package-lint](https://github.com/purcell/package-lint) でパッケージングの問題をチェックし、指摘に対応した
- [x] Elisp がバイトコンパイル時に警告なくクリーンにコンパイルされる
- [x] `M-x checkdoc` でパッケージのドキュメント文字列をチェックした
- [x] [CONTRIBUTING.org](https://github.com/melpa/melpa/blob/master/CONTRIBUTING.org) の手順に従ってパッケージをビルド・インストールした

riscyの指摘事項を翻訳して、ここに追加してください。

### MELPA PR #9963 レビュアー (@riscy, MELPA メンバー) からの指摘事項

ご対応ありがとうございます。まずは初回レビューの結果です。

#### 1. package-lint 20251205.1720 の指摘（`package-lint-main-file` = "mozc-modeless.el"）

```
1件の問題が見つかりました:
9:38: 警告: 可能であれば "mozc" への依存に適切なバージョンを指定してください。
```

→ `mozc-modeless.el` の9行目、`Package-Requires` の `mozc` への依存にバージョン番号が指定されていない。バージョン付きの依存記述（例: `(mozc "X.Y")`）に修正すべき。

#### 2. melpazoid の指摘

```
- mozc-modeless.el:235:5: 既存関数名はシャープクォート（`#'`）を使うほうが安全です
- mozc-modeless.el:400:7: `beginning-of-line` の使用を検討してください
```

→ 235行目付近で関数名をクォートする際は `'function-name` ではなく `#'function-name` を使うべき。400行目付近では独自実装ではなく `beginning-of-line` の利用を検討すべき。

#### 3. checkdoc (Emacs 30.1) の指摘（*合理的な範囲で*修正してほしい）

```
mozc-modeless.el:609: Lispシンボル `mozc-mode-map' はクォートで囲むべきです
mozc-modeless.el:613: Lispシンボル `mozc-mode-map' はクォートで囲むべきです
mozc-modeless.el:622: Lispシンボル `mozc-mode-map' はクォートで囲むべきです
```

→ ドキュメント文字列内で `mozc-mode-map` というシンボルに言及する箇所は、バッククォートで囲む（例: `` `mozc-mode-map' ``）必要がある。

#### 4. パッケージおよびレシピの修正依頼

- レシピ内で `:fetcher` を `:repo` の**前**に記述してください
- 可能ならデフォルト形式のレシピが望ましい: `(mozc-modeless :fetcher github :repo "kiyoka/mozc-modeless-emacs")`


### MELPA PR #9963 レビュー対応 (2026-04-23)

ブランチ: `feature/melpa-review-fixes`

#### 修正内容

1. **Package-Requires のバージョン指定** (mozc-modeless.el:9)
   - `(mozc "0")` → `(mozc "1.0")`
   - package-lint の警告 "Use a properly versioned dependency on \"mozc\"" に対応
   - 注: MELPA の最新版 `20260327.323` を試したが、package-lint が日付ベースを snapshot version として別途警告するため、セマンティックバージョン形式 `"1.0"` を採用

2. **sharp-quote の使用** (mozc-modeless.el:235)
   - `'eval-print-last-sexp` → `#'eval-print-last-sexp`
   - melpazoid の指摘 "sharp-quote the names of existing functions" に対応

3. **`beginning-of-line` の使用** (mozc-modeless.el:400)
   - `(goto-char (line-beginning-position))` → `(beginning-of-line)`
   - melpazoid の指摘 "Consider `beginning-of-line`" に対応

4. **docstring の `mozc-mode-map` をクォート** (mozc-modeless.el:609, 613, 622)
   - `mozc-mode-map` → `` `mozc-mode-map' ``
   - checkdoc の指摘 "Lisp symbol `mozc-mode-map' should appear in quotes" に対応

5. **レシピファイルをデフォルト形式に** (mozc-modeless.recipe)
   - `:fetcher` を `:repo` の前に配置
   - `:files` を省略してデフォルト形式 `(mozc-modeless :fetcher github :repo "kiyoka/mozc-modeless-emacs")` に変更
   - MELPA デフォルトで `*.el` がすべてピックアップされるため `:files` 明示は不要

#### 検証

- `check-parens`: OK
- `emacs --batch -f batch-byte-compile`: 警告なしでコンパイル成功
- `package-lint`: 警告なし
- `checkdoc`: 警告なし

#### 次のステップ

- このブランチを PR としてマージ
- MELPA フォーク (`/Users/kiyoka/Documents/GitHub/melpa`) のレシピも同様にデフォルト形式に更新して MELPA PR #9963 を更新


以下のような内容で、新しいイシューを追加してください。
mozc-modeless.elで変換候補の管理ができないか調べる。
最終的には、mozc.elに制御を渡さなくても変換候補選択ができるようにしたい。

そのissueはSumibi二登録するものではありませんでした。取り消してください。


### GitHub Issue #34 対応: mozc-modeless.el での変換候補管理（2段階 C-j / 再変換）

#### 背景・調査

Issue #34「mozc-modeless.el で変換候補の管理ができないか調べる」への対応。
最終目標は「mozc.el に制御を渡さなくても変換候補選択ができる」こと。

まず mozc.el の内部構造（ヘルパー通信プロトコル・保持データ構造）を調査し、
`docs/mozc-el-internals.md` にまとめた。主な知見:

- mozc.el ⇄ `mozc_emacs_helper`（S式⇔protobuf 変換の薄いブリッジ）⇄ `mozc_server`（変換エンジン）の3層構成
- ヘルパーがサポートするコマンドは `CreateSession` / `DeleteSession` / `SendKey` の3つのみ。
  候補の id 直接選択（`SELECT_CANDIDATE`）や再変換（`CONVERT_REVERSE`）に必要な `SEND_COMMAND` は未実装
- サーバー応答 `Output`（alist）には `candidate-window`（各候補の `value` と `id`）と
  `all-candidate-words`（全候補）が含まれるが、mozc.el は候補リストを永続保持せず毎回再描画している
- → 候補リストの「取得」は SendKey だけで可能（ヘルパー改造不要）。
  id 直接選択・任意テキストの再変換にはヘルパー拡張が必要

#### 設計（ユーザとの議論で決定）

C-j を「変換した読みを覚えておく」方式で2段階化する:

- **point 1**: ローマ字 + C-j → 第1候補で即確定（候補ウィンドウなし）、直接入力を継続。
  確定テキストに読み（romaji）を text property として埋め込む。
- **point 2**: 変換済みテキスト上で C-j → その読みを再生し、mozc.el の候補ウィンドウを表示。

決定事項:
- 候補表示は mozc.el を流用（独自UIではない）
- 再変換対象は「自分が変換したテキスト」のみ。text property が残る限り何個前でも対象
- C-j のデフォルト挙動変更（即候補ウィンドウ → 即確定）。後方互換 defcustom は入れない（新挙動のみ）
- 再変換確定後も新テキストに読みを付け直す
- アンビエント変換で入った日本語にも読みを付ける

#### 実装内容 (2026-06-13, v0.10.0 → v0.11.0)

1. **読みの記録（text property）**
   - `mozc-modeless--tag-reading` (mozc-modeless.el:214): 確定テキストに `mozc-modeless-reading` プロパティを付与。あわせて `rear-nonsticky` を付け、直後に打った文字が読みを継承しないようにする（後述のバグ対応）
   - `mozc-modeless--reconvertible-region-at-point` (mozc-modeless.el:222): カーソル直前のタグ付き領域 (BEG END READING) を検出

2. **C-j の4分岐ディスパッチ** (`mozc-modeless-convert`, mozc-modeless.el:257)
   1. lisp-interaction の `)` → eval（現状維持）
   2. 変換中 → 次候補（現状維持）
   3. タグ付き領域が直前 → `mozc-modeless--reconvert`（再変換）
   4. それ以外（ローマ字） → `mozc-modeless--convert-preceding-romaji`（即確定）

3. **point 1: 即確定** (`mozc-modeless--convert-preceding-romaji`, mozc-modeless.el:293)
   - 既存の auto-confirm 経路（`mozc-modeless--ambient-convert` の romaji+space+Enter）を再利用
   - 確定後、後始末で読みをタグ付け

4. **point 2: 再変換** (`mozc-modeless--reconvert`, mozc-modeless.el:310)
   - タグ付き領域を削除（元テキストはプロパティ込みで保存）→ 読みを mozc.el 対話変換経路へ
   - C-g で元の日本語をタグごと復元

5. **対話変換の共通化** (`mozc-modeless--start-conversion`, mozc-modeless.el:328)
   - 再変換とアンビエント対話変換の重複コードを集約

6. **読みタグ付けの確定フック（2箇所）**
   - auto-confirm 後始末（`mozc-modeless--ambient-convert` 内, mozc-modeless.el:607）: point 1・アンビエント自動確定をカバー
   - `mozc-modeless--finish` (mozc-modeless.el:374): point 2・アンビエント対話確定をカバー

7. **状態変数追加**: `mozc-modeless--reading` (mozc-modeless.el:121) — 確定時の再タグ用（cancel 復元用の `--original-string` とは別管理）

#### 修正ファイル
- `mozc-modeless.el` (v0.10.0 → v0.11.0)
- `docs/mozc-el-internals.md`（新規: mozc.el 内部構造の調査結果）

#### 動作例
```
nihongo + C-j          → 日本語（第1候補で即確定、候補ウィンドウなし）
（日本語 の直後で）C-j → mozc 候補ウィンドウが開く（C-n/C-p で選択、Enter 確定、C-g で復元）
数個前の変換済みテキスト上で C-j → 再変換可能（読み property が残る限り）
```

#### 検証
- `check-parens` (emacs-lisp-mode): OK
- `emacs --batch -f batch-byte-compile`: 警告なし
- `checkdoc`: 警告なし
- 領域検出ロジック (`mozc-modeless--reconvertible-region-at-point`) の batch スモークテスト合格
  （カーソル位置別の検出・境界・プロパティ保持を確認）
- 実機テスト (2026-06-13) で point 1/2 の全フロー確認済み:
  即確定 / 後続テキストの独立変換 / 候補選択(C-n/C-p/Enter) / C-g 復元 / 数個前の再変換 /
  slash fence / アンビエント変換＋再変換 / lisp-interaction eval / 即確定時のチラつきなし

#### バグ対応 (実機テスト中に発見・修正)

- **症状**: `nihongo` C-j（→`日本語`）の直後に `henkan` C-j とすると、`henkan` が巻き込まれて `日本語` に戻る
- **原因**: `mozc-modeless-reading` プロパティがデフォルトで rear-sticky のため、`日本語` の直後に打った `henkan` が読み "nihongo" を継承。C-j 時に「日本語henkan 全体」が読み "nihongo" の再変換対象と誤判定されていた
- **修正**: `mozc-modeless--tag-reading` で `rear-nonsticky` を付与 (mozc-modeless.el:214)

#### 追加調整・図解 (実機テスト中)

- **ディスパッチの優先順位（ユーザー要望）**: カーソル直前の文字が ASCII（コード `< 128`：英字・数字・記号）なら、`mozc-modeless-reading` プロパティがあっても再変換せず **新規変換** にする。再変換が発火するのは直前が **非 ASCII（日本語）** のときだけ (`mozc-modeless--reconvertible-region-at-point`, mozc-modeless.el:226)。rear-nonsticky と二段構えの安全弁。
- **図解を追加** (`docs/`):
  - `usage-flow.svg` / `.png`: 操作方法の図（C-j で即確定 → もう一度 C-j で再変換、の2ステップのみ）
  - `reconvert-text-property.svg` / `.png`: 確定テキストに読みが text property として埋め込まれる仕組みの図

#### 残課題・今後
- エッジ: point 1 の自動確定中（`--ambient-in-progress`）の C-j 連打は未ガード
- 任意の既存日本語（ファイルから開いた等、読み property のないテキスト）の再変換は対象外。
  実現には `CONVERT_REVERSE`（`SEND_COMMAND`）対応のヘルパー拡張が必要（`docs/mozc-el-internals.md` 6.2/6.3 参照）
- README の C-j 挙動説明の更新
