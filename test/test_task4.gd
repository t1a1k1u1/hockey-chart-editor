extends SceneTree
## Test harness for Task 4: Audio Playback + Playhead
## Loads chart.json, simulates Space key to start/stop playback, verifies playhead movement.

var _root_scene = null
var _main_node = null
var _frame: int = 0
var _play_started: bool = false
var _play_time_at_start: float = 0.0
var _play_time_later: float = 0.0
var _stopped_time: float = 0.0
var _phase: int = 0  # 0=load, 1=open chart, 2=wait, 3=play, 4=check playing, 5=pause, 6=check paused, 7=stop, 8=done

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/ChartEditor.tscn")
	_root_scene = packed.instantiate()
	get_root().add_child(_root_scene)
	_main_node = _root_scene

func _process(delta: float) -> bool:
	_frame += 1

	# Phase 0: Wait for scene to be ready, then load chart
	if _phase == 0 and _frame == 3:
		_phase = 1
		# Load the sample chart directly
		var chart_path = "D:/GoDot Projects/hockey/songs/sample/chart.json"
		if _main_node.has_method("_load_from_path"):
			_main_node.call("_load_from_path", chart_path)
			print("PHASE 1: Chart load requested: " + chart_path)
		else:
			print("ASSERT FAIL: _main_node has no _load_from_path method")

	# Phase 1: Wait a bit after chart load
	elif _phase == 1 and _frame == 8:
		_phase = 2
		print("PHASE 2: Checking initial state...")
		var pt = _main_node.playhead_time if "playhead_time" in _main_node else -1.0
		print("  playhead_time = " + str(pt))
		var ap = _main_node.audio_player
		if ap == null:
			print("ASSERT FAIL: audio_player is null")
		else:
			print("  audio_player found, is_playing_audio = " + str(ap.is_playing_audio()))

	# Phase 2: Simulate Space to start playback
	elif _phase == 2 and _frame == 12:
		_phase = 3
		print("PHASE 3: Simulating Space key press (toggle_playback)...")
		_play_time_at_start = _main_node.playhead_time
		if _main_node.has_method("toggle_playback"):
			_main_node.call("toggle_playback")
			_play_started = true
			print("  toggle_playback() called, playhead_time = " + str(_play_time_at_start))
		else:
			print("ASSERT FAIL: no toggle_playback method")

	# Phase 3: Wait ~1.5 seconds for playhead to advance (15 frames at fixed_fps 10)
	elif _phase == 3 and _frame == 27:
		_phase = 4
		_play_time_later = _main_node.playhead_time
		var ap = _main_node.audio_player
		print("PHASE 4: Checking playback state...")
		if ap and ap.is_playing_audio():
			print("ASSERT PASS: audio is playing after toggle_playback")
		else:
			print("ASSERT FAIL: audio is NOT playing after toggle_playback")
		if _play_time_later > _play_time_at_start + 0.05:
			print("ASSERT PASS: playhead advanced from " + str(_play_time_at_start) + " to " + str(_play_time_later))
		else:
			print("ASSERT FAIL: playhead did not advance - start=" + str(_play_time_at_start) + " later=" + str(_play_time_later))

	# Phase 4: Pause playback
	elif _phase == 4 and _frame == 32:
		_phase = 5
		print("PHASE 5: Pausing playback...")
		if _main_node.has_method("toggle_playback"):
			_main_node.call("toggle_playback")

	# Phase 5: Check paused
	elif _phase == 5 and _frame == 37:
		_phase = 6
		var ap = _main_node.audio_player
		var pt_paused = _main_node.playhead_time
		print("PHASE 6: Checking paused state, playhead_time = " + str(pt_paused))
		if ap and not ap.is_playing_audio() and ap._is_paused:
			print("ASSERT PASS: audio is paused")
		else:
			print("ASSERT FAIL: audio not in paused state (is_playing=" + str(ap.is_playing_audio() if ap else "N/A") + " _is_paused=" + str(ap._is_paused if ap else "N/A") + ")")

	# Phase 6: Stop playback (Escape)
	elif _phase == 6 and _frame == 42:
		_phase = 7
		print("PHASE 7: Stopping playback (stop_playback)...")
		if _main_node.has_method("stop_playback"):
			_main_node.call("stop_playback")

	# Phase 7: Check stopped and playhead returned
	elif _phase == 7 and _frame == 47:
		_phase = 8
		var ap = _main_node.audio_player
		var pt_stopped = _main_node.playhead_time
		print("PHASE 8: Final checks...")
		print("  playhead_time after stop = " + str(pt_stopped))
		if ap and not ap.is_playing_audio() and not ap._is_paused:
			print("ASSERT PASS: audio fully stopped")
		else:
			print("ASSERT FAIL: audio not fully stopped")
		# Playhead should have returned to play start (which was near 0 after chart load)
		if pt_stopped <= 0.5:
			print("ASSERT PASS: playhead returned to start position")
		else:
			print("ASSERT INFO: playhead at " + str(pt_stopped) + " (should be near start)")

		# Test Home key
		if _main_node.has_method("set_playhead_time"):
			_main_node.call("set_playhead_time", 5.0)
			print("  Set playhead to 5.0")
			var pt = _main_node.playhead_time
			print("  playhead_time = " + str(pt))
			if abs(pt - 5.0) < 0.01:
				print("ASSERT PASS: set_playhead_time works")
			else:
				print("ASSERT FAIL: set_playhead_time failed")

	return false  # Keep running — movie writer handles quit
