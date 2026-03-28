extends RefCounted
## res://scripts/NoteRenderer.gd
## Stateless note drawing helper for the Timeline canvas.

const COLOR_NORMAL = Color(0.302, 0.400, 1.0)         # #4D66FF
const COLOR_TOP = Color(0.102, 0.902, 0.302)           # #1AE64D
const COLOR_VERTICAL = Color(0.533, 0.333, 1.0)       # #8855FF
const COLOR_CHAIN_NORMAL = Color(0.478, 0.561, 1.0)   # #7A8FFF
const COLOR_CHAIN_TOP = Color(0.400, 1.0, 0.533)      # #66FF88
const COLOR_CHAIN_VERTICAL = Color(0.733, 0.533, 1.0) # #BB88FF
const COLOR_SELECTED = Color(1.0, 1.0, 0.0)

const TRACK_HEIGHT = 32.0
const SEP_HEIGHT = 4.0
const RULER_HEIGHT = 20.0
const BPM_BAND_HEIGHT = 16.0
const HEADER_HEIGHT = RULER_HEIGHT + BPM_BAND_HEIGHT   # 36px total header

func get_note_color(note: Dictionary) -> Color:
	var t = note.get("type", "normal")
	match t:
		"normal", "long_normal": return COLOR_NORMAL
		"top", "long_top": return COLOR_TOP
		"vertical", "long_vertical": return COLOR_VERTICAL
		"chain":
			match note.get("chain_type", "normal"):
				"top": return COLOR_CHAIN_TOP
				"vertical": return COLOR_CHAIN_VERTICAL
				_: return COLOR_CHAIN_NORMAL
	return COLOR_NORMAL

func get_row_y(row: int) -> float:
	## Returns absolute Y of the row top (including ruler and BPM band header)
	var sep_count = 0
	if row >= 1: sep_count += 1  # TOP0/TOP1
	if row >= 2: sep_count += 1  # TOP1/TOP2
	if row >= 3: sep_count += 1  # TOP2/NORMAL
	if row >= 4: sep_count += 1  # NORMAL/VERTICAL
	return HEADER_HEIGHT + row * TRACK_HEIGHT + sep_count * SEP_HEIGHT

func draw_note(canvas: CanvasItem, note: Dictionary, scroll_offset: float, pixels_per_second: float, is_selected: bool, grid_width: float) -> void:
	var t = note.get("type", "normal")
	var color = get_note_color(note)
	var row = _get_note_row(note)
	var y = get_row_y(row)
	var x = (note["time"] - scroll_offset) * pixels_per_second
	match t:
		"normal", "top", "vertical":
			_draw_normal_note(canvas, x, y, color, is_selected, grid_width)
		"long_normal", "long_top", "long_vertical":
			var x2 = (note.get("end_time", note["time"] + 0.5) - scroll_offset) * pixels_per_second
			_draw_long_note(canvas, x, x2, y, color, is_selected)
		"chain":
			_draw_chain_note(canvas, note, scroll_offset, pixels_per_second, y, color, is_selected, grid_width)

func _draw_normal_note(canvas: CanvasItem, x: float, y: float, color: Color, is_selected: bool, grid_width: float) -> void:
	var w = max(grid_width, 8.0)
	var h = TRACK_HEIGHT * 0.8
	var rect = Rect2(x - w * 0.5, y + (TRACK_HEIGHT - h) * 0.5, w, h)
	canvas.draw_rect(rect, color)
	if is_selected:
		canvas.draw_rect(rect, COLOR_SELECTED, false, 2.0)

func _draw_long_note(canvas: CanvasItem, x1: float, x2: float, y: float, color: Color, is_selected: bool) -> void:
	var h = TRACK_HEIGHT * 0.6
	var ry = y + (TRACK_HEIGHT - h) * 0.5
	var r = h * 0.5
	# Ensure x1 <= x2
	if x2 < x1:
		var tmp = x1
		x1 = x2
		x2 = tmp
	var rect = Rect2(x1, ry, x2 - x1, h)
	canvas.draw_rect(rect, color)
	canvas.draw_circle(Vector2(x1, ry + r), r, color)
	canvas.draw_circle(Vector2(x2, ry + r), r, color)
	if is_selected:
		canvas.draw_rect(rect, COLOR_SELECTED, false, 2.0)

func _draw_chain_note(canvas: CanvasItem, note: Dictionary, scroll_offset: float, pixels_per_second: float, y: float, color: Color, is_selected: bool, grid_width: float) -> void:
	var count = note.get("chain_count", 2)
	var interval = note.get("chain_interval", 0.4)
	var last_long = note.get("last_long", false)
	var last_end_time = note.get("last_end_time", 0.0)
	var start_time = note["time"]
	var prev_x = -1.0
	for i in range(count):
		var t_i = start_time + i * interval
		var xi = (t_i - scroll_offset) * pixels_per_second
		# Draw connector from previous
		if prev_x >= 0.0:
			var cy = y + TRACK_HEIGHT * 0.5
			canvas.draw_line(Vector2(prev_x, cy), Vector2(xi, cy), color, 2.0)
		# Draw the note (last may be long)
		if i == count - 1 and last_long and last_end_time > t_i:
			var x2 = (last_end_time - scroll_offset) * pixels_per_second
			_draw_long_note(canvas, xi, x2, y, color, is_selected)
		else:
			_draw_normal_note(canvas, xi, y, color, is_selected, grid_width)
		prev_x = xi

func _get_note_row(note: Dictionary) -> int:
	var t = note.get("type", "normal")
	var ct = note.get("chain_type", "normal")
	if t == "top" or t == "long_top" or (t == "chain" and ct == "top"):
		return note.get("top_lane", 0)
	elif t == "normal" or t == "long_normal" or (t == "chain" and ct == "normal"):
		return 3
	elif t == "vertical" or t == "long_vertical" or (t == "chain" and ct == "vertical"):
		return 4 + note.get("lane", 0)
	return 3
