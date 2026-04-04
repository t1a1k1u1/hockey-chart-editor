extends SceneTree
## Task 11 test: Long note visual redesign — band + endpoint rectangles.

var _root_node = null
var _main_node = null
var _frame: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/ChartEditor.tscn")
	_root_node = scene.instantiate()
	get_root().add_child(_root_node)
	_main_node = _root_node

func _process(delta: float) -> bool:
	_frame += 1

	if _frame == 2:
		# Set up chart data with several long notes for visual verification
		var chart_data = _main_node.chart_data
		if chart_data:
			chart_data.meta["bpm"] = 120.0
			chart_data.meta["bpm_changes"] = [{"time": 0.0, "bpm": 120.0}]
			chart_data.meta["offset"] = 0.0

			# Add a variety of long notes
			chart_data.notes = [
				# long_normal in lane 0
				{"type": "long_normal", "time": 0.5, "end_time": 1.5, "lane": 0},
				# long_top in top_lane 1
				{"type": "long_top", "time": 0.5, "end_time": 1.5, "top_lane": 1},
				# long_vertical in lane 2
				{"type": "long_vertical", "time": 0.5, "end_time": 1.5, "lane": 2},
				# normal note for comparison
				{"type": "normal", "time": 2.0, "lane": 0},
				# top note for comparison
				{"type": "top", "time": 2.0, "top_lane": 1},
				# Another long_normal with wider span
				{"type": "long_normal", "time": 2.5, "end_time": 4.0, "lane": 3},
			]

			if _main_node.has_method("_sync_controls_to_chart"):
				_main_node.call("_sync_controls_to_chart")

		# Scroll to show the notes
		var timeline = _main_node.get_node_or_null("RootVBox/MainArea/TimelineArea/Timeline")
		if timeline:
			timeline.scroll_offset = 0.0
			timeline.queue_redraw()
			print("ASSERT PASS: timeline found, notes injected")
		else:
			print("ASSERT FAIL: timeline not found")

	if _frame == 60:
		return true  # quit

	return false
