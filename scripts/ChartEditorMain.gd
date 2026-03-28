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

# Clipboard
var _clipboard: Array = []

# Pending action for "unsaved changes" guard
var _pending_action: String = ""   # "new", "open", "quit"

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

# Dialog references
var file_dialog: FileDialog = null
var confirm_dialog: ConfirmationDialog = null
var accept_dialog: AcceptDialog = null
var metadata_dialog: Window = null
var bpm_change_dialog: ConfirmationDialog = null
var _bpm_change_spin: SpinBox = null
var _file_dialog_mode: String = ""   # "open", "save_as"

# BPM change being edited in PropertyPanel
var _selected_bpm_change_index: int = -1

func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(1280, 720))
	chart_data = load("res://scripts/ChartData.gd").new()

	# Gather node references
	var vbox = get_node_or_null("RootVBox")

	if vbox:
		var ctrl_panel = vbox.get_node_or_null("ControlBarPanel")
		if ctrl_panel:
			var ctrl_bar = ctrl_panel.get_node_or_null("ControlBar")
			if ctrl_bar:
				time_label = ctrl_bar.get_node_or_null("TimeLabel")
				bpm_input = ctrl_bar.get_node_or_null("BpmInput")
				snap_div_select = ctrl_bar.get_node_or_null("SnapDivSelect")
				snap_toggle = ctrl_bar.get_node_or_null("SnapToggle")
				offset_input = ctrl_bar.get_node_or_null("OffsetInput")
				var play_btn = ctrl_bar.get_node_or_null("PlayButton")
				if play_btn:
					play_btn.pressed.connect(_on_play_button_pressed)
				var stop_btn = ctrl_bar.get_node_or_null("StopButton")
				if stop_btn:
					stop_btn.pressed.connect(_on_stop_button_pressed)
				if bpm_input:
					bpm_input.value_changed.connect(_on_bpm_changed)
				if offset_input:
					offset_input.value_changed.connect(_on_offset_changed)
				if snap_toggle:
					snap_toggle.toggled.connect(_on_snap_toggled)
				if snap_div_select:
					snap_div_select.item_selected.connect(_on_snap_div_selected)
				# Note type buttons
				for idx in range(7):
					var btn = ctrl_bar.get_node_or_null("NoteType%d" % (idx + 1))
					if btn:
						btn.pressed.connect(_on_note_type_pressed.bind(idx))

		var main_area = vbox.get_node_or_null("MainArea")
		if main_area:
			var tl_area = main_area.get_node_or_null("TimelineArea")
			if tl_area:
				timeline = tl_area.get_node_or_null("Timeline")
				var vscroll = tl_area.get_node_or_null("VScrollBar")
				if vscroll and timeline:
					vscroll.value_changed.connect(_on_vscroll_changed)
			var prop_cont = main_area.get_node_or_null("PropertyPanelContainer")
			if prop_cont:
				var scroll = prop_cont.get_node_or_null("PropertyPanel")
				if scroll:
					property_panel = scroll.get_node_or_null("PropertyPanelContent")

		var status_bar = vbox.get_node_or_null("StatusBar")
		if status_bar:
			status_label = status_bar.get_node_or_null("StatusLabel")

		# MenuBar signals
		var menu_bar = vbox.get_node_or_null("MenuBar")
		if menu_bar:
			var file_menu = menu_bar.get_node_or_null("FileMenu")
			if file_menu:
				file_menu.id_pressed.connect(_on_file_menu_id_pressed)
			var edit_menu = menu_bar.get_node_or_null("EditMenu")
			if edit_menu:
				edit_menu.id_pressed.connect(_on_edit_menu_id_pressed)
			var view_menu = menu_bar.get_node_or_null("ViewMenu")
			if view_menu:
				view_menu.id_pressed.connect(_on_view_menu_id_pressed)

	# Dialog references
	file_dialog = get_node_or_null("FileDialog")
	confirm_dialog = get_node_or_null("ConfirmationDialog")
	accept_dialog = get_node_or_null("AcceptDialog")
	metadata_dialog = get_node_or_null("MetadataDialog")

	if file_dialog:
		file_dialog.file_selected.connect(_on_file_dialog_file_selected)
		file_dialog.canceled.connect(_on_file_dialog_canceled)

	if confirm_dialog:
		confirm_dialog.confirmed.connect(_on_confirm_save_yes)
		confirm_dialog.custom_action.connect(_on_confirm_save_action)
		# Add "Don't Save" button
		confirm_dialog.add_button("Don't Save", false, "dont_save")

	if metadata_dialog:
		metadata_dialog.visible = false
		var ok_btn = metadata_dialog.get_node_or_null("MetaVBox/MetaBtnRow/MetaOkBtn")
		if ok_btn:
			ok_btn.pressed.connect(_on_metadata_ok)
		var cancel_btn = metadata_dialog.get_node_or_null("MetaVBox/MetaBtnRow/MetaCancelBtn")
		if cancel_btn:
			cancel_btn.pressed.connect(_on_metadata_cancel)
		metadata_dialog.close_requested.connect(_on_metadata_cancel)

	audio_player = get_node_or_null("AudioStreamPlayer")

	# Connect AudioPlayer signals
	if audio_player:
		if audio_player.has_signal("playback_started"):
			audio_player.connect("playback_started", _on_playback_started)
		if audio_player.has_signal("playback_stopped"):
			audio_player.connect("playback_stopped", _on_playback_stopped)
		if audio_player.has_signal("playback_paused"):
			audio_player.connect("playback_paused", _on_playback_paused)
		if audio_player.has_signal("playhead_time_changed"):
			audio_player.connect("playhead_time_changed", _on_audio_playhead_changed)

	# Build BPM change dialog
	_build_bpm_change_dialog()

	# Connect window close request
	get_tree().get_root().close_requested.connect(_on_window_close_requested)

	# Wire up Timeline signals and callbacks (use dynamic connect since timeline is typed Control)
	if timeline:
		if timeline.has_signal("note_placed"):
			timeline.connect("note_placed", _on_note_placed)
		if timeline.has_signal("note_clicked"):
			timeline.connect("note_clicked", _on_note_clicked)
		if timeline.has_signal("ruler_clicked"):
			timeline.connect("ruler_clicked", _on_ruler_clicked)
		if timeline.has_signal("bpm_marker_clicked"):
			timeline.connect("bpm_marker_clicked", _on_bpm_marker_clicked)
		if timeline.has_method("set_action_callback"):
			timeline.call("set_action_callback", _on_timeline_action_requested)
		if timeline.has_method("set_move_action_callback"):
			timeline.call("set_move_action_callback", _on_timeline_move_action)

	# Wire up PropertyPanel signals
	if property_panel:
		if property_panel.has_signal("property_changed"):
			property_panel.property_changed.connect(_on_property_changed)
		if property_panel.has_signal("metadata_changed"):
			property_panel.metadata_changed.connect(_on_metadata_field_changed)
		if property_panel.has_signal("bpm_change_edited"):
			property_panel.bpm_change_edited.connect(_on_bpm_change_edited)

	_new_chart()
	_update_note_type_buttons()

func _build_bpm_change_dialog() -> void:
	bpm_change_dialog = ConfirmationDialog.new()
	bpm_change_dialog.title = "Add BPM Change"
	var vb = VBoxContainer.new()
	var lbl = Label.new()
	lbl.text = "BPM value:"
	vb.add_child(lbl)
	_bpm_change_spin = SpinBox.new()
	_bpm_change_spin.min_value = 1.0
	_bpm_change_spin.max_value = 9999.0
	_bpm_change_spin.step = 0.001
	_bpm_change_spin.value = 120.0
	vb.add_child(_bpm_change_spin)
	bpm_change_dialog.add_child(vb)
	bpm_change_dialog.confirmed.connect(_on_bpm_change_dialog_confirmed)
	add_child(bpm_change_dialog)

#region File Operations

func _new_chart() -> void:
	chart_data.reset()
	current_file_path = ""
	is_dirty = false
	undo_stack.clear()
	redo_stack.clear()
	selected_notes.clear()
	_selected_bpm_change_index = -1
	_sync_controls_to_chart()
	_update_title()
	_update_status()
	if timeline:
		timeline.chart_data = chart_data
		timeline.selected_notes = selected_notes
		timeline.queue_redraw()
	if property_panel:
		property_panel.set_chart_data(chart_data)
		property_panel.show_metadata()
	chart_loaded.emit()

func _do_new() -> void:
	if is_dirty:
		_pending_action = "new"
		_show_save_confirm()
		return
	_new_chart()

func _do_open() -> void:
	if is_dirty:
		_pending_action = "open"
		_show_save_confirm()
		return
	_open_file_dialog()

func _do_save() -> void:
	if current_file_path == "":
		_do_save_as()
		return
	_save_to_path(current_file_path)

func _do_save_as() -> void:
	_file_dialog_mode = "save_as"
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		file_dialog.title = "Save Chart As..."
		if current_file_path != "":
			file_dialog.current_path = current_file_path
		file_dialog.popup_centered()

func _open_file_dialog() -> void:
	_file_dialog_mode = "open"
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.title = "Open Chart..."
		file_dialog.popup_centered()

func _save_to_path(path: String) -> void:
	var text = chart_data.save_to_json()
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_show_error("Failed to save: " + path)
		return
	f.store_string(text)
	f.close()
	current_file_path = path
	is_dirty = false
	_update_title()
	_update_status()
	chart_saved.emit()

func _load_from_path(path: String) -> void:
	var text = FileAccess.get_file_as_string(path)
	if text == "":
		_show_error("Failed to open: " + path)
		return
	if not chart_data.load_from_json(text):
		_show_error("Invalid chart JSON: " + path)
		return
	current_file_path = path
	is_dirty = false
	undo_stack.clear()
	redo_stack.clear()
	selected_notes.clear()
	_selected_bpm_change_index = -1
	# Try to auto-load audio
	_try_load_audio(path)
	_sync_controls_to_chart()
	_update_title()
	_update_status()
	if timeline:
		timeline.chart_data = chart_data
		timeline.selected_notes = selected_notes
		timeline.queue_redraw()
	if property_panel:
		property_panel.set_chart_data(chart_data)
		property_panel.show_metadata()
	chart_loaded.emit()

func _try_load_audio(chart_path: String) -> void:
	var dir = chart_path.get_base_dir()
	var audio_name = chart_data.meta.get("audio", "")
	if audio_name == "":
		return
	# Try meta.audio path first
	var candidate_paths = [
		dir.path_join(audio_name),
		dir.path_join("meta.audio"),
	]
	for ap in candidate_paths:
		if FileAccess.file_exists(ap) and audio_player:
			var loaded = audio_player.load_audio_file(ap)
			if loaded:
				break

#endregion

#region UI sync

func _sync_controls_to_chart() -> void:
	if bpm_input:
		bpm_input.set_block_signals(true)
		bpm_input.value = chart_data.meta.get("bpm", 120.0)
		bpm_input.set_block_signals(false)
	if offset_input:
		offset_input.set_block_signals(true)
		offset_input.value = chart_data.meta.get("offset", 0.0)
		offset_input.set_block_signals(false)

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

func _update_note_type_buttons() -> void:
	var note_type_names = ["normal", "top", "vertical", "long_normal", "long_top", "long_vertical", "chain"]
	var ctrl_bar_node = get_node_or_null("RootVBox/ControlBarPanel/ControlBar")
	if ctrl_bar_node == null:
		return
	for idx in range(7):
		var btn = ctrl_bar_node.get_node_or_null("NoteType%d" % (idx + 1))
		if btn:
			btn.button_pressed = (note_type_names[idx] == current_note_type)

#endregion

#region Signal handlers — menu

func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		0: _do_new()
		1: _do_open()
		2: _do_save()
		3: _do_save_as()

func _on_edit_menu_id_pressed(id: int) -> void:
	match id:
		0: _open_metadata_dialog()

func _on_view_menu_id_pressed(id: int) -> void:
	match id:
		0:  # Zoom reset
			pixels_per_second = 200.0
			if timeline:
				timeline.pixels_per_second = pixels_per_second
				timeline.queue_redraw()

#endregion

#region Signal handlers — control bar

func _on_bpm_changed(value: float) -> void:
	chart_data.meta["bpm"] = value
	if not chart_data.meta["bpm_changes"].is_empty():
		chart_data.meta["bpm_changes"][0]["bpm"] = value
	_mark_dirty()

func _on_offset_changed(value: float) -> void:
	chart_data.meta["offset"] = value
	_mark_dirty()

func _on_snap_toggled(pressed: bool) -> void:
	snap_enabled = pressed
	if timeline:
		timeline.snap_enabled = snap_enabled

func _on_snap_div_selected(index: int) -> void:
	var snap_vals = [1, 2, 3, 4, 6, 8]
	snap_division = snap_vals[index]
	if timeline:
		timeline.snap_division = snap_division

func _on_note_type_pressed(idx: int) -> void:
	var note_type_names = ["normal", "top", "vertical", "long_normal", "long_top", "long_vertical", "chain"]
	current_note_type = note_type_names[idx]
	if timeline:
		timeline.current_note_type = current_note_type
	_update_note_type_buttons()

func _on_play_button_pressed() -> void:
	toggle_playback()

func _on_stop_button_pressed() -> void:
	stop_playback()

func stop_playback() -> void:
	var return_time = playhead_time
	if audio_player:
		return_time = audio_player._play_start_playhead
		audio_player.stop_playback()
	playhead_time = return_time
	playhead_moved.emit(playhead_time)
	if timeline:
		timeline.playhead_time = playhead_time
		timeline.queue_redraw()
	if time_label:
		time_label.text = _format_time(playhead_time)

func _on_hscroll_changed(value: float) -> void:
	if timeline:
		timeline.scroll_offset = value
		timeline.queue_redraw()

func _on_vscroll_changed(value: float) -> void:
	if timeline:
		timeline.scroll_offset = value
		timeline.queue_redraw()

#endregion

#region Unsaved changes guard

func _mark_dirty() -> void:
	is_dirty = true
	_update_title()

func _show_save_confirm() -> void:
	if confirm_dialog:
		confirm_dialog.popup_centered()

func _on_confirm_save_yes() -> void:
	# User clicked "Save" (the default OK button)
	_do_save()
	_execute_pending_action()

func _on_confirm_save_action(action: StringName) -> void:
	if action == "dont_save":
		is_dirty = false
		_execute_pending_action()

func _execute_pending_action() -> void:
	var action = _pending_action
	_pending_action = ""
	match action:
		"new": _new_chart()
		"open": _open_file_dialog()
		"quit": get_tree().quit()

func _on_window_close_requested() -> void:
	if is_dirty:
		_pending_action = "quit"
		_show_save_confirm()
	else:
		get_tree().quit()

#endregion

#region File dialog callbacks

func _on_file_dialog_file_selected(path: String) -> void:
	if _file_dialog_mode == "open":
		_load_from_path(path)
	elif _file_dialog_mode == "save_as":
		_save_to_path(path)
	_file_dialog_mode = ""

func _on_file_dialog_canceled() -> void:
	_file_dialog_mode = ""

#endregion

#region Metadata dialog

func _open_metadata_dialog() -> void:
	if metadata_dialog == null:
		return
	# Populate fields from chart_data.meta
	var form_path = "MetaVBox/MetaMargin/MetaForm"
	var title_edit = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer/MetaTitleEdit")
	var artist_edit = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer2/MetaArtistEdit")
	var audio_edit = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer3/MetaAudioEdit")
	var level_spin = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer4/MetaLevelSpin")
	var bpm_spin = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer5/MetaBpmSpin")
	var offset_spin = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer6/MetaOffsetSpin")

	if title_edit:
		title_edit.text = chart_data.meta.get("title", "")
	if artist_edit:
		artist_edit.text = chart_data.meta.get("artist", "")
	if audio_edit:
		audio_edit.text = chart_data.meta.get("audio", "")
	if level_spin:
		level_spin.value = chart_data.meta.get("level", 1)
	if bpm_spin:
		bpm_spin.value = chart_data.meta.get("bpm", 120.0)
	if offset_spin:
		offset_spin.value = chart_data.meta.get("offset", 0.0)

	metadata_dialog.popup_centered()

func _on_metadata_ok() -> void:
	if metadata_dialog == null:
		return
	var form_path = "MetaVBox/MetaMargin/MetaForm"
	var title_edit = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer/MetaTitleEdit")
	var artist_edit = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer2/MetaArtistEdit")
	var audio_edit = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer3/MetaAudioEdit")
	var level_spin = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer4/MetaLevelSpin")
	var bpm_spin = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer5/MetaBpmSpin")
	var offset_spin = metadata_dialog.get_node_or_null(form_path + "/HBoxContainer6/MetaOffsetSpin")

	if title_edit:
		chart_data.meta["title"] = title_edit.text
	if artist_edit:
		chart_data.meta["artist"] = artist_edit.text
	if audio_edit:
		chart_data.meta["audio"] = audio_edit.text
	if level_spin:
		chart_data.meta["level"] = int(level_spin.value)
	if bpm_spin:
		chart_data.meta["bpm"] = bpm_spin.value
		if not chart_data.meta["bpm_changes"].is_empty():
			chart_data.meta["bpm_changes"][0]["bpm"] = bpm_spin.value
		if bpm_input:
			bpm_input.set_block_signals(true)
			bpm_input.value = bpm_spin.value
			bpm_input.set_block_signals(false)
	if offset_spin:
		chart_data.meta["offset"] = offset_spin.value
		if offset_input:
			offset_input.set_block_signals(true)
			offset_input.value = offset_spin.value
			offset_input.set_block_signals(false)

	metadata_dialog.hide()
	_mark_dirty()
	_update_status()

func _on_metadata_cancel() -> void:
	if metadata_dialog:
		metadata_dialog.hide()

#endregion

#region Undo/Redo

func execute_action(action) -> void:
	action.execute(chart_data)
	undo_stack.append(action)
	redo_stack.clear()
	_mark_dirty()
	_update_status()
	_sync_selection_to_timeline()
	if timeline:
		timeline.queue_redraw()

func undo() -> void:
	if undo_stack.is_empty():
		return
	var action = undo_stack.pop_back()
	action.undo(chart_data)
	redo_stack.append(action)
	_mark_dirty()
	_update_status()
	# Clear selection since indices may have shifted
	selected_notes.clear()
	_sync_selection_to_timeline()
	_update_property_panel()
	if timeline:
		timeline.queue_redraw()

func redo() -> void:
	if redo_stack.is_empty():
		return
	var action = redo_stack.pop_back()
	action.execute(chart_data)
	undo_stack.append(action)
	_mark_dirty()
	_update_status()
	selected_notes.clear()
	_sync_selection_to_timeline()
	_update_property_panel()
	if timeline:
		timeline.queue_redraw()

#endregion

#region Selection operations

func select_all_notes() -> void:
	selected_notes.clear()
	for i in range(chart_data.notes.size()):
		selected_notes.append(i)
	_sync_selection_to_timeline()
	_update_property_panel()
	selection_changed.emit(selected_notes)

func clear_selection() -> void:
	selected_notes.clear()
	_sync_selection_to_timeline()
	_update_property_panel()
	selection_changed.emit(selected_notes)

func delete_selected() -> void:
	if selected_notes.is_empty():
		return
	# Sort descending so indices remain valid after each deletion
	var sorted_sel = selected_notes.duplicate()
	sorted_sel.sort()
	sorted_sel.reverse()
	for idx in sorted_sel:
		if idx >= 0 and idx < chart_data.notes.size():
			var action_script = load("res://scripts/UndoRedoAction.gd")
			var action = action_script.DeleteNoteAction.new(idx, chart_data.notes[idx])
			action.execute(chart_data)
			undo_stack.append(action)
	redo_stack.clear()
	selected_notes.clear()
	_mark_dirty()
	_update_status()
	_sync_selection_to_timeline()
	_update_property_panel()
	if timeline:
		timeline.queue_redraw()

func duplicate_selected() -> void:
	if selected_notes.is_empty():
		return
	var offset_time = 0.5  # duplicate shifted by 0.5s
	var new_indices: Array = []
	for idx in selected_notes:
		if idx >= 0 and idx < chart_data.notes.size():
			var dup = chart_data.notes[idx].duplicate(true)
			dup["time"] = dup.get("time", 0.0) + offset_time
			if dup.has("end_time"):
				dup["end_time"] = dup["end_time"] + offset_time
			var action_script = load("res://scripts/UndoRedoAction.gd")
			var action = action_script.AddNoteAction.new(dup)
			action.execute(chart_data)
			undo_stack.append(action)
			new_indices.append(chart_data.notes.size() - 1)
	redo_stack.clear()
	selected_notes = new_indices
	_mark_dirty()
	_update_status()
	_sync_selection_to_timeline()
	_update_property_panel()
	if timeline:
		timeline.queue_redraw()

func copy_selected() -> void:
	_clipboard.clear()
	for idx in selected_notes:
		if idx >= 0 and idx < chart_data.notes.size():
			_clipboard.append(chart_data.notes[idx].duplicate(true))

func paste_clipboard() -> void:
	if _clipboard.is_empty():
		return
	# Find earliest time in clipboard
	var min_time = INF
	for note in _clipboard:
		var t = note.get("time", 0.0)
		if t < min_time:
			min_time = t
	var offset_time = playhead_time - min_time
	var new_indices: Array = []
	for note in _clipboard:
		var dup = note.duplicate(true)
		dup["time"] = dup.get("time", 0.0) + offset_time
		if dup.has("end_time"):
			dup["end_time"] = dup["end_time"] + offset_time
		var action_script = load("res://scripts/UndoRedoAction.gd")
		var action = action_script.AddNoteAction.new(dup)
		action.execute(chart_data)
		undo_stack.append(action)
		new_indices.append(chart_data.notes.size() - 1)
	redo_stack.clear()
	selected_notes = new_indices
	_mark_dirty()
	_update_status()
	_sync_selection_to_timeline()
	_update_property_panel()
	if timeline:
		timeline.queue_redraw()

func _sync_selection_to_timeline() -> void:
	if timeline:
		timeline.selected_notes = selected_notes
		timeline.queue_redraw()

#endregion

#region BPM change operations

func add_bpm_change_at_playhead() -> void:
	# Show dialog to enter BPM value
	if bpm_change_dialog == null or _bpm_change_spin == null:
		return
	var current_bpm = chart_data.bpm_at(playhead_time)
	_bpm_change_spin.value = current_bpm
	bpm_change_dialog.popup_centered()

func _on_bpm_change_dialog_confirmed() -> void:
	var new_bpm = _bpm_change_spin.value
	# Don't add if time=0 already exists with different bpm (edit instead)
	var new_change = {"time": playhead_time, "bpm": new_bpm}
	var action_script = load("res://scripts/UndoRedoAction.gd")
	var action = action_script.AddBpmChangeAction.new(new_change)
	execute_action(action)
	if timeline:
		timeline.queue_redraw()

func _on_bpm_change_edited(change_index: int, field: String, value: Variant) -> void:
	if chart_data == null:
		return
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	if change_index < 0 or change_index >= bpm_changes.size():
		return
	var old_value = bpm_changes[change_index].get(field, 0.0)
	if field == "bpm":
		var action_script = load("res://scripts/UndoRedoAction.gd")
		var action = action_script.EditPropertyAction.new(change_index, field, old_value, value)
		# Apply directly to bpm_changes rather than notes
		bpm_changes[change_index][field] = value
		undo_stack.append(action)
		redo_stack.clear()
		_mark_dirty()
	elif field == "time" and change_index > 0:
		var action_script = load("res://scripts/UndoRedoAction.gd")
		var action = action_script.MoveBpmChangeAction.new(change_index, old_value, float(value))
		execute_action(action)
	if timeline:
		timeline.queue_redraw()

#endregion

#region Keyboard input

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke = event as InputEventKey
	if not ke.pressed or ke.echo:
		return

	# File operations (action-mapped)
	if event.is_action("file_new"):
		_do_new()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action("file_open"):
		_do_open()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action("file_save"):
		_do_save()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action("file_save_as"):
		_do_save_as()
		get_viewport().set_input_as_handled()
		return

	# Block shortcuts when a text field has focus (avoid overriding typing)
	var focus = get_viewport().gui_get_focus_owner()
	if focus and (focus is LineEdit or focus is TextEdit or focus is SpinBox):
		return

	var ctrl = ke.ctrl_pressed
	var shift = ke.shift_pressed
	var kc = ke.keycode

	if ctrl and kc == KEY_Z:
		undo()
		get_viewport().set_input_as_handled()
	elif ctrl and (kc == KEY_Y or (shift and kc == KEY_Z)):
		redo()
		get_viewport().set_input_as_handled()
	elif ctrl and kc == KEY_A:
		select_all_notes()
		get_viewport().set_input_as_handled()
	elif ctrl and kc == KEY_D:
		duplicate_selected()
		get_viewport().set_input_as_handled()
	elif ctrl and kc == KEY_C:
		copy_selected()
		get_viewport().set_input_as_handled()
	elif ctrl and kc == KEY_V:
		paste_clipboard()
		get_viewport().set_input_as_handled()
	elif kc == KEY_DELETE:
		if _selected_bpm_change_index > 0:
			# Delete selected BPM change
			var bpm_changes = chart_data.meta.get("bpm_changes", [])
			if _selected_bpm_change_index < bpm_changes.size():
				var action_script = load("res://scripts/UndoRedoAction.gd")
				var action = action_script.DeleteBpmChangeAction.new(_selected_bpm_change_index, bpm_changes[_selected_bpm_change_index])
				execute_action(action)
				_selected_bpm_change_index = -1
				_update_property_panel()
		else:
			delete_selected()
		get_viewport().set_input_as_handled()
	elif kc == KEY_ESCAPE:
		if audio_player and (audio_player.is_playing_audio() or audio_player._is_paused):
			stop_playback()
		else:
			clear_selection()
		get_viewport().set_input_as_handled()
	elif ctrl and kc == KEY_B:
		add_bpm_change_at_playhead()
		get_viewport().set_input_as_handled()
	elif kc >= KEY_1 and kc <= KEY_7 and not ctrl:
		set_note_type(kc - KEY_1)
		get_viewport().set_input_as_handled()
	elif kc == KEY_S and not ctrl:
		toggle_select_mode()
		get_viewport().set_input_as_handled()
	elif kc == KEY_TAB:
		toggle_snap()
		get_viewport().set_input_as_handled()
	elif kc == KEY_BRACKETLEFT:
		snap_coarser()
		get_viewport().set_input_as_handled()
	elif kc == KEY_BRACKETRIGHT:
		snap_finer()
		get_viewport().set_input_as_handled()
	elif kc == KEY_SPACE:
		toggle_playback()
		get_viewport().set_input_as_handled()
	elif kc == KEY_HOME:
		set_playhead_time(0.0)
		get_viewport().set_input_as_handled()
	elif kc == KEY_END:
		var end_time = _get_chart_end_time()
		set_playhead_time(end_time)
		get_viewport().set_input_as_handled()
	elif kc == KEY_LEFT:
		var step = _get_measure_duration() if shift else _get_grid_interval()
		set_playhead_time(max(0.0, playhead_time - step))
		get_viewport().set_input_as_handled()
	elif kc == KEY_RIGHT:
		var step = _get_measure_duration() if shift else _get_grid_interval()
		set_playhead_time(playhead_time + step)
		get_viewport().set_input_as_handled()

func set_note_type(idx: int) -> void:
	var note_type_names = ["normal", "top", "vertical", "long_normal", "long_top", "long_vertical", "chain"]
	if idx >= 0 and idx < note_type_names.size():
		current_note_type = note_type_names[idx]
		if timeline:
			timeline.current_note_type = current_note_type
		_update_note_type_buttons()

func toggle_select_mode() -> void:
	is_select_mode = not is_select_mode
	if timeline:
		timeline.is_select_mode = is_select_mode

func toggle_snap() -> void:
	snap_enabled = not snap_enabled
	if snap_toggle:
		snap_toggle.set_block_signals(true)
		snap_toggle.button_pressed = snap_enabled
		snap_toggle.set_block_signals(false)
	if timeline:
		timeline.snap_enabled = snap_enabled

func snap_coarser() -> void:
	var snap_vals = [1, 2, 3, 4, 6, 8]
	var idx = snap_vals.find(snap_division)
	if idx > 0:
		snap_division = snap_vals[idx - 1]
		if timeline:
			timeline.snap_division = snap_division
		if snap_div_select:
			snap_div_select.selected = idx - 1

func snap_finer() -> void:
	var snap_vals = [1, 2, 3, 4, 6, 8]
	var idx = snap_vals.find(snap_division)
	if idx >= 0 and idx < snap_vals.size() - 1:
		snap_division = snap_vals[idx + 1]
		if timeline:
			timeline.snap_division = snap_division
		if snap_div_select:
			snap_div_select.selected = idx + 1

func toggle_playback() -> void:
	if audio_player == null:
		return
	if audio_player.is_playing_audio():
		audio_player.pause_playback()
	elif audio_player._is_paused:
		# Resume from pause position
		audio_player.play_from(audio_player._pause_position, chart_data.meta.get("offset", 0.0))
	else:
		audio_player.play_from(playhead_time, chart_data.meta.get("offset", 0.0))

func set_playhead_time(t: float) -> void:
	playhead_time = max(0.0, t)
	playhead_moved.emit(playhead_time)
	if audio_player:
		audio_player.set_playhead_time(playhead_time)
	if timeline:
		timeline.playhead_time = playhead_time
		timeline.queue_redraw()
	_update_time_label()

func _format_time(seconds_total: float) -> String:
	var m = int(seconds_total) / 60
	var s = int(seconds_total) % 60
	var ms = int(fmod(seconds_total, 1.0) * 1000.0)
	return "%d:%02d.%03d" % [m, s, ms]

func _update_time_label() -> void:
	if time_label:
		time_label.text = _format_time(playhead_time)

func _get_grid_interval() -> float:
	if chart_data == null:
		return 0.25
	var bpm_changes = chart_data.meta.get("bpm_changes", [])
	var bpm_grid_inst = load("res://scripts/BpmGrid.gd").new()
	return bpm_grid_inst.grid_interval(playhead_time, bpm_changes, snap_division)

func _get_measure_duration() -> float:
	if chart_data == null:
		return 2.0
	var bpm = chart_data.bpm_at(playhead_time)
	return (60.0 / bpm) * 4.0

func _get_chart_end_time() -> float:
	if chart_data == null or chart_data.notes.is_empty():
		return 0.0
	var end_time = 0.0
	for note in chart_data.notes:
		var t = note.get("end_time", note.get("time", 0.0))
		if t > end_time:
			end_time = t
		var chain_end = note.get("time", 0.0) + note.get("chain_count", 1) * note.get("chain_interval", 0.0)
		if chain_end > end_time:
			end_time = chain_end
	return end_time

#endregion

#region Timeline callbacks

func _on_note_placed(note_data: Dictionary) -> void:
	var action_script = load("res://scripts/UndoRedoAction.gd")
	var action = action_script.AddNoteAction.new(note_data)
	execute_action(action)

func _on_note_clicked(note_data: Dictionary, note_index: int) -> void:
	if note_index < 0:
		# Cleared
		selected_notes.clear()
		_selected_bpm_change_index = -1
	elif not selected_notes.has(note_index):
		selected_notes = [note_index]
	else:
		selected_notes = [note_index]
	_sync_selection_to_timeline()
	_update_property_panel()
	selection_changed.emit(selected_notes)

func _on_ruler_clicked(time: float) -> void:
	set_playhead_time(time)

func _on_bpm_marker_clicked(bpm_change: Dictionary, change_index: int) -> void:
	_selected_bpm_change_index = change_index
	selected_notes.clear()
	_sync_selection_to_timeline()
	if property_panel:
		property_panel.show_bpm_change(bpm_change, change_index)
	selection_changed.emit(selected_notes)

func _on_timeline_action_requested(action) -> void:
	execute_action(action)

func _on_timeline_move_action(note_index: int, old_note: Dictionary, new_note: Dictionary) -> void:
	var action_script = load("res://scripts/UndoRedoAction.gd")
	var action = action_script.MoveNoteAction.new(note_index, old_note, new_note)
	execute_action(action)

func _on_property_changed(note_index: int, field: String, value: Variant) -> void:
	if note_index < 0 or note_index >= chart_data.notes.size():
		return
	var old_value = chart_data.notes[note_index].get(field, null)
	var action_script = load("res://scripts/UndoRedoAction.gd")
	var action = action_script.EditPropertyAction.new(note_index, field, old_value, value)
	execute_action(action)

func _on_metadata_field_changed(field: String, value: Variant) -> void:
	chart_data.meta[field] = value
	if field == "bpm":
		if not chart_data.meta["bpm_changes"].is_empty():
			chart_data.meta["bpm_changes"][0]["bpm"] = float(value)
		if bpm_input:
			bpm_input.set_block_signals(true)
			bpm_input.value = float(value)
			bpm_input.set_block_signals(false)
	elif field == "offset":
		if offset_input:
			offset_input.set_block_signals(true)
			offset_input.value = float(value)
			offset_input.set_block_signals(false)
	_mark_dirty()

func _on_playback_started() -> void:
	var ctrl_bar = get_node_or_null("RootVBox/ControlBarPanel/ControlBar")
	if ctrl_bar:
		var play_btn = ctrl_bar.get_node_or_null("PlayButton")
		if play_btn:
			play_btn.text = "⏸"

func _on_playback_stopped() -> void:
	var ctrl_bar = get_node_or_null("RootVBox/ControlBarPanel/ControlBar")
	if ctrl_bar:
		var play_btn = ctrl_bar.get_node_or_null("PlayButton")
		if play_btn:
			play_btn.text = "▶"

func _on_playback_paused() -> void:
	var ctrl_bar = get_node_or_null("RootVBox/ControlBarPanel/ControlBar")
	if ctrl_bar:
		var play_btn = ctrl_bar.get_node_or_null("PlayButton")
		if play_btn:
			play_btn.text = "▶"

func _on_audio_playhead_changed(time: float) -> void:
	playhead_time = time
	if time_label:
		time_label.text = _format_time(time)
	if timeline:
		timeline.playhead_time = time
		timeline.queue_redraw()
	# Auto-scroll: keep playhead near the 80% mark of the visible timeline width
	if timeline and timeline.size.y > 0:
		var visible_height = (timeline.size.y - 24.0) / pixels_per_second
		var scroll_start = timeline.scroll_offset
		# Only scroll if playhead is near the bottom 20% or above visible area
		if time > scroll_start + visible_height * 0.8 or time < scroll_start:
			var target_scroll = time - visible_height * 0.8
			timeline.scroll_offset = max(0.0, target_scroll)
			# Sync VScrollBar
			var vscroll = get_node_or_null("RootVBox/MainArea/TimelineArea/VScrollBar")
			if vscroll:
				vscroll.set_block_signals(true)
				vscroll.value = timeline.scroll_offset
				vscroll.set_block_signals(false)
			timeline.queue_redraw()

func _update_property_panel() -> void:
	if property_panel == null:
		return
	if selected_notes.is_empty() and _selected_bpm_change_index < 0:
		property_panel.show_metadata()
	elif _selected_bpm_change_index >= 0:
		var bpm_changes = chart_data.meta.get("bpm_changes", [])
		if _selected_bpm_change_index < bpm_changes.size():
			property_panel.show_bpm_change(bpm_changes[_selected_bpm_change_index], _selected_bpm_change_index)
	else:
		property_panel.show_selection(selected_notes)

#endregion

#region Helpers

func _show_error(msg: String) -> void:
	if accept_dialog:
		accept_dialog.title = "Error"
		accept_dialog.dialog_text = msg
		accept_dialog.popup_centered()
	else:
		push_error(msg)

#endregion
