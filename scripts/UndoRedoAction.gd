extends RefCounted
## res://scripts/UndoRedoAction.gd
## Base class for undo/redo operations (Command pattern).

func execute(_chart_data) -> void:
	pass

func undo(_chart_data) -> void:
	pass

# ---------------------------------------------------------------------------
# AddNoteAction
# ---------------------------------------------------------------------------
class AddNoteAction extends RefCounted:
	var _note: Dictionary

	func _init(note: Dictionary) -> void:
		_note = note.duplicate(true)

	func execute(chart_data) -> void:
		chart_data.notes.append(_note.duplicate(true))

	func undo(chart_data) -> void:
		# Remove the last note that matches _note (by time + type identity)
		for i in range(chart_data.notes.size() - 1, -1, -1):
			var n = chart_data.notes[i]
			if _notes_match(n, _note):
				chart_data.notes.remove_at(i)
				return

	func _notes_match(a: Dictionary, b: Dictionary) -> bool:
		return a.get("time", -1.0) == b.get("time", -1.0) and a.get("type", "") == b.get("type", "")

# ---------------------------------------------------------------------------
# DeleteNoteAction
# ---------------------------------------------------------------------------
class DeleteNoteAction extends RefCounted:
	var _index: int
	var _note: Dictionary

	func _init(index: int, note: Dictionary) -> void:
		_index = index
		_note = note.duplicate(true)

	func execute(chart_data) -> void:
		if _index >= 0 and _index < chart_data.notes.size():
			chart_data.notes.remove_at(_index)

	func undo(chart_data) -> void:
		var insert_pos = clamp(_index, 0, chart_data.notes.size())
		chart_data.notes.insert(insert_pos, _note.duplicate(true))

# ---------------------------------------------------------------------------
# MoveNoteAction
# ---------------------------------------------------------------------------
class MoveNoteAction extends RefCounted:
	var _index: int
	var _old_time: float
	var _new_time: float
	var _old_end_time: float
	var _new_end_time: float
	var _old_top_lane: int
	var _new_top_lane: int
	var _old_lane: int
	var _new_lane: int

	func _init(index: int, old_note: Dictionary, new_note: Dictionary) -> void:
		_index = index
		_old_time = old_note.get("time", 0.0)
		_new_time = new_note.get("time", 0.0)
		_old_end_time = old_note.get("end_time", 0.0)
		_new_end_time = new_note.get("end_time", 0.0)
		_old_top_lane = old_note.get("top_lane", 0)
		_new_top_lane = new_note.get("top_lane", 0)
		_old_lane = old_note.get("lane", 0)
		_new_lane = new_note.get("lane", 0)

	func execute(chart_data) -> void:
		if _index >= 0 and _index < chart_data.notes.size():
			var n = chart_data.notes[_index]
			n["time"] = _new_time
			if n.has("end_time") or _new_end_time > 0.0:
				n["end_time"] = _new_end_time
			if n.has("top_lane"):
				n["top_lane"] = _new_top_lane
			if n.has("lane"):
				n["lane"] = _new_lane

	func undo(chart_data) -> void:
		if _index >= 0 and _index < chart_data.notes.size():
			var n = chart_data.notes[_index]
			n["time"] = _old_time
			if n.has("end_time") or _old_end_time > 0.0:
				n["end_time"] = _old_end_time
			if n.has("top_lane"):
				n["top_lane"] = _old_top_lane
			if n.has("lane"):
				n["lane"] = _old_lane

# ---------------------------------------------------------------------------
# EditPropertyAction
# ---------------------------------------------------------------------------
class EditPropertyAction extends RefCounted:
	var _index: int
	var _field: String
	var _old_value
	var _new_value

	func _init(index: int, field: String, old_value, new_value) -> void:
		_index = index
		_field = field
		_old_value = old_value
		_new_value = new_value

	func execute(chart_data) -> void:
		if _index >= 0 and _index < chart_data.notes.size():
			chart_data.notes[_index][_field] = _new_value

	func undo(chart_data) -> void:
		if _index >= 0 and _index < chart_data.notes.size():
			chart_data.notes[_index][_field] = _old_value

# ---------------------------------------------------------------------------
# AddBpmChangeAction
# ---------------------------------------------------------------------------
class AddBpmChangeAction extends RefCounted:
	var _change: Dictionary

	func _init(change: Dictionary) -> void:
		_change = change.duplicate(true)

	func execute(chart_data) -> void:
		var changes = chart_data.meta.get("bpm_changes", [])
		changes.append(_change.duplicate(true))
		changes.sort_custom(func(a, b): return a["time"] < b["time"])
		chart_data.meta["bpm_changes"] = changes

	func undo(chart_data) -> void:
		var changes = chart_data.meta.get("bpm_changes", [])
		for i in range(changes.size() - 1, -1, -1):
			var c = changes[i]
			if c.get("time", -1.0) == _change.get("time", -1.0) and c.get("bpm", -1.0) == _change.get("bpm", -1.0):
				changes.remove_at(i)
				return
		chart_data.meta["bpm_changes"] = changes

# ---------------------------------------------------------------------------
# DeleteBpmChangeAction
# ---------------------------------------------------------------------------
class DeleteBpmChangeAction extends RefCounted:
	var _index: int
	var _change: Dictionary

	func _init(index: int, change: Dictionary) -> void:
		_index = index
		_change = change.duplicate(true)

	func execute(chart_data) -> void:
		var changes = chart_data.meta.get("bpm_changes", [])
		if _index >= 0 and _index < changes.size():
			changes.remove_at(_index)

	func undo(chart_data) -> void:
		var changes = chart_data.meta.get("bpm_changes", [])
		var insert_pos = clamp(_index, 0, changes.size())
		changes.insert(insert_pos, _change.duplicate(true))

# ---------------------------------------------------------------------------
# MoveBpmChangeAction
# ---------------------------------------------------------------------------
class MoveBpmChangeAction extends RefCounted:
	var _index: int
	var _old_time: float
	var _new_time: float

	func _init(index: int, old_time: float, new_time: float) -> void:
		_index = index
		_old_time = old_time
		_new_time = new_time

	func execute(chart_data) -> void:
		var changes = chart_data.meta.get("bpm_changes", [])
		if _index >= 0 and _index < changes.size():
			changes[_index]["time"] = _new_time

	func undo(chart_data) -> void:
		var changes = chart_data.meta.get("bpm_changes", [])
		if _index >= 0 and _index < changes.size():
			changes[_index]["time"] = _old_time

# ---------------------------------------------------------------------------
# AddTimeSigChangeAction
# ---------------------------------------------------------------------------
class AddTimeSigChangeAction extends RefCounted:
	var _change: Dictionary

	func _init(change: Dictionary) -> void:
		_change = change.duplicate(true)

	func execute(chart_data) -> void:
		var changes = chart_data.meta.get("time_sig_changes", [])
		changes.append(_change.duplicate(true))
		changes.sort_custom(func(a, b): return a["time"] < b["time"])
		chart_data.meta["time_sig_changes"] = changes

	func undo(chart_data) -> void:
		var changes = chart_data.meta.get("time_sig_changes", [])
		for i in range(changes.size() - 1, -1, -1):
			var c = changes[i]
			if c.get("time", -1.0) == _change.get("time", -1.0) and \
			   c.get("numerator", -1) == _change.get("numerator", -1) and \
			   c.get("denominator", -1) == _change.get("denominator", -1):
				changes.remove_at(i)
				return

# ---------------------------------------------------------------------------
# DeleteTimeSigChangeAction
# ---------------------------------------------------------------------------
class DeleteTimeSigChangeAction extends RefCounted:
	var _index: int
	var _change: Dictionary

	func _init(index: int, change: Dictionary) -> void:
		_index = index
		_change = change.duplicate(true)

	func execute(chart_data) -> void:
		var changes = chart_data.meta.get("time_sig_changes", [])
		if _index >= 0 and _index < changes.size():
			changes.remove_at(_index)

	func undo(chart_data) -> void:
		var changes = chart_data.meta.get("time_sig_changes", [])
		var insert_pos = clamp(_index, 0, changes.size())
		changes.insert(insert_pos, _change.duplicate(true))

# ---------------------------------------------------------------------------
# AddSpeedChangeAction
# ---------------------------------------------------------------------------
class AddSpeedChangeAction extends RefCounted:
	var _change: Dictionary

	func _init(change: Dictionary) -> void:
		_change = change.duplicate(true)

	func execute(chart_data) -> void:
		var changes = chart_data.meta.get("speed_changes", [])
		changes.append(_change.duplicate(true))
		changes.sort_custom(func(a, b): return a["time"] < b["time"])
		chart_data.meta["speed_changes"] = changes

	func undo(chart_data) -> void:
		var changes = chart_data.meta.get("speed_changes", [])
		for i in range(changes.size() - 1, -1, -1):
			var c = changes[i]
			if c.get("time", -1.0) == _change.get("time", -1.0) and c.get("speed", -1.0) == _change.get("speed", -1.0):
				changes.remove_at(i)
				return
		chart_data.meta["speed_changes"] = changes

# ---------------------------------------------------------------------------
# DeleteSpeedChangeAction
# ---------------------------------------------------------------------------
class DeleteSpeedChangeAction extends RefCounted:
	var _index: int
	var _change: Dictionary

	func _init(index: int, change: Dictionary) -> void:
		_index = index
		_change = change.duplicate(true)

	func execute(chart_data) -> void:
		var changes = chart_data.meta.get("speed_changes", [])
		if _index >= 0 and _index < changes.size():
			changes.remove_at(_index)

	func undo(chart_data) -> void:
		var changes = chart_data.meta.get("speed_changes", [])
		var insert_pos = clamp(_index, 0, changes.size())
		changes.insert(insert_pos, _change.duplicate(true))

# ---------------------------------------------------------------------------
# MoveSpeedChangeAction
# ---------------------------------------------------------------------------
class MoveSpeedChangeAction extends RefCounted:
	var _index: int
	var _old_time: float
	var _new_time: float

	func _init(index: int, old_time: float, new_time: float) -> void:
		_index = index
		_old_time = old_time
		_new_time = new_time

	func execute(chart_data) -> void:
		var changes = chart_data.meta.get("speed_changes", [])
		if _index >= 0 and _index < changes.size():
			changes[_index]["time"] = _new_time

	func undo(chart_data) -> void:
		var changes = chart_data.meta.get("speed_changes", [])
		if _index >= 0 and _index < changes.size():
			changes[_index]["time"] = _old_time

# ---------------------------------------------------------------------------
# ReplaceNoteAction
# ---------------------------------------------------------------------------
class ReplaceNoteAction extends RefCounted:
	var _index: int
	var _old_note: Dictionary
	var _new_note: Dictionary

	func _init(index: int, old_note: Dictionary, new_note: Dictionary) -> void:
		_index = index
		_old_note = old_note.duplicate(true)
		_new_note = new_note.duplicate(true)

	func execute(chart_data) -> void:
		if _index >= 0 and _index < chart_data.notes.size():
			chart_data.notes[_index] = _new_note.duplicate(true)

	func undo(chart_data) -> void:
		if _index >= 0 and _index < chart_data.notes.size():
			chart_data.notes[_index] = _old_note.duplicate(true)
