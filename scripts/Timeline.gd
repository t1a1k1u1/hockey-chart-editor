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

	# --- 8. Playhead ---
	var px = time_to_x(playhead_time)
	if px >= 0 and px <= w:
		draw_line(Vector2(px, 0), Vector2(px, h), COLOR_PLAYHEAD, 2.0)

	# --- 9. Selection rectangle ---
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
		var note_time = note.get("time", 0.0)
		# Rough visibility check (chain notes may extend further)
		var note_end_time = note.get("end_time", note_time + note.get("chain_count", 1) * note.get("chain_interval", 0.5) + 0.5)
		if note_end_time < start_time - 1.0 or note_time > end_time + 1.0:
			continue
		var is_selected = selected_notes.has(i)
		note_renderer.draw_note(self, note, scroll_offset, pixels_per_second, is_selected, grid_width)

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

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe = event as InputEventMouseButton
		if mbe.pressed:
			if mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mbe.position, 1.15)
				get_viewport().set_input_as_handled()
			elif mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mbe.position, 1.0 / 1.15)
				get_viewport().set_input_as_handled()
			elif not mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_by(-120.0 / pixels_per_second)
				get_viewport().set_input_as_handled()
			elif not mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_by(120.0 / pixels_per_second)
				get_viewport().set_input_as_handled()
			elif mbe.button_index == MOUSE_BUTTON_LEFT:
				var clicked_time = x_to_time(mbe.position.x)
				if mbe.position.y < RULER_HEIGHT:
					ruler_clicked.emit(clicked_time)
				elif mbe.position.y < RULER_HEIGHT + BPM_BAND_HEIGHT:
					_check_bpm_marker_click(mbe.position.x)
				else:
					_drag_start = mbe.position
					_drag_end = mbe.position
					_is_dragging = true

	elif event is InputEventMouseMotion:
		if _is_dragging:
			_drag_end = (event as InputEventMouseMotion).position
			queue_redraw()

	elif event is InputEventKey:
		var ke = event as InputEventKey
		if ke.pressed and ke.ctrl_pressed and ke.keycode == KEY_0:
			pixels_per_second = DEFAULT_PPS
			_update_hscroll()
			queue_redraw()
			get_viewport().set_input_as_handled()

	# Handle drag end
	if event is InputEventMouseButton:
		var mbe = event as InputEventMouseButton
		if not mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT and _is_dragging:
			_is_dragging = false
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
