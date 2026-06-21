# mozc.el 内部構造の調査

> 関連 Issue: [#34 mozc-modeless.el で変換候補の管理ができないか調べる](https://github.com/kiyoka/mozc-modeless-emacs/issues/34)
>
> **目的**: mozc.el が「mozc ヘルパープロセスとどうやり取りしているか」と「Emacs Lisp 側がどんなデータ構造を保持しているか」を明らかにし、
> mozc.el に制御を渡さずに mozc-modeless.el 側で変換候補を管理・選択できるかどうかの判断材料にする。

## 調査対象（一次ソース）

行番号はいずれも mozc 本体リポジトリ `mozc/src/` 配下のソースを基準にする。

| 種別 | パス | 備考 |
|------|------|------|
| Emacs Lisp 本体 | `mozc/src/unix/emacs/mozc.el`（1996 行） | elpa の `mozc-20260327.323` と同一ソース |
| ヘルパー本体 | `mozc/src/unix/emacs/mozc_emacs_helper.cc` | プロセスのメインループ |
| ヘルパー I/O | `mozc/src/unix/emacs/mozc_emacs_helper_lib.{h,cc}` | S 式 ⇔ protobuf 変換 |
| プロトコル定義 | `mozc/src/protocol/commands.proto` | `Output` / `Input` / `SessionCommand` |
| プロトコル定義 | `mozc/src/protocol/candidate_window.proto` | `CandidateWindow` / `CandidateWord` |

---

## 1. 全体アーキテクチャ（3 層構成）

```
 ┌─────────────────────────────────────┐
 │ Emacs                               │
 │  mozc-modeless.el                   │  ← C-j / アンビエント変換などの上位ロジック
 │      │ (input-method "japanese-mozc")│
 │      ▼                              │
 │  mozc.el                            │  ← キーイベント送信・preedit/候補の描画
 └──────┬──────────────────────────────┘
        │  標準入出力パイプ（1 行 = 1 S 式、utf-8-unix、同期 req/resp）
        ▼
 ┌─────────────────────────────────────┐
 │ mozc_emacs_helper （別プロセス）       │  ← S 式 ⇔ protobuf 変換だけを行う薄いブリッジ
 └──────┬──────────────────────────────┘
        │  client::Client（mozc 標準 IPC, protobuf）
        ▼
 ┌─────────────────────────────────────┐
 │ mozc_server （変換エンジン本体）        │  ← 実際のかな漢字変換・候補生成
 └─────────────────────────────────────┘
```

ポイント:

- **変換ロジックは mozc_server 側**にある。ヘルパーも mozc.el も変換アルゴリズムは持たない。
- **ヘルパーは「S 式 ⇔ protobuf」の翻訳だけ**を担当する非常に薄いプロセス。`client::Client` 経由で mozc_server と通信する。
- mozc.el は protobuf を直接扱えないので、ヘルパーを挟んで **S 式（= Emacs の alist）** でやり取りする。

---

## 2. ヘルパーとのやり取り（プロセス通信）

### 2.1 プロセス起動

`mozc-helper-process-start`（mozc.el:1574）が次のように起動する。

```elisp
(start-process "mozc-helper-process" nil
               "mozc_emacs_helper" "--suppress_stderr")
```

- `process-connection-type` を `nil` にして **pty ではなくパイプ**を使う。
- 文字コードは **入出力とも `utf-8-unix`**（`set-process-coding-system`）。
- フィルタ `mozc-helper-process-filter`、センチネル `mozc-helper-process-sentinel` を設定。
- センチネルはプロセスが死ぬと `mozc-helper-process` を `nil` にし、次回アクセス時に再起動・セッション再作成される。

### 2.2 グリーティング（起動直後の挨拶）

起動するとヘルパーは 1 行の S 式を送ってくる（`PrintGreetingMessage`、helper.cc:56）。

```lisp
((mozc-emacs-helper . t)
 (version . "X.Y.Z.W")
 (config . ((preedit-method . roman))))   ; roman または kana
```

mozc.el はこれを `mozc-helper-process-recv-greeting`（mozc.el:1611）で受け取り、
`mozc-emacs-helper` が `t` であることを確認し、`version` と `config`（サーバー側設定）を保存する。

### 2.3 リクエスト形式（Emacs → ヘルパー）

`mozc-helper-process-send-sexpr`（mozc.el:1675）が `(format "%S\n" args)` で **1 行の S 式**として送る。
末尾の改行が出力フラッシュ＆メッセージ境界を兼ねる。形式は：

```
(EVENT-ID COMMAND [SESSION-ID] [ARG]...)
```

- `EVENT-ID`: リクエストとレスポンスを対応づける通し番号（`mozc-session-seq`、28bit でラップ）。
- `COMMAND`: **`CreateSession` / `DeleteSession` / `SendKey` の 3 つだけ**（後述 2.6）。
- `CreateSession` のみ SESSION-ID が不要。

具体例:

```lisp
(1 CreateSession)          ; セッション作成
(2 SendKey 1 97)           ; セッション1 へ キーコード97(?a) を送る
(3 SendKey 1 space)        ; キーシンボル space を送る
(4 SendKey 1 97 "ち")      ; キーコード + 確定文字列（kana キーマップ時）
(99 DeleteSession 1)       ; セッション1 を破棄
```

キーの表現は 3 種類（`ParseInputLine`、helper_lib.cc:128 / mozc.el の `mozc-key-event-to-key-and-modifiers`:389）：
数値（0–255 のキーコード）、シンボル（`space` `shift` `meta` `down` など）、ダブルクオート文字列（preedit に挿入する文字列）。

### 2.4 レスポンス形式（ヘルパー → Emacs）

`ProcessLoop`（helper.cc:118）が **1 行の S 式**で返す。

```lisp
((emacs-event-id . 2)        ; リクエストの EVENT-ID と一致
 (emacs-session-id . 1)      ; セッションID（エラー時は不一致/欠落）
 (output . (...)))           ; mozc::commands::Output を alist 化したもの
```

エラー時はヘルパーが `((error . scan-error)(message . "..."))` を返して終了することがある（`ErrorExit`、helper_lib.cc:375）。

### 2.5 受信と同期の仕組み

- フィルタ `mozc-helper-process-filter`（mozc.el:1649）が生文字列を貯め、`\n` で分割して**完全な行**だけを
  `mozc-helper-process-message-queue` に積む。行未満の端数は `mozc-helper-process-string-buf` に保持。
- `mozc-helper-process-recv-response`（mozc.el:1707）はキューから 1 行 pop。無ければ
  `accept-process-output`（タイムアウト **1 秒** = `mozc-helper-process-timeout-sec`）で待つ。
- `mozc-helper-process-recv-sexpr`（mozc.el:1682）が 1 行を `read-from-string` で Lisp オブジェクト（alist）に変換。
- `mozc-session-recv-corresponding-response`（mozc.el:1511）が **`emacs-event-id` が一致する応答だけ**を採用（クロストーク防止）。

→ つまり通信は **同期 request/response**。1 リクエストにつき 1 レスポンスを待って受け取る。

### 2.6 サポートされるコマンド（重要）

ヘルパーの `ProcessLoop`（helper.cc:92）と `ParseInputLine`（helper_lib.cc:97）が受け付けるのは：

| コマンド | Input.type | 引数 | 用途 |
|----------|-----------|------|------|
| `CreateSession` | `CREATE_SESSION` | なし | セッション作成（session-id 採番） |
| `DeleteSession` | `DELETE_SESSION` | SESSION-ID | セッション破棄 |
| `SendKey` | `SEND_KEY` | SESSION-ID, KEY... | キーイベント送信（変換の主役） |

ヘルパーのソースには次のコメントがある（helper_lib.cc:104）:

> Mozc has SendTestKey and SendCommand commands in addition to the above.
> But this code doesn't support them because of no need so far.

→ **`SendCommand`（= `SEND_COMMAND`）は現行ヘルパーバイナリでは未実装**。これが Issue #34 の鍵になる（第 6 節）。

### 2.7 主要関数の対応表（通信レイヤ）

| 関数 | 役割 |
|------|------|
| `mozc-session-create` (1432) | 必要ならヘルパー接続＋`CreateSession` |
| `mozc-session-sendkey` (1464) | `SendKey` を送り `Output` alist を返す |
| `mozc-session-execute-command` (1475) | `EVENT-ID COMMAND ...` を組み立て送受信 |
| `mozc-helper-process-send-sexpr` (1675) | S 式を 1 行で送信 |
| `mozc-helper-process-recv-sexpr` (1682) | 1 行を読んで alist 化 |
| `mozc-protobuf-get` (1721) | alist から `(get 'k1 i 'k2 ...)` でネスト取得 |

---

## 3. Emacs Lisp 側が保持するデータ構造

大きく **(A) 通信・セッション状態**、**(B) サーバー応答（protobuf を写した alist）**、**(C) 描画状態** の 3 種類。

### 3.1 (A) 通信・セッション状態変数

| 変数 | スコープ | 内容 |
|------|---------|------|
| `mozc-helper-process` (1555) | グローバル | ヘルパーのプロセスオブジェクト |
| `mozc-helper-process-version` (1558) | グローバル | ヘルパーのバージョン文字列 |
| `mozc-helper-process-message-queue` (1561) | グローバル | 受信済みの完全な行（応答）のリスト |
| `mozc-helper-process-string-buf` (1564) | グローバル | 行未満の受信端数 |
| `mozc-config-protobuf` (1537) | グローバル | サーバー側設定（`preedit-method` など） |
| `mozc-session-id` (1418) | **バッファローカル** | セッションID（バッファ毎に別セッション） |
| `mozc-session-process` (1411) | **バッファローカル** | 接続中プロセスの控え（再起動検出用） |
| `mozc-session-seq` (1424) | グローバル | 次の EVENT-ID（28bit でラップ） |

→ **セッションはバッファローカル**。バッファごとに独立した変換状態を持てる。

### 3.2 (B) サーバー応答 = `Output` を写した alist

ヘルパーの `PrintMessage`（helper_lib.cc:183）は **protobuf reflection で機械的に S 式へ変換**する。変換規則（helper_lib.h:68, helper_lib.cc:402, 441）:

| protobuf | S 式表現 |
|----------|---------|
| message / group | alist `((field . value) ...)` |
| repeated | リスト（message なら `(field (..)(..))`、スカラなら `(field v1 v2 ..)`） |
| int32 / uint32 | 数値そのまま |
| int64 / uint64 | **文字列**にエスケープ（Emacs の整数桁数制限回避）例: `"12345"` |
| double / float | `%f` |
| bool | `t` / `nil` |
| enum | シンボル（小文字化、`_`→`-`） |
| string | ダブルクオート文字列 |
| フィールド名 | 小文字化＋`_`→`-`（`NormalizeSymbol`）例: `candidate_window`→`candidate-window` |

→ つまり **Emacs 側の alist は `mozc::commands::Output` protobuf と 1:1 対応**。`commands.proto` / `candidate_window.proto` がそのままデータ構造の定義になる。アクセスは `mozc-protobuf-get`。

#### `Output`（トップレベル、commands.proto の `message Output`）の主なフィールド

| キー | 型 | 内容 |
|------|----|----|
| `id` | uint64→文字列 | サーバー内部 ID |
| `mode` | enum | 入力モード（`hiragana` など） |
| `consumed` | bool | キーをサーバーが消費したか |
| `result` | message | **確定文字列**（`type`=`string`, `value`=確定テキスト） |
| `preedit` | message | 未確定文字列（下記） |
| `candidate-window` | message | **表示中の候補ウィンドウ**（下記） |
| `all-candidate-words` | message | **全候補リスト**（`CandidateList`、表示ページに限らない） |
| `deletion-range` | message | 再変換などで削除すべき範囲 |
| `callback` | message | サーバーが要求するコールバック（`session_command` を含む） |
| `preedit-method` | enum | `roman` / `kana` 等 |

mozc.el が `mozc-handle-event`（327）で実際に読むのは `consumed` / `result` / `preedit` / `candidate-window`（古い版互換で `candidates` も）。
**`all-candidate-words` は mozc.el では一切参照していない**（第 4 節）。

#### `preedit`（未確定文字列）

```lisp
(preedit . ((cursor . 3)
            (segment ((annotation . highlight)(value . "変換")(key . "へんかん"))
                     ((annotation . underline)(value . "ちゅう")(key . "ちゅう")))))
```

- `cursor`: カーソル位置。
- `segment`: 文節のリスト。各文節は `value`（表示文字列）、`key`（読み）、`annotation`（`highlight` = 選択中文節 / `underline` / `none`）。

#### `candidate-window`（候補ウィンドウ、`candidate_window.proto` の `CandidateWindow`）

```lisp
(candidate-window .
 ((focused-index . 0)         ; 現在フォーカス中の候補（ページ内インデックス）
  (size . 9)                  ; 候補総数
  (candidate ((index . 0)(value . "愛")(id . 0)
              (annotation . ((shortcut . "1")(description . ".."))))
             ((index . 1)(value . "藍")(id . 12)
              (annotation . ((shortcut . "2"))))
             ...)             ; 表示中ページの候補（既定 page-size=9 件）
  (position . 0)
  (category . conversion)     ; conversion / suggestion / prediction ...
  (footer . ((index-visible . t)(label . "..")))
  (page-size . 9)))
```

各候補 `CandidateWord` の主フィールド（candidate_window.proto:176 / `CandidateWindow.Candidate` group:227）:

| キー | 内容 |
|------|----|
| `index` | ページ内の通し番号（0 起点） |
| `value` | 候補の表示文字列 |
| `id` | **候補を一意に指す ID**（`SELECT_CANDIDATE` 等で使う、field 9） |
| `key` | 読み |
| `annotation` | `description`（語義）, `shortcut`（数字キー）, `prefix`/`suffix`, `deletable` 等 |
| `information_id` | 語義辞書 (usages) との対応 |

> ⚠️ **`candidate-window` は「表示中ページ」だけ**（既定 9 件）。全候補は `all-candidate-words`（`CandidateList`、各要素は同じ `CandidateWord`）に入る。

### 3.3 (C) 描画状態変数 — ★候補リストは保持していない

mozc.el は受け取った候補 alist を **その場でレンダリングするだけ**で、候補リストを永続変数に保持しない。
保持しているのは overlay とプレースホルダ領域だけ（すべてバッファローカル）。

| 変数 | 内容 |
|------|----|
| `mozc-preedit-overlay` (761) | preedit 表示用 overlay |
| `mozc-preedit-point-origin` (686) | preedit 挿入位置のマーカー |
| `mozc-preedit-in-session-flag` (682) | preedit セッション中か |
| `mozc-cand-overlay-overlays` (1052) | 候補ウィンドウ描画用 overlay 群 |
| `mozc-cand-overlay-placeholder-regions` (1048) | 候補ウィンドウ用の一時領域 |
| `mozc-cand-echo-area-placeholder-region` (928) | エコーエリア版の一時領域 |

候補の描画は `mozc-candidate-update`（919）→ `mozc-candidate-dispatch`（894）で
`overlay` 版（`mozc-cand-overlay-update`:1095）か `echo-area` 版（`mozc-cand-echo-area-update`:940）に振り分けられる。
いずれも **引数で渡された `candidates` alist を読んで描くだけ**で、終わったら overlay を消す。

→ **重要**: 「いま何番目の候補か」「候補リストは何か」は **mozc.el は覚えていない**。すべて毎回サーバー応答（`candidate-window`）から再取得している。状態の真実は mozc_server 側にある。

---

## 4. 変換候補選択の現状フロー

```
ユーザのキー入力
   │  mozc-mode-map は [t]（全キー）を mozc-handle-event にバインド
   ▼
mozc-handle-event (327)
   │  mozc-send-key-event → mozc-session-sendkey → SendKey をヘルパーへ
   ▼
ヘルパー → mozc_server → 候補状態を更新
   ▼
Output 応答（consumed / preedit / candidate-window）を受信
   ▼
mozc-preedit-update (725) / mozc-candidate-update (919) で overlay 描画
```

- 候補選択（次候補・前候補・文節移動）も、結局は **`SendKey` でキーイベント（SPC / 矢印 / 数字キーなど）をサーバーに送る**ことで実現している。
- サーバーが `focused-index` を更新した新しい `candidate-window` を返し、mozc.el はそれを描き直すだけ。
- **mozc-modeless.el** は変換中に `C-n/C-p/C-f/C-b` を矢印キーへ変換して `unread-command-events` 経由で mozc.el（→サーバー）に流している（Issue #13）。これも「キーイベントを送る」方式。

---

## 5. データ構造・通信のまとめ図

```
SendKey 要求:  (SEQ SendKey SID KEY...)
                       │
                       ▼  (helper が protobuf 化 → server → 応答を S式化)
応答:  ((emacs-event-id . SEQ)
        (emacs-session-id . SID)
        (output . ((consumed . t)
                   (result . ((type . string)(value . "確定文字列")))     ; 確定時
                   (preedit . ((cursor . N)(segment (..)(..))))           ; 変換中
                   (candidate-window . ((focused-index . F)(size . S)
                                        (candidate (..id..)(..id..)..)    ; 表示ページ
                                        (category . conversion)
                                        (footer . ((index-visible . t)))))
                   (all-candidate-words . ((candidates (..)(..)..))))))   ; 全候補（mozc.el は未使用）
```

---

## 6. Issue #34 への示唆

### 6.1 候補リストの「取得」は今のままでも可能

- `mozc-session-sendkey`（および `mozc-handle-event` 内）が返す `Output` alist には、
  **`candidate-window`（各候補の `value` と `id` を含む）** が入っている。さらに **`all-candidate-words` に全候補**が入る（応答に含まれる場合）。
- よって **mozc-modeless 側で `mozc-protobuf-get` を使えば候補リストを読み取れる**。ヘルパー改造は不要。
  ただし mozc.el の `mozc-handle-event` は応答を内部処理して返り値を捨てるため、
  mozc-modeless から候補を取るには `mozc-session-sendkey` を直接呼ぶ／`mozc-handle-event` をラップする等の工夫が要る。

### 6.2 候補の「直接選択」はヘルパーの制約に当たる

- 候補 `id` を指定したダイレクト選択や、既存テキストの再変換は、mozc_server 側の
  **`SessionCommand`（`SEND_COMMAND`）** が担当する（commands.proto の `enum CommandType`）:
  - `SELECT_CANDIDATE`（id 指定で候補確定、候補窓を閉じる）
  - `HIGHLIGHT_CANDIDATE`（id 指定でフォーカスのみ、候補窓は開いたまま）
  - `CONVERT_REVERSE`（テキストを渡して**再変換** ← 過去の「再変換」実験で本来必要だった API）
  - `CONVERT_NEXT_PAGE` / `CONVERT_PREV_PAGE` / `SUBMIT` / `SUBMIT_CANDIDATE` など
- **しかし現行 `mozc_emacs_helper` は `SEND_COMMAND` を実装していない**（第 2.6 節）。
  したがって id 直接選択・再変換は **今の構成では送れない**。

### 6.3 取りうるアプローチ（叩き台）

| 案 | 概要 | ヘルパー改造 | 備考 |
|----|------|:---:|------|
| **A. 現状維持** | `SendKey` で矢印/数字/SPC を送って選択 | 不要 | Issue #13 の延長。UI は mozc.el 任せ |
| **B. 候補リストを読んで独自 UI** | 応答の `candidate-window`/`all-candidate-words` を mozc-modeless が読み、独自 overlay 等で一覧表示。選択は `SendKey`（数字キー/矢印）で実現 | 不要 | mozc.el に描画を渡さず候補管理が可能。**Issue #34 の現実的な第一歩** |
| **C. ヘルパー拡張** | `mozc_emacs_helper` に `SEND_COMMAND` を追加し、`SELECT_CANDIDATE`/`CONVERT_REVERSE` を使う | **必要** | id 直接選択・再変換まで可能。ただし C++ ビルド＆配布が必要で MELPA 配布パッケージとしては重い |

### 6.4 過去の「再変換」実験失敗との関係

CLAUDE.md に記録のある「リージョン選択した日本語を再変換する」実験が失敗したのは、
`listify-key-sequence` で日本語（マルチバイト）をキーイベント化して送れなかったため。
本来の正攻法は **`CONVERT_REVERSE`（`SEND_COMMAND`）にテキストを渡す**ことだが、
上記のとおり現行ヘルパーが `SEND_COMMAND` 未対応なので現状は不可。案 C を採るなら再変換も同時に解決できる。

---

## 7. 参照（ファイル:行）

- セッション管理: `mozc.el:1409-1534`
- ヘルパー通信: `mozc.el:1542-1718`
- protobuf アクセサ `mozc-protobuf-get`: `mozc.el:1721`
- キーイベント処理 `mozc-handle-event`: `mozc.el:327`
- preedit データ/描画: `mozc.el:680-869`
- 候補データ/描画: `mozc.el:870-1408`
- ヘルパー main ループ: `mozc_emacs_helper.cc:78-123`（対応コマンドは 92-110）
- S 式⇔protobuf 変換規則: `mozc_emacs_helper_lib.cc:174-208, 402-497`
- 入力パース（キー表現）: `mozc_emacs_helper_lib.cc:77-172`
- 候補構造定義: `candidate_window.proto:176-275`（`CandidateWord` / `CandidateWindow`）
- コマンド種別定義: `commands.proto` の `message Output` と `message SessionCommand` の `enum CommandType`
