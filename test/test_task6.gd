extends SceneTree
## Task 6 test: Vertical timeline — loads sample chart and verifies vertical layout.

var _main_node = null
var _timeline = null
var _frame: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/ChartEditor.tscn")
	var root_node = scene.instantiate()
	root_node.name = "ChartEditor"
	get_root().add_child(root_node)
	_main_node = root_node

	# Find timeline
	var tl_area = root_node.get_node_or_null("RootVBox/MainArea/TimelineArea")
	if tl_area:
		_timeline = tl_area.get_node_or_null("Timeline")
	if _timeline:
		print("ASSERT PASS: Timeline node found")
	else:
		print("ASSERT FAIL: Timeline node not found")

func _process(delta: float) -> bool:
	_frame += 1

	# Frame 1: load chart (after _ready() has run)
	if _frame == 1:
		var chart_path = "D:/GoDot Projects/hockey/songs/sample/chart.json"
		if FileAccess.file_exists(chart_path) and _main_node:
			_main_node.call("_load_from_path", chart_path)
			print("ASSERT PASS: chart load triggered")
		else:
			print("ASSERT FAIL: chart not found or main node missing")

	# Frame 2: initial view - show vertical timeline with all columns
	if _frame == 2:
		if _timeline:
			# Set good initial view
			_timeline.scroll_offset = 0.0
			_timeline.pixels_per_second = 200.0
			_timeline.queue_redraw()

			# Verify constants
			var col_w = _timeline.get_col_width() if _timeline.has_method("get_col_width") else -1.0
			if col_w > 0:
				print("ASSERT PASS: col_width = %.1f" % col_w)
			else:
				print("ASSERT FAIL: col_width not positive")

			# Verify coordinate transforms
			var t0_y = _timeline.time_to_y(0.0) if _timeline.has_method("time_to_y") else -1.0
			var t1_y = _timeline.time_to_y(1.0) if _timeline.has_method("time_to_y") else -1.0
			if t1_y > t0_y:
				print("ASSERT PASS: time increases downward (t0y=%.0f t1y=%.0f)" % [t0_y, t1_y])
			else:
				print("ASSERT FAIL: time should increase downward")

	# Frame 5: scroll down a bit to see more notes
	if _frame == 5:
		if _timeline:
			_timeline.scroll_offset = 2.0
			_timeline.queue_redraw()

	# Frame 8: zoom in
	if _frame == 8:
		if _timeline:
			_timeline.pixels_per_second = 300.0
			_timeline.scroll_offset = 1.0
			_timeline.queue_redraw()

	# Frame 11: zoom out to see full chart at once
	if _frame == 11:
		if _timeline:
			_timeline.pixels_per_second = 80.0
			_timeline.scroll_offset = 0.0
			_timeline.queue_redraw()

	# Frame 14: back to normal zoom, playhead visible
	if _frame == 14:
		if _timeline:
			_timeline.pixels_per_second = 200.0
			_timeline.scroll_offset = 0.0
			if _main_node:
				_main_node.set_playhead_time(2.5)
			_timeline.queue_redraw()

	return false
