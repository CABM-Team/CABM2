## GroupManager.gd
## 群聊数据管理，负责保存/加载群聊配置到 user://groups/
## AutoLoad 单例

extends Node

const GROUPS_DIR := "user://groups/"

## 保存群聊配置
## group_data: { id, name, character_ids: [] }
func save_group(group_data: Dictionary) -> void:
	_ensure_dir()
	var id: String = group_data.get("id", "")
	if id.is_empty():
		push_warning("GroupManager: group id 为空")
		return
	var path := GROUPS_DIR + id + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GroupManager: 无法写入 %s" % path)
		return
	file.store_string(JSON.stringify(group_data))
	file.close()

## 加载所有群聊
func load_all() -> Array[Dictionary]:
	_ensure_dir()
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(GROUPS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var data := _load_file(GROUPS_DIR + fname)
			if not data.is_empty():
				result.append(data)
		fname = dir.get_next()
	return result

## 删除群聊
func delete_group(group_id: String) -> void:
	var path := GROUPS_DIR + group_id + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## 生成唯一 ID
func generate_id() -> String:
	return "group_" + str(Time.get_unix_time_from_system()).replace(".", "_")

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(GROUPS_DIR):
		DirAccess.make_dir_recursive_absolute(GROUPS_DIR)

func _load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) == OK and json.get_data() is Dictionary:
		return json.get_data()
	return {}
