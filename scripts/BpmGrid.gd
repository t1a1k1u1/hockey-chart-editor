extends RefCounted
## res://scripts/BpmGrid.gd
## Calculates BPM grid positions and snap values.

func bpm_at(time: float, bpm_changes: Array) -> float:
	if bpm_changes.is_empty():
		return 120.0
	var current_bpm = bpm_changes[0]["bpm"]
	for change in bpm_changes:
		if change["time"] <= time:
			current_bpm = change["bpm"]
		else:
			break
	return current_bpm

func _time_sig_at(time: float, time_sig_changes: Array) -> Array:
	## Returns [numerator, denominator]
	var num = 4
	var den = 4
	for tc in time_sig_changes:
		if tc["time"] <= time:
			num = tc.get("numerator", 4)
			den = tc.get("denominator", 4)
		else:
			break
	return [num, den]

func _merged_boundaries(bpm_changes: Array, time_sig_changes: Array) -> Array:
	var set: Dictionary = {}
	for bc in bpm_changes:
		set[bc["time"]] = true
	for tc in time_sig_changes:
		set[tc["time"]] = true
	var boundaries = set.keys()
	boundaries.sort()
	return boundaries

func grid_interval(time: float, bpm_changes: Array, snap_division: int) -> float:
	var bpm = bpm_at(time, bpm_changes)
	var beat = 60.0 / bpm
	return beat * 4.0 / snap_division

func snap_time(time: float, bpm_changes: Array, snap_division: int, time_sig_changes: Array = []) -> float:
	var boundaries = _merged_boundaries(bpm_changes, time_sig_changes)
	if boundaries.is_empty():
		var interval = 60.0 / 120.0 * 4.0 / snap_division
		if interval <= 0.0:
			return time
		return round(time / interval) * interval

	var section_start: float = boundaries[0]
	var section_bpm: float = bpm_at(boundaries[0], bpm_changes)
	for b in boundaries:
		if b <= time:
			section_start = b
			section_bpm = bpm_at(b, bpm_changes)
		else:
			break

	var sub = 60.0 / section_bpm * 4.0 / snap_division
	if sub <= 0.0:
		return time
	return section_start + round((time - section_start) / sub) * sub

func get_grid_lines(start_time: float, end_time: float, bpm_changes: Array, snap_division: int, time_sig_changes: Array = []) -> Array:
	## Returns array of {time, line_type} where line_type is "measure", "beat", or "sub"
	var lines = []
	if bpm_changes.is_empty():
		return lines

	var boundaries = _merged_boundaries(bpm_changes, time_sig_changes)
	if boundaries.is_empty():
		return lines

	for i in range(boundaries.size()):
		var section_start = boundaries[i]
		var section_end = end_time if i + 1 >= boundaries.size() else boundaries[i + 1]

		var bpm = bpm_at(section_start, bpm_changes)
		var ts = _time_sig_at(section_start, time_sig_changes)
		var numerator = ts[0]
		var denominator = ts[1]

		var beat = 60.0 / bpm
		var note_dur = beat * 4.0 / denominator  # duration of one denominator note
		var measure = note_dur * numerator        # duration of one full measure
		var sub = beat * 4.0 / snap_division      # snap subdivision (quarter-note based)

		if sub <= 0.0 or measure <= 0.0:
			continue

		# Start from first grid point >= max(start_time, section_start)
		var t_start = max(start_time, section_start)
		var beat_num = ceil((t_start - section_start) / sub)
		var t = section_start + beat_num * sub
		var section_end_clamped = min(section_end, end_time)

		while t <= section_end_clamped + 0.0001:
			if t >= start_time - 0.0001:
				var rel = t - section_start
				var line_type = "sub"
				if abs(fmod(rel + 0.0001, measure) - 0.0001) < 0.001:
					line_type = "measure"
				elif abs(fmod(rel + 0.0001, note_dur) - 0.0001) < 0.001:
					line_type = "beat"
				lines.append({"time": t, "line_type": line_type})
			t += sub
	return lines
