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
	for v in ["4", "6", "8", "12", "16", "24", "32", "48", "64"]:
		snap_div.add_item(v)
	snap_div.selected = 4  # default: 16 (= 4 divisions per beat)
	ctrl_bar.add_child(snap_div)

	ctrl_bar.add_child(VSeparator.new())

	var bgm_label = Label.new()
	bgm_label.text = "BGM"
	ctrl_bar.add_child(bgm_label)

	var bgm_slider = HSlider.new()
	bgm_slider.name = "BgmVolumeSlider"
	bgm_slider.min_value = 0.0
	bgm_slider.max_value = 1.0
	bgm_slider.step = 0.01
	bgm_slider.value = 0.5
	bgm_slider.custom_minimum_size = Vector2(80, 0)
	bgm_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ctrl_bar.add_child(bgm_slider)

	# ---- Main Area (3 panels) ----
	var main_hbox = HBoxContainer.new()
	main_hbox.name = "MainArea"
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 0)
	vbox.add_child(main_hbox)

	# Timeline Area (expand) — Timeline + VScrollBar side by side
	var timeline_hbox = HBoxContainer.new()
	timeline_hbox.name = "TimelineArea"
	timeline_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline_hbox.add_theme_constant_override("separation", 0)
	main_hbox.add_child(timeline_hbox)

	var timeline = Control.new()
	timeline.name = "Timeline"
	timeline.set_script(load("res://scripts/Timeline.gd"))
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline.clip_contents = true
	timeline_hbox.add_child(timeline)

	var vscroll = VScrollBar.new()
	vscroll.name = "VScrollBar"
	vscroll.custom_minimum_size.x = 16
	vscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline_hbox.add_child(vscroll)

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

	# ---- Note Hit Sound Player ----
	var note_hit_player = AudioStreamPlayer.new()
	note_hit_player.name = "NoteHitPlayer"
	root.add_child(note_hit_player)

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
