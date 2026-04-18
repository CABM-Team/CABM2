## ApiClient.gd
## 封装 HTTP 请求，支持流式和非流式 OpenAI 兼容 API 调用
## AutoLoad 单例

extends Node

signal stream_chunk(text: String)
signal stream_done
signal stream_error(message: String)

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

# ── 流式对话请求 ──────────────────────────────────────────────
# Godot 原生 HTTPRequest 不支持真正的 SSE 流，
# 这里先用非流式请求模拟，后续可替换为 StreamPeerTCP 实现真正流式。
func chat_completion(messages: Array[Dictionary]) -> void:
	var api_key: String = ConfigManager.get_value("chat_api_key")
	var base_url: String = ConfigManager.get_value("chat_api_base_url")
	var model: String = ConfigManager.get_value("chat_model")

	if api_key.is_empty():
		stream_error.emit("未配置 API Key，请先在设置中填写。")
		return

	var url := base_url.rstrip("/") + "/chat/completions"
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	]
	var body := JSON.stringify({
		"model": model,
		"messages": messages,
		"max_tokens": 512,
		"temperature": 0.9,
		"stream": false,  # TODO: 实现真正的 SSE 流式
	})

	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		stream_error.emit("请求发送失败，错误码：%d" % err)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		stream_error.emit("网络请求失败，result=%d" % result)
		return
	if response_code != 200:
		stream_error.emit("API 返回错误，HTTP %d" % response_code)
		return

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		stream_error.emit("响应解析失败")
		return

	var data: Dictionary = json.get_data()
	var content: String = data.get("choices", [{}])[0].get("message", {}).get("content", "")
	if content.is_empty():
		stream_error.emit("响应内容为空")
		return

	# 模拟流式：逐句 emit
	stream_chunk.emit(content)
	stream_done.emit()
