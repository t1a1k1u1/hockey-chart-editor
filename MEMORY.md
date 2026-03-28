# Project Memory

## Task 7: Timeline Flip + Resize Fix

### Timeline axis flip (bottom=early, top=late)
- `time_to_y(t) = size.y - (t - scroll_offset) * pixels_per_second`
- `y_to_time(y) = (size.y - y) / pixels_per_second + scroll_offset`
- visible_start = scroll_offset (bottom/early), visible_end = scroll_offset + (h - TRACK_HEADER_HEIGHT) / pps (top/late)
- `_zoom_at`: `scroll_offset = pivot_time - (size.y - mouse_pos.y) / new_pps`
- Note move drag: `dt = -dy / pixels_per_second` (flipped sign — mouse down = earlier time)
- Auto-scroll in ChartEditorMain: `target_scroll = time - visible_duration * 0.1` (playhead at bottom 10%)
- `_scroll_by` direction unchanged: wheel_down = scroll_offset increases = see later time content

### Window resize fix
- Root scene node is `Node` (not Control), so `RootVBox`'s PRESET_FULL_RECT anchors don't work after window resize.
- Fix: connect `get_viewport().size_changed` in ChartEditorMain._ready(), handler calls `vbox.set_deferred("size", Vector2(DisplayServer.window_get_size()))`.
- Use `set_deferred` not direct assignment to avoid "non-equal opposite anchors" Godot warning.
- `get_viewport().size_changed` works correctly for this; `get_tree().get_root().size_changed` also works.

### Grid/ruler labels automatically correct
- After `time_to_y` flip, `_draw_grid_lines`, `_draw_ruler`, `_draw_bpm_markers` all use `time_to_y()` so they automatically get correct Y positions — no additional changes needed.

## Task 6: Vertical Timeline

### Architecture change: horizontal → vertical timeline
- Timeline.gd was completely rewritten. X=columns (11 total: TOP0-2, NORMAL, V0-6), Y=time.
- RULER_WIDTH=60px left edge, BPM_BAND_WIDTH=16px next to ruler, TRACK_HEADER_HEIGHT=24px top.
- CONTENT_OFFSET_X = RULER_WIDTH + BPM_BAND_WIDTH = 76px.
- `time_to_y(t)` = TRACK_HEADER_HEIGHT + (t - scroll_offset) * pixels_per_second.
- `col_to_x(col)` = CONTENT_OFFSET_X + col * col_width + col_width * 0.5 (center of column).

### NoteRenderer.gd signature change
- New signature: `draw_note(canvas, note, scroll_offset, pps, is_selected, grid_sec, col_width, content_offset_x, header_height)`.
- Removed old row-based drawing. Now column-based with vertical note orientation.
- Normal notes: wide rectangles (col_width * 0.8 wide, grid_sec * pps tall minimum 8px).
- Long notes: vertical bands with circular caps at top and bottom.
- Chain notes: connector lines drawn vertically between members.

### Scene builder: TrackHeaderPanel removed
- TrackHeaderPanel (120px left sidebar with row labels) was removed from the HBoxContainer.
- Track header is now drawn inside Timeline._draw() as the top 24px band.
- TimelineArea is now HBoxContainer (not VBoxContainer): Timeline on left, VScrollBar on right.
- VScrollBar replaces HScrollBar.

### ChartEditorMain auto-scroll for vertical
- `_on_audio_playhead_changed` now checks `timeline.size.y` and scrolls vertically.
- `visible_height = (timeline.size.y - 24.0) / pixels_per_second` (subtract header height).
- VScrollBar node path: `RootVBox/MainArea/TimelineArea/VScrollBar`.
- Added `_on_vscroll_changed` callback.

### VScrollBar in Timeline._ready()
- Timeline._ready() auto-connects to sibling VScrollBar via `get_parent().get_node_or_null("VScrollBar")`.
- Timeline._update_vscroll() sets max_value, page, value.

### visual_qa.py encoding issue on Windows
- `pathlib.Path.read_text()` without encoding= fails with cp932 on Windows for UTF-8 files.
- Fix: use `.read_text(encoding='utf-8')`.
- Also: `gemini-2.0-flash` is deprecated, use `gemini-2.5-flash`.

### Chart load timing in test harness
- `_load_from_path` called from `_initialize()` fails because chart_data is nil (set in `_ready()`).
- Solution: call `_load_from_path` in frame 1 of `_process()` (after `_ready()` has run).

## Task 5: Presentation Video

### Video capture on Windows
- `godot --rendering-driver opengl3 --write-movie output.avi --fixed-fps 30 --quit-after 900 --script test/presentation.gd` works cleanly on Windows with NVIDIA GPU.
- Output is MJPEG AVI; convert with `ffmpeg -c:v libx264 -pix_fmt yuv420p -crf 28 -preset slow -movflags +faststart`.
- 900 frames at 30 FPS renders at ~428% realtime (7 seconds wall-clock). Output AVI ~75MB, MP4 ~420KB.
- `quit()` in `_process()` exits cleanly after `--quit-after` fires; both are safe to use.

### Programmatic note insertion in presentation script
- `load("res://scripts/UndoRedoAction.gd").AddNoteAction.new(note_dict)` then `main_node.call("execute_action", action)` works from SceneTree scripts.
- After `execute_action`, note count in `chart_data.notes` is immediately updated — no need to wait a frame.

### Timeline scroll in presentation script
- Direct assignment of `tl.scroll_offset = value` + `tl.queue_redraw()` works for smooth animated scrolling in `_process()`.
- Sync HScrollBar via `set_block_signals(true)` / `value = x` / `set_block_signals(false)` to keep them in sync without signal loops.
- `pixels_per_second` must be set on BOTH `_main_node.pixels_per_second` AND `_main_node.timeline.pixels_per_second` for zoom to take effect.

### toggle_playback() needs audio_player not null
- `toggle_playback()` in ChartEditorMain returns immediately if `audio_player` is null (no audio file loaded).
- Sample chart `chart.json` has `meta.audio = "music.wav"` — audio is loaded automatically via `_try_load_audio()` after `_load_from_path()`.
- In presentation script, playback call at frame 391 works reliably 330 frames after chart load.

## Task 4: Audio Playback + Playhead

### AudioStreamWAV.load_from_file() for absolute paths
- `ResourceLoader.load()` fails on absolute external paths (outside `res://`) for `.wav` files — it tries to find an `.import` cache entry first.
- Use `AudioStreamWAV.load_from_file(path)` directly for loading WAV files from absolute filesystem paths. This is a static method that reads raw bytes.
- `AudioStreamOggVorbis.load_from_file(path)` works the same way for OGG files.

### Playhead timing with Time.get_ticks_msec()
- Wall-clock playhead: `_play_start_playhead + (Time.get_ticks_msec() - _play_start_wall) / 1000.0`
- This correctly tracks real elapsed time independent of frame rate, including during `--write-movie` captures that run at arbitrary speed.
- `--write-movie` at 10fps may run at 250-500% real speed, so playhead advances only `real_elapsed / movie_elapsed` × expected time.

### AudioPlayer signal connection via has_signal guard
- `audio_player` is declared as `AudioStreamPlayer` in ChartEditorMain. Its script-defined signals (`playback_started` etc.) are not visible at compile-time from the base type.
- Must use `audio_player.connect("signal_name", callback)` with `has_signal()` guard — same pattern as Timeline signals.

### toggle_playback() paused resume
- When `_is_paused = true`, resume by calling `play_from(_pause_position, offset)` NOT `play_from(playhead_time, offset)`.
- Accessing `audio_player._is_paused` directly from ChartEditorMain works (GDScript allows reading private-convention vars from other scripts).

### Auto-scroll implementation
- Auto-scroll triggers when playhead exits the leading 80% of the visible timeline width.
- `target_scroll = time - visible_width * 0.8` keeps playhead at 80% mark.
- Must sync `HScrollBar.value` (with blocked signals) after updating `timeline.scroll_offset` to keep them in sync.

### _format_time() format string
- `"%d:%02d.%03d" % [m, s, ms]` — minutes:seconds.milliseconds, e.g. `1:05.042`

## Task 3: Note Editing + Undo/Redo

### Signal access on typed Control references
- `timeline` is declared as `Control` in ChartEditorMain, so signals defined in Timeline.gd are NOT visible at compile time. Use `timeline.connect("signal_name", callback)` with `has_signal()` guard instead of `timeline.signal_name.connect(callback)`.
- Same pattern applies to any node whose script-defined signals aren't visible from the declared base type.

### Callable callbacks for Timeline→ChartEditorMain delegation
- Timeline needs to delegate actions (AddNote, DeleteNote, MoveNote) up to ChartEditorMain without importing it. Use `Callable` stored in `_action_callback` / `_move_action_callback` vars. ChartEditorMain calls `timeline.call("set_action_callback", callable)` to wire them.
- This avoids circular dependencies and keeps Timeline decoupled from ChartEditorMain.

### Variable re-declaration in same function scope
- GDScript does not allow re-declaring a variable name in the same function even in a nested if block. In `_draw_notes()`, the `bpm_changes`/`grid_sec`/`grid_width` vars declared at the top of the function can be reused directly in the move-preview block — no re-declaration needed.

### PropertyPanel signal guard (_building flag)
- `_rebuild_ui()` creates SpinBoxes whose initial value triggers `value_changed` immediately. Use `_building: bool = true` during `_rebuild_ui()` and check `if _building: return` in all signal handlers to suppress false property_changed emissions during UI construction.

### ChartEditorMain keyboard shortcuts
- `KEY_S` shortcut for toggle_select_mode must be blocked when a text field (LineEdit/TextEdit/SpinBox) has focus; otherwise typing 's' in metadata fields triggers mode switch.
- Check `get_viewport().gui_get_focus_owner()` before processing non-modifier key shortcuts.

### DeleteNoteAction with multiple deletions
- Deleting multiple selected notes requires processing in descending index order (sort then reverse) so earlier deletions don't shift subsequent indices.

### BPM change dialog
- Built programmatically in `_ready()` via `add_child()` — no scene file needed. SpinBox inside ConfirmationDialog works cleanly.

### PropertyPanel `show_bpm_change` method
- Added to PropertyPanel alongside `show_selection`/`show_metadata`. ChartEditorMain calls it on `_on_bpm_marker_clicked`.
- `bpm_change_edited` signal carries `(change_index, field, value)` — ChartEditorMain handles this in `_on_bpm_change_edited()`.



## Task 2: Timeline + BPM Grid + Note Rendering

### TrackHeader vs Timeline vertical alignment
- The Timeline control has a 36px header at top (RULER_HEIGHT=20 + BPM_BAND_HEIGHT=16). The TrackHeaderList (VBoxContainer) starts at y=0 with no header. This causes 36px vertical misalignment.
- Fix: Add a `HeaderSpacer` Control node (custom_minimum_size.y=36) as the FIRST child of TrackHeaderList in the .tscn scene. This pushes all row labels down to match the timeline content area.
- The NoteRenderer.get_row_y() must also include this 36px offset (HEADER_HEIGHT constant).

### Timeline HScrollBar wiring
- Timeline._ready() auto-connects to sibling HScrollBar via `get_parent().get_node_or_null("HScrollBar")`.
- ChartEditorMain._on_hscroll_changed() updates timeline.scroll_offset directly.
- Both paths update the scrollbar value via _update_hscroll() to keep them in sync.

### BPM grid line rendering
- get_grid_lines() uses fmod with epsilon tolerance to classify measure/beat/sub lines.
- Grid lines draw from content_top (ruler+bpm_band height) to bottom of canvas.
- Ruler only draws measure and beat lines (not sub-divisions) for cleanliness.

### Note rendering row Y
- NoteRenderer.HEADER_HEIGHT = 36 (ruler 20 + bpm_band 16) must be added to all row Y calculations.
- Timeline.get_row_y() and NoteRenderer.get_row_y() both use the same formula: HEADER_HEIGHT + row*32 + sep_count*4.

## Task 1: Core UI + File I/O

### Godot Window nodes auto-show
- `Window` nodes added to the scene tree automatically become visible. Always set `visible = false` in the scene builder AND in `_ready()` after the node reference is obtained.
- Use `metadata_dialog.visible = false` before calling `popup_centered()` is the correct flow.

### Screenshot capture on Windows
- `xvfb-run` does not exist on Windows. Use `godot --rendering-driver opengl3` with `--write-movie` directly — the NVIDIA GPU is available.
- `--headless --write-movie` crashes with signal 11 on Windows (dummy texture backend has no textures). Must use `--rendering-driver opengl3` (or vulkan) instead.
- GPU: NVIDIA GeForce RTX 4070 Ti, OpenGL 3.3.0 driver 576.52

### Chart note count discrepancy
- Task spec says sample chart has 67 notes; actual file at `D:/GoDot Projects/hockey/songs/sample/chart.json` has **52 notes**.
- The file has 68 lines total.

### Scene builder: Panel background colors
- Use `StyleBoxFlat` with `bg_color` to set colored Panel backgrounds in scene builders.
- Label inside a Panel: use `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)` to fill the panel.

### MetadataDialog node paths
- The HBoxContainer children auto-name as `HBoxContainer`, `HBoxContainer2`, `HBoxContainer3`, etc. when using the scene builder. Access them in scripts via these indexed names.

### save_to_json - note field stripping
- The task requires that normal notes have no `lane` field, top/long_top have `top_lane`, vertical/long_vertical have `lane`. Current ChartData.save_to_json() does NOT strip unused fields — this should be implemented in a future task when notes are actually written by the editor.

### Control bar layout
- Adding `VBoxContainer.add_theme_constant_override("separation", 0)` and `HBoxContainer` separation=0 eliminates unwanted spacing between track header rows.
- Note type buttons need `toggle_mode = true` to visually indicate the selected type.

### Audio file
- Sample audio at `D:/GoDot Projects/hockey/songs/sample/music.wav`
- Chart meta.audio field may be empty or relative path — try both `dir/audio` and `dir/meta.audio`.

### Metadata dialog form node paths
- The form VBox auto-generates HBoxContainer, HBoxContainer2, HBoxContainer3... names for rows.
- Reliable path: `MetaVBox/MetaMargin/MetaForm/HBoxContainer/MetaTitleEdit` etc.
