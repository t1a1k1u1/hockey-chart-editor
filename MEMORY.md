# Project Memory

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
