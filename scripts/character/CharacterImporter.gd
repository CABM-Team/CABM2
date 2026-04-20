## CharacterImporter.gd
## 从 ZIP 压缩包导入角色到 user://characters/
## 用法：CharacterImporter.import_from_zip(zip_path) -> Array[Dictionary]
## 每条结果：{ "id": str, "ok": bool, "message": str }

class_name CharacterImporter

const DEST_BASE := "user://characters/"

# 保留关键字，不允许作为角色 ID
const RESERVED_IDS := ["user", "group", "groups", "saves", "settings", "system", "admin", "root"]

## 扫描 ZIP，返回顶层角色文件夹字典 { folder_name -> Array[file_path] }
## 不执行任何写操作，可用于提前获取角色数量
static func scan_zip(zip_path: String) -> Dictionary:
	var char_folders: Dictionary = {}
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return char_folders
	var files := reader.get_files()
	reader.close()
	for f in files:
		var parts := f.split("/")
		if parts.size() < 2:
			continue
		var folder := parts[0]
		if folder.begins_with(".") or folder.is_empty():
			continue
		if not char_folders.has(folder):
			char_folders[folder] = []
		char_folders[folder].append(f)
	return char_folders

## 从 ZIP 文件导入，返回每个角色的导入结果列表
static func import_from_zip(zip_path: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		results.append({ "id": zip_path.get_file(), "ok": false, "message": "无法打开压缩包" })
		return results

	var files := reader.get_files()
	reader.close()

	# 收集压缩包内的顶层文件夹（即角色文件夹）
	var char_folders: Dictionary = {}  # folder_name -> Array[String] (file paths)
	for f in files:
		var parts := f.split("/")
		if parts.size() < 2:
			continue  # 忽略根目录散文件
		var folder := parts[0]
		if folder.begins_with(".") or folder.is_empty():
			continue
		if not char_folders.has(folder):
			char_folders[folder] = []
		char_folders[folder].append(f)

	if char_folders.is_empty():
		results.append({ "id": "?", "ok": false, "message": "压缩包内未找到角色文件夹" })
		return results

	# 逐个角色处理
	for folder_name in char_folders:
		var char_files: Array = char_folders[folder_name]
		var result := _import_one(zip_path, folder_name, char_files)
		results.append(result)

	return results

## 导入单个角色文件夹
static func _import_one(zip_path: String, folder_name: String, files: Array) -> Dictionary:
	var char_id := folder_name

	# ── 校验 ID ──
	if char_id.is_empty():
		return { "id": folder_name, "ok": false, "message": "角色 ID 为空" }

	if char_id in RESERVED_IDS:
		return { "id": char_id, "ok": false, "message": "ID '%s' 是保留关键字，无法导入" % char_id }

	# ID 只允许字母、数字、下划线、连字符
	var id_regex := RegEx.new()
	id_regex.compile("^[a-zA-Z0-9_\\-]+$")
	if not id_regex.search(char_id):
		return { "id": char_id, "ok": false, "message": "ID 含非法字符（只允许字母/数字/下划线/连字符）" }

	# ── 校验结构：必须有 <id>.json ──
	var json_entry := folder_name + "/" + char_id + ".json"
	var has_json := false
	for f in files:
		if f == json_entry:
			has_json = true
			break
	if not has_json:
		return { "id": char_id, "ok": false, "message": "缺少 %s.json 配置文件" % char_id }

	# ── 校验 JSON 内容 ──
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return { "id": char_id, "ok": false, "message": "无法重新打开压缩包" }

	var json_bytes := reader.read_file(json_entry)
	var json_text := json_bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		reader.close()
		return { "id": char_id, "ok": false, "message": "JSON 解析失败：" + json.get_error_message() }

	var data = json.get_data()
	if not data is Dictionary:
		reader.close()
		return { "id": char_id, "ok": false, "message": "JSON 根节点不是对象" }

	# JSON 中的 id 字段必须与文件夹名一致
	var json_id: String = data.get("id", "")
	if json_id != char_id:
		reader.close()
		return { "id": char_id, "ok": false, "message": "JSON 中 id='%s' 与文件夹名 '%s' 不一致" % [json_id, char_id] }

	# ── 校验 ID 冲突（res:// 内置 和 user:// 已有角色均不可覆盖）──
	for base in ["res://characters/", "user://characters/"]:
		var existing_path: String = base + char_id + "/" + char_id + ".json"
		if FileAccess.file_exists(existing_path):
			reader.close()
			return { "id": char_id, "ok": false, "message": "角色 ID '%s' 已存在，请先删除旧角色再导入" % char_id }

	# ── 复制文件到 user://characters/<id>/ ──
	var dest_dir := DEST_BASE + char_id + "/"
	if not DirAccess.dir_exists_absolute(dest_dir):
		DirAccess.make_dir_recursive_absolute(dest_dir)

	for file_path in files:
		# 跳过纯目录条目
		if file_path.ends_with("/"):
			continue
		var relative: String = file_path.substr(folder_name.length() + 1)  # 去掉 "folder_name/"
		if relative.is_empty():
			continue
		# 跳过 .import 文件（Godot 编辑器生成，运行时不需要）
		if relative.ends_with(".import"):
			continue
		var file_bytes := reader.read_file(file_path)
		var dest_path: String = dest_dir + relative
		# 确保子目录存在
		var dest_file_dir: String = dest_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dest_file_dir):
			DirAccess.make_dir_recursive_absolute(dest_file_dir)
		var out := FileAccess.open(dest_path, FileAccess.WRITE)
		if out == null:
			reader.close()
			return { "id": char_id, "ok": false, "message": "写入文件失败：" + dest_path }
		out.store_buffer(file_bytes)
		out.close()

	reader.close()
	return { "id": char_id, "ok": true, "message": "导入成功" }
