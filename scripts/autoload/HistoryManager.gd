## HistoryManager.gd
## 历史记录管理器，负责保存和加载对话历史到磁盘
## AutoLoad 单例

extends Node

const HISTORY_DIR := "user://history/"

## 保存群聊历史（group_id 作为文件名）
func save_group_history(group_id: String, messages: Array[Dictionary]) -> void:
	save_history(group_id, messages)

## 加载群聊历史
func load_group_history(group_id: String) -> Array[Dictionary]:
	return load_history(group_id)

## 保存指定角色的对话历史到磁盘
## @param character_id: 角色唯一标识（通常使用角色名称）
## @param messages: 消息数组 [{role: String, content: String}, ...]
func save_history(character_id: String, messages: Array[Dictionary]) -> void:
	if character_id.is_empty():
		push_warning("HistoryManager: character_id 为空，无法保存历史")
		return
	
	# 确保历史目录存在
	if not DirAccess.dir_exists_absolute(HISTORY_DIR):
		DirAccess.make_dir_recursive_absolute(HISTORY_DIR)
	
	var file_path := HISTORY_DIR + _sanitize_filename(character_id) + ".jsonl"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("HistoryManager: 无法打开文件 %s，错误码：%d" % [file_path, FileAccess.get_open_error()])
		return
	
	# 写入 JSONL 格式（每行一个 JSON 对象）
	for msg in messages:
		if msg.get("role", "") == "system":
			continue  # 不保存 system 消息
		var line := JSON.stringify(msg)
		file.store_line(line)
	
	file.close()
	print("HistoryManager: 已保存 %d 条消息到 %s" % [messages.size(), file_path])

## 加载指定角色的对话历史
## @param character_id: 角色唯一标识
## @return 消息数组 [{role: String, content: String}, ...]
func load_history(character_id: String) -> Array[Dictionary]:
	if character_id.is_empty():
		push_warning("HistoryManager: character_id 为空，无法加载历史")
		return []
	
	var file_path := HISTORY_DIR + _sanitize_filename(character_id) + ".jsonl"
	if not FileAccess.file_exists(file_path):
		print("HistoryManager: 历史文件不存在：%s" % file_path)
		return []
	
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("HistoryManager: 无法打开文件 %s，错误码：%d" % [file_path, FileAccess.get_open_error()])
		return []
	
	var messages: Array[Dictionary] = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		
		var json := JSON.new()
		if json.parse(line) == OK:
			var msg: Dictionary = json.get_data()
			if msg.has("role") and msg.has("content"):
				messages.append(msg)
		else:
			push_warning("HistoryManager: 解析 JSON 失败：%s" % line)
	
	file.close()
	print("HistoryManager: 已加载 %d 条消息从 %s" % [messages.size(), file_path])
	return messages

## 删除指定角色的对话历史
## @param character_id: 角色唯一标识
func delete_history(character_id: String) -> bool:
	if character_id.is_empty():
		push_warning("HistoryManager: character_id 为空，无法删除历史")
		return false
	
	var file_path := HISTORY_DIR + _sanitize_filename(character_id) + ".jsonl"
	if not FileAccess.file_exists(file_path):
		print("HistoryManager: 历史文件不存在：%s" % file_path)
		return false
	
	var dir := DirAccess.open(HISTORY_DIR)
	if dir == null:
		push_error("HistoryManager: 无法打开目录 %s" % HISTORY_DIR)
		return false
	
	var err := dir.remove(file_path)
	if err == OK:
		print("HistoryManager: 已删除历史文件：%s" % file_path)
		return true
	else:
		push_error("HistoryManager: 删除文件失败：%s，错误码：%d" % [file_path, err])
		return false

## 清理文件名中的非法字符
func _sanitize_filename(filename: String) -> String:
	var sanitized := filename.replace("/", "_").replace("\\", "_").replace(":", "_")
	sanitized = sanitized.replace("*", "_").replace("?", "_").replace('"', "_")
	sanitized = sanitized.replace("<", "_").replace(">", "_").replace("|", "_")
	return sanitized
