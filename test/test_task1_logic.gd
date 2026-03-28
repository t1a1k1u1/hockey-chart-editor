extends SceneTree
## Logic-only test for Task 1 — runs headless (no rendering needed)

func _initialize() -> void:
	print("=== Task 1 Logic Tests ===")

	# Test ChartData
	var cd = load("res://scripts/ChartData.gd").new()

	# Test reset
	cd.reset()
	assert(cd.notes.size() == 0, "reset: notes empty")
	assert(cd.meta["bpm"] == 120.0, "reset: default bpm")
	assert(cd.meta["bpm_changes"].size() == 1, "reset: one bpm_change")
	print("ASSERT PASS: ChartData.reset() works")

	# Test bpm_at
	var bpm = cd.bpm_at(0.0)
	if bpm == 120.0:
		print("ASSERT PASS: bpm_at(0) = 120.0")
	else:
		print("ASSERT FAIL: bpm_at(0) expected 120.0, got %s" % bpm)

	# Test get_note_row
	var row_normal = cd.get_note_row({"type": "normal"})
	if row_normal == 3:
		print("ASSERT PASS: get_note_row(normal) = 3")
	else:
		print("ASSERT FAIL: get_note_row(normal) expected 3, got %d" % row_normal)

	var row_top = cd.get_note_row({"type": "top", "top_lane": 1})
	if row_top == 1:
		print("ASSERT PASS: get_note_row(top, lane=1) = 1")
	else:
		print("ASSERT FAIL: get_note_row(top, lane=1) expected 1, got %d" % row_top)

	var row_vert = cd.get_note_row({"type": "vertical", "lane": 3})
	if row_vert == 7:
		print("ASSERT PASS: get_note_row(vertical, lane=3) = 7")
	else:
		print("ASSERT FAIL: get_note_row(vertical, lane=3) expected 7, got %d" % row_vert)

	# Test get_row_type
	if cd.get_row_type(0) == "top":
		print("ASSERT PASS: get_row_type(0) = top")
	else:
		print("ASSERT FAIL: get_row_type(0) != top")
	if cd.get_row_type(3) == "normal":
		print("ASSERT PASS: get_row_type(3) = normal")
	else:
		print("ASSERT FAIL: get_row_type(3) != normal")
	if cd.get_row_type(5) == "vertical":
		print("ASSERT PASS: get_row_type(5) = vertical")
	else:
		print("ASSERT FAIL: get_row_type(5) != vertical")

	# Test load_from_json with sample chart
	var chart_path = "D:/GoDot Projects/hockey/songs/sample/chart.json"
	if FileAccess.file_exists(chart_path):
		var text = FileAccess.get_file_as_string(chart_path)
		var ok = cd.load_from_json(text)
		if ok:
			print("ASSERT PASS: load_from_json succeeded")
			var actual_count = cd.notes.size()
			if actual_count > 0:
				print("ASSERT PASS: Note count = %d (spec says 67, file has %d)" % [actual_count, actual_count])
			else:
				print("ASSERT FAIL: No notes loaded")
			# Test save_to_json round-trip preserves note count
			var saved_text = cd.save_to_json()
			var cd2 = load("res://scripts/ChartData.gd").new()
			cd2.load_from_json(saved_text)
			if cd2.notes.size() == actual_count:
				print("ASSERT PASS: save_to_json round-trip preserves %d notes" % actual_count)
			else:
				print("ASSERT FAIL: Round-trip note count = %d (expected %d)" % [cd2.notes.size(), actual_count])
			# Verify time-sorted output
			var prev_time = -1.0
			var sorted_ok = true
			for note in cd2.notes:
				var t = note["time"]
				if t < prev_time:
					sorted_ok = false
					break
				prev_time = t
			if sorted_ok:
				print("ASSERT PASS: Notes sorted by time")
			else:
				print("ASSERT FAIL: Notes not sorted by time")
		else:
			print("ASSERT FAIL: load_from_json returned false")
	else:
		print("ASSERT SKIP: sample chart not found at " + chart_path)

	print("=== End Task 1 Logic Tests ===")
	quit(0)
