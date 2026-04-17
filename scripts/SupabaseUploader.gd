extends Node
## res://scripts/SupabaseUploader.gd
## Uploads chart.json (and optionally a music file) to Supabase Storage.

signal upload_progress(step: int, total: int, msg: String)
signal upload_complete()
signal upload_failed(error: String)

var _url: String
var _anon_key: String
var _bucket: String
var _song_id: String
var _chart_json: String
var _music_path: String
var _audio_filename: String
var _total_steps: int
var _current_step: int = 0

func upload(url: String, anon_key: String, bucket: String, song_id: String,
		chart_json_text: String, music_local_path: String, audio_filename: String) -> void:
	_url = url
	_anon_key = anon_key
	_bucket = bucket
	_song_id = song_id
	_chart_json = chart_json_text
	_music_path = music_local_path
	_audio_filename = audio_filename
	if music_local_path != "" and FileAccess.file_exists(music_local_path):
		_total_steps = 2
	else:
		_total_steps = 1
	_upload_chart()

func _upload_chart() -> void:
	_current_step += 1
	upload_progress.emit(_current_step, _total_steps, "chart.json をアップロード中...")
	var http = HTTPRequest.new()
	add_child(http)
	var storage_url = _url + "/storage/v1/object/" + _bucket + "/" + _song_id + "/chart.json"
	var headers = [
		"Authorization: Bearer " + _anon_key,
		"x-upsert: true",
		"Content-Type: application/json"
	]
	var body_bytes = _chart_json.to_utf8_buffer()
	http.request_completed.connect(_on_chart_uploaded.bind(http))
	var err = http.request_raw(storage_url, headers, HTTPClient.METHOD_POST, body_bytes)
	if err != OK:
		http.queue_free()
		upload_failed.emit("chart.json upload request failed: " + str(err))

func _on_chart_uploaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if code not in [200, 201]:
		upload_failed.emit("chart.json upload failed: " + str(code))
		return
	if _total_steps > 1:
		_upload_music()
	else:
		upload_complete.emit()

func _upload_music() -> void:
	_current_step += 1
	upload_progress.emit(_current_step, _total_steps, _audio_filename + " をアップロード中...")
	var f = FileAccess.open(_music_path, FileAccess.READ)
	if f == null:
		upload_failed.emit("Failed to read music file: " + _music_path)
		return
	var buf = f.get_buffer(f.get_length())
	f.close()

	var ext = _audio_filename.get_extension().to_lower()
	var content_type: String
	match ext:
		"ogg":
			content_type = "audio/ogg"
		"wav":
			content_type = "audio/wav"
		"mp3":
			content_type = "audio/mpeg"
		_:
			content_type = "application/octet-stream"

	var http = HTTPRequest.new()
	add_child(http)
	var storage_url = _url + "/storage/v1/object/" + _bucket + "/" + _song_id + "/" + _audio_filename
	var headers = [
		"Authorization: Bearer " + _anon_key,
		"x-upsert: true",
		"Content-Type: " + content_type
	]
	http.request_completed.connect(_on_music_uploaded.bind(http))
	var err = http.request_raw(storage_url, headers, HTTPClient.METHOD_POST, buf)
	if err != OK:
		http.queue_free()
		upload_failed.emit(_audio_filename + " upload request failed: " + str(err))

func _on_music_uploaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if code not in [200, 201]:
		upload_failed.emit(_audio_filename + " upload failed: " + str(code))
		return
	upload_complete.emit()
