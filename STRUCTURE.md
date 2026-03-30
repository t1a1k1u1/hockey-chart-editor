# Hockey Chart Editor

## Dimension: 2D (UI-only application, no game physics)

## Input Actions

| Action | Keys |
|--------|------|
| file_new | Ctrl+N |
| file_open | Ctrl+O |
| file_save | Ctrl+S |
| file_save_as | Ctrl+Shift+S |
| edit_undo | Ctrl+Z |
| edit_redo | Ctrl+Y, Ctrl+Shift+Z |
| edit_select_all | Ctrl+A |
| edit_duplicate | Ctrl+D |
| edit_copy | Ctrl+C |
| edit_paste | Ctrl+V |
| edit_delete | Delete |
| playback_toggle | Space |
| playback_stop | Escape (when playing) |
| playhead_home | Home |
| playhead_end | End |
| playhead_left | Left arrow |
| playhead_right | Right arrow |
| playhead_left_measure | Shift+Left |
| playhead_right_measure | Shift+Right |
| snap_toggle | Tab |
| snap_coarser | [ |
| snap_finer | ] |
| zoom_reset | Ctrl+0 |
| add_bpm_change | Ctrl+B |
| select_tool | S |
| note_type_1 | 1 (normal) |
| note_type_2 | 2 (top) |
| note_type_3 | 3 (vertical) |
| note_type_4 | 4 (long_normal) |
| note_type_5 | 5 (long_top) |
| note_type_6 | 6 (long_vertical) |
| note_type_7 | 7 (chain) |

## Scenes

### ChartEditor (Main)
- **File:** res://scenes/ChartEditor.tscn
- **Root type:** Node
- **Script:** res://scripts/ChartEditorMain.gd
- **Children:**
  - MenuBarContainer (PanelContainer) — menu bar row
    - MenuBar — File/Edit/View menus
  - ControlBarContainer (PanelContainer) — toolbar row
    - ControlBar (HBoxContainer)
      - PlayButton (Button, text="▶")
      - StopButton (Button, text="■")
      - TimeLabel (Label, text="0:00.000")
      - Separator (VSeparator)
      - BpmLabel (Label, text="BPM")
      - BpmInput (SpinBox, min=1, max=999, step=0.1)
      - Separator (VSeparator)
      - SnapLabel (Label, text="Snap")
      - SnapDivSelect (OptionButton) — options: 1/2/3/4/6/8
      - SnapToggle (CheckButton, text="Snap")
      - Separator (VSeparator)
      - NoteTypeLabel (Label, text="Type")
      - NoteType1 (Button, text="N") — normal
      - NoteType2 (Button, text="T") — top
      - NoteType3 (Button, text="V") — vertical
      - NoteType4 (Button, text="LN") — long_normal
      - NoteType5 (Button, text="LT") — long_top
      - NoteType6 (Button, text="LV") — long_vertical
      - NoteType7 (Button, text="CH") — chain
      - Separator (VSeparator)
      - OffsetLabel (Label, text="Offset")
      - OffsetInput (SpinBox, min=-10, max=10, step=0.001)
  - MainArea (HBoxContainer, size_flags=expand) — central 3-panel area
    - TrackHeaderPanel (PanelContainer, custom_minimum_size.x=120)
      - TrackHeaderList (VBoxContainer) — track row labels
    - TimelineArea (VBoxContainer, size_flags=expand)
      - Timeline (Control, script=Timeline.gd, size_flags=expand) — main canvas
      - HScrollBar (HScrollBar)
    - PropertyPanelContainer (PanelContainer, custom_minimum_size.x=240)
      - PropertyPanel (ScrollContainer)
        - PropertyPanelContent (VBoxContainer, script=PropertyPanel.gd)
  - StatusBar (PanelContainer) — bottom status row
    - StatusLabel (Label, text="Ready")
  - FileDialog (FileDialog) — open/save dialogs
  - ConfirmationDialog (ConfirmationDialog) — unsaved changes warning
  - AcceptDialog (AcceptDialog) — error messages
  - AudioStreamPlayer (AudioStreamPlayer, script=AudioPlayer.gd)

### Timeline (embedded in ChartEditor, no separate .tscn needed)

## Scripts

### ChartEditorMain
- **File:** res://scripts/ChartEditorMain.gd
- **Extends:** Node
- **Attaches to:** ChartEditor:ChartEditor
- **Signals emitted:** chart_loaded, chart_saved, selection_changed, playhead_moved
- **Signals received:** Timeline.note_clicked, Timeline.note_placed, PropertyPanel.property_changed
- **Responsibilities:** Editor state machine (current tool, selected notes, undo/redo stack, file path, dirty flag). Routes input actions to subsystems. Owns the UndoRedo stack.

### ChartData
- **File:** res://scripts/ChartData.gd
- **Extends:** RefCounted
- **Responsibilities:** Holds meta dict + notes array in memory. JSON serialization/deserialization. bpm_at(time) calculation. Sorting notes by time. Validates chart.json schema compatibility.

### Timeline
- **File:** res://scripts/Timeline.gd
- **Extends:** Control
- **Attaches to:** ChartEditor:MainArea:TimelineArea:Timeline
- **Signals emitted:** note_clicked(note_data), note_placed(note_data), ruler_clicked(time), bpm_marker_clicked(bpm_change)
- **Responsibilities:** Custom _draw() for ruler, BPM change band, grid lines, track rows, all note types, playhead, selection rect, drag preview. Handles mouse input for note placement, selection, dragging, right-click delete. Zoom and scroll state. Calls NoteRenderer for drawing.

### BpmGrid
- **File:** res://scripts/BpmGrid.gd
- **Extends:** RefCounted
- **Responsibilities:** Given bpm_changes array, computes bpm_at(time). Calculates beat/measure positions for grid rendering. Snaps time values to grid. Returns array of grid line positions (time, type) for a given visible range.

### NoteRenderer
- **File:** res://scripts/NoteRenderer.gd
- **Extends:** RefCounted
- **Responsibilities:** Stateless drawing helper. draw_note(canvas, note, rect, is_selected, pixels_per_second) draws the correct visual for each note type. Handles normal, long (with rounded caps), and chain (with connector lines) rendering.

### AudioPlayer
- **File:** res://scripts/AudioPlayer.gd
- **Extends:** AudioStreamPlayer
- **Attaches to:** ChartEditor:AudioStreamPlayer
- **Signals emitted:** playback_started, playback_stopped, playback_paused
- **Responsibilities:** Loads OGG/WAV files. play_from(time) respects meta.offset. Tracks playhead time in sync with audio position. Emits playhead_time each _process frame during playback.

### PropertyPanel
- **File:** res://scripts/PropertyPanel.gd
- **Extends:** VBoxContainer
- **Attaches to:** ChartEditor:MainArea:PropertyPanelContainer:PropertyPanel:PropertyPanelContent
- **Signals emitted:** property_changed(note_index, field, value), metadata_changed(field, value)
- **Responsibilities:** Shows/hides fields based on selected note type. Populates values from selection. Emits changes back to ChartEditorMain.

### UndoRedoAction
- **File:** res://scripts/UndoRedoAction.gd
- **Extends:** RefCounted
- **Responsibilities:** Base class for undo/redo operations. Subclasses: AddNoteAction, DeleteNoteAction, MoveNoteAction, EditPropertyAction, AddBpmChangeAction, DeleteBpmChangeAction, MoveBpmChangeAction.

## Signal Map

- ChartEditor:Timeline.note_placed -> ChartEditorMain._on_note_placed
- ChartEditor:Timeline.note_clicked -> ChartEditorMain._on_note_clicked
- ChartEditor:Timeline.ruler_clicked -> ChartEditorMain._on_ruler_clicked
- ChartEditor:Timeline.bpm_marker_clicked -> ChartEditorMain._on_bpm_marker_clicked
- ChartEditor:PropertyPanelContent.property_changed -> ChartEditorMain._on_property_changed
- ChartEditor:AudioStreamPlayer.playback_started -> ChartEditorMain._on_playback_started
- ChartEditor:AudioStreamPlayer.playback_stopped -> ChartEditorMain._on_playback_stopped

## Track Column Layout (NUM_COLS = 10)

Column index -> track type mapping (used by Timeline.gd, ChartData.gd, NoteRenderer.gd):

| Col | Label | Type | Note Field |
|-----|-------|------|------------|
| 0 | TOP 0 | top/long_top/chain(top) | top_lane=0 |
| 1 | TOP 1 | top/long_top/chain(top) | top_lane=1 |
| 2 | TOP 2 | top/long_top/chain(top) | top_lane=2 |
| 3 | L 0 | normal/long_normal/vertical/long_vertical/chain (shared) | lane=0 |
| 4 | L 1 | normal/long_normal/vertical/long_vertical/chain (shared) | lane=1 |
| 5 | L 2 | normal/long_normal/vertical/long_vertical/chain (shared) | lane=2 |
| 6 | L 3 | normal/long_normal/vertical/long_vertical/chain (shared) | lane=3 |
| 7 | L 4 | normal/long_normal/vertical/long_vertical/chain (shared) | lane=4 |
| 8 | L 5 | normal/long_normal/vertical/long_vertical/chain (shared) | lane=5 |
| 9 | L 6 | normal/long_normal/vertical/long_vertical/chain (shared) | lane=6 |

Column mapping formula:
- TOP notes: col = top_lane (0..2)
- All other notes (normal/long_normal/vertical/long_vertical/chain(non-top)): col = 3 + lane (3..9)

Separator drawing:
- Major separator between col 2 and col 3 (TOP / shared lanes boundary)
- Minor separators between all other adjacent columns

Background colors:
- col 0-2: COLOR_BG_TOP (#3A2200 orange)
- col 3,5,7,9 (even lane index): COLOR_BG_NORMAL (#001A3A blue)
- col 4,6,8 (odd lane index): COLOR_BG_VERTICAL (#001228 dark blue)

## Note Color Constants

```
COLOR_NORMAL = Color("#4D66FF")
COLOR_TOP = Color("#1AE64D")
COLOR_VERTICAL = Color("#8855FF")
COLOR_CHAIN_NORMAL = Color("#7A8FFF")   # normal系 明度高め
COLOR_CHAIN_TOP = Color("#66FF88")      # top系 明度高め
COLOR_CHAIN_VERTICAL = Color("#BB88FF") # vertical系 明度高め
COLOR_SELECTED_OUTLINE = Color("#FFFF00")
COLOR_PLAYHEAD = Color("#FF4444")
COLOR_BG_TOP = Color("#3A2200")         # TOP行背景 オレンジ系暗め
COLOR_BG_NORMAL = Color("#001A3A")      # NORMAL行背景 青系
COLOR_BG_VERTICAL = Color("#001228")    # VERTICAL行背景 青系暗め
COLOR_SEPARATOR = Color("#333344")
```

## Asset Hints

No external assets required — all visuals are drawn procedurally in GDScript using _draw().
