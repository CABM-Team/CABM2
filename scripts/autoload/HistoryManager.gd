## HistoryManager.gd
## 历史记录管理器，负责保存和加载对话历史到磁盘
## 存储路径：user://saves/<character_id>.json
## 文件格式：{ "history": [...], "last_play_time": <unix_timestamp> }
## AutoLoad 单例

extends Node

const SAVES_DIR := "user://saves/"

## 保存群聊历史（group_id 作为文件名）
func save_group_history(group_id: String, messages: Array[Dictionary]) -> void:
	save_history(group_id, messages)

## 加载群聊历史
func load_group_history(group_id: String) -> Array[Dictionary]:
	return load_history(group_id)

## 保存指定角色的对话历史
func save_history(character_id: String, messages: Array[Dictionary]) -> void:
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

	var payload := {
		"history": filtered,
		"last_play_time": int(Time.get_unix_time_from_system())
	}

	var file_path := SAVES_DIR + _sanitize_filename(character_id) + ".json"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("HistoryManager: 无法打开文件 %s，错误码：%d" % [file_path, FileAccess.get_open_error()])
		return

	file.store_string(JSON.stringify(payload))
	file.close()

## 加载指定角色的对话历史
func load_history(character_id: String) -> Array[Dictionary]:
	if character_id.is_empty():
		push_warning("HistoryManager: character_id 为空，无法加载历史")
		return []

	var file_path := SAVES_DIR + _sanitize_filename(character_id) + ".json"
	if not FileAccess.file_exists(file_path):
		return []

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("HistoryManager: 无法打开文件 %s，错误码：%d" % [file_path, FileAccess.get_open_error()])
		return []

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("HistoryManager: JSON 解析失败：%s" % file_path)
		return []

	var data = json.get_data()
	if not data is Dictionary:
		return []

	var history = data.get("history", [])
	var messages: Array[Dictionary] = []
	for item in history:
		if item is Dictionary and item.has("role") and item.has("content"):
			messages.append(item)
	return messages

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

## 删除指定角色的对话历史
func delete_history(character_id: String) -> bool:
	if character_id.is_empty():
		push_warning("HistoryManager: character_id 为空，无法删除历史")
		return false

	var file_path := SAVES_DIR + _sanitize_filename(character_id) + ".json"
	if not FileAccess.file_exists(file_path):
		return false

	var err := DirAccess.remove_absolute(file_path)
	if err == OK:
		return true
	else:
		push_error("HistoryManager: 删除文件失败：%s，错误码：%d" % [file_path, err])
		return false

func _sanitize_filename(filename: String) -> String:
	var s := filename.replace("/", "_").replace("\\", "_").replace(":", "_")
	s = s.replace("*", "_").replace("?", "_").replace('"', "_")
	s = s.replace("<", "_").replace(">", "_").replace("|", "_")
	return s
