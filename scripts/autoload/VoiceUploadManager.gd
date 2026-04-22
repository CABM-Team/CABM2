## VoiceUploadManager.gd
## 管理角色参考音频上传到 SiliconFlow TTS API
## 缓存 voice URI 到 user://voice_url.json
## AutoLoad 单例

extends Node

const CACHE_PATH := "user://voice_url.json"

# { character_id: "speech:xxx:xxx:xxx" }
var _cache: Dictionary = {}

func _ready() -> void:
	_load_cache()

# ── 缓存读写 ──────────────────────────────────────────────────
func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK:
		var data = json.get_data()
		if data is Dictionary:
			_cache = data

func _save_cache() -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_cache))

## 获取角色已缓存的 voice URI，没有则返回空字符串
func get_cached_uri(character_id: String) -> String:
	return _cache.get(character_id, "")

## 确保角色的参考音频已上传，返回 voice URI（通过回调）
## callback: func(uri: String, error: String)
##   uri 非空表示成功，error 非空表示失败
func ensure_voice_uploaded(character_id: String, callback: Callable) -> void:
	# 已有缓存直接返回
	var cached := get_cached_uri(character_id)
	if not cached.is_empty():
		callback.call(cached, "")
		return

	# 查找参考音频文件
	var audio_path := _find_ref_audio(character_id)
	if audio_path.is_empty():
		callback.call("", "未找到参考音频（ref.wav/mp3/ogg）")
		return

	# 读取参考文本
	var ref_text := _read_ref_text(character_id)
	if ref_text.is_empty():
		ref_text = "这是参考音频"

	# 读取音频文件数据
	var audio_data := _read_file_bytes(audio_path)
	if audio_data.is_empty():
		callback.call("", "无法读取参考音频文件")
		return

	var api_key: String = ConfigManager.get_effective_value("tts_api_key")
	if api_key.is_empty():
		api_key = ConfigManager.get_effective_value("chat_api_key")
	if api_key.is_empty():
		callback.call("", "未配置 TTS API Key")
		return

	_upload_audio(character_id, audio_path, audio_data, ref_text, api_key, callback)

# ── URL 构建 ──────────────────────────────────────────────────
func _upload_url() -> String:
	var base: String = ConfigManager.get_effective_value("tts_api_base_url")
	return base.rstrip("/") + "/uploads/audio/voice"

# ── 文件查找 ──────────────────────────────────────────────────
func _find_ref_audio(character_id: String) -> String:
	var exts := ["wav", "mp3", "ogg"]
	for base in ["user://characters/", "res://characters/"]:
		for ext in exts:
			var p := "%s%s/ref.%s" % [base, character_id, ext]
			if FileAccess.file_exists(p):
				return p
	return ""

func _read_ref_text(character_id: String) -> String:
	for base in ["user://characters/", "res://characters/"]:
		var p := "%s%s/ref.txt" % [base, character_id]
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f:
				return f.get_as_text().strip_edges()
	return ""

func _read_file_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	return f.get_buffer(f.get_length())

# ── HTTP 上传（multipart/form-data）──────────────────────────
func _upload_audio(
	character_id: String,
	audio_path: String,
	audio_data: PackedByteArray,
	ref_text: String,
	api_key: String,
	callback: Callable
) -> void:
	var http := HTTPRequest.new()
	add_child(http)

	var model: String = ConfigManager.get_effective_value("tts_model")
	var boundary := "----GodotBoundary%d" % randi()
	var filename := audio_path.get_file()
	var mime := _get_mime(filename)

	# 构建 multipart body
	var body := PackedByteArray()
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="file"; filename="%s"\r\n' % filename).to_utf8_buffer())
	body.append_array(("Content-Type: %s\r\n\r\n" % mime).to_utf8_buffer())
	body.append_array(audio_data)
	body.append_array(("\r\n--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="model"\r\n\r\n').to_utf8_buffer())
	body.append_array((model + "\r\n").to_utf8_buffer())
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="customName"\r\n\r\n').to_utf8_buffer())
	body.append_array((character_id + "\r\n").to_utf8_buffer())
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="text"\r\n\r\n').to_utf8_buffer())
	body.append_array((ref_text + "\r\n").to_utf8_buffer())
	body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())

	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: multipart/form-data; boundary=" + boundary,
	])

	var on_complete := func(result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			callback.call("", "上传请求失败，result=%d" % result)
			return
		if response_code != 200:
			var body_str := response_body.get_string_from_utf8()
			callback.call("", "上传失败 HTTP %d: %s" % [response_code, body_str])
			return
		var json := JSON.new()
		if json.parse(response_body.get_string_from_utf8()) != OK:
			callback.call("", "解析上传响应失败")
			return
		var data = json.get_data()
		var uri: String = data.get("uri", "")
		if uri.is_empty():
			callback.call("", "响应中无 uri 字段")
			return
		_cache[character_id] = uri
		_save_cache()
		callback.call(uri, "")
	http.request_completed.connect(on_complete, CONNECT_ONE_SHOT)

	var err := http.request_raw(_upload_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		callback.call("", "发起上传请求失败，错误码：%d" % err)

func _get_mime(filename: String) -> String:
	var ext := filename.get_extension().to_lower()
	match ext:
		"mp3": return "audio/mpeg"
		"ogg": return "audio/ogg"
		_: return "audio/wav"
