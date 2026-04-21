# TTSManager.gd
## TTS 语音合成管理器
## - 以角色ID+文本哈希缓存音频到 user://speech_cache/
## - 调用 /v1/audio/speech 接口（URL 和模型从 ConfigManager 读取）
## AutoLoad 单例

extends Node

const CACHE_DIR := "user://speech_cache"

# 文本注入规则：格式为 { "原文本": "替换文本" }
var text_injection_rules: Dictionary = {
	"希儿": "希而",
	"琪亚娜":"Kiyana",
	"布洛妮娅":"Bronya",
	"安柏":"安博"
}

signal tts_done(audio_path: String)
signal tts_error(message: String)

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_absolute(CACHE_DIR)

# ── 公共接口 ──────────────────────────────────────────────────
## 请求 TTS，优先读缓存，完成后通过信号返回本地音频路径
## character_id: 角色 ID
## character_name: 角色名（用于 voice 参数）
## text: 要合成的文本
func request(character_id: String, character_name: String, text: String) -> void:
	var cache_path := _cache_path(character_id, text)
	if FileAccess.file_exists(cache_path):
		print("[TTS缓存命中]"+text)
		tts_done.emit(cache_path)
		return
	print("[TTS合成]"+text)
	_synthesize(character_id, character_name, text, cache_path)

## 同步检查缓存是否存在
func has_cache(character_id: String, text: String) -> bool:
	return FileAccess.file_exists(_cache_path(character_id, text))

# ── 缓存路径 ──────────────────────────────────────────────────
func _cache_path(character_id: String, text: String) -> String:
	var key := character_id + "|" + text
	var hash_str := str(hash(key)).replace("-", "n")
	return "%s/%s_%s.mp3" % [CACHE_DIR, character_id, hash_str]

# ── 文本注入处理 ──────────────────────────────────────────────
## 对文本应用注入规则，返回处理后的文本
func _apply_text_injection(original_text: String) -> String:
	var processed_text := original_text
	for original_word in text_injection_rules.keys():
		processed_text = processed_text.replace(original_word, text_injection_rules[original_word])
	return processed_text

# ── 合成请求 ──────────────────────────────────────────────────
func _synthesize(character_id: String, character_name: String, text: String, cache_path: String) -> void:
	var api_key: String = ConfigManager.get_value("tts_api_key")
	if api_key.is_empty():
		api_key = ConfigManager.get_value("chat_api_key")
	if api_key.is_empty():
		tts_error.emit("未配置 TTS API Key")
		return

	var model: String = ConfigManager.get_value("tts_model")

	# 优先使用已上传的参考音频 URI，否则用模型默认音色
	var voice_uri := VoiceUploadManager.get_cached_uri(character_id)
	var voice: String
	if not voice_uri.is_empty():
		voice = voice_uri
	else:
		voice = model + ":" + character_name.to_lower().replace(" ", "_")

	# 应用文本注入规则（不影响原始 text 用于缓存）
	var injected_text := _apply_text_injection(text)

	var body := JSON.stringify({
		"model": model,
		"input": injected_text,  # 使用注入后的文本
		"voice": voice,
		"response_format": "mp3",
		"stream": true,
	})

	var http := HTTPRequest.new()
	add_child(http)

	var on_complete := func(result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			tts_error.emit("TTS 请求失败，result=%d" % result)
			return
		if response_code != 200:
			tts_error.emit("TTS 返回 HTTP %d" % response_code)
			return
		if response_body.is_empty():
			tts_error.emit("TTS 返回空数据")
			return
		# 写入缓存
		var f := FileAccess.open(cache_path, FileAccess.WRITE)
		if f == null:
			tts_error.emit("无法写入缓存文件")
			return
		f.store_buffer(response_body)
		f.close()
		tts_done.emit(cache_path)

	http.request_completed.connect(on_complete, CONNECT_ONE_SHOT)

	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json",
	])
	var tts_url: String = ConfigManager.get_value("tts_api_base_url").rstrip("/") + "/audio/speech"
	var err := http.request(tts_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		tts_error.emit("发起 TTS 请求失败，错误码：%d" % err)
