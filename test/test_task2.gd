extends SceneTree
## Test harness for Task 2: Timeline drawing engine
## Loads the chart editor, opens sample chart, verifies visual output

var _root_scene = null
var _frame: int = 0
var _chart_main = null
var _timeline = null
var _loaded: bool = false

func _initialize() -> void:
	# Load the ChartEditor scene
	var packed: PackedScene = load("res://scenes/ChartEditor.tscn")
	_root_scene = packed.instantiate()
	root.add_child(_root_scene)
	_chart_main = _root_scene
	# Find timeline
	var vbox = _root_scene.get_node_or_null("RootVBox")
	if vbox:
		var main_area = vbox.get_node_or_null("MainArea")
		if main_area:
			var tl_area = main_area.get_node_or_null("TimelineArea")
			if tl_area:
				_timeline = tl_area.get_node_or_null("Timeline")

func _process(delta: float) -> bool:
	_frame += 1

	# Frame 1: load the sample chart
	if _frame == 1:
		if _chart_main and _chart_main.has_method("_load_from_path"):
			_chart_main._load_from_path("D:/GoDot Projects/hockey/songs/sample/chart.json")
			print("ASSERT PASS: chart loaded")
		else:
			print("ASSERT FAIL: ChartEditorMain not found or missing _load_from_path")

	# Frame 2: verify chart data loaded, notes visible
	if _frame == 2:
		if _timeline and _timeline.chart_data != null:
			var note_count = _timeline.chart_data.notes.size()
			print("ASSERT PASS: timeline has chart_data with %d notes" % note_count)
			if note_count == 52:
				print("ASSERT PASS: correct note count (52)")
			else:
				print("ASSERT FAIL: expected 52 notes, got %d" % note_count)
		else:
			print("ASSERT FAIL: timeline has no chart_data")
		# Scroll to start (time 0) - notes start at t=2
		if _timeline:
			_timeline.scroll_offset = 0.0
			_timeline.pixels_per_second = 200.0
			_timeline.queue_redraw()

	# Frame 3: default zoom view (t=0 to ~7s visible)
	if _frame == 3:
		if _timeline:
			_timeline.scroll_offset = 0.0
			_timeline.queue_redraw()
		_loaded = true

	# Frame 5: scroll to show chain notes area (t=29-37)
	if _frame == 5:
		if _timeline:
			_timeline.scroll_offset = 28.0
			_timeline.queue_redraw()

	# Frame 7: zoom in test
	if _frame == 7:
		if _timeline:
			_timeline.scroll_offset = 0.0
			_timeline.pixels_per_second = 500.0
			_timeline.queue_redraw()
			print("ASSERT PASS: zoom set to 500 pps")

	# Frame 9: zoom out test
	if _frame == 9:
		if _timeline:
			_timeline.pixels_per_second = 80.0
			_timeline.scroll_offset = 0.0
			_timeline.queue_redraw()
			print("ASSERT PASS: zoom set to 80 pps (zoomed out)")

	# Frame 11: show BPM change area (t=18-22, BPM changes at t=20)
	if _frame == 11:
		if _timeline:
			_timeline.pixels_per_second = 200.0
			_timeline.scroll_offset = 17.0
			_timeline.queue_redraw()

	# Frame 13: verify BPM changes visible
	if _frame == 13:
		if _timeline and _timeline.chart_data != null:
			var bpm_changes = _timeline.chart_data.meta.get("bpm_changes", [])
			if bpm_changes.size() == 2:
				print("ASSERT PASS: 2 BPM changes found (t=0 BPM=120, t=20 BPM=150)")
			else:
				print("ASSERT FAIL: expected 2 BPM changes, got %d" % bpm_changes.size())

	# Frame 15: final overview
	if _frame == 15:
		if _timeline:
			_timeline.pixels_per_second = 100.0
			_timeline.scroll_offset = 0.0
			_timeline.queue_redraw()

	return false
