extends SceneTree
## Scene builder — run: timeout 60 godot --headless --script scenes/build_ChartEditor.gd

func _initialize() -> void:
	var root = Node.new()
	root.name = "ChartEditor"
	root.set_script(load("res://scripts/ChartEditorMain.gd"))

	# ---- Top-level VBoxContainer (full screen) ----
	var vbox = VBoxContainer.new()
	vbox.name = "RootVBox"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(vbox)

	# ---- Menu Bar row ----
	var menu_bar = MenuBar.new()
	menu_bar.name = "MenuBar"
	vbox.add_child(menu_bar)

	var file_menu = PopupMenu.new()
	file_menu.name = "FileMenu"
	file_menu.add_item("New", 0)
	file_menu.add_item("Open...", 1)
	file_menu.add_separator()
	file_menu.add_item("Save", 2)
	file_menu.add_item("Save As...", 3)
	menu_bar.add_child(file_menu)
	menu_bar.set_menu_title(0, "File")

	var edit_menu = PopupMenu.new()
	edit_menu.name = "EditMenu"
	edit_menu.add_item("Metadata...", 0)
	menu_bar.add_child(edit_menu)
	menu_bar.set_menu_title(1, "Edit")

	var view_menu = PopupMenu.new()
	view_menu.name = "ViewMenu"
	view_menu.add_item("Zoom Reset", 0)
	menu_bar.add_child(view_menu)
	menu_bar.set_menu_title(2, "View")

	# ---- Control Bar ----
	var ctrl_panel = PanelContainer.new()
	ctrl_panel.name = "ControlBarPanel"
	vbox.add_child(ctrl_panel)

	var ctrl_bar = HBoxContainer.new()
	ctrl_bar.name = "ControlBar"
	ctrl_panel.add_child(ctrl_bar)

	var play_btn = Button.new()
	play_btn.name = "PlayButton"
	play_btn.text = "▶"
	play_btn.custom_minimum_size = Vector2(32, 0)
	ctrl_bar.add_child(play_btn)

	var stop_btn = Button.new()
	stop_btn.name = "StopButton"
	stop_btn.text = "■"
	stop_btn.custom_minimum_size = Vector2(32, 0)
	ctrl_bar.add_child(stop_btn)

	var time_label = Label.new()
	time_label.name = "TimeLabel"
	time_label.text = "0:00.000"
	time_label.custom_minimum_size.x = 80
	ctrl_bar.add_child(time_label)

	ctrl_bar.add_child(VSeparator.new())

	var bpm_label = Label.new()
	bpm_label.name = "BpmLabel"
	bpm_label.text = "BPM"
	ctrl_bar.add_child(bpm_label)

	var bpm_input = SpinBox.new()
	bpm_input.name = "BpmInput"
	bpm_input.min_value = 1.0
	bpm_input.max_value = 999.0
	bpm_input.step = 0.1
	bpm_input.value = 120.0
	bpm_input.custom_minimum_size.x = 90
	ctrl_bar.add_child(bpm_input)

	ctrl_bar.add_child(VSeparator.new())

	var snap_label = Label.new()
	snap_label.text = "Snap"
	ctrl_bar.add_child(snap_label)

	var snap_div = OptionButton.new()
	snap_div.name = "SnapDivSelect"
	for v in ["1", "2", "3", "4", "6", "8"]:
		snap_div.add_item(v)
	snap_div.selected = 3  # default: 4
	ctrl_bar.add_child(snap_div)

	var snap_toggle = CheckButton.new()
	snap_toggle.name = "SnapToggle"
	snap_toggle.text = "Snap"
	snap_toggle.button_pressed = true
	ctrl_bar.add_child(snap_toggle)

	ctrl_bar.add_child(VSeparator.new())

	var note_type_label = Label.new()
	note_type_label.text = "Type:"
	ctrl_bar.add_child(note_type_label)

	var note_types = [["N", "normal"], ["T", "top"], ["V", "vertical"], ["LN", "long_normal"], ["LT", "long_top"], ["LV", "long_vertical"], ["CH", "chain"]]
	for i in range(note_types.size()):
		var btn = Button.new()
		btn.name = "NoteType%d" % (i + 1)
		btn.text = note_types[i][0]
		btn.tooltip_text = note_types[i][1]
		btn.toggle_mode = true
		ctrl_bar.add_child(btn)

	ctrl_bar.add_child(VSeparator.new())

	var offset_label = Label.new()
	offset_label.text = "Offset"
	ctrl_bar.add_child(offset_label)

	var offset_input = SpinBox.new()
	offset_input.name = "OffsetInput"
	offset_input.min_value = -10.0
	offset_input.max_value = 10.0
	offset_input.step = 0.001
	offset_input.value = 0.0
	offset_input.custom_minimum_size.x = 90
	ctrl_bar.add_child(offset_input)

	# ---- Main Area (3 panels) ----
	var main_hbox = HBoxContainer.new()
	main_hbox.name = "MainArea"
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 0)
	vbox.add_child(main_hbox)

	# Track Header (120px)
	var track_header_panel = PanelContainer.new()
	track_header_panel.name = "TrackHeaderPanel"
	track_header_panel.custom_minimum_size.x = 120
	main_hbox.add_child(track_header_panel)

	var track_header_vbox = VBoxContainer.new()
	track_header_vbox.name = "TrackHeaderList"
	track_header_vbox.add_theme_constant_override("separation", 0)
	track_header_panel.add_child(track_header_vbox)

	# Build track row labels with colored backgrounds
	# Colors: TOP0-2: #3A2200 orange, NORMAL: #001A3A blue, V0-6: #001228 dark blue
	var row_configs = [
		["TOP 0", Color(0.227, 0.133, 0.0)],     # #3A2200
		["TOP 1", Color(0.227, 0.133, 0.0)],
		["TOP 2", Color(0.227, 0.133, 0.0)],
		["NORMAL", Color(0.0, 0.102, 0.227)],     # #001A3A
		["V 0", Color(0.0, 0.071, 0.157)],        # #001228
		["V 1", Color(0.0, 0.071, 0.157)],
		["V 2", Color(0.0, 0.071, 0.157)],
		["V 3", Color(0.0, 0.071, 0.157)],
		["V 4", Color(0.0, 0.071, 0.157)],
		["V 5", Color(0.0, 0.071, 0.157)],
		["V 6", Color(0.0, 0.071, 0.157)],
	]
	for i in range(row_configs.size()):
		# Add 4px separator before rows 1,2,3,4
		if i == 1 or i == 2 or i == 3 or i == 4:
			var sep = Panel.new()
			sep.name = "TrackSep%d" % i
			sep.custom_minimum_size = Vector2(0, 4)
			var sep_style = StyleBoxFlat.new()
			sep_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
			sep.add_theme_stylebox_override("panel", sep_style)
			track_header_vbox.add_child(sep)

		# Row panel with colored background
		var row_panel = Panel.new()
		row_panel.name = "RowPanel%d" % i
		row_panel.custom_minimum_size = Vector2(0, 32)
		var bg_style = StyleBoxFlat.new()
		bg_style.bg_color = row_configs[i][1]
		row_panel.add_theme_stylebox_override("panel", bg_style)
		track_header_vbox.add_child(row_panel)

		var row_label = Label.new()
		row_label.name = "Row%d" % i
		row_label.text = row_configs[i][0]
		row_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row_label.modulate = Color(0.9, 0.9, 0.9, 1.0)
		row_panel.add_child(row_label)

	# Timeline Area (expand)
	var timeline_vbox = VBoxContainer.new()
	timeline_vbox.name = "TimelineArea"
	timeline_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_vbox.add_theme_constant_override("separation", 0)
	main_hbox.add_child(timeline_vbox)

	var timeline = Control.new()
	timeline.name = "Timeline"
	timeline.set_script(load("res://scripts/Timeline.gd"))
	timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline.clip_contents = true
	timeline_vbox.add_child(timeline)

	var hscroll = HScrollBar.new()
	hscroll.name = "HScrollBar"
	timeline_vbox.add_child(hscroll)

	# Property Panel (240px)
	var prop_panel = PanelContainer.new()
	prop_panel.name = "PropertyPanelContainer"
	prop_panel.custom_minimum_size.x = 240
	main_hbox.add_child(prop_panel)

	var prop_scroll = ScrollContainer.new()
	prop_scroll.name = "PropertyPanel"
	prop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prop_panel.add_child(prop_scroll)

	var prop_content = VBoxContainer.new()
	prop_content.name = "PropertyPanelContent"
	prop_content.set_script(load("res://scripts/PropertyPanel.gd"))
	prop_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prop_scroll.add_child(prop_content)

	# ---- Status Bar ----
	var status_panel = PanelContainer.new()
	status_panel.name = "StatusBar"
	vbox.add_child(status_panel)

	var status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Ready — No file loaded"
	status_panel.add_child(status_label)

	# ---- Dialogs ----
	var file_dialog = FileDialog.new()
	file_dialog.name = "FileDialog"
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; Chart JSON"])
	file_dialog.size = Vector2i(900, 600)
	root.add_child(file_dialog)

	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.name = "ConfirmationDialog"
	confirm_dialog.dialog_text = "保存しますか？\nSave changes before continuing?"
	root.add_child(confirm_dialog)

	var accept_dialog = AcceptDialog.new()
	accept_dialog.name = "AcceptDialog"
	root.add_child(accept_dialog)

	# ---- Metadata Dialog (Window with form) ----
	var meta_dialog = Window.new()
	meta_dialog.name = "MetadataDialog"
	meta_dialog.title = "Edit Metadata"
	meta_dialog.size = Vector2i(400, 320)
	meta_dialog.transient = true
	meta_dialog.exclusive = true
	meta_dialog.visible = false
	root.add_child(meta_dialog)

	var meta_vbox = VBoxContainer.new()
	meta_vbox.name = "MetaVBox"
	meta_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	meta_vbox.add_theme_constant_override("separation", 6)
	meta_dialog.add_child(meta_vbox)

	# Add margin container for padding
	var meta_margin = MarginContainer.new()
	meta_margin.name = "MetaMargin"
	meta_margin.add_theme_constant_override("margin_left", 12)
	meta_margin.add_theme_constant_override("margin_right", 12)
	meta_margin.add_theme_constant_override("margin_top", 8)
	meta_margin.add_theme_constant_override("margin_bottom", 8)
	meta_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	meta_vbox.add_child(meta_margin)

	var meta_form = VBoxContainer.new()
	meta_form.name = "MetaForm"
	meta_form.add_theme_constant_override("separation", 4)
	meta_margin.add_child(meta_form)

	var meta_fields = [
		["Title:", "MetaTitleEdit", ""],
		["Artist:", "MetaArtistEdit", ""],
		["Audio:", "MetaAudioEdit", ""],
	]
	for mf in meta_fields:
		var row = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = mf[0]
		lbl.custom_minimum_size.x = 60
		row.add_child(lbl)
		var edit = LineEdit.new()
		edit.name = mf[1]
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
		meta_form.add_child(row)

	# Level row
	var level_row = HBoxContainer.new()
	var level_lbl = Label.new()
	level_lbl.text = "Level:"
	level_lbl.custom_minimum_size.x = 60
	level_row.add_child(level_lbl)
	var level_spin = SpinBox.new()
	level_spin.name = "MetaLevelSpin"
	level_spin.min_value = 1
	level_spin.max_value = 99
	level_spin.value = 1
	level_row.add_child(level_spin)
	meta_form.add_child(level_row)

	# BPM row
	var bpm_row = HBoxContainer.new()
	var bpm_lbl2 = Label.new()
	bpm_lbl2.text = "BPM:"
	bpm_lbl2.custom_minimum_size.x = 60
	bpm_row.add_child(bpm_lbl2)
	var meta_bpm_spin = SpinBox.new()
	meta_bpm_spin.name = "MetaBpmSpin"
	meta_bpm_spin.min_value = 1.0
	meta_bpm_spin.max_value = 999.0
	meta_bpm_spin.step = 0.1
	meta_bpm_spin.value = 120.0
	bpm_row.add_child(meta_bpm_spin)
	meta_form.add_child(bpm_row)

	# Offset row
	var offset_row2 = HBoxContainer.new()
	var offset_lbl2 = Label.new()
	offset_lbl2.text = "Offset:"
	offset_lbl2.custom_minimum_size.x = 60
	offset_row2.add_child(offset_lbl2)
	var meta_offset_spin = SpinBox.new()
	meta_offset_spin.name = "MetaOffsetSpin"
	meta_offset_spin.min_value = -10.0
	meta_offset_spin.max_value = 10.0
	meta_offset_spin.step = 0.001
	meta_offset_spin.value = 0.0
	offset_row2.add_child(meta_offset_spin)
	meta_form.add_child(offset_row2)

	# OK / Cancel buttons
	var btn_row = HBoxContainer.new()
	btn_row.name = "MetaBtnRow"
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	meta_vbox.add_child(btn_row)

	var meta_ok = Button.new()
	meta_ok.name = "MetaOkBtn"
	meta_ok.text = "OK"
	btn_row.add_child(meta_ok)

	var meta_cancel = Button.new()
	meta_cancel.name = "MetaCancelBtn"
	meta_cancel.text = "Cancel"
	btn_row.add_child(meta_cancel)

	# ---- Audio Player ----
	var audio_player = AudioStreamPlayer.new()
	audio_player.name = "AudioStreamPlayer"
	audio_player.set_script(load("res://scripts/AudioPlayer.gd"))
	root.add_child(audio_player)

	# Save
	set_owner_on_new_nodes(root, root)
	var packed = PackedScene.new()
	var err = packed.pack(root)
	if err != OK:
		push_error("Pack failed: " + str(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, "res://scenes/ChartEditor.tscn")
	if err != OK:
		push_error("Save failed: " + str(err))
		quit(1)
		return
	print("Saved: res://scenes/ChartEditor.tscn")
	quit(0)

func set_owner_on_new_nodes(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		if c.scene_file_path.is_empty():
			set_owner_on_new_nodes(c, owner)
