## ApiClient.gd
## 封装流式 HTTP 请求，支持 OpenAI 兼容 SSE 流式 API
## AutoLoad 单例

extends Node

signal stream_chunk(text: String)   # 解析出的 content 片段
signal stream_mood(mood: int)       # 解析出的 mood 值（流中首次出现时 emit）
signal stream_done                  # 流结束
signal stream_error(message: String)

# ── 内部状态 ──────────────────────────────────────────────────
var _http: HTTPClient = null
var _is_streaming := false

# 流式 JSON 解析状态
var _raw_buffer := ""          # 原始 SSE 数据缓冲
var _json_buffer := ""         # 累积的 JSON 字符串
var _in_content := false       # 是否正在读取 content 字段值
var _content_started := false  # content 值的引号是否已开始
var _mood_emitted := false     # mood 是否已 emit
var _escape_next := false      # 上一个字符是否是反斜杠

# HTTP 轮询
var _poll_timer: SceneTreeTimer = null
var _host := ""
var _path := ""
var _port := 443
var _use_ssl := true

func _ready() -> void:
	pass

# ── 公共接口 ──────────────────────────────────────────────────
func chat_completion(messages: Array[Dictionary]) -> void:
	var api_key: String = ConfigManager.get_value("chat_api_key")
	var base_url: String = ConfigManager.get_value("chat_api_base_url")
	var model: String = ConfigManager.get_value("chat_model")

	if api_key.is_empty():
		stream_error.emit("未配置 API Key，请先在设置中填写。")
		return

	if _is_streaming:
		stream_error.emit("上一个请求尚未完成。")
		return

	# 解析 URL
	var url := base_url.rstrip("/") + "/chat/completions"
	var regex := RegEx.new()
	regex.compile("^(https?)://([^/]+)(/.*)$")
	var result := regex.search(url)
	if result == null:
		stream_error.emit("API URL 格式错误：" + url)
		return

	var scheme := result.get_string(1)
	_host = result.get_string(2)
	_path = result.get_string(3)
	_use_ssl = (scheme == "https")
	_port = 443 if _use_ssl else 80

	# 处理自定义端口
	if ":" in _host:
		var parts := _host.split(":")
		_host = parts[0]
		_port = int(parts[1])

	# 构建请求体（JSON 格式要求 AI 返回 JSON）
	var char_data := AppState.current_character
	var moods: Array = char_data.get("moods", [])
	var mood_list := ""
	for i in moods.size():
		mood_list += "%d:%s " % [i, moods[i]]

	var system_prompt_suffix := "\n你必须严格以JSON格式输出，包含以下字段：\n\"mood\": <int> 当前情绪序号，必须是以下之一：%s\n\"content\": <string> 回复内容，1-6句话，禁止换行和markdown\n\"note\": <string> 内心独白（简短）" % mood_list

	# 注入 mood 格式要求到 system 消息
	var patched_messages: Array[Dictionary] = []
	var has_system := false
	for msg in messages:
		if msg["role"] == "system":
			patched_messages.append({"role": "system", "content": msg["content"] + system_prompt_suffix})
			has_system = true
		else:
			patched_messages.append(msg)
	if not has_system:
		patched_messages.insert(0, {"role": "system", "content": system_prompt_suffix})

	var body_dict := {
		"model": model,
		"messages": patched_messages,
		"max_tokens": 512,
		"temperature": 0.9,
		"stream": true,
		"response_format": {"type": "json_object"},
	}
	var body := JSON.stringify(body_dict)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
		"Accept: text/event-stream",
		"Cache-Control: no-cache",
	])

	# 重置解析状态
	_raw_buffer = ""
	_json_buffer = ""
	_in_content = false
	_content_started = false
	_mood_emitted = false
	_escape_next = false
	_is_streaming = true

	# 创建 HTTPClient 并发起请求
	_http = HTTPClient.new()
	var connect_err := _http.connect_to_host(_host, _port, TLSOptions.client() if _use_ssl else null)
	if connect_err != OK:
		_is_streaming = false
		stream_error.emit("连接失败，错误码：%d" % connect_err)
		return

	# 等待连接建立后发送请求
	_start_poll(body, headers)

# ── 轮询连接与读取 ────────────────────────────────────────────
var _pending_body := ""
var _pending_headers: PackedStringArray = []
var _request_sent := false

func _start_poll(body: String, headers: PackedStringArray) -> void:
	_pending_body = body
	_pending_headers = headers
	_request_sent = false
	_schedule_poll()

func _schedule_poll() -> void:
	_poll_timer = get_tree().create_timer(0.016)  # ~60fps
	_poll_timer.timeout.connect(_poll_step, CONNECT_ONE_SHOT)

func _poll_step() -> void:
	if _http == null:
		return

	_http.poll()
	var status := _http.get_status()

	match status:
		HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING:
			_schedule_poll()

		HTTPClient.STATUS_CONNECTED:
			if not _request_sent:
				var err := _http.request(HTTPClient.METHOD_POST, _path, _pending_headers, _pending_body)
				if err != OK:
					_finish_stream()
					stream_error.emit("请求发送失败，错误码：%d" % err)
					return
				_request_sent = true
			_schedule_poll()

		HTTPClient.STATUS_REQUESTING:
			_schedule_poll()

		HTTPClient.STATUS_BODY:
			var code := _http.get_response_code()
			if code != 200:
				_finish_stream()
				stream_error.emit("API 返回错误，HTTP %d" % code)
				return
			_read_body_chunk()

		HTTPClient.STATUS_DISCONNECTED:
			# 连接断开，处理剩余缓冲
			_process_raw_buffer()
			_finish_stream()
			stream_done.emit()

		HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_finish_stream()
			stream_error.emit("连接错误，status=%d" % status)

		_:
			_schedule_poll()

func _read_body_chunk() -> void:
	if _http == null:
		return
	if _http.get_status() != HTTPClient.STATUS_BODY:
		_schedule_poll()
		return

	var chunk := _http.read_response_body_chunk()
	if chunk.size() > 0:
		_raw_buffer += chunk.get_string_from_utf8()
		_process_raw_buffer()

	if _http != null and _http.get_status() == HTTPClient.STATUS_BODY:
		_schedule_poll()
	else:
		_process_raw_buffer()
		_finish_stream()
		stream_done.emit()

# ── SSE 解析 ──────────────────────────────────────────────────
func _process_raw_buffer() -> void:
	# 按行处理 SSE 数据
	while "\n" in _raw_buffer:
		var newline_pos := _raw_buffer.find("\n")
		var line := _raw_buffer.substr(0, newline_pos).strip_edges()
		_raw_buffer = _raw_buffer.substr(newline_pos + 1)

		if line.begins_with("data: "):
			var data := line.substr(6)
			if data == "[DONE]":
				continue
			_parse_sse_data(data)

# ── 流式 JSON 解析（实时提取 content 和 mood）────────────────
# 策略：逐字符扫描累积的 JSON 字符串，定位 "content" 和 "mood" 字段
func _parse_sse_data(data: String) -> void:
	var json := JSON.new()
	if json.parse(data) != OK:
		return

	var obj: Dictionary = json.get_data()
	var choices: Array = obj.get("choices", [])
	if choices.is_empty():
		return

	var delta: Dictionary = choices[0].get("delta", {})
	var token: String = delta.get("content", "")
	if token.is_empty():
		return

	_json_buffer += token
	_extract_from_json_stream()

func _extract_from_json_stream() -> void:
	# 尝试提取 mood（只需一次）
	if not _mood_emitted:
		_try_extract_mood()

	# 实时提取 content 字段的字符
	_try_extract_content()

func _try_extract_mood() -> void:
	# 支持两种格式：
	# "mood": 2          → 直接用下标
	# "mood": "害羞"     → 在 moods 数组中查找对应下标
	var pattern_int := RegEx.new()
	pattern_int.compile('"mood"\\s*:\\s*(\\d+)')
	var result_int := pattern_int.search(_json_buffer)
	if result_int:
		_mood_emitted = true
		stream_mood.emit(int(result_int.get_string(1)))
		return

	var pattern_str := RegEx.new()
	pattern_str.compile('"mood"\\s*:\\s*"([^"]+)"')
	var result_str := pattern_str.search(_json_buffer)
	if result_str:
		var mood_name := result_str.get_string(1)
		var moods: Array = AppState.current_character.get("moods", [])
		var idx := 0
		for i in moods.size():
			if str(moods[i]) == mood_name:
				idx = i
				break
		_mood_emitted = true
		stream_mood.emit(idx)

func _try_extract_content() -> void:
	# 状态机：找到 "content": " 后开始逐字 emit，直到遇到未转义的 "
	var i := 0
	var buf := _json_buffer

	if not _in_content:
		# 寻找 "content": " 的起始位置
		var marker := '"content"'
		var marker_pos := buf.find(marker)
		if marker_pos == -1:
			return
		# 找冒号和引号
		var colon_pos := buf.find(":", marker_pos + marker.length())
		if colon_pos == -1:
			return
		var quote_pos := buf.find('"', colon_pos + 1)
		if quote_pos == -1:
			return
		# content 值从 quote_pos+1 开始
		_in_content = true
		_content_started = true
		i = quote_pos + 1
		# 截断已处理部分，只保留 content 值之后的内容
		_json_buffer = buf.substr(quote_pos + 1)
		buf = _json_buffer
		i = 0
	# 已在 content 值内，逐字符 emit 直到遇到未转义的结束引号
	var emit_str := ""
	while i < buf.length():
		var c := buf[i]
		if _escape_next:
			_escape_next = false
			# 处理转义字符
			match c:
				"n": emit_str += "\n"
				"t": emit_str += "\t"
				"r": emit_str += ""
				_: emit_str += c
			i += 1
			continue
		if c == "\\":
			_escape_next = true
			i += 1
			continue
		if c == '"':
			# content 字段结束
			if not emit_str.is_empty():
				stream_chunk.emit(emit_str)
			_json_buffer = buf.substr(i + 1)
			_in_content = false
			return
		emit_str += c
		i += 1

	if not emit_str.is_empty():
		stream_chunk.emit(emit_str)
	_json_buffer = ""  # 已全部处理，等待更多数据

# ── 清理 ──────────────────────────────────────────────────────
func _finish_stream() -> void:
	_is_streaming = false
	if _http != null:
		_http.close()
		_http = null
