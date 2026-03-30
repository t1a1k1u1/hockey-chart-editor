# Game Plan: Hockey Chart Editor

## Game Description

リフレクビート風音楽ゲーム「hockey」用の譜面エディター（chart.json エディター）を Godot 4.x / GDScript で作成する。
chart.json を GUI で作成・編集するデスクトップアプリケーション。音楽を再生しながら視覚的にノーツを配置できる。

ノーツ種別: normal / top / vertical / long_normal / long_top / long_vertical / chain
トラック行: TOP 0〜2（オレンジ系）, NORMAL（青系）, V 0〜V 6（青系暗め）の計11行
タイムライン: X軸=時間（秒）, デフォルト200px/秒, ズーム50〜2000px/秒
ファイル操作: chart.json の読み書き（ゲーム本体と完全互換スキーマ）

---

## 1. Core UI + File I/O

- **Status:** done
- **Depends on:** (none)
- **Targets:** project.godot, scenes/ChartEditor.tscn, scenes/build_ChartEditor.gd, scripts/ChartEditorMain.gd, scripts/ChartData.gd
- **Goal:** Godotプロジェクトの基本構造と画面レイアウトを確立する。メニューバー・コントロールバー・トラックヘッダー・プロパティパネル・ステータスバーを持つメインウィンドウを構築し、chart.json の読み書きを実装する。
- **Requirements:**
  - `DisplayServer.window_set_min_size(Vector2i(1280, 720))` で最小サイズを設定
  - メニューバー: File（New/Open/Save/Save As）, Edit（Metadata）, View
  - コントロールバー（左→右）: ▶ボタン, ■ボタン, 時刻表示(0:00.000形式), BPM入力, スナップ分割セレクター(1/2/3/4/6/8), スナップON/OFFトグル, ノーツ種別ボタン(7種), オフセット入力
  - トラックヘッダー(120px幅): TOP 0/1/2（オレンジ系背景）, NORMAL（青系）, V 0〜V 6（青系暗め）、グループ間に4pxセパレーター
  - プロパティパネル(240px幅): 選択ノーツのフィールド表示・編集エリア（初期はメタデータ表示）
  - ステータスバー: カーソル時刻・総ノーツ数・ファイルパス表示
  - `ChartData.gd`: メモリ上のmeta+notes保持、JSON読み書き（chart.jsonスキーマ完全準拠）
  - File→New: デフォルト値で初期化（bpm=120, bpm_changes=[{time:0,bpm:120}]）
  - File→Open（Ctrl+O）: ファイルダイアログでchart.jsonを選択して読み込み
  - File→Save（Ctrl+S）: notes配列をtime昇順ソート、インデント付きJSONで保存
  - File→Save As（Ctrl+Shift+S）: ファイルダイアログで保存先指定
  - 未保存変更がある場合の終了/新規/開く時に「保存しますか？」ダイアログ
  - Edit→Metadata: MetadataDialogでtitle/artist/level/bpm/offset/audio編集
  - normal ノーツはlaneフィールドを含まない、top/long_topはtop_lane含む、vertical/long_verticalはlane含む
- **Verify:** ウィンドウが1280×720以上で表示される。メニューバー・コントロールバー・左のトラックヘッダー（11行+セパレーター）・右のプロパティパネル・下部ステータスバーが正しく配置されている。File→Openでsample/chart.jsonを読み込んでノーツ数がステータスバーに表示される。Ctrl+Sで保存できる。

---

## 2. Timeline + BPM Grid + Note Rendering

- **Status:** done
- **Depends on:** 1
- **Targets:** scenes/Timeline.tscn, scenes/build_Timeline.gd, scenes/Ruler.tscn, scenes/build_Ruler.gd, scripts/Timeline.gd, scripts/BpmGrid.gd, scripts/NoteRenderer.gd
- **Goal:** タイムラインの描画エンジンを実装する。時間軸上にBPMグリッド線・ルーラー・BPMチェンジ帯・全ノーツ種別の描画を行い、ズーム・スクロール操作を実装する。
- **Requirements:**
  - X軸=時間（秒）、デフォルトズーム200px/秒、範囲50〜2000px/秒
  - Ctrl+マウスホイールでズーム（プレイヘッド位置を中心に拡縮）
  - マウスホイールで水平スクロール、スクロールバーでもスクロール可能
  - Ctrl+0でズームをデフォルト(200px/秒)に戻す
  - 時間ルーラー: BPMスナップON時に小節線（太い白線alpha=0.5）・拍線（細い白線alpha=0.3）・細分割線（薄い白線alpha=0.15、グリッド間隔<4pxなら非表示）、OFF時は0.5秒ごとに目盛り
  - ルーラー直下にBPMチェンジ帯（高さ16px）: 各BPMチェンジ時刻にマーカー（縦線+BPM値テキスト）表示
  - `BpmGrid.gd`: bpm_at(time)でBPMチェンジを考慮したBPM取得、グリッド位置計算
  - `NoteRenderer.gd`: 全ノーツ種別の描画ロジック
    - 通常ノーツ: 幅=1グリッド幅(最小8px)、高さ=行高さ80%、中心X=time位置
    - ロングノーツ: time〜end_timeの横帯、高さ=60%、両端に丸い頭部
    - chainノーツ: chain_count個をchain_interval間隔で配置、コネクターライン（細線）で連結、last_long=trueなら最後のメンバーを帯として描画
  - ノーツの色: normal/long_normal=#4D66FF, top/long_top=#1AE64D, vertical/long_vertical=#8855FF, chain(各系列の明度高め), 選択中=黄色アウトライン
  - プレイヘッド（赤い縦線）が現在時刻位置を示す
  - トラック行の高さ32px、セパレーター4px
  - 描画: pixel_x = (time - scroll_offset) * pixels_per_second
- **Verify:** タイムラインにsample/chart.jsonのノーツが全種別正しく表示される（青のnormal、緑のtop、紫のvertical、各ロング、各chain）。ズームイン/アウトでノーツが拡縮する。BPMグリッド線が表示される。ルーラー下のBPMチェンジマーカーが2箇所表示される。

---

## 3. Note Editing + Undo/Redo

- **Status:** done
- **Depends on:** 2
- **Targets:** scripts/UndoRedoAction.gd, scripts/Timeline.gd
- **Goal:** ノーツの配置・削除・選択・移動・複製・Undo/Redo を実装する。編集操作の完全な入力ハンドリングを実装する。
- **Requirements:**
  - **配置ツール（数字キー1〜7でノーツ種別選択）:**
    - 単発（normal/top/vertical）: 対象トラック行を左クリックで配置。スナップON時はグリッドにスナップ
    - ロング（long系）: 対象行でドラッグ→離す。ドラッグ中はリアルタイム帯描画。最小長1グリッド幅未満は配置しない
    - chain: 左クリック後にプロパティパネルでchain_count(デフォルト3)/chain_interval(デフォルト0.4)/last_long(デフォルトfalse)を設定して確定
  - **削除:** 右クリック=クリックしたノーツを削除、Delete=選択中ノーツをすべて削除
  - **選択ツールモード（Sキー）:**
    - 左クリック=単一選択、Ctrl+クリック=追加/解除
    - 空き場所でドラッグ=矩形選択
    - Ctrl+A=全選択、Escape=選択解除
    - 選択中ノーツを左ドラッグで移動（水平=スナップON時グリッドスナップ、垂直=同種グループ内のみ許可）
    - chainノーツはグループ全体が一緒に移動
  - **複製:** Ctrl+D=選択ノーツを1グリッド右に複製、Ctrl+C/Ctrl+V=コピー&貼り付け
  - **Undo/Redo（Commandパターン）:** すべての編集操作がスタックに積まれる。Ctrl+Z=Undo（無制限）、Ctrl+Y / Ctrl+Shift+Z=Redo
  - **キーボードショートカット:** Tab=スナップON/OFFトグル、[/]=スナップ分割を粗く/細かく
  - **プロパティパネル連動:** 選択ノーツのtime/end_time/top_lane/lane/chain系フィールドを数値入力で編集可能。複数選択時は共通フィールドのみ（個別は「複数」表示）
  - **BPMチェンジ編集:** Ctrl+B=カーソル位置にBPMチェンジ追加（ダイアログでBPM値入力）、マーカーをクリックして選択・プロパティパネルで編集・Deleteで削除（time=0.0は削除/移動不可）
- **Verify:** タイムライン上でnormalノーツを左クリックで配置できる。long_normalをドラッグで配置できる。右クリックで削除できる。Sキーで選択モードに切り替え、ノーツを選択してドラッグで移動できる。Ctrl+ZでUndoが機能する。選択ノーツのtimeがプロパティパネルに表示され編集できる。

---

## 4. Audio Playback + Playhead

- **Status:** done
- **Depends on:** 3
- **Targets:** scripts/AudioPlayer.gd
- **Goal:** 音楽ファイルの再生とプレイヘッドの同期を実装する。再生中のタイムライン自動スクロールを実装する。
- **Requirements:**
  - `AudioStreamPlayer` でOGG/WAV再生
  - meta.audio で指定されたファイルをロード（File→Open時に同フォルダから自動ロード）
  - 再生開始時にmeta.offset秒遅延してから音楽再生（offsetが正の場合、offset秒後に音楽開始）
  - Space=再生/一時停止トグル、Escape（再生中）=停止してプレイヘッドを再生開始位置に戻す
  - Home=プレイヘッドを0秒へ、End=プレイヘッドを末尾へ
  - ←/→=プレイヘッドを1グリッド分移動、Shift+←/→=1小節分移動
  - タイムラインのルーラーを左クリック=プレイヘッドをその位置に移動
  - 再生中はプレイヘッドがリアルタイム移動し、タイムラインが自動スクロール（プレイヘッドが常に画面内右側20%付近）
  - 再生中もノーツの配置・削除が可能
  - コントロールバーの時刻表示が再生中にリアルタイム更新
  - オフセット調整モード: ボタン押下後、曲再生中にSpaceキーを押すと最初の拍としてoffsetを自動設定
- **Verify:** sample/chart.jsonを開いた状態でSpaceキーで再生が開始し、時刻表示がカウントアップし、プレイヘッドが移動し、タイムラインが自動スクロールする。再生中もノーツを配置できる。Spaceで一時停止、Escapeで停止して開始位置に戻る。

---

## 6. Vertical Timeline

- **Status:** done

---

## 7. Timeline Flip + Resize Fix

- **Status:** done
- **Depends on:** 6
- **Targets:** scripts/Timeline.gd, scripts/NoteRenderer.gd, scripts/ChartEditorMain.gd
- **Depends on:** 4
- **Targets:** scripts/Timeline.gd, scripts/NoteRenderer.gd, scripts/ChartEditorMain.gd, scenes/ChartEditor.tscn, scenes/build_ChartEditor.gd
- **Goal:** タイムラインを縦向きに変更する。X軸=トラック列、Y軸=時間（上が早い）。プレイヘッドは水平線。

---

## 8. Shared Lane System for Non-Top Notes

- **Status:** done
- **Depends on:** 7
- **Targets:** scripts/ChartData.gd, scripts/Timeline.gd, scripts/NoteRenderer.gd, STRUCTURE.md
- **Goal:** normal/long_normal/chain(normal) ノートと vertical/long_vertical/chain(vertical) ノートが同じレーン群（lane 0~6）を共有するよう変更する。chart.jsonスキーマ変更：normal/long_normal/chain(normal) にも lane フィールドを追加。ノートの重なり配置を禁止する。
- **Requirements:**
  - NUM_COLS を 11 → 10 に変更（TOP 0~2 が col 0~2、共有レーン 0~6 が col 3~9）
  - ChartData.gd: `get_note_row` / `get_row_type` を新レイアウトに対応。normal/long_normal/chain(normal) が lane フィールドを持つ
  - Timeline.gd: `_note_to_col` 更新（normal系=col 3+lane、vertical系=col 3+lane）、`_build_note_data` 更新（normal/long_normal/chain(normal) に lane を付与）、`_constrain_col_for_note` 更新（normal/vertical 系は col 3~9 の共有レンジ）、カラムラベル更新（"L0"~"L6"）
  - NoteRenderer.gd: `_get_note_col` 更新（normal系も 3+lane で計算）
  - 配置時重なり検出：同一 lane に既存ノートが時間的に重なる場合は配置不可
    - single note: 同一時刻に同 lane のノートがあれば不可
    - long note: [start, end_time] が同 lane の既存ノート占有区間と重なれば不可
    - chain: [start, chain_end] が同 lane の既存ノートと重なれば不可（last_long の場合は long の end_time まで）
    - 既存ノートの占有区間: long は [time, end_time]、chain は [time, time+(count-1)*interval] (last_long時は+long duration)、single は [time, time]（点）
  - 移動時も重なり検出を行い、重なる場合は移動をキャンセル
- **Verify:** タイムラインに10列（TOP 0/1/2 + L0~L6）が表示される。normal ノートと vertical ノートを同じ列（L0 など）に配置できる。同一レーン同一時刻への重複配置がブロックされる。long ノートの占有区間内への別ノート配置がブロックされる。

---

## 9. Key+Click Note Placement (Remove Type Buttons)

- **Status:** done
- **Depends on:** 8
- **Targets:** scenes/build_ChartEditor.gd, scenes/ChartEditor.tscn, scripts/ChartEditorMain.gd, scripts/Timeline.gd
- **Goal:** ノートタイプ選択ボタンを廃止し、キー押下+クリックでノートタイプを決定する方式に変更する。
- **Requirements:**
  - build_ChartEditor.gd: NoteType1-7 ボタン、"Type:"ラベル、前後のセパレーターを削除。代わりにヒントラベル「click=N/T | v=V | x=Long | c=Chain | v+x=LV | v+c=CV」を追加
  - ChartEditorMain.gd: NoteTypeボタン接続ループ削除、`_on_note_type_pressed`削除、`_update_note_type_buttons`削除、`set_note_type`削除、数字キー1-7のノートタイプ切り替え削除、`current_note_type`変数削除
  - Timeline.gd: `current_note_type`変数削除。`_build_note_data`をキー状態ベースに変更:
    - v_held = Input.is_key_pressed(KEY_V) and not Input.is_key_pressed(KEY_CTRL)
    - x_held = Input.is_key_pressed(KEY_X)
    - c_held = Input.is_key_pressed(KEY_C) and not Input.is_key_pressed(KEY_CTRL)
    - col<=2 (top lane): no key→top, x→long_top, c→chain(top), v→top (vertical n/a)
    - col>=3 (shared lane): no key→normal, v→vertical, x→long_normal, v+x→long_vertical, c→chain(normal), v+c→chain(vertical)
  - long ノートドラッグ: X キーが押されているときに開始。ドラッグ開始時に note_type をキャプチャして`_long_drag_note_type`に保存し、リリース時に使用
  - 選択モード（Sキー）は変更なし
  - ChartEditor.tscn を build_ChartEditor.gd から再生成
- **Verify:** ノートタイプボタンがコントロールバーから消えている。クリックで normal/top が配置される。v+クリックで vertical、x+クリックで long、c+クリックで chain が配置される。v+x+クリックで long_vertical、v+c+クリックで chain(vertical) が配置される。

---

## 10. Chain Click: Convert/Extend from Previous Note

- **Status:** done
- **Depends on:** 9
- **Targets:** scripts/Timeline.gd, scripts/UndoRedoAction.gd
- **Goal:** c+クリック・v+c+クリック時の挙動を変更。同レーンの直前ノートを確認し、normal/vertical/top なら chain に変換、chain（last_long=false）なら chain を一つ伸ばす。どの条件にも当てはまらない場合は何もしない。
- **Requirements:**
  - UndoRedoAction.gd: `ReplaceNoteAction(index, old_note, new_note)` を追加（undo/redo でノートを丸ごと入れ替え）
  - Timeline.gd: `_place_note_at` で c_held を検出したら `_handle_chain_click(snapped_time, col)` を呼ぶ
  - `_handle_chain_click(snapped_time, col)`:
    1. 同 col で `time < snapped_time` の最も近いノートを検索 → `prev_note`, `prev_index`
    2. prev が存在しなければ何もしない
    3. prev.type が "normal"/"vertical"/"top" の場合:
       - interval = snapped_time - prev_note.time
       - chain_type = prev.type ("normal"→"normal","vertical"→"vertical","top"→"top")
       - new_chain = { type:"chain", time:prev.time, chain_type, lane or top_lane from prev, chain_count:2, chain_interval:interval, last_long:false }
       - ReplaceNoteAction(prev_index, prev_note, new_chain) を _request_action で実行
    4. prev.type が "chain" かつ prev.last_long==false の場合:
       - EditPropertyAction(prev_index, "chain_count", old_count, old_count+1) を _request_action で実行
    5. それ以外（long系、chain+last_long=true）: 何もしない
  - v_held の有無は chain_type の決定に影響しない（chain_type は prev_note の type から決まる）
- **Verify:** normal ノートの後を c+クリックすると chain に変換される（time/lane/chain_type が正しい）。chain の後を c+クリックすると chain_count が+1される。long ノートの後、またはchainのlast_long=trueの後はc+クリックしても何も起こらない。

---

## 5. Presentation Video

- **Status:** done
- **Depends on:** 4
- **Goal:** 完成したチャートエディターを30秒のデモ動画で紹介する。
- **Requirements:**
  - Write test/presentation.gd — a SceneTree script (extends SceneTree)
  - sample/chart.jsonを読み込んだエディター画面を映す
  - タイムラインのスクロール、ズームイン/アウト、ノーツ配置、再生操作などを順に見せる
  - ~900 frames at 30 FPS (30 seconds)
  - Use Video Capture from godot-capture (AVI via --write-movie, convert to MP4 with ffmpeg)
  - Output: screenshots/presentation/gameplay.mp4
  - 2Dアプリなのでカメラパンは不要。UIの各部分を順番に映す
- **Verify:** A smooth MP4 video showing the chart editor UI with notes on the timeline, smooth scrolling, and playback controls visible.
