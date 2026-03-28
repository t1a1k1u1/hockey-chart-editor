extends Control
## res://scripts/Timeline.gd
## Main timeline canvas: drawing, input handling, zoom/scroll.

signal note_clicked(note_data: Dictionary, note_index: int)
signal note_placed(note_data: Dictionary)
signal ruler_clicked(time: float)
signal bpm_marker_clicked(bpm_change: Dictionary, change_index: int)

const RULER_HEIGHT = 20.0
const BPM_BAND_HEIGHT = 16.0
const TRACK_HEIGHT = 32.0
const SEP_HEIGHT = 4.0
const DEFAULT_PPS = 200.0  # pixels per second

var pixels_per_second: float = DEFAULT_PPS
var scroll_offset: float = 0.0  # seconds
var playhead_time: float = 0.0

var chart_data = null
var bpm_grid = null
var note_renderer = null

var snap_enabled: bool = true
var snap_division: int = 4
var current_note_type: String = "normal"
var is_select_mode: bool = false
var selected_notes: Array = []

func _ready() -> void:
	bpm_grid = load("res://scripts/BpmGrid.gd").new()
	note_renderer = load("res://scripts/NoteRenderer.gd").new()
	clip_contents = true

func _draw() -> void:
	pass

func time_to_x(time: float) -> float:
	return (time - scroll_offset) * pixels_per_second

func x_to_time(x: float) -> float:
	return x / pixels_per_second + scroll_offset

func y_to_row(y: float) -> int:
	var content_y = y - RULER_HEIGHT - BPM_BAND_HEIGHT
	if content_y < 0:
		return -1
	# Walk rows with separators
	var rows = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	var cursor = 0.0
	for i in range(11):
		# Add separator before row if applicable
		if i == 1 or i == 2 or i == 3 or i == 4:
			cursor += SEP_HEIGHT
		if content_y < cursor + TRACK_HEIGHT:
			return i
		cursor += TRACK_HEIGHT
	return -1

func get_row_y(row: int) -> float:
	var sep_count = 0
	if row >= 1: sep_count += 1
	if row >= 2: sep_count += 1
	if row >= 3: sep_count += 1
	if row >= 4: sep_count += 1
	return RULER_HEIGHT + BPM_BAND_HEIGHT + row * TRACK_HEIGHT + sep_count * SEP_HEIGHT

func _gui_input(event: InputEvent) -> void:
	pass
