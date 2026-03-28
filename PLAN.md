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

- **Status:** pending
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

- **Status:** pending
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

- **Status:** pending
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

## 5. Presentation Video

- **Status:** pending
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
