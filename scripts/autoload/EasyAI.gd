## EasyAI.gd
## 通用 AI 工具，使用 option_model 配置，OpenAI 格式，非流式请求
## 用法：EasyAI.ask(system_prompt, user_prompt, callback)
## callback: func(reply: String) -> void，失败时 reply 为空字符串

extends Node

var _busy := false

func _ready() -> void:
	pass

## 发送一次非流式请求
## on_done: Callable(reply: String)
func ask(system_prompt: String, user_prompt: String, on_done: Callable) -> void:
	if _busy:
		on_done.call("")
		return

	var api_key: String = ConfigManager.get_value("option_api_key")
	var base_url: String = ConfigManager.get_value("option_api_base_url")
	var model: String = ConfigManager.get_value("option_model")

	# 如果 option_api_key 未配置
	if api_key.is_empty():
		on_done.call("")
		return

	var url := base_url.rstrip("/") + "/chat/completions"

	var messages := [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt},
	]
	var body := JSON.stringify({
		"model": model,
		"messages": messages,
		"max_tokens": 64,
		"temperature": 0.3,
		"enable_thinking": false,
		"stream": false,
	})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])

	_busy = true
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
		if is_instance_valid(http):
			http.queue_free()
		_busy = false
		var obj = on_done.get_object()
		if obj != null and not is_instance_valid(obj):
			return
		if not on_done.is_valid():
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			on_done.call("")
			return
		var json := JSON.new()
		var text: String = body_bytes.get_string_from_utf8()
		if json.parse(text) != OK:
			on_done.call("")
			return
		var data = json.get_data()
		var reply: String = data.get("choices", [{}])[0].get("message", {}).get("content", "")
		print("[EasyAI]回复："+reply)
		on_done.call(reply.strip_edges())
	)
	http.request_raw(url, headers, HTTPClient.METHOD_POST, body.to_utf8_buffer())
