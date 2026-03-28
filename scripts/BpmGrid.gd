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

func grid_interval(time: float, bpm_changes: Array, snap_division: int) -> float:
	var bpm = bpm_at(time, bpm_changes)
	var beat = 60.0 / bpm
	return beat / snap_division

func snap_time(time: float, bpm_changes: Array, snap_division: int) -> float:
	var interval = grid_interval(time, bpm_changes, snap_division)
	if interval <= 0.0:
		return time
	return round(time / interval) * interval

func get_grid_lines(start_time: float, end_time: float, bpm_changes: Array, snap_division: int) -> Array:
	## Returns array of {time, line_type} where line_type is "measure", "beat", or "sub"
	var lines = []
	if bpm_changes.is_empty():
		return lines
	# Walk through BPM sections
	var sorted_changes = bpm_changes.duplicate()
	sorted_changes.sort_custom(func(a, b): return a["time"] < b["time"])
	for i in range(sorted_changes.size()):
		var section_start = sorted_changes[i]["time"]
		var section_end = end_time if i + 1 >= sorted_changes.size() else sorted_changes[i + 1]["time"]
		var bpm = sorted_changes[i]["bpm"]
		var beat = 60.0 / bpm
		var measure = beat * 4.0
		var sub = beat / snap_division
		# Start from first grid point >= max(start_time, section_start)
		var t_start = max(start_time, section_start)
		# Align to measure grid from section_start
		var beat_num = ceil((t_start - section_start) / sub)
		var t = section_start + beat_num * sub
		var section_end_clamped = min(section_end, end_time)
		while t <= section_end_clamped + 0.0001:
			if t >= start_time - 0.0001:
				var rel = t - section_start
				var line_type = "sub"
				if abs(fmod(rel + 0.0001, measure) - 0.0001) < 0.001:
					line_type = "measure"
				elif abs(fmod(rel + 0.0001, beat) - 0.0001) < 0.001:
					line_type = "beat"
				lines.append({"time": t, "line_type": line_type})
			t += sub
	return lines
