## StreamParser.gd
## 解析 AI 响应文本，按暂停标记分句，提取情绪标签

class_name StreamParser
extends Node

# 触发分句的标点
const PAUSE_MARKERS := ["。", "！", "？", "!", "?", "…", "♪", "~", ".", "..."]

signal sentence_ready(sentence: String)
signal mood_detected(mood: String)
signal parse_complete

var _buffer := ""

func feed(text: String) -> void:
	# 尝试解析 JSON 格式响应 {"content":"...","mood":"..."}
	var json := JSON.new()
	if json.parse(text) == OK:
		var data: Dictionary = json.get_data()
		if data.has("mood"):
			mood_detected.emit(data["mood"])
		text = data.get("content", text)

	_buffer += text
	_flush_sentences()

func _flush_sentences() -> void:
	for marker in PAUSE_MARKERS:
		var idx := _buffer.find(marker)
		while idx != -1:
			var sentence := _buffer.substr(0, idx + marker.length()).strip_edges()
			if not sentence.is_empty():
				sentence_ready.emit(sentence)
			_buffer = _buffer.substr(idx + marker.length())
			idx = _buffer.find(marker)

func finish() -> void:
	if not _buffer.strip_edges().is_empty():
		sentence_ready.emit(_buffer.strip_edges())
	_buffer = ""
	parse_complete.emit()

func reset() -> void:
	_buffer = ""
