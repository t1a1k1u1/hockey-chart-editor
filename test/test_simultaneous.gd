extends SceneTree
## Test: simultaneous note rings — two notes at same time should show yellow rings.

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
		# _new_chart() wires timeline.chart_data; call it first
		_main_node.call("_new_chart")

	if _frame == 3:
		var chart_data = _main_node.chart_data
		if chart_data:
			chart_data.meta["bpm"] = 120.0
			chart_data.meta["bpm_changes"] = [{"time": 0.0, "bpm": 120.0}]

			# Three simultaneous notes at time=1.0 (should all get yellow rings)
			# Two simultaneous at time=2.0
			# One solo at time=3.0 (no ring)
			chart_data.notes = [
				{"type": "normal",   "time": 1.0, "lane": 0},
				{"type": "vertical", "time": 1.0, "lane": 2},
				{"type": "top",      "time": 1.0, "top_lane": 1},
				{"type": "normal",   "time": 2.0, "lane": 1},
				{"type": "vertical", "time": 2.0, "lane": 3},
				{"type": "normal",   "time": 3.0, "lane": 0},
			]
			var tl = _main_node.get_node_or_null("RootVBox/MainArea/TimelineArea/Timeline")
			if tl:
				tl.queue_redraw()

	if _frame == 8:
		var dir = "screenshots/test_simultaneous"
		DirAccess.make_dir_recursive_absolute("res://" + dir)
		var img = get_root().get_viewport().get_texture().get_image()
		img.save_png("res://" + dir + "/rings.png")
		print("Screenshot saved: ", dir + "/rings.png")
		return true
	return false
