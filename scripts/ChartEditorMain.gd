extends Node
## res://scripts/ChartEditorMain.gd
## Main editor state: tool selection, undo/redo, file operations, UI coordination.

signal chart_loaded
signal chart_saved
signal selection_changed(selected_indices: Array)
signal playhead_moved(time: float)

var chart_data = null
var current_file_path: String = ""
var is_dirty: bool = false
var undo_stack: Array = []
var redo_stack: Array = []
var selected_notes: Array = []
var current_note_type: String = "normal"
var is_select_mode: bool = false
var playhead_time: float = 0.0
var snap_enabled: bool = true
var snap_division: int = 4
var pixels_per_second: float = 200.0

# Node references (set in _ready)
var timeline: Control = null
var property_panel: VBoxContainer = null
var audio_player: AudioStreamPlayer = null
var status_label: Label = null
var time_label: Label = null
var bpm_input: SpinBox = null
var snap_div_select: OptionButton = null
var snap_toggle: CheckButton = null
var offset_input: SpinBox = null

func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(1280, 720))
	chart_data = load("res://scripts/ChartData.gd").new()
	_new_chart()

func _new_chart() -> void:
	chart_data.reset()
	current_file_path = ""
	is_dirty = false
	undo_stack.clear()
	redo_stack.clear()
	selected_notes.clear()
	_update_title()
	_update_status()

func _update_title() -> void:
	var title = "Hockey Chart Editor"
	if current_file_path != "":
		title += " — " + current_file_path.get_file()
	if is_dirty:
		title += " *"
	get_window().title = title

func _update_status() -> void:
	if status_label:
		var note_count = chart_data.notes.size() if chart_data else 0
		var path_str = current_file_path if current_file_path != "" else "(unsaved)"
		status_label.text = "Notes: %d  |  %s" % [note_count, path_str]

func execute_action(action) -> void:
	action.execute(chart_data)
	undo_stack.append(action)
	redo_stack.clear()
	is_dirty = true
	_update_title()
	_update_status()
	if timeline:
		timeline.queue_redraw()

func undo() -> void:
	if undo_stack.is_empty():
		return
	var action = undo_stack.pop_back()
	action.undo(chart_data)
	redo_stack.append(action)
	is_dirty = true
	_update_title()
	_update_status()
	if timeline:
		timeline.queue_redraw()

func redo() -> void:
	if redo_stack.is_empty():
		return
	var action = redo_stack.pop_back()
	action.execute(chart_data)
	undo_stack.append(action)
	is_dirty = true
	_update_title()
	_update_status()
	if timeline:
		timeline.queue_redraw()

func _on_note_placed(note_data: Dictionary) -> void:
	pass

func _on_note_clicked(note_data: Dictionary, note_index: int) -> void:
	pass

func _on_ruler_clicked(time: float) -> void:
	playhead_time = time
	playhead_moved.emit(time)

func _on_bpm_marker_clicked(bpm_change: Dictionary, change_index: int) -> void:
	pass

func _on_property_changed(note_index: int, field: String, value: Variant) -> void:
	pass

func _on_playback_started() -> void:
	pass

func _on_playback_stopped() -> void:
	pass

func _input(event: InputEvent) -> void:
	pass
