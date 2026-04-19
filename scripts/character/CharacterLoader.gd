## CharacterLoader.gd
## 从 JSON 文件加载角色配置数据
## 扫描 res://characters/<id>/<id>.json 和 user://characters/<id>/<id>.json

class_name CharacterLoader

static func load_all() -> Array[Dictionary]:
	var characters: Array[Dictionary] = []
	# 用 id 做去重，user:// 优先覆盖 res://
	var seen: Dictionary = {}

	for base in ["res://characters/", "user://characters/"]:
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				var json_path: String = base + entry + "/" + entry + ".json"
				var data := load_from_file(json_path)
				if not data.is_empty():
					var cid: String = data.get("id", entry)
					seen[cid] = data
			entry = dir.get_next()

	for cid in seen:
		characters.append(seen[cid])
	return characters

static func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CharacterLoader: 无法打开文件 " + path)
		return {}
	var text := file.get_as_text().strip_edges()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("CharacterLoader: JSON 解析失败 " + path + " — " + json.get_error_message())
		return {}
	var data = json.get_data()
	if data is Dictionary:
		return data
	push_warning("CharacterLoader: JSON 根节点不是 Dictionary " + path)
	return {}
