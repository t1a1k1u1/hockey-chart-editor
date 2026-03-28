extends VBoxContainer
## res://scripts/PropertyPanel.gd
## Displays and edits properties of selected notes and chart metadata.

signal property_changed(note_index: int, field: String, value: Variant)
signal metadata_changed(field: String, value: Variant)

var _selected_notes: Array = []
var _chart_data = null

func _ready() -> void:
	pass

func set_chart_data(data) -> void:
	_chart_data = data

func show_selection(note_indices: Array) -> void:
	_selected_notes = note_indices
	_rebuild_ui()

func show_metadata() -> void:
	_selected_notes = []
	_rebuild_ui()

func _rebuild_ui() -> void:
	for child in get_children():
		child.queue_free()
