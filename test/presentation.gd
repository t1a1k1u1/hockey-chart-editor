extends SceneTree
## Presentation script for the Hockey Chart Editor demo video.
## ~900 frames at 30 FPS = 30 seconds
## Sequence:
##   0-60:   Opening — full editor UI
##   61-120: Load sample/chart.json
##   121-270: Scroll timeline left→right to show notes
##   271-390: Zoom in to show note details
##   391-510: Play (Space) — playhead moves
##   511-570: Stop (Escape)
##   571-690: Add a new note programmatically
##   691-900: Select note, show property panel

var _root_scene = null
var _main_node = null
var _frame: int = 0
var _phase: int = 0
var _added_note_index: int = -1

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/ChartEditor.tscn")
	_root_scene = packed.instantiate()
	get_root().add_child(_root_scene)
	_main_node = _root_scene

func _process(delta: float) -> bool:
	_frame += 1

	# --- Phase 0: Opening (frames 1-60) ---
	# Just show the empty editor with UI visible
	if _frame == 3:
		print("PRES: Phase 0 — Editor loaded, showing full UI")

	# --- Phase 1: Load chart.json (frame 61-120) ---
	elif _frame == 61:
		_phase = 1
		print("PRES: Phase 1 — Loading sample/chart.json")
		var chart_path = "D:/GoDot Projects/hockey/songs/sample/chart.json"
		if _main_node.has_method("_load_from_path"):
			_main_node.call("_load_from_path", chart_path)
		else:
			print("PRES ERROR: no _load_from_path method")

	# --- Phase 2: Scroll timeline left→right (frames 121-270) ---
	elif _frame >= 121 and _frame <= 270 and _phase == 1:
		_phase = 2
		print("PRES: Phase 2 — Scrolling timeline")
	elif _frame >= 121 and _frame <= 270 and _phase == 2:
		# Gradually scroll from 0 to ~8 seconds over 150 frames
		var progress = float(_frame - 121) / 150.0
		var target_scroll = progress * 8.0
		if _main_node.get("timeline") != null:
			var tl = _main_node.timeline
			if tl != null:
				tl.scroll_offset = target_scroll
				tl.queue_redraw()
				# Sync hscrollbar
				var hscroll = _get_hscroll()
				if hscroll:
					hscroll.set_block_signals(true)
					hscroll.value = target_scroll
					hscroll.set_block_signals(false)

	# --- Phase 3: Zoom in (frames 271-390) ---
	elif _frame == 271:
		_phase = 3
		print("PRES: Phase 3 — Zoom in to show note details")
		# Scroll to a busy section around 2 seconds
		if _main_node.get("timeline") != null:
			var tl = _main_node.timeline
			if tl != null:
				tl.scroll_offset = 1.5
				tl.queue_redraw()
	elif _frame >= 280 and _frame <= 360 and _phase == 3:
		# Gradually zoom in from 200 to 500 pps
		var progress = float(_frame - 280) / 80.0
		var target_pps = lerp(200.0, 500.0, progress)
		if _main_node.get("pixels_per_second") != null:
			_main_node.pixels_per_second = target_pps
		if _main_node.get("timeline") != null:
			var tl = _main_node.timeline
			if tl != null:
				tl.pixels_per_second = target_pps
				tl.queue_redraw()

	# --- Phase 4: Start playback (frame 391) ---
	elif _frame == 391:
		_phase = 4
		print("PRES: Phase 4 — Starting playback")
		# Scroll back to start for playback
		if _main_node.get("timeline") != null:
			var tl = _main_node.timeline
			if tl != null:
				tl.pixels_per_second = 200.0
				tl.scroll_offset = 0.0
				tl.queue_redraw()
		if _main_node.get("pixels_per_second") != null:
			_main_node.pixels_per_second = 200.0
		_main_node.call("set_playhead_time", 0.0)
		if _main_node.has_method("toggle_playback"):
			_main_node.call("toggle_playback")

	# --- Phase 5: Stop playback (frame 511) ---
	elif _frame == 511:
		_phase = 5
		print("PRES: Phase 5 — Stopping playback")
		if _main_node.has_method("stop_playback"):
			_main_node.call("stop_playback")

	# --- Phase 6: Add a new note (frame 571) ---
	elif _frame == 571:
		_phase = 6
		print("PRES: Phase 6 — Adding a new note programmatically")
		# Scroll to time ~5.0 where we'll add the note
		if _main_node.get("timeline") != null:
			var tl = _main_node.timeline
			if tl != null:
				tl.scroll_offset = 4.0
				tl.queue_redraw()
		_main_node.call("set_playhead_time", 5.0)
		# Add a "top" type note at time 5.0, row 2 (top lane 2)
		var new_note = {
			"time": 5.0,
			"type": "top",
			"top_lane": 2
		}
		var action_script = load("res://scripts/UndoRedoAction.gd")
		var action = action_script.AddNoteAction.new(new_note)
		if _main_node.has_method("execute_action"):
			_main_node.call("execute_action", action)
			# Find the index of the note we just added
			var notes = _main_node.chart_data.notes
			_added_note_index = notes.size() - 1
			print("PRES: Note added at index " + str(_added_note_index))

	# --- Phase 7: Select the new note, show property panel (frame 691) ---
	elif _frame == 691:
		_phase = 7
		print("PRES: Phase 7 — Selecting note, showing property panel")
		if _added_note_index >= 0:
			_main_node.selected_notes = [_added_note_index]
			if _main_node.get("timeline") != null:
				var tl = _main_node.timeline
				if tl != null:
					tl.selected_notes = _main_node.selected_notes
					tl.queue_redraw()
			if _main_node.has_method("_update_property_panel"):
				_main_node.call("_update_property_panel")

	# --- End (frame 900) ---
	elif _frame >= 900:
		print("PRES: Complete — quitting")
		quit()

	return false

func _get_hscroll():
	if _main_node == null:
		return null
	var vbox = _main_node.get_node_or_null("RootVBox")
	if vbox == null:
		return null
	var main_area = vbox.get_node_or_null("MainArea")
	if main_area == null:
		return null
	var tl_area = main_area.get_node_or_null("TimelineArea")
	if tl_area == null:
		return null
	return tl_area.get_node_or_null("HScrollBar")
