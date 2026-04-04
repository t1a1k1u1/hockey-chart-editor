extends RefCounted
## res://scripts/NoteRenderer.gd
## Stateless note drawing helper for the vertical Timeline canvas.
## Columns are horizontal (X), time is vertical (Y).

const COLOR_NORMAL = Color(0.302, 0.400, 1.0)         # #4D66FF
const COLOR_TOP = Color(1.0, 0.6, 0.1)                # #FF9919 orange
const COLOR_VERTICAL = Color(0.533, 0.333, 1.0)       # #8855FF
const COLOR_CHAIN_NORMAL = Color(0.478, 0.561, 1.0)   # #7A8FFF
const COLOR_CHAIN_TOP = Color(1.0, 0.76, 0.42)        # orange tint
const COLOR_CHAIN_VERTICAL = Color(0.733, 0.533, 1.0) # #BB88FF
const COLOR_SELECTED = Color(1.0, 1.0, 0.0)

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

func draw_note(canvas: CanvasItem, note: Dictionary, scroll_offset: float, pixels_per_second: float, is_selected: bool, grid_sec: float, col_width: float, content_offset_x: float, header_height: float, canvas_height: float = 0.0, is_simultaneous: bool = false) -> void:
	var t = note.get("type", "normal")
	var color = get_note_color(note)
	var col = _get_note_col(note)
	var cx = content_offset_x + col * col_width + col_width * 0.5
	# Flipped axis: bottom=early, top=late. Use canvas_height to mirror (same as time_to_y).
	var h = canvas_height if canvas_height > 0.0 else (canvas as Control).size.y
	var center_y = h - (note["time"] - scroll_offset) * pixels_per_second

	# Fixed note height: always use snap=8 at current BPM so height doesn't change with snap
	var fixed_grid_sec = grid_sec  # caller passes fixed_grid_sec

	match t:
		"normal", "top", "vertical":
			_draw_normal_note(canvas, cx, center_y, color, is_selected, col_width, fixed_grid_sec, pixels_per_second)
		"long_normal", "long_top", "long_vertical":
			var y2 = h - (note.get("end_time", note["time"] + 0.5) - scroll_offset) * pixels_per_second
			_draw_long_note(canvas, cx, center_y, y2, color, is_selected, col_width, fixed_grid_sec, pixels_per_second)
		"chain":
			_draw_chain_note(canvas, note, scroll_offset, pixels_per_second, cx, color, is_selected, col_width, fixed_grid_sec, h)

	if is_simultaneous:
		var note_h = maxf(fixed_grid_sec * pixels_per_second, 8.0)
		var ring_center = Vector2(cx, center_y - note_h * 0.5)
		var ring_r = col_width * 0.55
		canvas.draw_arc(ring_center, ring_r, 0.0, TAU, 32, Color(1.0, 1.0, 0.0), 2.0)

func _draw_normal_note(canvas: CanvasItem, cx: float, cy: float, color: Color, is_selected: bool, col_width: float, grid_sec: float, pixels_per_second: float) -> void:
	var h = max(grid_sec * pixels_per_second, 8.0)
	var w = col_width * 0.8
	var rect = Rect2(cx - w * 0.5, cy - h, w, h)
	canvas.draw_rect(rect, color)
	if is_selected:
		canvas.draw_rect(rect, COLOR_SELECTED, false, 2.0)

func _draw_long_note(canvas: CanvasItem, cx: float, y1: float, y2: float, color: Color, is_selected: bool, col_width: float, grid_sec: float = 0.0, pixels_per_second: float = 200.0) -> void:
	# Ensure y1 < y2 (y1=top=later time, y2=bottom=earlier time in flipped axis)
	# start note is at bottom (larger y), end note at top (smaller y)
	# So: start_y = max(y1, y2), end_y = min(y1, y2)
	var start_y = maxf(y1, y2)   # bottom = start time (earlier)
	var end_y = minf(y1, y2)     # top = end time (later)

	# Band between start and end: same width as endpoints, faded color
	var band_w = col_width * 0.8
	var faded = Color(color.r, color.g, color.b, color.a * 0.35)
	var band_rect = Rect2(cx - band_w * 0.5, end_y, band_w, start_y - end_y)
	canvas.draw_rect(band_rect, faded)

	# Note height for endpoints (same as _draw_normal_note)
	var note_h = maxf(grid_sec * pixels_per_second, 8.0) if grid_sec > 0.0 else 8.0
	var note_w = col_width * 0.8

	# Start note (bottom = early time): rect from start_y-note_h to start_y
	var start_rect = Rect2(cx - note_w * 0.5, start_y - note_h, note_w, note_h)
	canvas.draw_rect(start_rect, color)

	# End note (top = late time): rect from end_y to end_y+note_h
	var end_rect = Rect2(cx - note_w * 0.5, end_y, note_w, note_h)
	canvas.draw_rect(end_rect, color)

	if is_selected:
		canvas.draw_rect(band_rect, COLOR_SELECTED, false, 2.0)
		canvas.draw_rect(start_rect, COLOR_SELECTED, false, 2.0)
		canvas.draw_rect(end_rect, COLOR_SELECTED, false, 2.0)

func _draw_chain_note(canvas: CanvasItem, note: Dictionary, scroll_offset: float, pixels_per_second: float, cx: float, color: Color, is_selected: bool, col_width: float, grid_sec: float, canvas_height: float) -> void:
	var count = note.get("chain_count", 2)
	var interval = note.get("chain_interval", 0.4)
	var last_long = note.get("last_long", false)
	var last_end_time = note.get("last_end_time", 0.0)
	var start_time = note["time"]
	var prev_y = -1.0
	for i in range(count):
		var t_i = start_time + i * interval
		var yi = canvas_height - (t_i - scroll_offset) * pixels_per_second
		# Draw connector line vertically from previous note
		if prev_y >= 0.0:
			canvas.draw_line(Vector2(cx, prev_y), Vector2(cx, yi), color, 2.0)
		# Draw the note (last may be long)
		if i == count - 1 and last_long and last_end_time > t_i:
			var y2 = canvas_height - (last_end_time - scroll_offset) * pixels_per_second
			_draw_long_note(canvas, cx, yi, y2, color, is_selected, col_width, grid_sec, pixels_per_second)
		else:
			_draw_normal_note(canvas, cx, yi, color, is_selected, col_width, grid_sec, pixels_per_second)
		prev_y = yi

func _get_note_col(note: Dictionary) -> int:
	var t = note.get("type", "normal")
	var ct = note.get("chain_type", "normal")
	if t == "top" or t == "long_top" or (t == "chain" and ct == "top"):
		return note.get("top_lane", 0)
	elif t == "normal" or t == "long_normal" or (t == "chain" and ct == "normal"):
		return 3 + note.get("lane", 0)
	elif t == "vertical" or t == "long_vertical" or (t == "chain" and ct == "vertical"):
		return 3 + note.get("lane", 0)
	return 3
