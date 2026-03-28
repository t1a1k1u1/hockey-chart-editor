# Project Memory

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
