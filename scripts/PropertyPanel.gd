extends VBoxContainer
## res://scripts/PropertyPanel.gd
## Displays and edits properties of selected notes and chart metadata.

signal property_changed(note_index: int, field: String, value: Variant)
signal metadata_changed(field: String, value: Variant)
signal bpm_change_edited(change_index: int, field: String, value: Variant)
signal time_sig_change_edited(change_index: int, field: String, value: Variant)

var _selected_notes: Array = []
var _chart_data = null
var _selected_bpm_change_index: int = -1
var _selected_bpm_change: Dictionary = {}
var _selected_time_sig_change_index: int = -1
var _selected_ts_change: Dictionary = {}
var _building: bool = false  # Guard against signal re-entrancy

func _ready() -> void:
	pass

func set_chart_data(data) -> void:
	_chart_data = data

func show_selection(note_indices: Array) -> void:
	_selected_notes = note_indices.duplicate()
	_selected_bpm_change_index = -1
	_selected_time_sig_change_index = -1
	_rebuild_ui()

func show_metadata() -> void:
	_selected_notes = []
	_selected_bpm_change_index = -1
	_selected_time_sig_change_index = -1
	_rebuild_ui()

func show_bpm_change(bpm_change: Dictionary, change_index: int) -> void:
	_selected_notes = []
	_selected_bpm_change_index = change_index
	_selected_time_sig_change_index = -1
	_selected_bpm_change = bpm_change.duplicate(true)
	_rebuild_ui()

func show_time_sig_change(ts_change: Dictionary, change_index: int) -> void:
	_selected_notes = []
	_selected_bpm_change_index = -1
	_selected_time_sig_change_index = change_index
	_selected_ts_change = ts_change.duplicate(true)
	_rebuild_ui()

func _rebuild_ui() -> void:
	_building = true
	for child in get_children():
		child.queue_free()

	if _selected_notes.is_empty() and _selected_bpm_change_index < 0 and _selected_time_sig_change_index < 0:
		_build_metadata_ui()
	elif _selected_bpm_change_index >= 0:
		_build_bpm_change_ui()
	elif _selected_time_sig_change_index >= 0:
		_build_time_sig_change_ui()
	else:
		_build_note_properties_ui()

	_building = false

func _build_section_label(text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
	lbl.add_theme_font_size_override("font_size", 11)
	add_child(lbl)
	var sep = HSeparator.new()
	add_child(sep)

func _build_row(label_text: String, widget: Control) -> void:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 90
	lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(lbl)
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(widget)
	add_child(hbox)

func _make_spinbox(val: float, step: float, minv: float, maxv: float, note_idx: int, field: String) -> SpinBox:
	var sb = SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.step = step
	sb.value = val
	sb.allow_lesser = false
	sb.allow_greater = false
	sb.value_changed.connect(_on_spinbox_changed.bind(note_idx, field))
	return sb

func _make_disabled_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.modulate = Color(0.6, 0.6, 0.6)
	lbl.add_theme_font_size_override("font_size", 11)
	return lbl

# -----------------------------------------------------------------------
# Metadata section (no notes selected)
# -----------------------------------------------------------------------
func _build_metadata_ui() -> void:
	_build_section_label("Chart Metadata")
	if _chart_data == null:
		return
	var meta = _chart_data.meta

	# title
	var title_edit = LineEdit.new()
	title_edit.text = meta.get("title", "")
	title_edit.text_changed.connect(_on_meta_text_changed.bind("title"))
	_build_row("Title:", title_edit)

	# artist
	var artist_edit = LineEdit.new()
	artist_edit.text = meta.get("artist", "")
	artist_edit.text_changed.connect(_on_meta_text_changed.bind("artist"))
	_build_row("Artist:", artist_edit)

	# level
	var level_spin = SpinBox.new()
	level_spin.min_value = 1
	level_spin.max_value = 99
	level_spin.step = 1
	level_spin.value = meta.get("level", 1)
	level_spin.value_changed.connect(_on_meta_numeric_changed.bind("level", true))
	_build_row("Level:", level_spin)

	# bpm
	var bpm_spin = SpinBox.new()
	bpm_spin.min_value = 1.0
	bpm_spin.max_value = 9999.0
	bpm_spin.step = 0.001
	bpm_spin.value = meta.get("bpm", 120.0)
	bpm_spin.value_changed.connect(_on_meta_numeric_changed.bind("bpm", false))
	_build_row("BPM:", bpm_spin)

	# offset
	var offset_spin = SpinBox.new()
	offset_spin.min_value = -10.0
	offset_spin.max_value = 60.0
	offset_spin.step = 0.001
	offset_spin.value = meta.get("offset", 0.0)
	offset_spin.value_changed.connect(_on_meta_numeric_changed.bind("offset", false))
	_build_row("Offset:", offset_spin)

	# audio
	var audio_edit = LineEdit.new()
	audio_edit.text = meta.get("audio", "")
	audio_edit.text_changed.connect(_on_meta_text_changed.bind("audio"))
	_build_row("Audio:", audio_edit)

# -----------------------------------------------------------------------
# BPM change section
# -----------------------------------------------------------------------
func _build_bpm_change_ui() -> void:
	_build_section_label("BPM Change")
	if _chart_data == null:
		return
	var bpm_changes = _chart_data.meta.get("bpm_changes", [])
	if _selected_bpm_change_index >= bpm_changes.size():
		return
	var bc = bpm_changes[_selected_bpm_change_index]

	# time (read-only if index==0)
	if _selected_bpm_change_index == 0:
		_build_row("Time:", _make_disabled_label("0.000 (fixed)"))
	else:
		var time_spin = SpinBox.new()
		time_spin.min_value = 0.001
		time_spin.max_value = 9999.0
		time_spin.step = 0.001
		time_spin.value = bc.get("time", 0.0)
		time_spin.value_changed.connect(_on_bpm_change_field_changed.bind(_selected_bpm_change_index, "time"))
		_build_row("Time:", time_spin)

	# bpm
	var bpm_spin = SpinBox.new()
	bpm_spin.min_value = 1.0
	bpm_spin.max_value = 9999.0
	bpm_spin.step = 0.001
	bpm_spin.value = bc.get("bpm", 120.0)
	bpm_spin.value_changed.connect(_on_bpm_change_field_changed.bind(_selected_bpm_change_index, "bpm"))
	_build_row("BPM:", bpm_spin)

	if _selected_bpm_change_index > 0:
		var hint = Label.new()
		hint.text = "(Delete key to remove)"
		hint.modulate = Color(0.6, 0.6, 0.6)
		hint.add_theme_font_size_override("font_size", 10)
		add_child(hint)

# -----------------------------------------------------------------------
# Time sig change section
# -----------------------------------------------------------------------
func _build_time_sig_change_ui() -> void:
	_build_section_label("小節長チェンジ")
	if _chart_data == null:
		return
	var ts_changes = _chart_data.meta.get("time_sig_changes", [])
	if _selected_time_sig_change_index >= ts_changes.size():
		return
	var tc = ts_changes[_selected_time_sig_change_index]

	if _selected_time_sig_change_index == 0:
		_build_row("Time:", _make_disabled_label("0.000 (固定)"))
	else:
		var time_spin = SpinBox.new()
		time_spin.min_value = 0.001
		time_spin.max_value = 9999.0
		time_spin.step = 0.001
		time_spin.value = tc.get("time", 0.0)
		time_spin.value_changed.connect(_on_ts_field_changed.bind(_selected_time_sig_change_index, "time"))
		_build_row("Time:", time_spin)

	var num_spin = SpinBox.new()
	num_spin.min_value = 1
	num_spin.max_value = tc.get("denominator", 4)
	num_spin.step = 1
	num_spin.value = tc.get("numerator", 4)
	num_spin.value_changed.connect(_on_ts_field_changed.bind(_selected_time_sig_change_index, "numerator"))
	_build_row("分子:", num_spin)

	var den_opt = OptionButton.new()
	den_opt.add_item("4", 0)
	den_opt.add_item("8", 1)
	den_opt.add_item("12", 2)
	den_opt.add_item("16", 3)
	var denoms = [4, 8, 12, 16]
	var den_idx = denoms.find(tc.get("denominator", 4))
	if den_idx >= 0:
		den_opt.selected = den_idx
	den_opt.item_selected.connect(_on_ts_denom_selected.bind(_selected_time_sig_change_index))
	_build_row("分母:", den_opt)

	if _selected_time_sig_change_index > 0:
		var hint = Label.new()
		hint.text = "(Delete キーで削除)"
		hint.modulate = Color(0.6, 0.6, 0.6)
		hint.add_theme_font_size_override("font_size", 10)
		add_child(hint)

# -----------------------------------------------------------------------
# Note properties section
# -----------------------------------------------------------------------
func _build_note_properties_ui() -> void:
	if _chart_data == null or _selected_notes.is_empty():
		return

	var multi = _selected_notes.size() > 1
	_build_section_label("Note Properties" if not multi else "Notes (%d selected)" % _selected_notes.size())

	# Gather notes
	var notes = []
	for idx in _selected_notes:
		if idx >= 0 and idx < _chart_data.notes.size():
			notes.append(_chart_data.notes[idx])
	if notes.is_empty():
		return

	var first = notes[0]
	var primary_idx = _selected_notes[0]

	# --- type (read-only) ---
	var type_str = first.get("type", "normal")
	if multi:
		var all_same_type = true
		for n in notes:
			if n.get("type", "normal") != type_str:
				all_same_type = false
				break
		if not all_same_type:
			type_str = "(mixed)"
	_build_row("Type:", _make_disabled_label(type_str))

	# --- time ---
	if not multi:
		var time_spin = _make_spinbox(first.get("time", 0.0), 0.001, 0.0, 9999.0, primary_idx, "time")
		_build_row("Time:", time_spin)
	else:
		_build_row("Time:", _make_disabled_label("(multiple)"))

	# --- end_time (long notes only) ---
	var note_type = first.get("type", "normal")
	var is_long = note_type in ["long_normal", "long_top", "long_vertical"]
	if is_long and not multi:
		var et_spin = _make_spinbox(first.get("end_time", first.get("time", 0.0) + 0.5), 0.001, 0.0, 9999.0, primary_idx, "end_time")
		_build_row("End Time:", et_spin)
	elif is_long and multi:
		_build_row("End Time:", _make_disabled_label("(multiple)"))

	# --- top_lane (top notes) ---
	if note_type in ["top", "long_top"] or (note_type == "chain" and first.get("chain_type", "") == "top"):
		if not multi:
			var tl_spin = _make_spinbox(float(first.get("top_lane", 0)), 1, 0, 2, primary_idx, "top_lane")
			_build_row("Top Lane:", tl_spin)
		else:
			_build_row("Top Lane:", _make_disabled_label("(multiple)"))

	# --- lane (vertical notes) ---
	if note_type in ["vertical", "long_vertical"] or (note_type == "chain" and first.get("chain_type", "") == "vertical"):
		if not multi:
			var lane_spin = _make_spinbox(float(first.get("lane", 0)), 1, 0, 6, primary_idx, "lane")
			_build_row("Lane:", lane_spin)
		else:
			_build_row("Lane:", _make_disabled_label("(multiple)"))

	# --- chain-specific fields ---
	if note_type == "chain":
		# chain_type
		if not multi:
			var ct_opt = OptionButton.new()
			ct_opt.add_item("normal", 0)
			ct_opt.add_item("top", 1)
			ct_opt.add_item("vertical", 2)
			var ct_val = first.get("chain_type", "normal")
			match ct_val:
				"top": ct_opt.selected = 1
				"vertical": ct_opt.selected = 2
				_: ct_opt.selected = 0
			ct_opt.item_selected.connect(_on_chain_type_selected.bind(primary_idx))
			_build_row("Chain Type:", ct_opt)

		# chain_count
		if not multi:
			var cc_spin = _make_spinbox(float(first.get("chain_count", 2)), 1, 2, 99, primary_idx, "chain_count")
			_build_row("Chain Count:", cc_spin)

		# chain_interval
		if not multi:
			var ci_spin = _make_spinbox(first.get("chain_interval", 0.4), 0.001, 0.001, 99.0, primary_idx, "chain_interval")
			_build_row("Interval:", ci_spin)

		# last_long
		if not multi:
			var ll_check = CheckBox.new()
			ll_check.button_pressed = first.get("last_long", false)
			ll_check.toggled.connect(_on_last_long_toggled.bind(primary_idx))
			_build_row("Last Long:", ll_check)

			# last_end_time (only when last_long = true)
			if first.get("last_long", false):
				var let_spin = _make_spinbox(first.get("last_end_time", first.get("time", 0.0) + 0.5), 0.001, 0.0, 9999.0, primary_idx, "last_end_time")
				_build_row("Last End:", let_spin)

# -----------------------------------------------------------------------
# Signal handlers for property edits
# -----------------------------------------------------------------------
func _on_spinbox_changed(value: float, note_idx: int, field: String) -> void:
	if _building:
		return
	var emit_value: Variant = value
	if field in ["top_lane", "lane", "chain_count"]:
		emit_value = int(value)
	property_changed.emit(note_idx, field, emit_value)

func _on_chain_type_selected(index: int, note_idx: int) -> void:
	if _building:
		return
	var types = ["normal", "top", "vertical"]
	property_changed.emit(note_idx, "chain_type", types[index])

func _on_last_long_toggled(pressed: bool, note_idx: int) -> void:
	if _building:
		return
	property_changed.emit(note_idx, "last_long", pressed)
	# Rebuild to show/hide last_end_time field
	if not _building:
		_rebuild_ui()

func _on_meta_text_changed(text: String, field: String) -> void:
	if _building:
		return
	metadata_changed.emit(field, text)

func _on_meta_numeric_changed(value: float, field: String, as_int: bool) -> void:
	if _building:
		return
	if as_int:
		metadata_changed.emit(field, int(value))
	else:
		metadata_changed.emit(field, value)

func _on_bpm_change_field_changed(value: float, change_index: int, field: String) -> void:
	if _building:
		return
	bpm_change_edited.emit(change_index, field, value)

func _on_ts_field_changed(value: float, change_index: int, field: String) -> void:
	if _building:
		return
	var emit_value: Variant = value
	if field in ["numerator", "denominator"]:
		emit_value = int(value)
	time_sig_change_edited.emit(change_index, field, emit_value)

func _on_ts_denom_selected(index: int, change_index: int) -> void:
	if _building:
		return
	var denoms = [4, 8, 12, 16]
	time_sig_change_edited.emit(change_index, "denominator", denoms[index])
