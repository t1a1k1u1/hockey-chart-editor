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
var is_select_mode: bool = false
var playhead_time: float = 0.0
var playback_base_time: float = 0.0
var snap_enabled: bool = true
var snap_division: int = 16
var pixels_per_second: float = 200.0

# Note hit sound
var note_hit_player: AudioStreamPlayer = null
var bgm_volume_slider: HSlider = null
var _last_playhead_time: float = 0.0
# Sorted list of note times (including chain steps) — rebuilt on chart load
var _note_hit_times: Array = []

# Clipboard
var _paste_clipboard: Array = []

# Pending action for "unsaved changes" guard
var _pending_action: String = ""   # "new", "open", "quit"

# Node references (set in _ready)
var timeline: Control = null
var property_panel: VBoxContainer = null
var audio_player: AudioStreamPlayer = null
var status_label: Label = null
var time_label: Label = null
var snap_div_select: OptionButton = null

# Dialog references
var file_dialog: FileDialog = null
var confirm_dialog: ConfirmationDialog = null
var accept_dialog: AcceptDialog = null
var metadata_dialog: Window = null
var _file_dialog_mode: String = ""   # "open", "save_as"

# Add-change dialog (BPM + time sig + speed)
var _add_change_dialog: Window = null
var _add_change_pending_time: float = 0.0
var _add_change_time_label: Label = null
var _add_change_bpm_check: CheckBox = null
var _add_change_bpm_spin: SpinBox = null
var _add_change_ts_check: CheckBox = null
var _add_change_denom_opt: OptionButton = null
var _add_change_num_spin: SpinBox = null
var _add_change_speed_check: CheckBox = null
var _add_change_speed_spin: SpinBox = null

# BPM / time sig / speed change selected in PropertyPanel
var _selected_bpm_change_index: int = -1
var _selected_time_sig_change_index: int = -1
var _selected_speed_change_index: int = -1

# Supabase upload
var _supabase_config: Dictionary = {}
var _upload_dialog: Window = null
var _upload_status_label: Label = null
var _uploader: Node = null

func _ready() -> void:

	chart_data = load("res://scripts/ChartData.gd").new()

	# Gather node references
	var vbox = get_node_or_null("RootVBox")

	if vbox:
		var ctrl_panel = vbox.get_node_or_null("ControlBarPanel")
		if ctrl_panel:
			var ctrl_bar = ctrl_panel.get_node_or_null("ControlBar")
			if ctrl_bar:
				time_label = ctrl_bar.get_node_or_null("TimeLabel")
				snap_div_select = ctrl_bar.get_node_or_null("SnapDivSelect")
				var play_btn = ctrl_bar.get_node_or_null("PlayButton")
				if play_btn:
					play_btn.pressed.connect(_on_play_button_pressed)
				var stop_btn = ctrl_bar.get_node_or_null("StopButton")
				if stop_btn:
					stop_btn.pressed.connect(_on_stop_button_pressed)
				var reset_base_btn = ctrl_bar.get_node_or_null("ResetBaseButton")
				if reset_base_btn:
					reset_base_btn.pressed.connect(_on_reset_base_pressed)
				if snap_div_select:
					snap_div_select.item_selected.connect(_on_snap_div_selected)
				bgm_volume_slider = ctrl_bar.get_node_or_null("BgmVolumeSlider")
				if bgm_volume_slider:
					bgm_volume_slider.value_changed.connect(_on_bgm_volume_changed)
	

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

	# Note hit player
	note_hit_player = get_node_or_null("NoteHitPlayer")
	if note_hit_player:
		note_hit_player.stream = _generate_click_sound()
		note_hit_player.volume_db = linear_to_db(0.7)

	# Build combined add-change dialog
	_build_add_change_dialog()

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
		if timeline.has_signal("ruler_right_clicked"):
			timeline.connect("ruler_right_clicked", _on_ruler_right_clicked)
		if timeline.has_signal("bpm_marker_clicked"):
			timeline.connect("bpm_marker_clicked", _on_bpm_marker_clicked)
		if timeline.has_signal("paste_confirmed"):
			timeline.connect("paste_confirmed", _on_paste_confirmed)
		if timeline.has_signal("time_sig_marker_clicked"):
			timeline.connect("time_sig_marker_clicked", _on_time_sig_marker_clicked)
		if timeline.has_signal("speed_marker_clicked"):
			timeline.connect("speed_marker_clicked", _on_speed_marker_clicked)
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
		if property_panel.has_signal("time_sig_change_edited"):
			property_panel.time_sig_change_edited.connect(_on_time_sig_change_edited)
		if property_panel.has_signal("speed_change_edited"):
			property_panel.speed_change_edited.connect(_on_speed_change_edited)

	_new_chart()
	_load_supabase_config()

func _build_add_change_dialog() -> void:
	_add_change_dialog = Window.new()
	_add_change_dialog.title = "チェンジを追加"
	_add_change_dialog.size = Vector2i(310, 340)
	_add_change_dialog.transient = true
	_add_change_dialog.close_requested.connect(func(): _add_change_dialog.hide())

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_add_change_time_label = Label.new()
	_add_change_time_label.text = "Time: 0.000"
	vbox.add_child(_add_change_time_label)
	vbox.add_child(HSeparator.new())

	# BPM section
	_add_change_bpm_check = CheckBox.new()
	_add_change_bpm_check.text = "BPMを変更する"
	_add_change_bpm_check.button_pressed = true
	vbox.add_child(_add_change_bpm_check)

	var bpm_row = HBoxContainer.new()
	var bpm_lbl = Label.new()
	bpm_lbl.text = "BPM:"
	bpm_lbl.custom_minimum_size.x = 60
	bpm_row.add_child(bpm_lbl)
	_add_change_bpm_spin = SpinBox.new()
	_add_change_bpm_spin.min_value = 1.0
	_add_change_bpm_spin.max_value = 9999.0
	_add_change_bpm_spin.step = 0.001
	_add_change_bpm_spin.value = 120.0
	_add_change_bpm_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bpm_row.add_child(_add_change_bpm_spin)
	vbox.add_child(bpm_row)
	_add_change_bpm_check.toggled.connect(func(v): _add_change_bpm_spin.editable = v)

	vbox.add_child(HSeparator.new())

	# Time sig section
	_add_change_ts_check = CheckBox.new()
	_add_change_ts_check.text = "小節長を変更する"
	_add_change_ts_check.button_pressed = false
	vbox.add_child(_add_change_ts_check)

	var ts_row = HBoxContainer.new()
	var ts_lbl = Label.new()
	ts_lbl.text = "小節長:"
	ts_lbl.custom_minimum_size.x = 60
	ts_row.add_child(ts_lbl)
	_add_change_num_spin = SpinBox.new()
	_add_change_num_spin.min_value = 1
	_add_change_num_spin.max_value = 4
	_add_change_num_spin.step = 1
	_add_change_num_spin.value = 4
	_add_change_num_spin.custom_minimum_size.x = 52
	ts_row.add_child(_add_change_num_spin)
	var slash_lbl = Label.new()
	slash_lbl.text = "/"
	ts_row.add_child(slash_lbl)
	_add_change_denom_opt = OptionButton.new()
	_add_change_denom_opt.add_item("4", 0)
	_add_change_denom_opt.add_item("8", 1)
	_add_change_denom_opt.add_item("12", 2)
	_add_change_denom_opt.add_item("16", 3)
	_add_change_denom_opt.selected = 0
	_add_change_denom_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ts_row.add_child(_add_change_denom_opt)
	vbox.add_child(ts_row)
	_add_change_denom_opt.item_selected.connect(_on_add_change_denom_selected)
	_add_change_ts_check.toggled.connect(func(v):
		_add_change_num_spin.editable = v
		_add_change_denom_opt.disabled = not v
	)
	_add_change_num_spin.editable = false
	_add_change_denom_opt.disabled = true

	vbox.add_child(HSeparator.new())

	# Speed section
	_add_change_speed_check = CheckBox.new()
	_add_change_speed_check.text = "ノーツスピードを変更する"
	_add_change_speed_check.button_pressed = false
	vbox.add_child(_add_change_speed_check)

	var speed_row = HBoxContainer.new()
	var speed_lbl = Label.new()
	speed_lbl.text = "Speed:"
	speed_lbl.custom_minimum_size.x = 60
	speed_row.add_child(speed_lbl)
	_add_change_speed_spin = SpinBox.new()
	_add_change_speed_spin.min_value = 0.1
	_add_change_speed_spin.max_value = 10.0
	_add_change_speed_spin.step = 0.1
	_add_change_speed_spin.value = 1.0
	_add_change_speed_spin.editable = false
	_add_change_speed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(_add_change_speed_spin)
	vbox.add_child(speed_row)
	_add_change_speed_check.toggled.connect(func(v): _add_change_speed_spin.editable = v)

	vbox.add_child(HSeparator.new())

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	var ok_btn = Button.new()
	ok_btn.text = "OK"
	ok_btn.pressed.connect(_on_add_change_dialog_ok)
	btn_row.add_child(ok_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "キャンセル"
	cancel_btn.pressed.connect(func(): _add_change_dialog.hide())
	btn_row.add_child(cancel_btn)
	vbox.add_child(btn_row)

	_add_change_dialog.add_child(margin)
	add_child(_add_change_dialog)
	_add_change_dialog.visible = false

func _on_add_change_denom_selected(index: int) -> void:
	var denoms = [4, 8, 12, 16]
	var den = denoms[index]
	if _add_change_num_spin:
		_add_change_num_spin.max_value = den
		if _add_change_num_spin.value > den:
			_add_change_num_spin.value = den

func _show_add_change_dialog_at(time: float) -> void:
	if _add_change_dialog == null:
		return
	_add_change_pending_time = time
	if _add_change_time_label:
		_add_change_time_label.text = "Time: %.3f" % time
	if _add_change_bpm_spin:
		_add_change_bpm_spin.value = chart_data.bpm_at(time)
	if _add_change_speed_spin and chart_data:
		_add_change_speed_spin.value = chart_data.speed_at(time)
	if chart_data and _add_change_denom_opt and _add_change_num_spin:
		var ts = chart_data.time_sig_at(time)
		var denoms = [4, 8, 12, 16]
		var den_idx = denoms.find(ts["denominator"])
		if den_idx >= 0:
			_add_change_denom_opt.selected = den_idx
		_add_change_num_spin.max_value = ts["denominator"]
		_add_change_num_spin.value = ts["numerator"]
	_add_change_dialog.popup_centered()

func _on_add_change_dialog_ok() -> void:
	var action_script = load("res://scripts/UndoRedoAction.gd")
	if _add_change_bpm_check and _add_change_bpm_check.button_pressed and _add_change_bpm_spin:
		var new_change = {"time": _add_change_pending_time, "bpm": _add_change_bpm_spin.value}
		execute_action(action_script.AddBpmChangeAction.new(new_change))
	if _add_change_ts_check and _add_change_ts_check.button_pressed and _add_change_num_spin and _add_change_denom_opt:
		var denoms = [4, 8, 12, 16]
		var den = denoms[_add_change_denom_opt.selected]
		var num = int(_add_change_num_spin.value)
		var new_ts = {"time": _add_change_pending_time, "numerator": num, "denominator": den}
		execute_action(action_script.AddTimeSigChangeAction.new(new_ts))
	if _add_change_speed_check and _add_change_speed_check.button_pressed and _add_change_speed_spin:
		var new_sc = {"time": _add_change_pending_time, "speed": _add_change_speed_spin.value}
		execute_action(action_script.AddSpeedChangeAction.new(new_sc))
	_add_change_dialog.hide()
	if timeline:
		timeline.queue_redraw()

#region Supabase Upload

func _load_supabase_config() -> void:
	var path = "user://supabase_config.json"
	if not FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string('{"url":"YOUR_SUPABASE_URL","anon_key":"YOUR_ANON_KEY","service_role_key":"YOUR_SERVICE_ROLE_KEY","bucket":"songs"}')
			f.close()
	var f = FileAccess.open(path, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			_supabase_config = parsed

func _is_supabase_configured() -> bool:
	var url = _supabase_config.get("url", "")
	return url.length() > 0 and not url.begins_with("YOUR_")

func _on_upload_pressed() -> void:
	if current_file_path == "":
		if accept_dialog:
			accept_dialog.title = "エラー"
			accept_dialog.dialog_text = "先にファイルを保存してください"
			accept_dialog.popup_centered()
		return
	_show_upload_dialog()

func _show_upload_dialog() -> void:
	# If dialog exists, just show it again
	if _upload_dialog != null and is_instance_valid(_upload_dialog):
		_upload_dialog.popup_centered()
		return

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(margin)

	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(inner_vbox)

	# Config section (always show for easy updates)
	var cfg_lbl = Label.new()
	cfg_lbl.text = "Supabase 設定"
	cfg_lbl.add_theme_font_size_override("font_size", 13)
	inner_vbox.add_child(cfg_lbl)

	var url_hbox = HBoxContainer.new()
	var url_lbl = Label.new()
	url_lbl.text = "URL:"
	url_lbl.custom_minimum_size.x = 70
	url_hbox.add_child(url_lbl)
	var url_edit = LineEdit.new()
	url_edit.name = "UrlEdit"
	url_edit.placeholder_text = "https://xxx.supabase.co"
	url_edit.text = _supabase_config.get("url", "")
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_hbox.add_child(url_edit)
	inner_vbox.add_child(url_hbox)

	var key_hbox = HBoxContainer.new()
	var key_lbl = Label.new()
	key_lbl.text = "Anon Key:"
	key_lbl.custom_minimum_size.x = 100
	key_hbox.add_child(key_lbl)
	var key_edit = LineEdit.new()
	key_edit.name = "KeyEdit"
	key_edit.placeholder_text = "anon key (読み取り用)"
	key_edit.secret = true
	key_edit.text = _supabase_config.get("anon_key", "")
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_hbox.add_child(key_edit)
	inner_vbox.add_child(key_hbox)

	var svc_hbox = HBoxContainer.new()
	var svc_lbl = Label.new()
	svc_lbl.text = "Service Key:"
	svc_lbl.custom_minimum_size.x = 100
	svc_hbox.add_child(svc_lbl)
	var svc_edit = LineEdit.new()
	svc_edit.name = "ServiceKeyEdit"
	svc_edit.placeholder_text = "service_role key (アップロード用)"
	svc_edit.secret = true
	svc_edit.text = _supabase_config.get("service_role_key", "")
	svc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc_hbox.add_child(svc_edit)
	inner_vbox.add_child(svc_hbox)

	var bucket_hbox = HBoxContainer.new()
	var bucket_lbl = Label.new()
	bucket_lbl.text = "Bucket:"
	bucket_lbl.custom_minimum_size.x = 100
	bucket_hbox.add_child(bucket_lbl)
	var bucket_edit = LineEdit.new()
	bucket_edit.name = "BucketEdit"
	bucket_edit.text = _supabase_config.get("bucket", "songs")
	bucket_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bucket_hbox.add_child(bucket_edit)
	inner_vbox.add_child(bucket_hbox)

	var save_cfg_btn = Button.new()
	save_cfg_btn.text = "設定を保存"
	save_cfg_btn.pressed.connect(_save_supabase_config.bind(url_edit, key_edit, svc_edit, bucket_edit))
	inner_vbox.add_child(save_cfg_btn)

	inner_vbox.add_child(HSeparator.new())

	# Song ID row
	var sid_hbox = HBoxContainer.new()
	var sid_lbl = Label.new()
	sid_lbl.text = "Song ID:"
	sid_lbl.custom_minimum_size.x = 70
	sid_hbox.add_child(sid_lbl)
	var song_id_edit = LineEdit.new()
	song_id_edit.name = "SongIdEdit"
	# Default: folder name of the current file
	song_id_edit.text = current_file_path.get_base_dir().get_file()
	song_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sid_hbox.add_child(song_id_edit)
	inner_vbox.add_child(sid_hbox)

	var include_check = CheckBox.new()
	include_check.name = "IncludeMusicCheck"
	include_check.text = "音楽ファイルも含める"
	include_check.button_pressed = true
	inner_vbox.add_child(include_check)

	_upload_status_label = Label.new()
	_upload_status_label.text = ""
	_upload_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	inner_vbox.add_child(_upload_status_label)

	# Button row
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	var upload_btn = Button.new()
	upload_btn.text = "アップロード"
	upload_btn.pressed.connect(_do_upload.bind(song_id_edit, include_check))
	btn_hbox.add_child(upload_btn)
	var close_btn = Button.new()
	close_btn.text = "閉じる"
	close_btn.pressed.connect(func(): if _upload_dialog: _upload_dialog.hide())
	btn_hbox.add_child(close_btn)
	inner_vbox.add_child(btn_hbox)

	_upload_dialog = Window.new()
	_upload_dialog.title = "Supabase にアップロード"
	_upload_dialog.size = Vector2i(480, 340)
	_upload_dialog.transient = true
	_upload_dialog.close_requested.connect(func(): if _upload_dialog: _upload_dialog.hide())
	_upload_dialog.add_child(vbox)
	get_tree().root.add_child(_upload_dialog)
	_upload_dialog.popup_centered()

func _save_supabase_config(url_edit: LineEdit, key_edit: LineEdit, svc_edit: LineEdit, bucket_edit: LineEdit) -> void:
	var cfg = {
		"url": url_edit.text.strip_edges(),
		"anon_key": key_edit.text.strip_edges(),
		"service_role_key": svc_edit.text.strip_edges(),
		"bucket": bucket_edit.text.strip_edges()
	}
	var f = FileAccess.open("user://supabase_config.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cfg))
		f.close()
	_supabase_config = cfg
	if _upload_status_label:
		_upload_status_label.text = "設定を保存しました"

func _do_upload(song_id_edit: LineEdit, include_check: CheckBox) -> void:
	var song_id = song_id_edit.text.strip_edges()
	if song_id == "":
		if _upload_status_label:
			_upload_status_label.text = "Song ID を入力してください"
		return
	var include_music = include_check.button_pressed
	var chart_json = chart_data.save_to_json()
	var music_path = ""
	var audio_fn = ""
	if include_music:
		audio_fn = chart_data.meta.get("audio", "music.ogg")
		music_path = current_file_path.get_base_dir().path_join(audio_fn)

	if _uploader and is_instance_valid(_uploader):
		_uploader.queue_free()
		_uploader = null

	_uploader = load("res://scripts/SupabaseUploader.gd").new()
	add_child(_uploader)
	_uploader.upload_progress.connect(_on_upload_progress)
	_uploader.upload_complete.connect(_on_upload_complete)
	_uploader.upload_failed.connect(_on_upload_failed)
	_uploader.upload(
		_supabase_config.get("url", ""),
		_supabase_config.get("service_role_key", _supabase_config.get("anon_key", "")),
		_supabase_config.get("bucket", "songs"),
		song_id,
		chart_json,
		music_path,
		audio_fn
	)

func _on_upload_progress(step: int, total: int, msg: String) -> void:
	if _upload_status_label:
		_upload_status_label.text = "[%d/%d] %s" % [step, total, msg]

func _on_upload_complete() -> void:
	if _upload_status_label:
		_upload_status_label.text = "✓ アップロード完了"
	if _uploader and is_instance_valid(_uploader):
		_uploader.queue_free()
		_uploader = null

func _on_upload_failed(error: String) -> void:
	if _upload_status_label:
		_upload_status_label.text = "✗ " + error
	if _uploader and is_instance_valid(_uploader):
		_uploader.queue_free()
		_uploader = null

#endregion

#region File Operations

func _new_chart() -> void:
	chart_data.reset()
	current_file_path = ""
	is_dirty = false
	undo_stack.clear()
	redo_stack.clear()
	selected_notes.clear()
	_selected_bpm_change_index = -1
	_selected_time_sig_change_index = -1
	_selected_speed_change_index = -1
	_update_title()
	_update_status()
	if timeline:
		timeline.chart_data = chart_data
		timeline.selected_notes = selected_notes
		timeline.queue_redraw()
	if property_panel:
		property_panel.set_chart_data(chart_data)
		property_panel.show_metadata()
	_rebuild_note_hit_times()
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
	_selected_time_sig_change_index = -1
	_selected_speed_change_index = -1
	# Try to auto-load audio
	_try_load_audio(path)
	_update_title()
	_update_status()
	if timeline:
		timeline.chart_data = chart_data
		timeline.selected_notes = selected_notes
		timeline.queue_redraw()
	if property_panel:
		property_panel.set_chart_data(chart_data)
		property_panel.show_metadata()
	_rebuild_note_hit_times()
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

#endregion

#region Signal handlers — menu

func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		0: _do_new()
		1: _do_open()
		2: _do_save()
		3: _do_save_as()
		5: _on_upload_pressed()

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

func _on_snap_div_selected(index: int) -> void:
	var snap_vals = [4, 6, 8, 12, 16, 24, 32, 48, 64]
	snap_division = snap_vals[index]
	if timeline:
		timeline.snap_division = snap_division
		timeline.queue_redraw()  # Bug 3 fix: update grid immediately on snap change

func _on_play_button_pressed() -> void:
	toggle_playback()

func _on_stop_button_pressed() -> void:
	stop_playback()

func _on_reset_base_pressed() -> void:
	playback_base_time = 0.0
	if timeline:
		timeline.playback_base_time = playback_base_time
		timeline.queue_redraw()
	set_playhead_time(0.0)

func stop_playback() -> void:
	if audio_player:
		audio_player.stop_playback()
	playhead_time = playback_base_time
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
	if offset_spin:
		chart_data.meta["offset"] = offset_spin.value

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
	_rebuild_note_hit_times()
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

func _on_paste_confirmed(snapped_min_time: float) -> void:
	if _paste_clipboard.is_empty():
		return
	var min_time = INF
	for note in _paste_clipboard:
		var t = note.get("time", 0.0)
		if t < min_time:
			min_time = t
	if min_time == INF:
		return
	var time_offset = snapped_min_time - min_time
	var new_indices: Array = []
	var action_script = load("res://scripts/UndoRedoAction.gd")
	for note in _paste_clipboard:
		var dup = note.duplicate(true)
		dup["time"] = dup.get("time", 0.0) + time_offset
		if dup.has("end_time"):
			dup["end_time"] = dup["end_time"] + time_offset
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
	_show_add_change_dialog_at(playhead_time)

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
		if not selected_notes.is_empty():
			_paste_clipboard.clear()
			for idx in selected_notes:
				if idx >= 0 and idx < chart_data.notes.size():
					_paste_clipboard.append(chart_data.notes[idx].duplicate(true))
			if not _paste_clipboard.is_empty() and timeline:
				timeline.call("enter_paste_mode", _paste_clipboard)
		get_viewport().set_input_as_handled()
	elif kc == KEY_DELETE:
		if _selected_bpm_change_index > 0:
			var bpm_changes = chart_data.meta.get("bpm_changes", [])
			if _selected_bpm_change_index < bpm_changes.size():
				var action_script = load("res://scripts/UndoRedoAction.gd")
				var action = action_script.DeleteBpmChangeAction.new(_selected_bpm_change_index, bpm_changes[_selected_bpm_change_index])
				execute_action(action)
				_selected_bpm_change_index = -1
				_update_property_panel()
		elif _selected_time_sig_change_index > 0:
			var ts_changes = chart_data.meta.get("time_sig_changes", [])
			if _selected_time_sig_change_index < ts_changes.size():
				var action_script = load("res://scripts/UndoRedoAction.gd")
				var action = action_script.DeleteTimeSigChangeAction.new(_selected_time_sig_change_index, ts_changes[_selected_time_sig_change_index])
				execute_action(action)
				_selected_time_sig_change_index = -1
				_update_property_panel()
		elif _selected_speed_change_index > 0:
			var speed_changes = chart_data.meta.get("speed_changes", [])
			if _selected_speed_change_index < speed_changes.size():
				var action_script = load("res://scripts/UndoRedoAction.gd")
				var action = action_script.DeleteSpeedChangeAction.new(_selected_speed_change_index, speed_changes[_selected_speed_change_index])
				execute_action(action)
				_selected_speed_change_index = -1
				_update_property_panel()
		else:
			delete_selected()
		get_viewport().set_input_as_handled()
	elif kc == KEY_ESCAPE:
		if timeline:
			timeline.call("exit_paste_mode")
		if audio_player and (audio_player.is_playing_audio() or audio_player._is_paused):
			stop_playback()
		else:
			clear_selection()
		get_viewport().set_input_as_handled()
	elif ctrl and kc == KEY_B:
		add_bpm_change_at_playhead()
		get_viewport().set_input_as_handled()
	elif kc == KEY_S and not ctrl:
		toggle_select_mode()
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

func toggle_select_mode() -> void:
	is_select_mode = not is_select_mode
	if timeline:
		timeline.is_select_mode = is_select_mode


func snap_coarser() -> void:
	var snap_vals = [4, 6, 8, 12, 16, 24, 32, 48, 64]
	var idx = snap_vals.find(snap_division)
	if idx > 0:
		snap_division = snap_vals[idx - 1]
		if timeline:
			timeline.snap_division = snap_division
		if snap_div_select:
			snap_div_select.selected = idx - 1

func snap_finer() -> void:
	var snap_vals = [4, 6, 8, 12, 16, 24, 32, 48, 64]
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
		# Clicking to change position while paused cancels pause state
		if audio_player._is_paused:
			audio_player._is_paused = false
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
		_selected_time_sig_change_index = -1
	else:
		# Read full selection from Timeline to preserve rect-select multi-selection
		if timeline:
			selected_notes = timeline.selected_notes.duplicate()
		else:
			selected_notes = [note_index]
	_update_property_panel()
	selection_changed.emit(selected_notes)

func _on_ruler_clicked(time: float) -> void:
	playback_base_time = time
	if timeline:
		timeline.playback_base_time = playback_base_time
		timeline.queue_redraw()
	set_playhead_time(time)

func _on_ruler_right_clicked(snapped_time: float) -> void:
	_show_add_change_dialog_at(snapped_time)

func _on_bpm_marker_clicked(bpm_change: Dictionary, change_index: int) -> void:
	_selected_bpm_change_index = change_index
	_selected_time_sig_change_index = -1
	selected_notes.clear()
	_sync_selection_to_timeline()
	if property_panel:
		property_panel.show_bpm_change(bpm_change, change_index)
	selection_changed.emit(selected_notes)

func _on_time_sig_marker_clicked(ts_change: Dictionary, change_index: int) -> void:
	_selected_time_sig_change_index = change_index
	_selected_bpm_change_index = -1
	selected_notes.clear()
	_sync_selection_to_timeline()
	if property_panel:
		property_panel.show_time_sig_change(ts_change, change_index)
	selection_changed.emit(selected_notes)

func _on_time_sig_change_edited(change_index: int, field: String, value: Variant) -> void:
	if chart_data == null:
		return
	var ts_changes = chart_data.meta.get("time_sig_changes", [])
	if change_index < 0 or change_index >= ts_changes.size():
		return
	ts_changes[change_index][field] = value
	_mark_dirty()
	if timeline:
		timeline.queue_redraw()

func _on_speed_marker_clicked(speed_change: Dictionary, change_index: int) -> void:
	_selected_speed_change_index = change_index
	_selected_bpm_change_index = -1
	_selected_time_sig_change_index = -1
	selected_notes.clear()
	_sync_selection_to_timeline()
	if property_panel:
		property_panel.show_speed_change(speed_change, change_index)
	selection_changed.emit(selected_notes)

func _on_speed_change_edited(change_index: int, field: String, value: Variant) -> void:
	if chart_data == null:
		return
	var speed_changes = chart_data.meta.get("speed_changes", [])
	if change_index < 0 or change_index >= speed_changes.size():
		return
	speed_changes[change_index][field] = value
	_mark_dirty()
	if timeline:
		timeline.queue_redraw()

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
	_mark_dirty()

func _on_playback_started() -> void:
	_last_playhead_time = audio_player._play_start_playhead
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
	# Trigger note hit sounds for notes passed since last frame
	if note_hit_player and not _note_hit_times.is_empty() and time > _last_playhead_time:
		for hit_t in _note_hit_times:
			if hit_t > _last_playhead_time and hit_t <= time:
				note_hit_player.play()
				break  # one click per frame is enough for a clear click sound
	_last_playhead_time = time
	# Auto-scroll (flipped axis: bottom=early time): keep playhead near bottom 10%
	if timeline and timeline.size.y > 0:
		var visible_duration = (timeline.size.y - 24.0) / pixels_per_second
		var scroll_start = timeline.scroll_offset
		# Scroll when playhead exits the lower 80% of visible area or goes above visible area
		if time < scroll_start or time > scroll_start + visible_duration * 0.8:
			var target_scroll = time - visible_duration * 0.1
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
	if selected_notes.is_empty() and _selected_bpm_change_index < 0 and _selected_time_sig_change_index < 0 and _selected_speed_change_index < 0:
		property_panel.show_metadata()
	elif _selected_bpm_change_index >= 0:
		var bpm_changes = chart_data.meta.get("bpm_changes", [])
		if _selected_bpm_change_index < bpm_changes.size():
			property_panel.show_bpm_change(bpm_changes[_selected_bpm_change_index], _selected_bpm_change_index)
	elif _selected_time_sig_change_index >= 0:
		var ts_changes = chart_data.meta.get("time_sig_changes", [])
		if _selected_time_sig_change_index < ts_changes.size():
			property_panel.show_time_sig_change(ts_changes[_selected_time_sig_change_index], _selected_time_sig_change_index)
	elif _selected_speed_change_index >= 0:
		var speed_changes = chart_data.meta.get("speed_changes", [])
		if _selected_speed_change_index < speed_changes.size():
			property_panel.show_speed_change(speed_changes[_selected_speed_change_index], _selected_speed_change_index)
	else:
		property_panel.show_selection(selected_notes)

#endregion

#region Note hit sound

func _generate_click_sound() -> AudioStreamWAV:
	var sample_rate = 44100
	var duration_samples = 1764  # ~40ms
	var freq = 880.0
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	var data = PackedByteArray()
	data.resize(duration_samples * 2)
	for i in range(duration_samples):
		var t = float(i) / float(sample_rate)
		var envelope = exp(-t * 80.0)
		var sample = sin(2.0 * PI * freq * t) * envelope
		var val = int(clamp(sample * 32767.0, -32768.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	wav.data = data
	return wav

func _rebuild_note_hit_times() -> void:
	_note_hit_times.clear()
	if chart_data == null:
		return
	for note in chart_data.notes:
		var t = note.get("time", 0.0)
		_note_hit_times.append(t)
		# Expand chain note steps
		if note.get("type", "") == "chain":
			var count = note.get("chain_count", 1)
			var interval = note.get("chain_interval", 0.0)
			for step in range(1, count):
				_note_hit_times.append(t + step * interval)
	_note_hit_times.sort()

func _on_bgm_volume_changed(value: float) -> void:
	if audio_player:
		audio_player.volume_db = -80.0 if value <= 0.0 else linear_to_db(value)


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
