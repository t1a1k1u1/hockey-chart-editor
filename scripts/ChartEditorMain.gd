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
var _file_dialog_mode: String = ""   # "open", "save_as"

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
				var snap_vals = [1, 2, 3, 4, 6, 8]
				for idx in range(7):
					var btn = ctrl_bar.get_node_or_null("NoteType%d" % (idx + 1))
					if btn:
						btn.pressed.connect(_on_note_type_pressed.bind(idx))

		var main_area = vbox.get_node_or_null("MainArea")
		if main_area:
			var tl_area = main_area.get_node_or_null("TimelineArea")
			if tl_area:
				timeline = tl_area.get_node_or_null("Timeline")
				var hscroll = tl_area.get_node_or_null("HScrollBar")
				if hscroll and timeline:
					hscroll.value_changed.connect(_on_hscroll_changed)
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

	# Connect window close request
	get_tree().get_root().close_requested.connect(_on_window_close_requested)

	_new_chart()
	_update_note_type_buttons()

#region File Operations

func _new_chart() -> void:
	chart_data.reset()
	current_file_path = ""
	is_dirty = false
	undo_stack.clear()
	redo_stack.clear()
	selected_notes.clear()
	_sync_controls_to_chart()
	_update_title()
	_update_status()
	if timeline:
		timeline.chart_data = chart_data
		timeline.queue_redraw()
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
	# Try to auto-load audio
	_try_load_audio(path)
	_sync_controls_to_chart()
	_update_title()
	_update_status()
	if timeline:
		timeline.chart_data = chart_data
		timeline.queue_redraw()
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
	if audio_player and audio_player.is_playing_audio():
		audio_player.pause_playback()
	elif audio_player:
		audio_player.play_from(playhead_time, chart_data.meta.get("offset", 0.0))

func _on_stop_button_pressed() -> void:
	if audio_player:
		audio_player.stop_playback()
	playhead_time = 0.0
	playhead_moved.emit(playhead_time)
	if timeline:
		timeline.playhead_time = playhead_time
		timeline.queue_redraw()
	if time_label:
		time_label.text = "0:00.000"

func _on_hscroll_changed(value: float) -> void:
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
	if timeline:
		timeline.queue_redraw()

#endregion

#region Keyboard input

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("file_new"):
			_do_new()
			get_viewport().set_input_as_handled()
		elif event.is_action("file_open"):
			_do_open()
			get_viewport().set_input_as_handled()
		elif event.is_action("file_save"):
			_do_save()
			get_viewport().set_input_as_handled()
		elif event.is_action("file_save_as"):
			_do_save_as()
			get_viewport().set_input_as_handled()
		elif event.is_action("edit_undo"):
			undo()
			get_viewport().set_input_as_handled()
		elif event.is_action("edit_redo"):
			redo()
			get_viewport().set_input_as_handled()

#endregion

#region Timeline callbacks

func _on_note_placed(note_data: Dictionary) -> void:
	chart_data.notes.append(note_data)
	_mark_dirty()
	_update_status()
	if timeline:
		timeline.queue_redraw()

func _on_note_clicked(note_data: Dictionary, note_index: int) -> void:
	if not selected_notes.has(note_index):
		selected_notes = [note_index]
	else:
		selected_notes = []
	selection_changed.emit(selected_notes)
	if property_panel:
		property_panel.show_selection(selected_notes)

func _on_ruler_clicked(time: float) -> void:
	playhead_time = time
	playhead_moved.emit(time)
	if timeline:
		timeline.playhead_time = playhead_time
		timeline.queue_redraw()

func _on_bpm_marker_clicked(bpm_change: Dictionary, change_index: int) -> void:
	pass

func _on_property_changed(note_index: int, field: String, value: Variant) -> void:
	if note_index >= 0 and note_index < chart_data.notes.size():
		chart_data.notes[note_index][field] = value
		_mark_dirty()
		if timeline:
			timeline.queue_redraw()

func _on_playback_started() -> void:
	pass

func _on_playback_stopped() -> void:
	pass

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
