extends AudioStreamPlayer
## res://scripts/AudioPlayer.gd
## Manages audio playback and playhead synchronization.

signal playback_started
signal playback_stopped
signal playback_paused
signal playhead_time_changed(time: float)

var _playhead_time: float = 0.0
var _play_start_time: float = 0.0
var _audio_offset: float = 0.0
var _is_playing: bool = false
var _is_paused: bool = false

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	pass

func load_audio_file(path: String) -> bool:
	return false

func play_from(time: float, offset: float) -> void:
	pass

func pause_playback() -> void:
	pass

func stop_playback() -> void:
	pass

func get_playhead_time() -> float:
	return _playhead_time

func set_playhead_time(time: float) -> void:
	_playhead_time = time
	playhead_time_changed.emit(time)

func is_playing_audio() -> bool:
	return _is_playing
