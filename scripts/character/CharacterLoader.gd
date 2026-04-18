## CharacterLoader.gd
## 从 JSON 文件加载角色配置数据

class_name CharacterLoader

const CHARACTERS_DIR := "res://character_configs/"

static func load_all() -> Array[Dictionary]:
	var characters: Array[Dictionary] = []
	var dir := DirAccess.open(CHARACTERS_DIR)
	if dir == null:
		push_warning("CharacterLoader: 角色目录不存在 " + CHARACTERS_DIR)
		return characters

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var data := load_from_file(CHARACTERS_DIR + file_name)
			if not data.is_empty():
				characters.append(data)
		file_name = dir.get_next()
	return characters

static func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("CharacterLoader: 文件不存在 " + path)
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
