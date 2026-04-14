extends Control
## res://scripts/Timeline.gd
## Vertical timeline canvas: X=track columns, Y=time (top=early, bottom=late).

signal note_clicked(note_data: Dictionary, note_index: int)
signal note_placed(note_data: Dictionary)
signal ruler_clicked(time: float)
signal bpm_marker_clicked(bpm_change: Dictionary, change_index: int)
signal paste_confirmed(snapped_min_time: float)

const RULER_WIDTH = 60.0          # Left ruler width (px)
const BPM_BAND_WIDTH = 16.0       # BPM change band width (px)
const TRACK_HEADER_HEIGHT = 24.0  # Top track header height (px)
const CONTENT_OFFSET_X = RULER_WIDTH + BPM_BAND_WIDTH  # 76px
const DEFAULT_PPS = 200.0         # pixels per second (vertical)
const NUM_COLS = 10               # columns: TOP0,TOP1,TOP2,L0..L6

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
const COLOR_BASE_LINE = Color(1.0, 1.0, 0.0, 0.7)  # yellow
const COLOR_SELECT_RECT = Color(1.0, 1.0, 0.0, 0.15)
const COLOR_SELECT_RECT_BORDER = Color(1.0, 1.0, 0.0, 0.6)
const COLOR_LONG_PREVIEW = Color(0.6, 0.8, 1.0, 0.4)

var pixels_per_second: float = DEFAULT_PPS
var scroll_offset: float = 0.0  # seconds
var playhead_time: float = 0.0
var playback_base_time: float = 0.0
var _vscroll_max_scroll: float = 0.0  # total_duration - visible_secs (for inverted scrollbar)

var chart_data = null
var bpm_grid = null
var note_renderer = null

var snap_enabled: bool = true
var snap_division: int = 16
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
var _long_drag_note_type: String = ""

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

# Paste mode state
var _paste_mode_active: bool = false
var _paste_clipboard: Array = []
var _paste_ghost_mouse_y: float = 0.0

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
	# Update scrollbar page whenever Timeline is resized (e.g. window resize)
	resized.connect(_update_vscroll)

func _process(_delta: float) -> void:
	if _paste_mode_active:
		var new_y = get_local_mouse_position().y
		if abs(new_y - _paste_ghost_mouse_y) > 0.5:
			_paste_ghost_mouse_y = new_y
			queue_redraw()

#region Coordinate Transforms

func get_col_width() -> float:
	return (size.x - CONTENT_OFFSET_X) / float(NUM_COLS)

func time_to_y(time: float) -> float:
	return size.y - (time - scroll_offset) * pixels_per_second

func y_to_time(y: float) -> float:
	return (size.y - y) / pixels_per_second + scroll_offset

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
		return 3 + note.get("lane", 0)  # 3..9 shared lanes
	elif t == "vertical" or t == "long_vertical" or (t == "chain" and ct == "vertical"):
		return 3 + note.get("lane", 0)  # 3..9 shared lanes
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

	# Flipped axis: bottom = early time (scroll_offset), top = later time
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

	# 10. Playback base line (yellow) + Playhead (red)
	var by = time_to_y(playback_base_time)
	if by >= TRACK_HEADER_HEIGHT and by <= h:
		draw_line(Vector2(CONTENT_OFFSET_X, by), Vector2(w, by), COLOR_BASE_LINE, 1.5)
	var py = time_to_y(playhead_time)
	if py >= TRACK_HEADER_HEIGHT and py <= h:
		draw_line(Vector2(CONTENT_OFFSET_X, py), Vector2(w, py), COLOR_PLAYHEAD, 2.0)

	# 11. Selection rectangle
	if _is_dragging:
		var rect = _get_drag_rect()
		draw_rect(rect, COLOR_SELECT_RECT)
		draw_rect(rect, COLOR_SELECT_RECT_BORDER, false, 1.0)

	# 12. Paste mode ghosts
	if _paste_mode_active and not _paste_clipboard.is_empty():
		_draw_paste_ghosts()

func _draw_paste_ghosts() -> void:
	var mouse_time = y_to_time(_paste_ghost_mouse_y)
	var snapped_time = _snap_time(mouse_time)
	var min_time = INF
	for note in _paste_clipboard:
		var t = note.get("time", 0.0)
		if t < min_time:
			min_time = t
	if min_time == INF:
		return
	var time_offset = snapped_time - min_time
	var cw = get_col_width()
	var ghost_fill = Color(1.0, 1.0, 0.0, 0.25)
	var ghost_border = Color(1.0, 1.0, 0.3, 0.85)
	for note in _paste_clipboard:
		var adjusted_time = note.get("time", 0.0) + time_offset
		var col = _note_to_col(note)
		# cx = column center (matches NoteRenderer convention)
		var cx = CONTENT_OFFSET_X + col * cw + cw * 0.5
		var grid_sec = _grid_interval_at(adjusted_time)
		var note_h = max(grid_sec * pixels_per_second, 8.0) * 0.5
		var note_w = cw * 0.8
		# cy = snap point = bottom edge of rect (matches _draw_normal_note)
		var cy = time_to_y(adjusted_time)
		var rect = Rect2(cx - note_w * 0.5, cy - note_h, note_w, note_h)
		draw_rect(rect, ghost_fill)
		draw_rect(rect, ghost_border, false, 1.5)
		var note_type = note.get("type", "normal")
		if note_type in ["long_normal", "long_top", "long_vertical"]:
			var dur = note.get("end_time", note.get("time", 0.0)) - note.get("time", 0.0)
			var end_y = time_to_y(adjusted_time + dur)
			# End note: bottom edge at end_y, drawn downward (end_y to end_y + note_h)
			var end_rect = Rect2(cx - note_w * 0.5, end_y, note_w, note_h)
			draw_rect(end_rect, ghost_fill)
			draw_rect(end_rect, ghost_border, false, 1.5)
			var band_w = cw * 0.8
			var top_y = end_y
			var bot_y = cy - note_h
			if bot_y > top_y:
				draw_rect(Rect2(cx - band_w * 0.5, top_y, band_w, bot_y - top_y), Color(1.0, 1.0, 0.0, 0.15))

func _draw_col_backgrounds(h: float) -> void:
	var cw = get_col_width()
	for col in range(NUM_COLS):
		var cx = CONTENT_OFFSET_X + col * cw
		var color: Color
		if col <= 2:
			color = COLOR_BG_TOP
		else:
			# Shared lanes: alternate even=NORMAL, odd=VERTICAL for visual separation
			var lane = col - 3
			color = COLOR_BG_NORMAL if (lane % 2 == 0) else COLOR_BG_VERTICAL
		draw_rect(Rect2(cx, TRACK_HEADER_HEIGHT, cw, h - TRACK_HEADER_HEIGHT), color)
		# Draw thin separator line between columns
		if col > 0:
			# Major separator only between col 2 and col 3 (TOP / shared lanes boundary)
			var sep_color = COLOR_SEP_MAJOR if col == 3 else COLOR_SEP_MINOR
			var sep_w = 2.0 if col == 3 else 1.0
			draw_line(Vector2(cx, TRACK_HEADER_HEIGHT), Vector2(cx, h), sep_color, sep_w)

func _draw_track_header(w: float) -> void:
	# Background
	draw_rect(Rect2(0, 0, w, TRACK_HEADER_HEIGHT), COLOR_HEADER_BG)
	# Ruler / BPM band area in header
	draw_rect(Rect2(0, 0, CONTENT_OFFSET_X, TRACK_HEADER_HEIGHT), Color(0.05, 0.05, 0.07, 1.0))
	var cw = get_col_width()
	var col_labels = ["TOP 0", "TOP 1", "TOP 2", "L 0", "L 1", "L 2", "L 3", "L 4", "L 5", "L 6"]
	for col in range(NUM_COLS):
		var cx = CONTENT_OFFSET_X + col * cw
		var cx_mid = cx + cw * 0.5
		# Column background for header
		var color: Color
		if col <= 2:
			color = Color(0.3, 0.18, 0.0, 1.0)
		else:
			var lane = col - 3
			color = Color(0.0, 0.14, 0.3, 1.0) if (lane % 2 == 0) else Color(0.0, 0.1, 0.2, 1.0)
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
	# Use fixed snap=32 (= 8 divisions per beat) for note height so it doesn't change with snap_division
	var fixed_grid_sec = bpm_grid.grid_interval(center_time, bpm_changes, 32)

	for i in range(chart_data.notes.size()):
		var note = chart_data.notes[i]
		if _note_move_active and i == _note_move_index:
			continue
		var note_time = note.get("time", 0.0)
		var note_end_time = note.get("end_time", note_time + note.get("chain_count", 1) * note.get("chain_interval", 0.5) + 0.5)
		if note_end_time < start_time - 1.0 or note_time > end_time + 1.0:
			continue
		var is_selected = selected_notes.has(i)
		# Bug 1 fix: pass size.y as canvas_height so NoteRenderer uses correct flipped Y
		note_renderer.draw_note(self, note, scroll_offset, pixels_per_second, is_selected, fixed_grid_sec, get_col_width(), CONTENT_OFFSET_X, TRACK_HEADER_HEIGHT, size.y)

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
		elif nt in ["normal", "long_normal", "vertical", "long_vertical"]:
			preview_note["lane"] = clamp(pc - 3, 0, 6)
		elif nt == "chain":
			var ct = preview_note.get("chain_type", "normal")
			if ct == "top":
				preview_note["top_lane"] = clamp(pc, 0, 2)
			else:
				preview_note["lane"] = clamp(pc - 3, 0, 6)
		note_renderer.draw_note(self, preview_note, scroll_offset, pixels_per_second, true, fixed_grid_sec, get_col_width(), CONTENT_OFFSET_X, TRACK_HEADER_HEIGHT, size.y)

func _draw_long_preview() -> void:
	var cw = get_col_width()
	var cx = CONTENT_OFFSET_X + _long_drag_col * cw + cw * 0.5
	var start_y = time_to_y(_long_drag_start_time)
	var end_y = time_to_y(_long_drag_end_time)
	# start_y > end_y in flipped axis (start = bottom/early, end = top/late)
	if end_y > start_y:
		var tmp = start_y
		start_y = end_y
		end_y = tmp
	# Grid sec for note height
	var grid_sec = _grid_interval_at(_long_drag_start_time)
	var note_h = max(grid_sec * pixels_per_second, 8.0)
	var nw = cw * 0.8
	# Band (full width, faded)
	draw_rect(Rect2(cx - nw * 0.5, end_y, nw, start_y - end_y), COLOR_LONG_PREVIEW)
	# Start cap (bottom)
	draw_rect(Rect2(cx - nw * 0.5, start_y - note_h, nw, note_h), Color(COLOR_LONG_PREVIEW, 1.0))
	# End cap (top)
	draw_rect(Rect2(cx - nw * 0.5, end_y, nw, note_h), Color(COLOR_LONG_PREVIEW, 1.0))

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
	_vscroll_max_scroll = max(total_duration - visible_secs, 0.0)
	vscrollbar.set_block_signals(true)
	vscrollbar.min_value = 0.0
	vscrollbar.max_value = total_duration
	vscrollbar.page = visible_secs
	# Inverted mapping: scroll_offset=0 (start of chart) → scrollbar at bottom
	vscrollbar.value = _vscroll_max_scroll - scroll_offset
	vscrollbar.set_block_signals(false)

func _on_vscroll_changed(value: float) -> void:
	scroll_offset = clamp(_vscroll_max_scroll - value, 0.0, _vscroll_max_scroll)
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
	elif note_type in ["normal", "long_normal", "vertical", "long_vertical"]:
		return clamp(new_col, 3, 9)
	elif note_type == "chain":
		var ct = note.get("chain_type", "normal")
		if ct == "top":
			return clamp(new_col, 0, 2)
		else:
			return clamp(new_col, 3, 9)
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
			_scroll_by(80.0 / pixels_per_second)
			get_viewport().set_input_as_handled()
			return
		elif not mbe.ctrl_pressed and mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(-80.0 / pixels_per_second)
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

	# Paste mode: click confirms paste position
	if _paste_mode_active:
		var snapped_time = _snap_time(y_to_time(pos.y))
		paste_confirmed.emit(snapped_time)
		exit_paste_mode()
		return

	# Ctrl+drag/click: range select (available regardless of select mode)
	if ctrl_held:
		var note_idx = _note_at_position(pos)
		if note_idx >= 0:
			if selected_notes.has(note_idx):
				selected_notes.erase(note_idx)
			else:
				selected_notes.append(note_idx)
			_emit_note_clicked_for_selection()
			queue_redraw()
		else:
			_drag_start = pos
			_drag_end = pos
			_is_dragging = true
		return

	if is_select_mode:
		var note_idx = _note_at_position(pos)
		if note_idx >= 0:
			selected_notes = [note_idx]
			_emit_note_clicked_for_selection()
			queue_redraw()
			if chart_data != null and note_idx < chart_data.notes.size():
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

	# Chain click: special behavior
	var c_held = Input.is_key_pressed(KEY_C) and not Input.is_key_pressed(KEY_CTRL)
	if c_held:
		_handle_chain_click(snapped_time, col)
		return

	var note_data = _build_note_data(snapped_time, col)
	if note_data.is_empty():
		return

	var note_type = note_data.get("type", "normal")
	if note_type in ["long_normal", "long_top", "long_vertical"]:
		_long_drag_active = true
		_long_drag_start_time = snapped_time
		_long_drag_end_time = snapped_time + _grid_interval_at(snapped_time)
		_long_drag_col = col
		_long_drag_note_type = note_type
		queue_redraw()
	else:
		# Bug 2 fix: skip placement if a note with same type/column/time already exists
		if not _note_exists_at(note_data, snapped_time):
			note_placed.emit(note_data)

func _handle_chain_click(snapped_time: float, col: int) -> void:
	## Find the closest note in the same col with time < snapped_time.
	if chart_data == null:
		return
	var prev_index = -1
	var prev_time = -INF
	for i in range(chart_data.notes.size()):
		var note = chart_data.notes[i]
		if _note_to_col(note) != col:
			continue
		var nt = note.get("time", 0.0)
		if nt < snapped_time and nt > prev_time:
			prev_time = nt
			prev_index = i
	if prev_index < 0:
		return  # No previous note — do nothing

	var prev_note = chart_data.notes[prev_index]
	var prev_type = prev_note.get("type", "normal")
	var action_script = load("res://scripts/UndoRedoAction.gd")

	if prev_type in ["normal", "vertical", "top"]:
		# Convert to chain
		var interval = snapped_time - prev_note.get("time", 0.0)
		if interval <= 0.0:
			return
		var chain_type: String
		match prev_type:
			"top": chain_type = "top"
			"vertical": chain_type = "vertical"
			_: chain_type = "normal"
		var new_chain = {
			"type": "chain",
			"time": prev_note.get("time", 0.0),
			"chain_type": chain_type,
			"chain_count": 2,
			"chain_interval": interval,
			"last_long": false
		}
		if chain_type == "top":
			new_chain["top_lane"] = prev_note.get("top_lane", 0)
		else:
			new_chain["lane"] = prev_note.get("lane", 0)
		var action = action_script.ReplaceNoteAction.new(prev_index, prev_note, new_chain)
		_request_action(action)

	elif prev_type == "chain" and not prev_note.get("last_long", false):
		# Extend chain by 1
		var old_count = prev_note.get("chain_count", 2)
		var action = action_script.EditPropertyAction.new(prev_index, "chain_count", old_count, old_count + 1)
		_request_action(action)
	# else: long note, or chain+last_long=true — do nothing

func _note_exists_at(note_data: Dictionary, snapped_time: float) -> bool:
	## Returns true if the new note_data would overlap an existing note.
	if chart_data == null:
		return false
	var new_col = _note_to_col(note_data)
	# Top notes only check for exact column+time collision
	if new_col <= 2:
		var half_epsilon = _grid_interval_at(snapped_time) * 0.5
		for existing in chart_data.notes:
			if _note_to_col(existing) != new_col:
				continue
			if abs(existing.get("time", -1.0) - snapped_time) < half_epsilon:
				return true
		return false
	# Shared lane notes: use full overlap detection
	var lane = new_col - 3
	var note_type = note_data.get("type", "normal")
	var t_end: float
	if note_type in ["long_normal", "long_top", "long_vertical"]:
		t_end = note_data.get("end_time", snapped_time + _grid_interval_at(snapped_time))
	elif note_type == "chain":
		var count = note_data.get("chain_count", 2)
		var interval = note_data.get("chain_interval", 0.4)
		var chain_end = snapped_time + (count - 1) * interval
		if note_data.get("last_long", false):
			chain_end += note_data.get("last_end_time", chain_end) - chain_end
		t_end = chain_end
	else:
		t_end = snapped_time
	return _lane_occupied(lane, snapped_time, t_end)

func _build_col_from_note(note_data: Dictionary) -> int:
	return _note_to_col(note_data)

func _lane_occupied(lane: int, start_t: float, end_t: float, exclude_index: int = -1) -> bool:
	## Returns true if [start_t, end_t] overlaps any existing note in the given shared lane.
	if chart_data == null:
		return false
	var epsilon = 0.01
	for i in range(chart_data.notes.size()):
		if i == exclude_index:
			continue
		var note = chart_data.notes[i]
		var note_col = _note_to_col(note)
		# Skip top-lane notes (cols 0-2)
		if note_col < 3:
			continue
		var note_lane = note_col - 3
		if note_lane != lane:
			continue
		# Compute note's occupied interval
		var nt = note.get("time", 0.0)
		var note_end: float
		var note_type = note.get("type", "normal")
		if note_type in ["long_normal", "long_top", "long_vertical"]:
			note_end = note.get("end_time", nt)
		elif note_type == "chain":
			var count = note.get("chain_count", 2)
			var interval = note.get("chain_interval", 0.4)
			note_end = nt + (count - 1) * interval
			if note.get("last_long", false) and note.get("last_end_time", 0.0) > note_end:
				note_end = note.get("last_end_time", note_end)
		else:
			note_end = nt  # single note = point
		# Overlap check: [start_t, end_t] overlaps [nt, note_end]?
		# They don't overlap if end_t < nt - epsilon or start_t > note_end + epsilon
		if end_t < nt - epsilon or start_t > note_end + epsilon:
			continue
		return true
	return false

func _build_note_data(time: float, col: int) -> Dictionary:
	var note: Dictionary = {}
	note["time"] = time

	# Determine note type from held keys
	var v_held = Input.is_key_pressed(KEY_V) and not Input.is_key_pressed(KEY_CTRL)
	var x_held = Input.is_key_pressed(KEY_X)
	var c_held = Input.is_key_pressed(KEY_C) and not Input.is_key_pressed(KEY_CTRL)

	if col <= 2:
		# Top lane
		if x_held:
			note["type"] = "long_top"
			note["top_lane"] = col
			note["end_time"] = time + _grid_interval_at(time)
		elif c_held:
			note["type"] = "chain"
			note["chain_type"] = "top"
			note["top_lane"] = col
			note["chain_count"] = 2
			note["chain_interval"] = _grid_interval_at(time) * 2.0
			note["last_long"] = false
		else:
			# v_held or no modifier → top note
			note["type"] = "top"
			note["top_lane"] = col
	else:
		# Shared lane (col 3-9 → lane 0-6)
		var lane = col - 3
		if v_held and x_held:
			note["type"] = "long_vertical"
			note["lane"] = lane
			note["end_time"] = time + _grid_interval_at(time)
		elif v_held and c_held:
			note["type"] = "chain"
			note["chain_type"] = "vertical"
			note["lane"] = lane
			note["chain_count"] = 2
			note["chain_interval"] = _grid_interval_at(time) * 2.0
			note["last_long"] = false
		elif v_held:
			note["type"] = "vertical"
			note["lane"] = lane
		elif x_held:
			note["type"] = "long_normal"
			note["lane"] = lane
			note["end_time"] = time + _grid_interval_at(time)
		elif c_held:
			note["type"] = "chain"
			note["chain_type"] = "normal"
			note["lane"] = lane
			note["chain_count"] = 2
			note["chain_interval"] = _grid_interval_at(time) * 2.0
			note["last_long"] = false
		else:
			note["type"] = "normal"
			note["lane"] = lane

	return note

func _handle_mouse_motion(mme: InputEventMouseMotion) -> void:
	if _paste_mode_active:
		return

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
		# Flipped axis: moving down (positive dy) = earlier time (smaller time)
		var dt = -dy / pixels_per_second
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

	# If drag start coincides with a chain tail (last_long=false), attach long to chain
	var chain_idx = _find_chain_at_tail(t_start, col)
	if chain_idx >= 0:
		var chain_note = chart_data.notes[chain_idx]
		# Overlap check: [t_start, t_end] must be free (excluding the chain itself)
		if col >= 3:
			var lane = clamp(col - 3, 0, 6)
			if _lane_occupied(lane, t_start, t_end, chain_idx):
				return
		var new_note = chain_note.duplicate(true)
		new_note["last_long"] = true
		new_note["last_end_time"] = t_end
		var action_script = load("res://scripts/UndoRedoAction.gd")
		_request_action(action_script.ReplaceNoteAction.new(chain_idx, chain_note, new_note))
		return

	# Normal long note placement
	var note: Dictionary = {}
	note["time"] = t_start
	note["end_time"] = t_end
	match _long_drag_note_type:
		"long_normal":
			note["type"] = "long_normal"
			note["lane"] = clamp(col - 3, 0, 6)
		"long_top":
			note["type"] = "long_top"
			note["top_lane"] = clamp(col, 0, 2)
		"long_vertical":
			note["type"] = "long_vertical"
			note["lane"] = clamp(col - 3, 0, 6)
	# Overlap check for shared-lane long notes
	if col >= 3:
		var lane = clamp(col - 3, 0, 6)
		if _lane_occupied(lane, t_start, t_end):
			return
	note_placed.emit(note)

func _find_chain_at_tail(time: float, col: int) -> int:
	## Find a chain in the same col whose last member time ≈ given time and last_long=false.
	if chart_data == null:
		return -1
	var epsilon = 0.02
	for i in range(chart_data.notes.size()):
		var note = chart_data.notes[i]
		if note.get("type", "") != "chain":
			continue
		if _note_to_col(note) != col:
			continue
		if note.get("last_long", false):
			continue
		var tail_time = note.get("time", 0.0) + (note.get("chain_count", 2) - 1) * note.get("chain_interval", 0.4)
		if abs(tail_time - time) <= epsilon:
			return i
	return -1

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
	elif nt in ["normal", "long_normal", "vertical", "long_vertical"] and pc >= 3:
		new_note["lane"] = pc - 3
	elif nt == "chain":
		var ct = note.get("chain_type", "normal")
		if ct == "top" and pc <= 2:
			new_note["top_lane"] = pc
		elif pc >= 3:
			new_note["lane"] = pc - 3
	# Only emit action if actually moved
	var time_changed = new_note["time"] != old_note.get("time", 0.0)
	var col_changed = _note_to_col(new_note) != _note_to_col(old_note)
	if time_changed or col_changed:
		# Overlap check for shared-lane notes on move
		var new_col = _note_to_col(new_note)
		if new_col >= 3:
			var move_lane = new_col - 3
			var nt_type = new_note.get("type", "normal")
			var move_start = new_note["time"]
			var move_end: float
			if nt_type in ["long_normal", "long_top", "long_vertical"]:
				move_end = new_note.get("end_time", move_start)
			elif nt_type == "chain":
				var count = new_note.get("chain_count", 2)
				var interval = new_note.get("chain_interval", 0.4)
				move_end = move_start + (count - 1) * interval
				if new_note.get("last_long", false) and new_note.get("last_end_time", 0.0) > move_end:
					move_end = new_note.get("last_end_time", move_end)
			else:
				move_end = move_start
			if _lane_occupied(move_lane, move_start, move_end, _note_move_index):
				# Cancel move: overlap detected
				_note_move_index = -1
				return
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
	# Keep time_at_mouse at same Y position (flipped axis):
	# y = size.y - (time - scroll_offset) * pps
	# => scroll_offset = time - (size.y - y) / pps
	scroll_offset = time_at_mouse - (size.y - mouse_pos.y) / new_pps
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

func enter_paste_mode(clipboard: Array) -> void:
	_paste_clipboard = clipboard.duplicate(true)
	_paste_mode_active = true
	_paste_ghost_mouse_y = get_local_mouse_position().y
	queue_redraw()

func exit_paste_mode() -> void:
	if not _paste_mode_active:
		return
	_paste_mode_active = false
	_paste_clipboard.clear()
	queue_redraw()

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
