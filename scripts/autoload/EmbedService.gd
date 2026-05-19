## EmbedService.gd
## 文本嵌入服务，负责调用API将文本转换为向量
## AutoLoad 单例

extends Node

signal embedding_completed(embeddings: Array, error: String)
signal embedding_progress(current: int, total: int)

var _current_request: HTTPRequest = null
var _pending_queue: Array = []
var _is_processing := false

func _ready() -> void:
	pass

## 获取API配置
func _get_api_config() -> Dictionary:
	return {
		"api_key": ConfigManager.get_effective_value("embed_api_key"),
		"base_url": ConfigManager.get_effective_value("embed_api_base_url"),
		"model": ConfigManager.get_effective_value("embed_model")
	}

## 检查API是否已配置
func is_configured() -> bool:
	var config := _get_api_config()
	return not config["api_key"].is_empty()

## 将单条文本转换为嵌入向量
## text: String 要嵌入的文本
## on_done: Callable(embeddings: Array, error: String)
func embed_text(text: String, on_done: Callable) -> void:
	if not is_configured():
		on_done.call([], "未配置嵌入API密钥")
		return

	_pend_request([text], on_done)

## 批量将文本转换为嵌入向量
## texts: Array[String] 要嵌入的文本数组
## on_done: Callable(embeddings: Array, error: String)
## on_progress: Callable(current: int, total: int) 可选，进度回调
## embeddings数组顺序与texts数组顺序一致
func embed_batch(texts: Array[String], on_done: Callable, on_progress: Callable = func(_c, _t): pass) -> void:
	if not is_configured():
		on_done.call([], "未配置嵌入API密钥")
		return
	
	if texts.is_empty():
		on_done.call([], "")
		return
	
	const BATCH_SIZE := 16
	
	var total_count := texts.size()
	var total_batches := ceili(float(total_count) / float(BATCH_SIZE))
	var all_embeddings: Array = []
	all_embeddings.resize(total_count)
	
	_process_batch_chunk(texts, 0, BATCH_SIZE, all_embeddings, total_batches, on_progress, on_done)

## 递归处理批次分块
func _process_batch_chunk(texts: Array[String], start_idx: int, batch_size: int, all_embeddings: Array, total_batches: int, on_progress: Callable, final_callback: Callable) -> void:
	var end_idx := mini(start_idx + batch_size, texts.size())
	var chunk := texts.slice(start_idx, end_idx)
	var current_batch := start_idx / batch_size + 1
	
	on_progress.call(current_batch, total_batches)
	
	_send_single_batch_request(chunk, 
		func(embeddings: Array, error: String):
			if not error.is_empty():
				final_callback.call([], error)
				return
			
			for i in range(embeddings.size()):
				all_embeddings[start_idx + i] = embeddings[i]
			
			if end_idx >= texts.size():
				final_callback.call(all_embeddings, "")
			else:
				_process_batch_chunk(texts, end_idx, batch_size, all_embeddings, total_batches, on_progress, final_callback)
	)

## 实际发送单个批次的请求（不经过队列，直接发送）
func _send_single_batch_request(texts: Array[String], on_done: Callable) -> void:
	var config := _get_api_config()
	
	var http_request := HTTPRequest.new()
	add_child(http_request)
	
	http_request.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			_handle_single_response(result, code, body_bytes, on_done)
			http_request.queue_free()
	)
	
	var url = config["base_url"].rstrip("/") + "/embeddings"
	var body := JSON.stringify({
		"model": config["model"],
		"input": texts,
		"encoding_format": "float"
	})
	
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + config["api_key"]
	])
	
	var err = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		on_done.call([], "请求失败: " + str(err))
		http_request.queue_free()

## 处理单个批次响应
func _handle_single_response(result: int, code: int, body_bytes: PackedByteArray, on_done: Callable) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		on_done.call([], "网络请求失败")
		return
	
	if code != 200:
		var error_text := body_bytes.get_string_from_utf8()
		on_done.call([], "API错误: " + str(code) + " - " + error_text)
		return
	
	var json := JSON.new()
	var text := body_bytes.get_string_from_utf8()
	if json.parse(text) != OK:
		on_done.call([], "JSON解析失败")
		return
	
	var data = json.get_data()
	if not data is Dictionary:
		on_done.call([], "响应格式错误")
		return
	
	var embeddings: Array = []
	var raw_embeddings: Array = data.get("data", [])
	# 按 index 排序以确保顺序正确
	raw_embeddings.sort_custom(func(a, b): return a.get("index", 0) < b.get("index", 0))
	
	for item in raw_embeddings:
		if item is Dictionary:
			var embedding: Array = Array(item.get("embedding", []))
			embedding = _normalize_vector(embedding)
			embeddings.append(embedding)
	
	on_done.call(embeddings, "")

## 将请求加入队列
func _pend_request(texts: Array[String], on_done: Callable) -> void:
	_pending_queue.append({"texts": texts, "callback": on_done})
	if not _is_processing:
		_process_next()

## 处理队列中的下一个请求
func _process_next() -> void:
	if _pending_queue.is_empty():
		_is_processing = false
		return

	_is_processing = true
	var request = _pending_queue.pop_front()
	_send_embedding_request(request["texts"], request["callback"])

## 发送嵌入请求
func _send_embedding_request(texts: Array[String], on_done: Callable) -> void:
	var config := _get_api_config()

	if _current_request != null:
		_current_request.queue_free()

	_current_request = HTTPRequest.new()
	add_child(_current_request)
	_current_request.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			_handle_response(result, code, body_bytes, on_done)
	)

	var url = config["base_url"].rstrip("/") + "/embeddings"
	var body := JSON.stringify({
		"model": config["model"],
		"input": texts,
		"encoding_format": "float"
	})

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + config["api_key"]
	])

	var err = _current_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		on_done.call([], "请求失败: " + str(err))

## 处理API响应
func _handle_response(result: int, code: int, body_bytes: PackedByteArray, on_done: Callable) -> void:
	if _current_request != null:
		_current_request.queue_free()
		_current_request = null

	if result != HTTPRequest.RESULT_SUCCESS:
		on_done.call([], "网络请求失败")
		_process_next()
		return

	if code != 200:
		var error_text := body_bytes.get_string_from_utf8()
		on_done.call([], "API错误: " + str(code) + " - " + error_text)
		_process_next()
		return

	var json := JSON.new()
	var text := body_bytes.get_string_from_utf8()
	if json.parse(text) != OK:
		on_done.call([], "JSON解析失败")
		_process_next()
		return

	var data = json.get_data()
	if not data is Dictionary:
		on_done.call([], "响应格式错误")
		_process_next()
		return

	var embeddings: Array = []
	var raw_embeddings: Array = data.get("data", [])
	for item in raw_embeddings:
		if item is Dictionary:
			var embedding: Array = Array(item.get("embedding", []))
			# 归一化向量（用户要求向量均为归一化的）
			embedding = _normalize_vector(embedding)
			embeddings.append(embedding)

	on_done.call(embeddings, "")
	_process_next()

## 归一化向量（将向量除以其模长）
func _normalize_vector(vec: Array) -> Array:
	if vec.is_empty():
		return vec

	var magnitude := 0.0
	for val in vec:
		magnitude += val * val
	magnitude = sqrt(magnitude)

	if magnitude == 0.0:
		return vec

	var normalized: Array = []
	for val in vec:
		normalized.append(val / magnitude)

	return normalized

## 取消当前请求
func cancel() -> void:
	if _current_request != null:
		_current_request.cancel_request()
		_current_request.queue_free()
		_current_request = null
	_pending_queue.clear()
	_is_processing = false