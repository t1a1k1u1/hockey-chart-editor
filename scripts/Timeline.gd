extends Control
## res://scripts/Timeline.gd
## Main timeline canvas: drawing, input handling, zoom/scroll.

signal note_clicked(note_data: Dictionary, note_index: int)
signal note_placed(note_data: Dictionary)
signal ruler_clicked(time: float)
signal bpm_marker_clicked(bpm_change: Dictionary, change_index: int)

const RULER_HEIGHT = 20.0
const BPM_BAND_HEIGHT = 16.0
const TRACK_HEIGHT = 32.0
const SEP_HEIGHT = 4.0
const DEFAULT_PPS = 200.0  # pixels per second

# Track colors
const COLOR_BG_TOP = Color(0.227, 0.133, 0.0)       # #3A2200
const COLOR_BG_NORMAL = Color(0.0, 0.102, 0.227)    # #001A3A
const COLOR_BG_VERTICAL = Color(0.0, 0.071, 0.157)  # #001228
const COLOR_SEP = Color(0.2, 0.2, 0.267)             # #333344
const COLOR_RULER_BG = Color(0.1, 0.1, 0.12, 1.0)
const COLOR_BPM_BAND_BG = Color(0.08, 0.08, 0.1, 1.0)
const COLOR_PLAYHEAD = Color(1.0, 0.267, 0.267)       # #FF4444
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
var _is_dragging: bool = false  # rect selection

# Long note drag state
var _long_drag_active: bool = false
var _long_drag_start_time: float = 0.0
var _long_drag_end_time: float = 0.0
var _long_drag_row: int = 0

# Note move drag state
var _note_move_active: bool = false
var _note_move_index: int = -1
var _note_move_origin_mouse_x: float = 0.0
var _note_move_origin_mouse_y: float = 0.0
var _note_move_original_time: float = 0.0
var _note_move_original_top_lane: int = 0
var _note_move_original_lane: int = 0
var _note_move_preview_time: float = 0.0
var _note_move_preview_row: int = 0

# BPM marker drag state
var _bpm_drag_active: bool = false
var _bpm_drag_index: int = -1
var _bpm_drag_original_time: float = 0.0

# HScrollBar reference (set by ChartEditorMain or self during ready)
var hscrollbar = null

func _ready() -> void:
	bpm_grid = load("res://scripts/BpmGrid.gd").new()
	note_renderer = load("res://scripts/NoteRenderer.gd").new()
	clip_contents = true
	# Try to find HScrollBar sibling
	var parent = get_parent()
	if parent:
		hscrollbar = parent.get_node_or_null("HScrollBar")
		if hscrollbar:
			hscrollbar.value_changed.connect(_on_hscroll_changed)

func _draw() -> void:
	var w = size.x
	var h = size.y
	if w <= 0 or h <= 0:
		return

	var bpm_changes: Array = []
	if chart_data != null:
		bpm_changes = chart_data.meta.get("bpm_changes", [])

	var visible_start = scroll_offset
	var visible_end = scroll_offset + w / pixels_per_second

	# --- 1. Background track rows ---
	_draw_track_backgrounds(w)

	# --- 2. Grid lines ---
	_draw_grid_lines(visible_start, visible_end, bpm_changes, w)

	# --- 3. Ruler (top 20px) ---
	draw_rect(Rect2(0, 0, w, RULER_HEIGHT), COLOR_RULER_BG)

	# --- 4. BPM change band (below ruler, 16px) ---
	draw_rect(Rect2(0, RULER_HEIGHT, w, BPM_BAND_HEIGHT), COLOR_BPM_BAND_BG)

	# --- 5. Ruler tick marks and labels ---
	_draw_ruler(visible_start, visible_end, bpm_changes, w)

	# --- 6. BPM change markers ---
	_draw_bpm_markers(bpm_changes, w)

	# --- 7. Notes ---
	if chart_data != null:
		_draw_notes(visible_start, visible_end)

	# --- 8. Long note drag preview ---
	if _long_drag_active:
		_draw_long_preview()

	# --- 9. Playhead ---
	var px = time_to_x(playhead_time)
	if px >= 0 and px <= w:
		draw_line(Vector2(px, 0), Vector2(px, h), COLOR_PLAYHEAD, 2.0)

	# --- 10. Selection rectangle ---
	if _is_dragging:
		var rect = _get_drag_rect()
		draw_rect(rect, COLOR_SELECT_RECT)
		draw_rect(rect, COLOR_SELECT_RECT_BORDER, false, 1.0)

func _draw_track_backgrounds(w: float) -> void:
	for row in range(11):
		var y = _content_row_y(row)
		var color: Color
		if row <= 2:
			color = COLOR_BG_TOP
		elif row == 3:
			color = COLOR_BG_NORMAL
		else:
			color = COLOR_BG_VERTICAL
		draw_rect(Rect2(0, y, w, TRACK_HEIGHT), color)
		# Draw separator before row (groups: 1, 2, 3, 4)
		if row == 1 or row == 2 or row == 3 or row == 4:
			draw_rect(Rect2(0, y - SEP_HEIGHT, w, SEP_HEIGHT), COLOR_SEP)

func _content_row_y(row: int) -> float:
	return get_row_y(row)

func _draw_grid_lines(start_time: float, end_time: float, bpm_changes: Array, w: float) -> void:
	if bpm_changes.is_empty():
		return
	var lines = bpm_grid.get_grid_lines(start_time, end_time, bpm_changes, snap_division)
	var content_top = RULER_HEIGHT + BPM_BAND_HEIGHT
	var content_bottom = size.y
	for line in lines:
		var x = time_to_x(line["time"])
		if x < 0 or x > w:
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
			_:  # sub
				# Check pixel spacing - skip if too dense
				col = Color(1, 1, 1, 0.15)
				lw = 1.0
		draw_line(Vector2(x, content_top), Vector2(x, content_bottom), col, lw)

func _draw_ruler(start_time: float, end_time: float, bpm_changes: Array, w: float) -> void:
	# Draw ruler ticks at measure/beat positions
	if bpm_changes.is_empty():
		return
	var lines = bpm_grid.get_grid_lines(start_time, end_time, bpm_changes, snap_division)
	for line in lines:
		var x = time_to_x(line["time"])
		if x < 0 or x > w:
			continue
		var lt = line["line_type"]
		if lt == "measure":
			# Draw tick
			draw_line(Vector2(x, 0), Vector2(x, RULER_HEIGHT * 0.6), Color(1, 1, 1, 0.8), 1.0)
			# Draw label
			var label_text: String
			if snap_enabled:
				# Show measure number
				var measure_num = _get_measure_number(line["time"], bpm_changes)
				label_text = str(measure_num)
			else:
				label_text = "%.1f" % line["time"]
			draw_string(ThemeDB.fallback_font, Vector2(x + 2, RULER_HEIGHT - 4), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))
		elif lt == "beat":
			draw_line(Vector2(x, RULER_HEIGHT * 0.4), Vector2(x, RULER_HEIGHT * 0.8), Color(1, 1, 1, 0.5), 1.0)

func _get_measure_number(time: float, bpm_changes: Array) -> int:
	## Returns 1-based measure number at given time
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

func _draw_bpm_markers(bpm_changes: Array, w: float) -> void:
	var band_y = RULER_HEIGHT
	var band_h = BPM_BAND_HEIGHT
	for i in range(bpm_changes.size()):
		var bc = bpm_changes[i]
		var x = time_to_x(bc["time"])
		if x < -50 or x > w + 50:
			continue
		# Vertical line
		draw_line(Vector2(x, band_y), Vector2(x, band_y + band_h), Color(1.0, 0.8, 0.2, 0.9), 1.5)
		# BPM label
		var label = "BPM:%.0f" % bc["bpm"]
		draw_string(ThemeDB.fallback_font, Vector2(x + 2, band_y + band_h - 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.8, 0.2, 0.9))

func _draw_notes(start_time: float, end_time: float) -> void:
	if chart_data == null or chart_data.notes.is_empty():
		return
	# Compute grid_width (one snap interval in pixels)
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	var grid_sec = bpm_grid.grid_interval(scroll_offset + (size.x * 0.5 / pixels_per_second), bpm_changes, snap_division)
	var grid_width = max(grid_sec * pixels_per_second, 8.0)

	for i in range(chart_data.notes.size()):
		var note = chart_data.notes[i]
		# Skip note being moved - draw preview instead
		if _note_move_active and i == _note_move_index:
			continue
		var note_time = note.get("time", 0.0)
		# Rough visibility check (chain notes may extend further)
		var note_end_time = note.get("end_time", note_time + note.get("chain_count", 1) * note.get("chain_interval", 0.5) + 0.5)
		if note_end_time < start_time - 1.0 or note_time > end_time + 1.0:
			continue
		var is_selected = selected_notes.has(i)
		note_renderer.draw_note(self, note, scroll_offset, pixels_per_second, is_selected, grid_width)

	# Draw move preview note
	if _note_move_active and _note_move_index >= 0 and _note_move_index < chart_data.notes.size():
		var orig_note = chart_data.notes[_note_move_index]
		var preview_note = orig_note.duplicate(true)
		preview_note["time"] = _note_move_preview_time
		if preview_note.has("end_time"):
			var dur = orig_note.get("end_time", orig_note["time"]) - orig_note["time"]
			preview_note["end_time"] = _note_move_preview_time + dur
		# Update lane based on preview row
		var pr = _note_move_preview_row
		if pr <= 2:
			preview_note["top_lane"] = pr
		elif pr >= 4:
			preview_note["lane"] = pr - 4
		# Draw semi-transparent (reuse grid_width computed above)
		note_renderer.draw_note(self, preview_note, scroll_offset, pixels_per_second, true, grid_width)

func _draw_long_preview() -> void:
	if chart_data == null:
		return
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	var grid_sec = bpm_grid.grid_interval(scroll_offset + (size.x * 0.5 / pixels_per_second), bpm_changes, snap_division)
	var grid_width = max(grid_sec * pixels_per_second, 8.0)
	var row = _long_drag_row
	var y = get_row_y(row)
	var x1 = time_to_x(_long_drag_start_time)
	var x2 = time_to_x(_long_drag_end_time)
	if x2 < x1:
		var tmp = x1
		x1 = x2
		x2 = tmp
	var h = TRACK_HEIGHT * 0.6
	var ry = y + (TRACK_HEIGHT - h) * 0.5
	var r = h * 0.5
	draw_rect(Rect2(x1, ry, x2 - x1, h), COLOR_LONG_PREVIEW)
	draw_circle(Vector2(x1, ry + r), r, COLOR_LONG_PREVIEW)
	draw_circle(Vector2(x2, ry + r), r, COLOR_LONG_PREVIEW)

func time_to_x(time: float) -> float:
	return (time - scroll_offset) * pixels_per_second

func x_to_time(x: float) -> float:
	return x / pixels_per_second + scroll_offset

func get_row_y(row: int) -> float:
	var sep_count = 0
	if row >= 1: sep_count += 1
	if row >= 2: sep_count += 1
	if row >= 3: sep_count += 1
	if row >= 4: sep_count += 1
	return RULER_HEIGHT + BPM_BAND_HEIGHT + row * TRACK_HEIGHT + sep_count * SEP_HEIGHT

func y_to_row(y: float) -> int:
	var content_y = y - RULER_HEIGHT - BPM_BAND_HEIGHT
	if content_y < 0:
		return -1
	var cursor = 0.0
	for i in range(11):
		if i == 1 or i == 2 or i == 3 or i == 4:
			cursor += SEP_HEIGHT
		if content_y < cursor + TRACK_HEIGHT:
			return i
		cursor += TRACK_HEIGHT
	return -1

func _get_drag_rect() -> Rect2:
	var min_x = min(_drag_start.x, _drag_end.x)
	var min_y = min(_drag_start.y, _drag_end.y)
	var max_x = max(_drag_start.x, _drag_end.x)
	var max_y = max(_drag_start.y, _drag_end.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func _update_hscroll() -> void:
	if hscrollbar == null:
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
	var page = size.x / pixels_per_second
	hscrollbar.set_block_signals(true)
	hscrollbar.min_value = 0.0
	hscrollbar.max_value = total_duration
	hscrollbar.page = page
	hscrollbar.value = scroll_offset
	hscrollbar.set_block_signals(false)

func _on_hscroll_changed(value: float) -> void:
	scroll_offset = value
	queue_redraw()

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
	## Returns note index at screen position, or -1 if none
	if chart_data == null:
		return -1
	var click_time = x_to_time(pos.x)
	var row = y_to_row(pos.y)
	if row < 0:
		return -1
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	var grid_sec = bpm_grid.grid_interval(click_time, bpm_changes, snap_division)
	var half_w_sec = max(grid_sec * 0.6, 4.0 / pixels_per_second)
	for i in range(chart_data.notes.size() - 1, -1, -1):
		var note = chart_data.notes[i]
		var note_row = chart_data.get_note_row(note)
		if note_row != row:
			continue
		var nt = note.get("time", 0.0)
		var net = note.get("end_time", nt)
		# For long notes: hit test is across the full extent
		var note_type = note.get("type", "normal")
		if note_type in ["long_normal", "long_top", "long_vertical"]:
			if click_time >= nt - half_w_sec and click_time <= net + half_w_sec:
				return i
		elif note_type == "chain":
			var count = note.get("chain_count", 2)
			var interval = note.get("chain_interval", 0.4)
			for ci in range(count):
				var ct = nt + ci * interval
				if abs(click_time - ct) <= half_w_sec:
					return i
		else:
			if abs(click_time - nt) <= half_w_sec:
				return i
	return -1

func _bpm_marker_at_x(x: float) -> int:
	## Returns BPM change index near x, or -1
	if chart_data == null:
		return -1
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	for i in range(bpm_changes.size()):
		var bx = time_to_x(bpm_changes[i]["time"])
		if abs(bx - x) < 8.0:
			return i
	return -1

func _constrain_row_for_note(note: Dictionary, new_row: int) -> int:
	## Enforce vertical movement constraints based on note type
	var note_type = note.get("type", "normal")
	if note_type in ["top", "long_top"]:
		return clamp(new_row, 0, 2)
	elif note_type in ["normal", "long_normal"]:
		return 3  # Normal notes can't move between rows
	elif note_type in ["vertical", "long_vertical"]:
		return clamp(new_row, 4, 10)
	elif note_type == "chain":
		var ct = note.get("chain_type", "normal")
		if ct == "top":
			return clamp(new_row, 0, 2)
		elif ct == "normal":
			return 3
		else:
			return clamp(new_row, 4, 10)
	return new_row

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe = event as InputEventMouseButton
		_handle_mouse_button(mbe)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		var ke = event as InputEventKey
		if ke.pressed and ke.ctrl_pressed and ke.keycode == KEY_0:
			pixels_per_second = DEFAULT_PPS
			_update_hscroll()
			queue_redraw()
			get_viewport().set_input_as_handled()

func _handle_mouse_button(mbe: InputEventMouseButton) -> void:
	if mbe.pressed:
		# Zoom / scroll via wheel
		if mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mbe.position, 1.15)
			get_viewport().set_input_as_handled()
			return
		elif mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mbe.position, 1.0 / 1.15)
			get_viewport().set_input_as_handled()
			return
		elif not mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_by(-120.0 / pixels_per_second)
			get_viewport().set_input_as_handled()
			return
		elif not mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(120.0 / pixels_per_second)
			get_viewport().set_input_as_handled()
			return

		# Right click — delete note or BPM marker
		if mbe.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(mbe.position)
			get_viewport().set_input_as_handled()
			return

		# Left click
		if mbe.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(mbe.position, mbe.ctrl_pressed)
			get_viewport().set_input_as_handled()
			return
	else:
		# Button released
		if mbe.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_release(mbe.position)

func _handle_right_click(pos: Vector2) -> void:
	if pos.y >= RULER_HEIGHT and pos.y < RULER_HEIGHT + BPM_BAND_HEIGHT:
		# BPM band: delete BPM marker (except time=0)
		var idx = _bpm_marker_at_x(pos.x)
		if idx > 0:  # Don't delete the first one (time=0)
			var bpm_changes = chart_data.meta.get("bpm_changes", []) if chart_data else []
			var action_script = load("res://scripts/UndoRedoAction.gd")
			var action = action_script.DeleteBpmChangeAction.new(idx, bpm_changes[idx])
			# Signal to parent to execute action
			_request_action(action)
		return
	# Track area: delete note
	var idx = _note_at_position(pos)
	if idx >= 0:
		var action_script = load("res://scripts/UndoRedoAction.gd")
		var action = action_script.DeleteNoteAction.new(idx, chart_data.notes[idx])
		_request_action(action)

func _handle_left_click(pos: Vector2, ctrl_held: bool) -> void:
	if pos.y < RULER_HEIGHT:
		# Ruler clicked
		ruler_clicked.emit(x_to_time(pos.x))
		return

	if pos.y < RULER_HEIGHT + BPM_BAND_HEIGHT:
		# BPM band clicked
		var idx = _bpm_marker_at_x(pos.x)
		if idx >= 0:
			var bpm_changes = chart_data.meta.get("bpm_changes", []) if chart_data else []
			bpm_marker_clicked.emit(bpm_changes[idx], idx)
			# Start BPM drag if not at time=0
			if idx > 0:
				_bpm_drag_active = true
				_bpm_drag_index = idx
				_bpm_drag_original_time = bpm_changes[idx]["time"]
		return

	# Track area
	if is_select_mode:
		# Select mode
		var note_idx = _note_at_position(pos)
		if note_idx >= 0:
			if ctrl_held:
				# Toggle selection
				if selected_notes.has(note_idx):
					selected_notes.erase(note_idx)
				else:
					selected_notes.append(note_idx)
			else:
				selected_notes = [note_idx]
			_emit_note_clicked_for_selection()
			queue_redraw()
			# Start note move drag
			if selected_notes.has(note_idx) and chart_data != null and note_idx < chart_data.notes.size():
				_note_move_active = true
				_note_move_index = note_idx
				_note_move_origin_mouse_x = pos.x
				_note_move_origin_mouse_y = pos.y
				var n = chart_data.notes[note_idx]
				_note_move_original_time = n.get("time", 0.0)
				_note_move_original_top_lane = n.get("top_lane", 0)
				_note_move_original_lane = n.get("lane", 0)
				_note_move_preview_time = _note_move_original_time
				_note_move_preview_row = chart_data.get_note_row(n)
		else:
			if not ctrl_held:
				selected_notes.clear()
				_emit_selection_cleared()
				queue_redraw()
			# Start rect selection drag
			_drag_start = pos
			_drag_end = pos
			_is_dragging = true
	else:
		# Placement mode
		_place_note_at(pos)

func _place_note_at(pos: Vector2) -> void:
	if chart_data == null:
		return
	var clicked_time = x_to_time(pos.x)
	var snapped_time = _snap_time(clicked_time)
	var row = y_to_row(pos.y)
	if row < 0:
		return

	var note_data = _build_note_data(snapped_time, row)
	if note_data.is_empty():
		return

	var note_type = current_note_type
	if note_type in ["long_normal", "long_top", "long_vertical"]:
		# Start long drag
		_long_drag_active = true
		_long_drag_start_time = snapped_time
		_long_drag_end_time = snapped_time + _grid_interval_at(snapped_time)
		_long_drag_row = row
		queue_redraw()
	else:
		note_placed.emit(note_data)

func _build_note_data(time: float, row: int) -> Dictionary:
	var note: Dictionary = {}
	note["time"] = time

	match current_note_type:
		"normal":
			if row != 3:
				return {}
			note["type"] = "normal"
		"top":
			if row > 2:
				return {}
			note["type"] = "top"
			note["top_lane"] = row
		"vertical":
			if row < 4:
				return {}
			note["type"] = "vertical"
			note["lane"] = row - 4
		"long_normal":
			if row != 3:
				return {}
			note["type"] = "long_normal"
			note["end_time"] = time + _grid_interval_at(time)
		"long_top":
			if row > 2:
				return {}
			note["type"] = "long_top"
			note["top_lane"] = row
			note["end_time"] = time + _grid_interval_at(time)
		"long_vertical":
			if row < 4:
				return {}
			note["type"] = "long_vertical"
			note["lane"] = row - 4
			note["end_time"] = time + _grid_interval_at(time)
		"chain":
			# Chain notes can be placed on any row type
			var chain_type = "normal"
			if row <= 2:
				chain_type = "top"
			elif row >= 4:
				chain_type = "vertical"
			note["type"] = "chain"
			note["chain_type"] = chain_type
			if row <= 2:
				note["top_lane"] = row
			elif row >= 4:
				note["lane"] = row - 4
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
		var t = x_to_time(mme.position.x)
		_long_drag_end_time = _snap_time(t)
		queue_redraw()
		return

	if _note_move_active and _note_move_index >= 0:
		var dx = mme.position.x - _note_move_origin_mouse_x
		var dy = mme.position.y - _note_move_origin_mouse_y
		var dt = dx / pixels_per_second
		var new_time = max(0.0, _snap_time(_note_move_original_time + dt))
		_note_move_preview_time = new_time

		# Vertical: compute new row from current mouse y
		var new_row = y_to_row(mme.position.y)
		if new_row < 0:
			new_row = _note_move_preview_row
		if chart_data != null and _note_move_index < chart_data.notes.size():
			new_row = _constrain_row_for_note(chart_data.notes[_note_move_index], new_row)
		_note_move_preview_row = new_row
		queue_redraw()
		return

	if _bpm_drag_active and _bpm_drag_index > 0:
		var t = x_to_time(mme.position.x)
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
		var nx = time_to_x(nt)
		var row = chart_data.get_note_row(note)
		var ny = get_row_y(row) + TRACK_HEIGHT * 0.5
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
		# Too short, don't place
		return
	var row = _long_drag_row
	var note: Dictionary = {}
	note["time"] = t_start
	note["end_time"] = t_end
	match current_note_type:
		"long_normal":
			note["type"] = "long_normal"
		"long_top":
			note["type"] = "long_top"
			note["top_lane"] = clamp(row, 0, 2)
		"long_vertical":
			note["type"] = "long_vertical"
			note["lane"] = clamp(row - 4, 0, 6)
	note_placed.emit(note)

func _complete_note_move() -> void:
	if chart_data == null or _note_move_index < 0 or _note_move_index >= chart_data.notes.size():
		return
	var note = chart_data.notes[_note_move_index]
	var old_note = note.duplicate(true)
	var new_note = note.duplicate(true)
	new_note["time"] = _note_move_preview_time
	var pr = _note_move_preview_row
	if note.has("end_time"):
		var dur = note.get("end_time", note["time"]) - note["time"]
		new_note["end_time"] = _note_move_preview_time + dur
	if note.has("top_lane") and pr <= 2:
		new_note["top_lane"] = pr
	if note.has("lane") and pr >= 4:
		new_note["lane"] = pr - 4
	# Only emit action if actually moved
	if new_note["time"] != old_note.get("time", 0.0) or new_note.get("top_lane", -1) != old_note.get("top_lane", -1) or new_note.get("lane", -1) != old_note.get("lane", -1):
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

func _emit_note_clicked_for_selection() -> void:
	if selected_notes.is_empty():
		note_clicked.emit({}, -1)
	else:
		var idx = selected_notes[-1]
		if chart_data != null and idx < chart_data.notes.size():
			note_clicked.emit(chart_data.notes[idx], idx)

func _emit_selection_cleared() -> void:
	note_clicked.emit({}, -1)

# These functions let the Timeline delegate actions up to ChartEditorMain via signal.
# We store a callback reference set by ChartEditorMain.
var _action_callback: Callable = Callable()
var _move_action_callback: Callable = Callable()

func set_action_callback(cb: Callable) -> void:
	_action_callback = cb

func set_move_action_callback(cb: Callable) -> void:
	_move_action_callback = cb

func _request_action(action) -> void:
	if _action_callback.is_valid():
		_action_callback.call(action)
	else:
		# Fallback: apply directly
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

func _zoom_at(mouse_pos: Vector2, factor: float) -> void:
	var time_at_mouse = x_to_time(mouse_pos.x)
	var new_pps = clamp(pixels_per_second * factor, 50.0, 2000.0)
	# Adjust scroll_offset so that time_at_mouse stays at the same screen position
	# x = (time - scroll_offset) * pps  =>  scroll_offset = time - x / pps
	scroll_offset = time_at_mouse - mouse_pos.x / new_pps
	scroll_offset = max(scroll_offset, 0.0)
	pixels_per_second = new_pps
	_update_hscroll()
	queue_redraw()

func _scroll_by(delta_sec: float) -> void:
	scroll_offset = max(scroll_offset + delta_sec, 0.0)
	_update_hscroll()
	queue_redraw()

func _check_bpm_marker_click(x: float) -> void:
	if chart_data == null:
		return
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	for i in range(bpm_changes.size()):
		var bc = bpm_changes[i]
		var bx = time_to_x(bc["time"])
		if abs(bx - x) < 8.0:
			bpm_marker_clicked.emit(bc, i)
			return
