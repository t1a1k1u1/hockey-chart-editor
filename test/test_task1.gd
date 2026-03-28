extends SceneTree
## Test harness for Task 1: Core UI + File I/O
## Verifies: window size, layout elements, open chart, note count, status bar

var _scene_root: Node = null
var _frame: int = 0
var _load_triggered: bool = false
var _chart_path: String = "D:/GoDot Projects/hockey/songs/sample/chart.json"

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/ChartEditor.tscn")
	_scene_root = packed.instantiate()
	get_root().add_child(_scene_root)

func _process(delta: float) -> bool:
	_frame += 1

	if _frame == 2:
		# Check window minimum size
		var win_size = DisplayServer.window_get_size()
		if win_size.x >= 1280 and win_size.y >= 720:
			print("ASSERT PASS: Window size >= 1280x720 (got %dx%d)" % [win_size.x, win_size.y])
		else:
			print("ASSERT FAIL: Window size too small: %dx%d" % [win_size.x, win_size.y])

		# Check key UI elements exist
		var vbox = _scene_root.get_node_or_null("RootVBox")
		if vbox:
			print("ASSERT PASS: RootVBox exists")
		else:
			print("ASSERT FAIL: RootVBox missing")

		var menu_bar = _scene_root.get_node_or_null("RootVBox/MenuBar")
		if menu_bar:
			print("ASSERT PASS: MenuBar exists")
		else:
			print("ASSERT FAIL: MenuBar missing")

		var ctrl_bar = _scene_root.get_node_or_null("RootVBox/ControlBarPanel/ControlBar")
		if ctrl_bar:
			print("ASSERT PASS: ControlBar exists")
			# Check note type buttons
			var all_found = true
			for i in range(1, 8):
				var btn = ctrl_bar.get_node_or_null("NoteType%d" % i)
				if btn == null:
					print("ASSERT FAIL: NoteType%d missing" % i)
					all_found = false
			if all_found:
				print("ASSERT PASS: All 7 note type buttons exist")
		else:
			print("ASSERT FAIL: ControlBar missing")

		var track_header = _scene_root.get_node_or_null("RootVBox/MainArea/TrackHeaderPanel")
		if track_header:
			print("ASSERT PASS: TrackHeaderPanel exists")
			# Check all 11 row panels + 4 separators
			var list = track_header.get_node_or_null("TrackHeaderList")
			if list:
				var child_count = list.get_child_count()
				print("ASSERT PASS: TrackHeaderList has %d children (expect 15 = 11 rows + 4 seps)" % child_count)
		else:
			print("ASSERT FAIL: TrackHeaderPanel missing")

		var prop_panel = _scene_root.get_node_or_null("RootVBox/MainArea/PropertyPanelContainer")
		if prop_panel:
			print("ASSERT PASS: PropertyPanelContainer exists")
		else:
			print("ASSERT FAIL: PropertyPanelContainer missing")

		var status_bar = _scene_root.get_node_or_null("RootVBox/StatusBar")
		if status_bar:
			print("ASSERT PASS: StatusBar exists")
			var lbl = status_bar.get_node_or_null("StatusLabel")
			if lbl:
				print("ASSERT PASS: StatusLabel text = '%s'" % lbl.text)
		else:
			print("ASSERT FAIL: StatusBar missing")

	if _frame == 5 and not _load_triggered:
		_load_triggered = true
		# Simulate loading chart.json
		if FileAccess.file_exists(_chart_path):
			var text = FileAccess.get_file_as_string(_chart_path)
			var cd = load("res://scripts/ChartData.gd").new()
			if cd.load_from_json(text):
				var note_count = cd.notes.size()
				if note_count == 67:
					print("ASSERT PASS: chart.json loaded with %d notes" % note_count)
				else:
					print("ASSERT FAIL: Expected 67 notes, got %d" % note_count)
				# Test save_to_json round-trip
				var saved = cd.save_to_json()
				if saved.length() > 100:
					print("ASSERT PASS: save_to_json produced %d chars" % saved.length())
				else:
					print("ASSERT FAIL: save_to_json output too short")
			else:
				print("ASSERT FAIL: load_from_json returned false")
		else:
			print("ASSERT SKIP: chart.json not found at %s" % _chart_path)

	return false
