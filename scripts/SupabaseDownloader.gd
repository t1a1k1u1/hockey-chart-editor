extends Node
## res://scripts/SupabaseDownloader.gd
## Fetches song list and downloads files from Supabase Storage for the chart editor.

signal song_list_loaded(songs: Array)   # [{song_id, title, artist, level, bpm, audio, chart_data}]
signal audio_downloaded(song_id: String, local_path: String)
signal fetch_failed(error: String)

var _url: String
var _anon_key: String
var _bucket: String
var _pending_charts: int = 0
var _chart_results: Array = []
var _song_ids: Array = []

func fetch_song_list(url: String, anon_key: String, bucket: String) -> void:
	_url = url
	_anon_key = anon_key
	_bucket = bucket
	var list_url = url + "/storage/v1/object/list/" + bucket
	var headers = [
		"Authorization: Bearer " + anon_key,
		"Content-Type: application/json"
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_list_response.bind(http))
	http.request(list_url, headers, HTTPClient.METHOD_POST, '{"prefix":"","limit":1000,"offset":0}')

func _on_list_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		fetch_failed.emit("曲一覧の取得に失敗しました: HTTP " + str(code))
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Array:
		song_list_loaded.emit([])
		return
	var folders: Array = []
	for item in parsed:
		if item is Dictionary and item.get("id") == null:
			folders.append(item.get("name", ""))
	if folders.is_empty():
		song_list_loaded.emit([])
		return
	_song_ids = folders.duplicate()
	_chart_results.clear()
	_chart_results.resize(folders.size())
	_pending_charts = folders.size()
	for i in range(folders.size()):
		var chart_url = _url + "/storage/v1/object/authenticated/" + _bucket + "/" + folders[i] + "/chart.json"
		var http2 = HTTPRequest.new()
		add_child(http2)
		http2.request_completed.connect(_on_chart_response.bind(http2, i))
		http2.request(chart_url, PackedStringArray(["Authorization: Bearer " + _anon_key]), HTTPClient.METHOD_GET, "")

func _on_chart_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, index: int) -> void:
	http.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		_chart_results[index] = parsed if parsed is Dictionary else null
	else:
		_chart_results[index] = null
	_pending_charts -= 1
	if _pending_charts == 0:
		_build_and_emit()

func _build_and_emit() -> void:
	var songs: Array = []
	for i in range(_song_ids.size()):
		var sid: String = _song_ids[i]
		var cd = _chart_results[i]
		var meta: Dictionary = cd.get("meta", {}) if cd is Dictionary else {}
		songs.append({
			"song_id": sid,
			"title": meta.get("title", sid),
			"artist": meta.get("artist", ""),
			"level": meta.get("level", 1),
			"bpm": meta.get("bpm", 120.0),
			"audio": meta.get("audio", "music.ogg"),
			"chart_data": cd if cd is Dictionary else {}
		})
	song_list_loaded.emit(songs)

func download_audio(url: String, anon_key: String, bucket: String, song_id: String, audio_filename: String) -> void:
	var cache_dir = "user://editor_cache/" + song_id
	var cache_path = cache_dir + "/" + audio_filename
	DirAccess.make_dir_recursive_absolute(cache_dir)
	if FileAccess.file_exists(cache_path):
		audio_downloaded.emit(song_id, cache_path)
		return
	var dl_url = url + "/storage/v1/object/authenticated/" + bucket + "/" + song_id + "/" + audio_filename
	var http = HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(_on_audio_response.bind(http, cache_path, song_id))
	http.request(dl_url, PackedStringArray(["Authorization: Bearer " + anon_key]), HTTPClient.METHOD_GET, "")

func _on_audio_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, cache_path: String, song_id: String) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		fetch_failed.emit("音楽ファイルのダウンロードに失敗しました: HTTP " + str(code))
		return
	var f = FileAccess.open(cache_path, FileAccess.WRITE)
	if f:
		f.store_buffer(body)
		f.close()
	audio_downloaded.emit(song_id, cache_path)
