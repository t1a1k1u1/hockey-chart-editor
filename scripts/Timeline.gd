extends Control
## res://scripts/Timeline.gd
## Vertical timeline canvas: X=track columns, Y=time (top=early, bottom=late).

signal note_clicked(note_data: Dictionary, note_index: int)
signal note_placed(note_data: Dictionary)
signal ruler_clicked(time: float)
signal bpm_marker_clicked(bpm_change: Dictionary, change_index: int)

const RULER_WIDTH = 60.0          # Left ruler width (px)
const BPM_BAND_WIDTH = 16.0       # BPM change band width (px)
const TRACK_HEADER_HEIGHT = 24.0  # Top track header height (px)
const CONTENT_OFFSET_X = RULER_WIDTH + BPM_BAND_WIDTH  # 76px
const DEFAULT_PPS = 200.0         # pixels per second (vertical)
const NUM_COLS = 11               # columns: TOP0,TOP1,TOP2,NORMAL,V0..V6

# Track column colors
const COLOR_BG_TOP = Color(0.227, 0.133, 0.0)       # #3A2200 orange
const COLOR_BG_NORMAL = Color(0.0, 0.102, 0.227)    # #001A3A blue
const COLOR_BG_VERTICAL = Color(0.0, 0.071, 0.157)  # #001228 dark blue
const COLOR_SEP_MINOR = Color(0.15, 0.15, 0.2, 0.8)
const COLOR_SEP_MAJOR = Color(0.3, 0.3, 0.4, 1.0)
const COLOR_RULER_BG = Color(0.08, 0.08, 0.10, 1.0)
const COLOR_BPM_BAND_BG = Color(0.06, 0.06, 0.09, 1.0)
const COLOR_HEADER_BG = Color(0.12, 0.12, 0.15, 1.0)
const COLOR_PLAYHEAD = Color(1.0, 0.267, 0.267)     # #FF4444
const COLOR_SELECT_RECT = Color(1.0, 1.0, 0.0, 0.15)
const COLOR_SELECT_RECT_BORDER = Color(1.0, 1.0, 0.0, 0.6)
const COLOR_LONG_PREVIEW = Color(0.6, 0.8, 1.0, 0.4)

var pixels_per_second: float = DEFAULT_PPS
var scroll_offset: float = 0.0  # seconds
var playhead_time: float = 0.0

var chart_data = null
var bpm_grid = null
var note_renderer = null

var snap_enabled: bool = true
var snap_division: int = 4
var current_note_type: String = "normal"
var is_select_mode: bool = false
var selected_notes: Array = []

# Drag/selection state
var _drag_start: Vector2 = Vector2.ZERO
var _drag_end: Vector2 = Vector2.ZERO
var _is_dragging: bool = false

# Long note drag state
var _long_drag_active: bool = false
var _long_drag_start_time: float = 0.0
var _long_drag_end_time: float = 0.0
var _long_drag_col: int = 0

# Note move drag state
var _note_move_active: bool = false
var _note_move_index: int = -1
var _note_move_origin_mouse_x: float = 0.0
var _note_move_origin_mouse_y: float = 0.0
var _note_move_original_time: float = 0.0
var _note_move_original_col: int = 0
var _note_move_preview_time: float = 0.0
var _note_move_preview_col: int = 0

# BPM marker drag state
var _bpm_drag_active: bool = false
var _bpm_drag_index: int = -1
var _bpm_drag_original_time: float = 0.0

# VScrollBar reference (set by ChartEditorMain or self during ready)
var vscrollbar = null

# Callbacks (set by ChartEditorMain)
var _action_callback: Callable = Callable()
var _move_action_callback: Callable = Callable()

func _ready() -> void:
	bpm_grid = load("res://scripts/BpmGrid.gd").new()
	note_renderer = load("res://scripts/NoteRenderer.gd").new()
	clip_contents = true
	# Try to find VScrollBar sibling
	var parent = get_parent()
	if parent:
		vscrollbar = parent.get_node_or_null("VScrollBar")
		if vscrollbar:
			vscrollbar.value_changed.connect(_on_vscroll_changed)

#region Coordinate Transforms

func get_col_width() -> float:
	return (size.x - CONTENT_OFFSET_X) / float(NUM_COLS)

func time_to_y(time: float) -> float:
	return TRACK_HEADER_HEIGHT + (time - scroll_offset) * pixels_per_second

func y_to_time(y: float) -> float:
	return (y - TRACK_HEADER_HEIGHT) / pixels_per_second + scroll_offset

func col_to_x(col: int) -> float:
	var cw = get_col_width()
	return CONTENT_OFFSET_X + col * cw + cw * 0.5

func x_to_col(x: float) -> int:
	var cw = get_col_width()
	if cw <= 0:
		return 0
	var col = int((x - CONTENT_OFFSET_X) / cw)
	return clamp(col, 0, NUM_COLS - 1)

func _note_to_col(note: Dictionary) -> int:
	var t = note.get("type", "normal")
	var ct = note.get("chain_type", "normal")
	if t == "top" or t == "long_top" or (t == "chain" and ct == "top"):
		return note.get("top_lane", 0)  # 0,1,2
	elif t == "normal" or t == "long_normal" or (t == "chain" and ct == "normal"):
		return 3
	elif t == "vertical" or t == "long_vertical" or (t == "chain" and ct == "vertical"):
		return 4 + note.get("lane", 0)  # 4..10
	return 3

#endregion

#region Draw

func _draw() -> void:
	var w = size.x
	var h = size.y
	if w <= 0 or h <= 0:
		return

	var bpm_changes: Array = []
	if chart_data != null:
		bpm_changes = chart_data.meta.get("bpm_changes", [])

	var visible_start = scroll_offset
	var visible_end = scroll_offset + (h - TRACK_HEADER_HEIGHT) / pixels_per_second

	# 1. Column backgrounds
	_draw_col_backgrounds(h)

	# 2. Grid lines (horizontal)
	_draw_grid_lines(visible_start, visible_end, bpm_changes, h)

	# 3. Ruler (left 60px column)
	draw_rect(Rect2(0, TRACK_HEADER_HEIGHT, RULER_WIDTH, h - TRACK_HEADER_HEIGHT), COLOR_RULER_BG)

	# 4. BPM change band (16px column next to ruler)
	draw_rect(Rect2(RULER_WIDTH, TRACK_HEADER_HEIGHT, BPM_BAND_WIDTH, h - TRACK_HEADER_HEIGHT), COLOR_BPM_BAND_BG)

	# 5. Ruler tick marks and labels
	_draw_ruler(visible_start, visible_end, bpm_changes)

	# 6. BPM change markers
	_draw_bpm_markers(bpm_changes)

	# 7. Track header (top 24px)
	_draw_track_header(w)

	# 8. Notes
	if chart_data != null:
		_draw_notes(visible_start, visible_end)

	# 9. Long note drag preview
	if _long_drag_active:
		_draw_long_preview()

	# 10. Playhead (horizontal line)
	var py = time_to_y(playhead_time)
	if py >= TRACK_HEADER_HEIGHT and py <= h:
		draw_line(Vector2(CONTENT_OFFSET_X, py), Vector2(w, py), COLOR_PLAYHEAD, 2.0)

	# 11. Selection rectangle
	if _is_dragging:
		var rect = _get_drag_rect()
		draw_rect(rect, COLOR_SELECT_RECT)
		draw_rect(rect, COLOR_SELECT_RECT_BORDER, false, 1.0)

func _draw_col_backgrounds(h: float) -> void:
	var cw = get_col_width()
	for col in range(NUM_COLS):
		var cx = CONTENT_OFFSET_X + col * cw
		var color: Color
		if col <= 2:
			color = COLOR_BG_TOP
		elif col == 3:
			color = COLOR_BG_NORMAL
		else:
			color = COLOR_BG_VERTICAL
		draw_rect(Rect2(cx, TRACK_HEADER_HEIGHT, cw, h - TRACK_HEADER_HEIGHT), color)
		# Draw thin separator line between columns
		if col > 0:
			var sep_color = COLOR_SEP_MAJOR if (col == 3 or col == 4) else COLOR_SEP_MINOR
			var sep_w = 2.0 if (col == 3 or col == 4) else 1.0
			draw_line(Vector2(cx, TRACK_HEADER_HEIGHT), Vector2(cx, h), sep_color, sep_w)

func _draw_track_header(w: float) -> void:
	# Background
	draw_rect(Rect2(0, 0, w, TRACK_HEADER_HEIGHT), COLOR_HEADER_BG)
	# Ruler / BPM band area in header
	draw_rect(Rect2(0, 0, CONTENT_OFFSET_X, TRACK_HEADER_HEIGHT), Color(0.05, 0.05, 0.07, 1.0))
	var cw = get_col_width()
	var col_labels = ["TOP 0", "TOP 1", "TOP 2", "NORMAL", "V 0", "V 1", "V 2", "V 3", "V 4", "V 5", "V 6"]
	for col in range(NUM_COLS):
		var cx = CONTENT_OFFSET_X + col * cw
		var cx_mid = cx + cw * 0.5
		# Column background for header
		var color: Color
		if col <= 2:
			color = Color(0.3, 0.18, 0.0, 1.0)
		elif col == 3:
			color = Color(0.0, 0.14, 0.3, 1.0)
		else:
			color = Color(0.0, 0.1, 0.2, 1.0)
		draw_rect(Rect2(cx, 0, cw, TRACK_HEADER_HEIGHT), color)
		# Label
		var label = col_labels[col]
		var font_size = 9
		var text_width = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var tx = cx_mid - text_width * 0.5
		var ty = TRACK_HEADER_HEIGHT - 5.0
		draw_string(ThemeDB.fallback_font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.9, 0.9, 0.9))

func _draw_grid_lines(start_time: float, end_time: float, bpm_changes: Array, h: float) -> void:
	if bpm_changes.is_empty():
		return
	var lines = bpm_grid.get_grid_lines(start_time, end_time, bpm_changes, snap_division)
	var content_left = CONTENT_OFFSET_X
	var content_right = size.x
	for line in lines:
		var y = time_to_y(line["time"])
		if y < TRACK_HEADER_HEIGHT or y > h:
			continue
		var lt = line["line_type"]
		var col: Color
		var lw: float
		match lt:
			"measure":
				col = Color(1, 1, 1, 0.5)
				lw = 2.0
			"beat":
				col = Color(1, 1, 1, 0.3)
				lw = 1.0
			_:
				col = Color(1, 1, 1, 0.15)
				lw = 1.0
		draw_line(Vector2(content_left, y), Vector2(content_right, y), col, lw)

func _draw_ruler(start_time: float, end_time: float, bpm_changes: Array) -> void:
	if bpm_changes.is_empty():
		# No BPM: draw 0.5s interval lines
		var t = ceil(start_time * 2.0) / 2.0
		while t <= end_time + 0.01:
			var y = time_to_y(t)
			if y >= TRACK_HEADER_HEIGHT:
				draw_line(Vector2(RULER_WIDTH * 0.5, y), Vector2(RULER_WIDTH, y), Color(1, 1, 1, 0.6), 1.0)
				var label = "%.1f" % t
				draw_string(ThemeDB.fallback_font, Vector2(2, y - 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.8))
			t += 0.5
		return

	var lines = bpm_grid.get_grid_lines(start_time, end_time, bpm_changes, snap_division)
	for line in lines:
		var y = time_to_y(line["time"])
		if y < TRACK_HEADER_HEIGHT:
			continue
		var lt = line["line_type"]
		if lt == "measure":
			draw_line(Vector2(RULER_WIDTH * 0.4, y), Vector2(RULER_WIDTH, y), Color(1, 1, 1, 0.8), 1.5)
			var label_text: String
			if snap_enabled:
				var measure_num = _get_measure_number(line["time"], bpm_changes)
				label_text = str(measure_num)
			else:
				label_text = "%.1f" % line["time"]
			draw_string(ThemeDB.fallback_font, Vector2(2, y - 2), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.85))
		elif lt == "beat":
			draw_line(Vector2(RULER_WIDTH * 0.6, y), Vector2(RULER_WIDTH, y), Color(1, 1, 1, 0.5), 1.0)
		else:
			draw_line(Vector2(RULER_WIDTH * 0.8, y), Vector2(RULER_WIDTH, y), Color(1, 1, 1, 0.2), 1.0)

func _get_measure_number(time: float, bpm_changes: Array) -> int:
	if bpm_changes.is_empty():
		return 1
	var sorted_changes = bpm_changes.duplicate()
	sorted_changes.sort_custom(func(a, b): return a["time"] < b["time"])
	var total_beats = 0.0
	for i in range(sorted_changes.size()):
		var section_start = sorted_changes[i]["time"]
		var section_end = time if i + 1 >= sorted_changes.size() else min(sorted_changes[i + 1]["time"], time)
		if section_start >= time:
			break
		var bpm = sorted_changes[i]["bpm"]
		var beat = 60.0 / bpm
		total_beats += (section_end - section_start) / beat
	return int(floor(total_beats / 4.0)) + 1

func _draw_bpm_markers(bpm_changes: Array) -> void:
	var h = size.y
	for i in range(bpm_changes.size()):
		var bc = bpm_changes[i]
		var y = time_to_y(bc["time"])
		if y < TRACK_HEADER_HEIGHT - 10 or y > h + 10:
			continue
		# Horizontal line in the BPM band
		draw_line(Vector2(RULER_WIDTH, y), Vector2(RULER_WIDTH + BPM_BAND_WIDTH, y), Color(1.0, 0.8, 0.2, 0.9), 1.5)
		# BPM label (rotated text approximated as small text)
		var label = "%.0f" % bc["bpm"]
		draw_string(ThemeDB.fallback_font, Vector2(RULER_WIDTH + 1, y - 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.8, 0.2, 0.9))

func _draw_notes(start_time: float, end_time: float) -> void:
	if chart_data == null or chart_data.notes.is_empty():
		return
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	var center_time = scroll_offset + (size.y - TRACK_HEADER_HEIGHT) * 0.5 / pixels_per_second
	var grid_sec = bpm_grid.grid_interval(center_time, bpm_changes, snap_division)

	for i in range(chart_data.notes.size()):
		var note = chart_data.notes[i]
		if _note_move_active and i == _note_move_index:
			continue
		var note_time = note.get("time", 0.0)
		var note_end_time = note.get("end_time", note_time + note.get("chain_count", 1) * note.get("chain_interval", 0.5) + 0.5)
		if note_end_time < start_time - 1.0 or note_time > end_time + 1.0:
			continue
		var is_selected = selected_notes.has(i)
		note_renderer.draw_note(self, note, scroll_offset, pixels_per_second, is_selected, grid_sec, get_col_width(), CONTENT_OFFSET_X, TRACK_HEADER_HEIGHT)

	# Draw move preview
	if _note_move_active and _note_move_index >= 0 and _note_move_index < chart_data.notes.size():
		var orig_note = chart_data.notes[_note_move_index]
		var preview_note = orig_note.duplicate(true)
		preview_note["time"] = _note_move_preview_time
		if preview_note.has("end_time"):
			var dur = orig_note.get("end_time", orig_note["time"]) - orig_note["time"]
			preview_note["end_time"] = _note_move_preview_time + dur
		var pc = _note_move_preview_col
		var nt = preview_note.get("type", "normal")
		if nt == "top" or nt == "long_top":
			preview_note["top_lane"] = clamp(pc, 0, 2)
		elif nt == "vertical" or nt == "long_vertical":
			preview_note["lane"] = clamp(pc - 4, 0, 6)
		elif nt == "chain":
			var ct = preview_note.get("chain_type", "normal")
			if ct == "top":
				preview_note["top_lane"] = clamp(pc, 0, 2)
			elif ct == "vertical":
				preview_note["lane"] = clamp(pc - 4, 0, 6)
		note_renderer.draw_note(self, preview_note, scroll_offset, pixels_per_second, true, grid_sec, get_col_width(), CONTENT_OFFSET_X, TRACK_HEADER_HEIGHT)

func _draw_long_preview() -> void:
	var cw = get_col_width()
	var cx = CONTENT_OFFSET_X + _long_drag_col * cw + cw * 0.5
	var y1 = time_to_y(_long_drag_start_time)
	var y2 = time_to_y(_long_drag_end_time)
	if y2 < y1:
		var tmp = y1
		y1 = y2
		y2 = tmp
	var bw = cw * 0.6
	var rx = cx - bw * 0.5
	var r = bw * 0.5
	draw_rect(Rect2(rx, y1, bw, y2 - y1), COLOR_LONG_PREVIEW)
	draw_circle(Vector2(cx, y1), r, COLOR_LONG_PREVIEW)
	draw_circle(Vector2(cx, y2), r, COLOR_LONG_PREVIEW)

#endregion

#region Scrollbar

func _update_vscroll() -> void:
	if vscrollbar == null:
		return
	var total_duration = 0.0
	if chart_data != null and not chart_data.notes.is_empty():
		for note in chart_data.notes:
			var et = note.get("end_time", note.get("time", 0.0))
			if et > total_duration:
				total_duration = et
			var nt = note.get("time", 0.0)
			var chain_dur = note.get("chain_count", 1) * note.get("chain_interval", 0.0)
			if nt + chain_dur > total_duration:
				total_duration = nt + chain_dur
	total_duration = max(total_duration + 10.0, 60.0)
	var visible_secs = (size.y - TRACK_HEADER_HEIGHT) / pixels_per_second
	vscrollbar.set_block_signals(true)
	vscrollbar.min_value = 0.0
	vscrollbar.max_value = total_duration
	vscrollbar.page = visible_secs
	vscrollbar.value = scroll_offset
	vscrollbar.set_block_signals(false)

func _on_vscroll_changed(value: float) -> void:
	scroll_offset = value
	queue_redraw()

#endregion

#region Input

func _snap_time(time: float) -> float:
	if not snap_enabled or chart_data == null:
		return time
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	if bpm_changes.is_empty():
		return time
	return bpm_grid.snap_time(time, bpm_changes, snap_division)

func _grid_interval_at(time: float) -> float:
	if chart_data == null:
		return 0.25
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	return bpm_grid.grid_interval(time, bpm_changes, snap_division)

func _note_at_position(pos: Vector2) -> int:
	if chart_data == null:
		return -1
	var click_time = y_to_time(pos.y)
	var col = x_to_col(pos.x)
	if pos.x < CONTENT_OFFSET_X:
		return -1
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	var grid_sec = bpm_grid.grid_interval(click_time, bpm_changes, snap_division)
	var half_h_sec = max(grid_sec * 0.6, 4.0 / pixels_per_second)
	for i in range(chart_data.notes.size() - 1, -1, -1):
		var note = chart_data.notes[i]
		var note_col = _note_to_col(note)
		if note_col != col:
			continue
		var nt = note.get("time", 0.0)
		var net = note.get("end_time", nt)
		var note_type = note.get("type", "normal")
		if note_type in ["long_normal", "long_top", "long_vertical"]:
			if click_time >= nt - half_h_sec and click_time <= net + half_h_sec:
				return i
		elif note_type == "chain":
			var count = note.get("chain_count", 2)
			var interval = note.get("chain_interval", 0.4)
			for ci in range(count):
				var ct = nt + ci * interval
				if abs(click_time - ct) <= half_h_sec:
					return i
		else:
			if abs(click_time - nt) <= half_h_sec:
				return i
	return -1

func _bpm_marker_at_y(y: float) -> int:
	if chart_data == null:
		return -1
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	for i in range(bpm_changes.size()):
		var by = time_to_y(bpm_changes[i]["time"])
		if abs(by - y) < 8.0:
			return i
	return -1

func _constrain_col_for_note(note: Dictionary, new_col: int) -> int:
	var note_type = note.get("type", "normal")
	if note_type in ["top", "long_top"]:
		return clamp(new_col, 0, 2)
	elif note_type in ["normal", "long_normal"]:
		return 3
	elif note_type in ["vertical", "long_vertical"]:
		return clamp(new_col, 4, 10)
	elif note_type == "chain":
		var ct = note.get("chain_type", "normal")
		if ct == "top":
			return clamp(new_col, 0, 2)
		elif ct == "normal":
			return 3
		else:
			return clamp(new_col, 4, 10)
	return new_col

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		var ke = event as InputEventKey
		if ke.pressed and ke.ctrl_pressed and ke.keycode == KEY_0:
			pixels_per_second = DEFAULT_PPS
			_update_vscroll()
			queue_redraw()
			get_viewport().set_input_as_handled()

func _handle_mouse_button(mbe: InputEventMouseButton) -> void:
	if mbe.pressed:
		if mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mbe.position, 1.15)
			get_viewport().set_input_as_handled()
			return
		elif mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mbe.position, 1.0 / 1.15)
			get_viewport().set_input_as_handled()
			return
		elif not mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_by(-80.0 / pixels_per_second)
			get_viewport().set_input_as_handled()
			return
		elif not mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(80.0 / pixels_per_second)
			get_viewport().set_input_as_handled()
			return

		if mbe.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(mbe.position)
			get_viewport().set_input_as_handled()
			return

		if mbe.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(mbe.position, mbe.ctrl_pressed)
			get_viewport().set_input_as_handled()
			return
	else:
		if mbe.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_release(mbe.position)

func _handle_right_click(pos: Vector2) -> void:
	# BPM band click: delete BPM marker
	if pos.x >= RULER_WIDTH and pos.x < CONTENT_OFFSET_X and pos.y >= TRACK_HEADER_HEIGHT:
		var idx = _bpm_marker_at_y(pos.y)
		if idx > 0:
			var bpm_changes = chart_data.meta.get("bpm_changes", []) if chart_data else []
			var action_script = load("res://scripts/UndoRedoAction.gd")
			var action = action_script.DeleteBpmChangeAction.new(idx, bpm_changes[idx])
			_request_action(action)
		return
	# Track area: delete note
	if pos.x >= CONTENT_OFFSET_X and pos.y >= TRACK_HEADER_HEIGHT:
		var idx = _note_at_position(pos)
		if idx >= 0:
			var action_script = load("res://scripts/UndoRedoAction.gd")
			var action = action_script.DeleteNoteAction.new(idx, chart_data.notes[idx])
			_request_action(action)

func _handle_left_click(pos: Vector2, ctrl_held: bool) -> void:
	if chart_data == null:
		return

	# Ruler click: move playhead
	if pos.x < RULER_WIDTH and pos.y >= TRACK_HEADER_HEIGHT:
		ruler_clicked.emit(y_to_time(pos.y))
		return

	# BPM band click
	if pos.x >= RULER_WIDTH and pos.x < CONTENT_OFFSET_X and pos.y >= TRACK_HEADER_HEIGHT:
		var idx = _bpm_marker_at_y(pos.y)
		if idx >= 0:
			var bpm_changes = chart_data.meta.get("bpm_changes", []) if chart_data else []
			bpm_marker_clicked.emit(bpm_changes[idx], idx)
			if idx > 0:
				_bpm_drag_active = true
				_bpm_drag_index = idx
				_bpm_drag_original_time = bpm_changes[idx]["time"]
		return

	# Header click: ignored
	if pos.y < TRACK_HEADER_HEIGHT:
		return

	# Track area
	if pos.x < CONTENT_OFFSET_X:
		return

	if is_select_mode:
		var note_idx = _note_at_position(pos)
		if note_idx >= 0:
			if ctrl_held:
				if selected_notes.has(note_idx):
					selected_notes.erase(note_idx)
				else:
					selected_notes.append(note_idx)
			else:
				selected_notes = [note_idx]
			_emit_note_clicked_for_selection()
			queue_redraw()
			if selected_notes.has(note_idx) and chart_data != null and note_idx < chart_data.notes.size():
				_note_move_active = true
				_note_move_index = note_idx
				_note_move_origin_mouse_x = pos.x
				_note_move_origin_mouse_y = pos.y
				var n = chart_data.notes[note_idx]
				_note_move_original_time = n.get("time", 0.0)
				_note_move_original_col = _note_to_col(n)
				_note_move_preview_time = _note_move_original_time
				_note_move_preview_col = _note_move_original_col
		else:
			if not ctrl_held:
				selected_notes.clear()
				_emit_selection_cleared()
				queue_redraw()
			_drag_start = pos
			_drag_end = pos
			_is_dragging = true
	else:
		_place_note_at(pos)

func _place_note_at(pos: Vector2) -> void:
	if chart_data == null:
		return
	var clicked_time = y_to_time(pos.y)
	var snapped_time = _snap_time(clicked_time)
	var col = x_to_col(pos.x)

	var note_data = _build_note_data(snapped_time, col)
	if note_data.is_empty():
		return

	var note_type = current_note_type
	if note_type in ["long_normal", "long_top", "long_vertical"]:
		_long_drag_active = true
		_long_drag_start_time = snapped_time
		_long_drag_end_time = snapped_time + _grid_interval_at(snapped_time)
		_long_drag_col = col
		queue_redraw()
	else:
		note_placed.emit(note_data)

func _build_note_data(time: float, col: int) -> Dictionary:
	var note: Dictionary = {}
	note["time"] = time

	match current_note_type:
		"normal":
			if col != 3:
				return {}
			note["type"] = "normal"
		"top":
			if col > 2:
				return {}
			note["type"] = "top"
			note["top_lane"] = col
		"vertical":
			if col < 4:
				return {}
			note["type"] = "vertical"
			note["lane"] = col - 4
		"long_normal":
			if col != 3:
				return {}
			note["type"] = "long_normal"
			note["end_time"] = time + _grid_interval_at(time)
		"long_top":
			if col > 2:
				return {}
			note["type"] = "long_top"
			note["top_lane"] = col
			note["end_time"] = time + _grid_interval_at(time)
		"long_vertical":
			if col < 4:
				return {}
			note["type"] = "long_vertical"
			note["lane"] = col - 4
			note["end_time"] = time + _grid_interval_at(time)
		"chain":
			var chain_type = "normal"
			if col <= 2:
				chain_type = "top"
			elif col >= 4:
				chain_type = "vertical"
			note["type"] = "chain"
			note["chain_type"] = chain_type
			if col <= 2:
				note["top_lane"] = col
			elif col >= 4:
				note["lane"] = col - 4
			note["chain_count"] = 2
			note["chain_interval"] = _grid_interval_at(time) * 2.0
			note["last_long"] = false
		_:
			return {}

	return note

func _handle_mouse_motion(mme: InputEventMouseMotion) -> void:
	if _is_dragging:
		_drag_end = mme.position
		queue_redraw()
		return

	if _long_drag_active:
		var t = y_to_time(mme.position.y)
		_long_drag_end_time = _snap_time(t)
		queue_redraw()
		return

	if _note_move_active and _note_move_index >= 0:
		var dy = mme.position.y - _note_move_origin_mouse_y
		var dt = dy / pixels_per_second
		var new_time = max(0.0, _snap_time(_note_move_original_time + dt))
		_note_move_preview_time = new_time

		# Horizontal: compute new col from current mouse x
		var new_col = x_to_col(mme.position.x)
		if chart_data != null and _note_move_index < chart_data.notes.size():
			new_col = _constrain_col_for_note(chart_data.notes[_note_move_index], new_col)
		_note_move_preview_col = new_col
		queue_redraw()
		return

	if _bpm_drag_active and _bpm_drag_index > 0:
		var t = y_to_time(mme.position.y)
		var st = _snap_time(t)
		if chart_data != null:
			var bpm_changes = chart_data.meta.get("bpm_changes", [])
			if _bpm_drag_index < bpm_changes.size():
				bpm_changes[_bpm_drag_index]["time"] = max(0.001, st)
				queue_redraw()

func _handle_left_release(pos: Vector2) -> void:
	if _is_dragging:
		_is_dragging = false
		_complete_rect_selection()
		queue_redraw()
		return

	if _long_drag_active:
		_long_drag_active = false
		_complete_long_drag()
		queue_redraw()
		return

	if _note_move_active:
		_note_move_active = false
		_complete_note_move()
		queue_redraw()
		return

	if _bpm_drag_active:
		_bpm_drag_active = false
		_complete_bpm_drag()
		queue_redraw()

func _complete_rect_selection() -> void:
	if chart_data == null:
		return
	var rect = _get_drag_rect()
	var new_selection: Array = []
	for i in range(chart_data.notes.size()):
		var note = chart_data.notes[i]
		var nt = note.get("time", 0.0)
		var ny = time_to_y(nt)
		var col = _note_to_col(note)
		var nx = col_to_x(col)
		if rect.has_point(Vector2(nx, ny)):
			new_selection.append(i)
	selected_notes = new_selection
	_emit_note_clicked_for_selection()

func _complete_long_drag() -> void:
	if chart_data == null:
		return
	var t_start = min(_long_drag_start_time, _long_drag_end_time)
	var t_end = max(_long_drag_start_time, _long_drag_end_time)
	var min_len = _grid_interval_at(t_start)
	if t_end - t_start < min_len * 0.5:
		return
	var col = _long_drag_col
	var note: Dictionary = {}
	note["time"] = t_start
	note["end_time"] = t_end
	match current_note_type:
		"long_normal":
			note["type"] = "long_normal"
		"long_top":
			note["type"] = "long_top"
			note["top_lane"] = clamp(col, 0, 2)
		"long_vertical":
			note["type"] = "long_vertical"
			note["lane"] = clamp(col - 4, 0, 6)
	note_placed.emit(note)

func _complete_note_move() -> void:
	if chart_data == null or _note_move_index < 0 or _note_move_index >= chart_data.notes.size():
		return
	var note = chart_data.notes[_note_move_index]
	var old_note = note.duplicate(true)
	var new_note = note.duplicate(true)
	new_note["time"] = _note_move_preview_time
	var pc = _note_move_preview_col
	if note.has("end_time"):
		var dur = note.get("end_time", note["time"]) - note["time"]
		new_note["end_time"] = _note_move_preview_time + dur
	var nt = note.get("type", "normal")
	if (nt == "top" or nt == "long_top") and pc <= 2:
		new_note["top_lane"] = pc
	elif (nt == "vertical" or nt == "long_vertical") and pc >= 4:
		new_note["lane"] = pc - 4
	elif nt == "chain":
		var ct = note.get("chain_type", "normal")
		if ct == "top" and pc <= 2:
			new_note["top_lane"] = pc
		elif ct == "vertical" and pc >= 4:
			new_note["lane"] = pc - 4
	# Only emit action if actually moved
	var time_changed = new_note["time"] != old_note.get("time", 0.0)
	var col_changed = _note_to_col(new_note) != _note_to_col(old_note)
	if time_changed or col_changed:
		_request_move_action(_note_move_index, old_note, new_note)
	_note_move_index = -1

func _complete_bpm_drag() -> void:
	if chart_data == null or _bpm_drag_index <= 0:
		_bpm_drag_index = -1
		return
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	if _bpm_drag_index < bpm_changes.size():
		var new_time = bpm_changes[_bpm_drag_index]["time"]
		if new_time != _bpm_drag_original_time:
			var action_script = load("res://scripts/UndoRedoAction.gd")
			var action = action_script.MoveBpmChangeAction.new(_bpm_drag_index, _bpm_drag_original_time, new_time)
			_request_action(action)
	_bpm_drag_index = -1

func _get_drag_rect() -> Rect2:
	var min_x = min(_drag_start.x, _drag_end.x)
	var min_y = min(_drag_start.y, _drag_end.y)
	var max_x = max(_drag_start.x, _drag_end.x)
	var max_y = max(_drag_start.y, _drag_end.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func _emit_note_clicked_for_selection() -> void:
	if selected_notes.is_empty():
		note_clicked.emit({}, -1)
	else:
		var idx = selected_notes[-1]
		if chart_data != null and idx < chart_data.notes.size():
			note_clicked.emit(chart_data.notes[idx], idx)

func _emit_selection_cleared() -> void:
	note_clicked.emit({}, -1)

#endregion

#region Zoom/Scroll

func _zoom_at(mouse_pos: Vector2, factor: float) -> void:
	var time_at_mouse = y_to_time(mouse_pos.y)
	var new_pps: float = clamp(pixels_per_second * factor, 50.0, 2000.0)
	# Keep time_at_mouse at same Y position:
	# y = TRACK_HEADER_HEIGHT + (time - scroll_offset) * pps
	# => scroll_offset = time - (y - TRACK_HEADER_HEIGHT) / pps
	scroll_offset = time_at_mouse - (mouse_pos.y - TRACK_HEADER_HEIGHT) / new_pps
	scroll_offset = max(scroll_offset, 0.0)
	pixels_per_second = new_pps
	_update_vscroll()
	queue_redraw()

func _scroll_by(delta_sec: float) -> void:
	scroll_offset = max(scroll_offset + delta_sec, 0.0)
	_update_vscroll()
	queue_redraw()

#endregion

#region Callbacks

func set_action_callback(cb: Callable) -> void:
	_action_callback = cb

func set_move_action_callback(cb: Callable) -> void:
	_move_action_callback = cb

func _request_action(action) -> void:
	if _action_callback.is_valid():
		_action_callback.call(action)
	else:
		if chart_data:
			action.execute(chart_data)
		queue_redraw()

func _request_move_action(idx: int, old_note: Dictionary, new_note: Dictionary) -> void:
	if _move_action_callback.is_valid():
		_move_action_callback.call(idx, old_note, new_note)
	else:
		if chart_data:
			var note = chart_data.notes[idx]
			note["time"] = new_note.get("time", note["time"])
			if note.has("end_time"):
				note["end_time"] = new_note.get("end_time", note["end_time"])
			if note.has("top_lane") and new_note.has("top_lane"):
				note["top_lane"] = new_note["top_lane"]
			if note.has("lane") and new_note.has("lane"):
				note["lane"] = new_note["lane"]
		queue_redraw()

#endregion
