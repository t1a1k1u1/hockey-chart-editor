extends SceneTree
## Task 9 test: Key+Click note placement — verify note type buttons removed, hint label present,
## and key-based placement logic is wired correctly.

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
		# Load a chart so timeline is active
		var chart_data = _main_node.chart_data
		if chart_data:
			chart_data.meta["bpm"] = 120.0
			chart_data.meta["bpm_changes"] = [{"time": 0.0, "bpm": 120.0}]
			chart_data.meta["offset"] = 0.0
			if _main_node.has_method("_sync_controls_to_chart"):
				_main_node.call("_sync_controls_to_chart")

		# Verify note type buttons are NOT present
		var ctrl_bar = _main_node.get_node_or_null("RootVBox/ControlBarPanel/ControlBar")
		if ctrl_bar:
			var found_type_btn = false
			for i in range(1, 8):
				var btn = ctrl_bar.get_node_or_null("NoteType%d" % i)
				if btn != null:
					found_type_btn = true
					break
			if found_type_btn:
				print("ASSERT FAIL: NoteType buttons still present in ControlBar")
			else:
				print("ASSERT PASS: NoteType buttons removed from ControlBar")

			# Verify hint label IS present
			var hint = ctrl_bar.get_node_or_null("HintLabel")
			if hint == null:
				print("ASSERT FAIL: HintLabel not found in ControlBar")
			else:
				print("ASSERT PASS: HintLabel found: '%s'" % hint.text)
		else:
			print("ASSERT FAIL: ControlBar not found")

		# Verify current_note_type variable doesn't exist on main or timeline
		if "current_note_type" in _main_node:
			print("ASSERT FAIL: current_note_type still exists in ChartEditorMain")
		else:
			print("ASSERT PASS: current_note_type removed from ChartEditorMain")

		var timeline = _main_node.get_node_or_null("RootVBox/MainArea/TimelineArea/Timeline")
		if timeline:
			if "current_note_type" in timeline:
				print("ASSERT FAIL: current_note_type still exists in Timeline")
			else:
				print("ASSERT PASS: current_note_type removed from Timeline")

			# Verify _long_drag_note_type var exists
			if "_long_drag_note_type" in timeline:
				print("ASSERT PASS: _long_drag_note_type variable present in Timeline")
			else:
				print("ASSERT FAIL: _long_drag_note_type variable missing from Timeline")

	if _frame == 60:
		return true  # quit

	return false
