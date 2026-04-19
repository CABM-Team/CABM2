## HistoryManager.gd
## 历史记录管理器，负责保存和加载对话历史到磁盘
## 单角色存储路径：user://saves/<character_id>.json
## 群聊存储路径：user://groups/<group_id>.json（与群聊配置共用同一文件）
## 文件格式：{ "history": [...], "last_play_time": <unix_timestamp>, ...其他群聊字段 }
## AutoLoad 单例

extends Node

const SAVES_DIR := "user://saves/"
const GROUPS_DIR := "user://groups/"

## 保存群聊历史到 groups/<group_id>.json，保留其他字段
## displayed_char_ids: 当前屏幕上角色 id 列表（顺序对应左右位置）
## active_speaker_id: 当前高亮发言角色 id
## last_moods: { char_id: mood_index } 各角色最后表情
func save_group_history(group_id: String, messages: Array[Dictionary],
		displayed_char_ids: Array = [], active_speaker_id: String = "",
		last_moods: Dictionary = {}) -> void:
	if group_id.is_empty():
		push_warning("HistoryManager: group_id 为空，无法保存群聊历史")
		return
	if not DirAccess.dir_exists_absolute(GROUPS_DIR):
		DirAccess.make_dir_recursive_absolute(GROUPS_DIR)
	var path := GROUPS_DIR + group_id + ".json"
	# 读取现有数据，保留群聊配置字段
	var existing := _load_json_file(path)
	# 过滤掉 system 消息
	var filtered: Array = []
	for msg in messages:
		if msg.get("role", "") != "system":
			filtered.append(msg)
	existing["history"] = filtered
	existing["last_play_time"] = int(Time.get_unix_time_from_system())
	existing["displayed_char_ids"] = displayed_char_ids
	existing["active_speaker_id"] = active_speaker_id
	existing["last_moods"] = last_moods
	_write_json_file(path, existing)

## 加载群聊历史，返回 { "history": [...], "displayed_char_ids": [...], "active_speaker_id": "", "last_moods": {} }
func load_group_history(group_id: String) -> Dictionary:
	if group_id.is_empty():
		return {"history": [], "displayed_char_ids": [], "active_speaker_id": "", "last_moods": {}}
	var path := GROUPS_DIR + group_id + ".json"
	var data := _load_json_file(path)
	var history = data.get("history", [])
	var messages: Array[Dictionary] = []
	for item in history:
		if item is Dictionary and item.has("role") and item.has("content"):
			messages.append(item)
	var moods = data.get("last_moods", {})
	if not moods is Dictionary:
		moods = {}
	return {
		"history": messages,
		"displayed_char_ids": data.get("displayed_char_ids", []),
		"active_speaker_id": data.get("active_speaker_id", ""),
		"last_moods": moods
	}

## 清空群聊历史（仅清空 history/状态字段，保留其他字段）
func clear_group_history(group_id: String) -> void:
	if group_id.is_empty():
		return
	var path := GROUPS_DIR + group_id + ".json"
	var existing := _load_json_file(path)
	existing["history"] = []
	existing["last_play_time"] = int(Time.get_unix_time_from_system())
	existing["displayed_char_ids"] = []
	existing["active_speaker_id"] = ""
	existing["last_moods"] = {}
	_write_json_file(path, existing)

## 获取群聊最后游玩时间
func get_group_last_play_time(group_id: String) -> int:
	if group_id.is_empty():
		return 0
	var path := GROUPS_DIR + group_id + ".json"
	var data := _load_json_file(path)
	return int(data.get("last_play_time", 0))

## 保存指定角色的对话历史，可附带最后表情索引
func save_history(character_id: String, messages: Array[Dictionary], last_mood: int = 0) -> void:
	if character_id.is_empty():
		push_warning("HistoryManager: character_id 为空，无法保存历史")
		return

	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_recursive_absolute(SAVES_DIR)

	# 过滤掉 system 消息
	var filtered: Array = []
	for msg in messages:
		if msg.get("role", "") != "system":
			filtered.append(msg)

	var file_path := SAVES_DIR + _sanitize_filename(character_id) + ".json"
	var existing := _load_json_file(file_path)
	existing["history"] = filtered
	existing["last_play_time"] = int(Time.get_unix_time_from_system())
	existing["last_mood"] = last_mood
	_write_json_file(file_path, existing)

## 加载指定角色的对话历史，返回 { "history": [...], "last_mood": int }
func load_history(character_id: String) -> Dictionary:
	if character_id.is_empty():
		push_warning("HistoryManager: character_id 为空，无法加载历史")
		return {"history": [], "last_mood": 0}

	var file_path := SAVES_DIR + _sanitize_filename(character_id) + ".json"
	var data := _load_json_file(file_path)

	var history = data.get("history", [])
	var messages: Array[Dictionary] = []
	for item in history:
		if item is Dictionary and item.has("role") and item.has("content"):
			messages.append(item)
	return {"history": messages, "last_mood": int(data.get("last_mood", 0))}

## 获取最后游玩时间（unix 时间戳），不存在返回 0
func get_last_play_time(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	var file_path := SAVES_DIR + _sanitize_filename(character_id) + ".json"
	if not FileAccess.file_exists(file_path):
		return 0
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return 0
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return 0
	file.close()
	var data = json.get_data()
	if data is Dictionary:
		return int(data.get("last_play_time", 0))
	return 0

## 清空指定角色的对话历史（仅清空 history/last_mood 字段，保留文件）
func delete_history(character_id: String) -> bool:
	if character_id.is_empty():
		push_warning("HistoryManager: character_id 为空，无法清空历史")
		return false

	var file_path := SAVES_DIR + _sanitize_filename(character_id) + ".json"
	var existing := _load_json_file(file_path)
	existing["history"] = []
	existing["last_mood"] = 0
	existing["last_play_time"] = int(Time.get_unix_time_from_system())
	_write_json_file(file_path, existing)
	return true

func _sanitize_filename(filename: String) -> String:
	var s := filename.replace("/", "_").replace("\\", "_").replace(":", "_")
	s = s.replace("*", "_").replace("?", "_").replace('"', "_")
	s = s.replace("<", "_").replace(">", "_").replace("|", "_")
	return s

func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) == OK and json.get_data() is Dictionary:
		return json.get_data()
	return {}

func _write_json_file(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("HistoryManager: 无法写入文件 %s，错误码：%d" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data))
	file.close()
