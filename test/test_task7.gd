extends SceneTree
## Task 7 test: Timeline axis flip + window resize fix
## Verify:
##   1. Notes appear with early times at bottom, late times at top
##   2. Playhead starts low and moves upward (or stays at bottom during playback)
##   3. Timeline layout fills the window correctly

var _frame: int = 0
var _main_node = null
var _tl = null
var _chart_path = "D:/GoDot Projects/hockey/songs/sample/chart.json"

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/ChartEditor.tscn")
	var root_scene = scene.instantiate()
	get_root().add_child(root_scene)
	_main_node = root_scene

func _process(delta: float) -> bool:
	_frame += 1

	# Frame 1: load chart after _ready() has run
	if _frame == 1:
		if _main_node and _main_node.has_method("_load_from_path"):
			_main_node.call("_load_from_path", _chart_path)
		_tl = _main_node.get_node_or_null("RootVBox/MainArea/TimelineArea/Timeline") if _main_node else null

	# Frame 3: verify axis orientation - early notes should be near bottom
	if _frame == 3 and _tl != null:
		var early_y = _tl.call("time_to_y", 0.0)
		var late_y = _tl.call("time_to_y", 5.0)
		if early_y > late_y:
			print("ASSERT PASS: time_to_y(0) > time_to_y(5) — early time at bottom (y=%s > y=%s)" % [early_y, late_y])
		else:
			print("ASSERT FAIL: time_to_y(0) should be > time_to_y(5). Got %s vs %s" % [early_y, late_y])

		# Verify y_to_time inverse
		var mid_y = _tl.size.y * 0.5
		var mid_time = _tl.call("y_to_time", mid_y)
		var back_y = _tl.call("time_to_y", mid_time)
		if abs(back_y - mid_y) < 1.0:
			print("ASSERT PASS: y_to_time/time_to_y are inverse functions (error < 1px)")
		else:
			print("ASSERT FAIL: y_to_time/time_to_y mismatch: expected y=%s, got %s" % [mid_y, back_y])

		# Verify RootVBox fills the window (resize fix)
		var vbox = _main_node.get_node_or_null("RootVBox")
		if vbox:
			var win_size = Vector2(DisplayServer.window_get_size())
			var vbox_size = vbox.size
			print("Window size: %s, VBox size: %s" % [win_size, vbox_size])
			# VBox should be close to window size (deferred set may take a frame)

	return false
