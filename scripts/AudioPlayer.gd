extends AudioStreamPlayer
## res://scripts/AudioPlayer.gd
## Manages audio playback and playhead synchronization.

signal playback_started
signal playback_stopped
signal playback_paused
signal playhead_time_changed(time: float)

var _playhead_time: float = 0.0
var _play_start_playhead: float = 0.0  # playhead_time at the moment play started
var _play_start_wall: float = 0.0      # Time.get_ticks_msec() at the moment play started
var _audio_offset: float = 0.0         # meta.offset in seconds
var _is_playing: bool = false
var _is_paused: bool = false
var _pause_position: float = 0.0       # playhead time at pause
var _audio_started: bool = false       # whether AudioStreamPlayer.play() has been called

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	if _is_playing:
		var t = get_playhead_time()
		playhead_time_changed.emit(t)
		if stream != null:
			if not _audio_started:
				# Wait until chart time reaches the audio start point
				var audio_pos = t - _audio_offset
				if audio_pos >= 0.0:
					play(audio_pos)
					_audio_started = true
			elif not is_playing():
				# AudioStreamPlayer finished naturally
				stop_playback()

func load_audio_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("AudioPlayer: file not found: " + path)
		return false
	var ext = path.get_extension().to_lower()
	if ext == "ogg":
		var s = AudioStreamOggVorbis.load_from_file(path)
		if s == null:
			push_warning("AudioPlayer: failed to load ogg: " + path)
			return false
		stream = s
		return true
	elif ext == "wav":
		var s = AudioStreamWAV.load_from_file(path)
		if s == null:
			push_warning("AudioPlayer: failed to load wav: " + path)
			return false
		stream = s
		return true
	else:
		push_warning("AudioPlayer: unsupported audio format: " + ext)
		return false

func play_from(time: float, audio_offset: float) -> void:
	_play_start_playhead = time
	_audio_offset = audio_offset
	_play_start_wall = Time.get_ticks_msec()
	_is_playing = true
	_is_paused = false
	_audio_started = false

	if stream != null:
		var audio_pos = time - audio_offset
		if audio_pos >= 0.0:
			play(audio_pos)
			_audio_started = true
		# else: audio hasn't started yet; _process will call play() when ready

	playback_started.emit()

func pause_playback() -> void:
	_pause_position = get_playhead_time()
	stop()  # AudioStreamPlayer stop
	_is_playing = false
	_is_paused = true
	playback_paused.emit()

func stop_playback() -> void:
	stop()  # AudioStreamPlayer stop
	_is_playing = false
	_is_paused = false
	playback_stopped.emit()

func get_playhead_time() -> float:
	if _is_playing:
		return _play_start_playhead + (Time.get_ticks_msec() - _play_start_wall) / 1000.0
	elif _is_paused:
		return _pause_position
	else:
		return _playhead_time

func set_playhead_time(time: float) -> void:
	_playhead_time = time
	playhead_time_changed.emit(time)

func is_playing_audio() -> bool:
	return _is_playing
