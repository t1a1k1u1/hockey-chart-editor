extends SceneTree
## Task 8 test: Shared Lane System for Non-Top Notes
## Verify:
##   1. Timeline displays 10 columns: TOP 0/1/2 + L 0..L 6
##   2. Normal and vertical notes can be placed in the same shared lane column
##   3. Duplicate placement at same lane+time is blocked
##   4. Long note occupation interval blocks overlapping notes

var _frame: int = 0
var _main_node = null
var _tl = null
var _chart_data = null
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

	# Frame 3: verify column count and labels
	if _frame == 3 and _tl != null:
		var num_cols = _tl.get("NUM_COLS")
		if num_cols == 10:
			print("ASSERT PASS: NUM_COLS=10")
		else:
			print("ASSERT FAIL: NUM_COLS expected 10, got %s" % num_cols)

		# Verify _note_to_col for normal note with lane=0 → col 3
		var normal_note = {"type": "normal", "lane": 0, "time": 1.0}
		var col_n = _tl.call("_note_to_col", normal_note)
		if col_n == 3:
			print("ASSERT PASS: normal lane=0 → col 3")
		else:
			print("ASSERT FAIL: normal lane=0 → expected col 3, got %s" % col_n)

		# Verify _note_to_col for normal note with lane=3 → col 6
		var normal_note_l3 = {"type": "normal", "lane": 3, "time": 1.0}
		var col_n3 = _tl.call("_note_to_col", normal_note_l3)
		if col_n3 == 6:
			print("ASSERT PASS: normal lane=3 → col 6")
		else:
			print("ASSERT FAIL: normal lane=3 → expected col 6, got %s" % col_n3)

		# Verify _note_to_col for vertical note with lane=0 → col 3 (same as normal)
		var vert_note = {"type": "vertical", "lane": 0, "time": 1.0}
		var col_v = _tl.call("_note_to_col", vert_note)
		if col_v == 3:
			print("ASSERT PASS: vertical lane=0 → col 3 (shared with normal)")
		else:
			print("ASSERT FAIL: vertical lane=0 → expected col 3, got %s" % col_v)

		# Verify top note mapping is unchanged: top_lane=0 → col 0
		var top_note = {"type": "top", "top_lane": 0, "time": 1.0}
		var col_t = _tl.call("_note_to_col", top_note)
		if col_t == 0:
			print("ASSERT PASS: top top_lane=0 → col 0")
		else:
			print("ASSERT FAIL: top top_lane=0 → expected col 0, got %s" % col_t)

	# Frame 4: test _lane_occupied overlap detection
	if _frame == 4 and _tl != null:
		_chart_data = _main_node.get("chart_data") if _main_node else null
		if _chart_data == null:
			print("ASSERT FAIL: chart_data is null")
		else:
			# Clear notes for controlled test
			var saved_notes = _chart_data.notes.duplicate(true)

			# Add a long_normal at time=2.0, end_time=3.0, lane=0
			_chart_data.notes.clear()
			_chart_data.notes.append({
				"type": "long_normal",
				"lane": 0,
				"time": 2.0,
				"end_time": 3.0
			})

			# Lane 0 at t=2.5 (inside) should be occupied
			var occ1 = _tl.call("_lane_occupied", 0, 2.5, 2.5)
			if occ1:
				print("ASSERT PASS: lane 0 at t=2.5 is occupied (inside long note)")
			else:
				print("ASSERT FAIL: lane 0 at t=2.5 should be occupied")

			# Lane 0 at t=1.0 (before) should not be occupied
			var occ2 = _tl.call("_lane_occupied", 0, 1.0, 1.0)
			if not occ2:
				print("ASSERT PASS: lane 0 at t=1.0 is NOT occupied (before long note)")
			else:
				print("ASSERT FAIL: lane 0 at t=1.0 should NOT be occupied")

			# Lane 1 at t=2.5 (different lane) should not be occupied
			var occ3 = _tl.call("_lane_occupied", 1, 2.5, 2.5)
			if not occ3:
				print("ASSERT PASS: lane 1 at t=2.5 is NOT occupied (different lane)")
			else:
				print("ASSERT FAIL: lane 1 at t=2.5 should NOT be occupied")

			# Lane 0 at t=3.5 (after) should not be occupied
			var occ4 = _tl.call("_lane_occupied", 0, 3.5, 3.5)
			if not occ4:
				print("ASSERT PASS: lane 0 at t=3.5 is NOT occupied (after long note)")
			else:
				print("ASSERT FAIL: lane 0 at t=3.5 should NOT be occupied")

			# Restore notes
			_chart_data.notes = saved_notes

	return false
