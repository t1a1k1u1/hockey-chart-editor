extends RefCounted
## res://scripts/ChartData.gd
## Holds chart data in memory and handles JSON serialization/deserialization.

var meta: Dictionary = {}
var notes: Array = []

func _init() -> void:
	reset()

func reset() -> void:
	meta = {
		"title": "",
		"artist": "",
		"level": 1,
		"bpm": 120.0,
		"offset": 0.0,
		"audio": "",
		"bpm_changes": [{"time": 0.0, "bpm": 120.0}]
	}
	notes = []

func load_from_json(text: String) -> bool:
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		return false
	var data = json.get_data()
	if not data is Dictionary:
		return false
	meta = data.get("meta", {}).duplicate(true)
	notes = data.get("notes", []).duplicate(true)
	# Ensure bpm_changes exists
	if not meta.has("bpm_changes") or meta["bpm_changes"].is_empty():
		meta["bpm_changes"] = [{"time": 0.0, "bpm": meta.get("bpm", 120.0)}]
	return true

func save_to_json() -> String:
	var sorted_notes = notes.duplicate(true)
	sorted_notes.sort_custom(func(a, b): return a["time"] < b["time"])
	# Sync meta.bpm with bpm_changes[0]
	if not meta["bpm_changes"].is_empty():
		meta["bpm"] = meta["bpm_changes"][0]["bpm"]
	var data = {
		"meta": meta,
		"notes": sorted_notes
	}
	return JSON.stringify(data, "\t")

func bpm_at(time: float) -> float:
	var changes = meta.get("bpm_changes", [])
	if changes.is_empty():
		return meta.get("bpm", 120.0)
	var current_bpm = changes[0]["bpm"]
	for change in changes:
		if change["time"] <= time:
			current_bpm = change["bpm"]
		else:
			break
	return current_bpm

func get_note_row(note: Dictionary) -> int:
	## Returns the track row index (0-10) for a given note.
	var t = note.get("type", "normal")
	var ct = note.get("chain_type", "normal")
	if t == "top" or t == "long_top" or (t == "chain" and ct == "top"):
		return note.get("top_lane", 0)
	elif t == "normal" or t == "long_normal" or (t == "chain" and ct == "normal"):
		return 3
	elif t == "vertical" or t == "long_vertical" or (t == "chain" and ct == "vertical"):
		return 4 + note.get("lane", 0)
	return 3

func get_row_type(row: int) -> String:
	if row <= 2:
		return "top"
	elif row == 3:
		return "normal"
	else:
		return "vertical"
