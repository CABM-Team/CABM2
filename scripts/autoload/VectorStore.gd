## VectorStore.gd
## 知识库向量存储管理器
## 负责知识库的增删改查和向量检索
## 支持每个角色独立的知识库
## AutoLoad 单例

extends Node

# cosine_calculator插件实例（通过GDExtension调用C++实现的余弦相似度计算）
var _cosine_calc: RefCounted = null

# 当前加载的角色ID
var _current_char_id := ""

# 内存中的知识库数据
var _entries: Array[Dictionary] = []

# 知识库开关状态（每个角色独立）
var _knowledge_enabled: Dictionary = {}

# 插件初始化标志
var _plugin_initialized := false

func _ready() -> void:
	# 尝试加载cosine_calculator插件
	_init_cosine_calculator()

## 初始化余弦相似度计算插件
func _init_cosine_calculator() -> void:
	if ClassDB.class_exists("CosineCalculator"):
		_cosine_calc = ClassDB.instantiate("CosineCalculator")
		if _cosine_calc:
			_plugin_initialized = true
			print("[VectorStore] 余弦相似插件初始化成功")
		else:
			push_warning("[VectorStore] 无法实例化CosineCalculator")
	else:
		push_warning("[VectorStore] CosineCalculator类不存在，请确保插件已正确编译安装")

## 获取角色知识库文件路径
func _get_knowledge_path(char_id: String) -> String:
	if char_id.is_empty():
		return ""
	# 优先user://，其次res://
	for base in ["user://characters/", "res://characters/"]:
		var path: String = base + char_id + "/knowledge.json"
		if base.begins_with("user://"):
			# user:// 路径总是可写的
			return path
		elif FileAccess.file_exists(path):
			# res:// 路径只读，需要复制到user://
			var user_path: String = "user://characters/" + char_id + "/knowledge.json"
			return user_path
	# 默认返回user://路径
	return "user://characters/" + char_id + "/knowledge.json"

## 加载指定角色的知识库
func load_character_knowledge(char_id: String) -> void:
	print("[VectorStore] 加载角色知识库：%s，嵌入用时开始计时" % char_id)
	var start_time := Time.get_ticks_msec()
	
	_current_char_id = char_id
	_entries.clear()
	
	if char_id.is_empty():
		print("[VectorStore] 角色ID为空，跳过加载")
		return
	
	var path := _get_knowledge_path(char_id)
	if not FileAccess.file_exists(path):
		print("[VectorStore] 知识库文件不存在：%s" % path)
		return
	
	var data_file := FileAccess.open(path, FileAccess.READ)
	if data_file == null:
		push_warning("[VectorStore] 无法打开知识库文件: " + str(FileAccess.get_open_error()))
		return
	
	var json_str := data_file.get_as_text()
	data_file.close()
	
	var json := JSON.new()
	if json.parse(json_str) != OK:
		push_warning("[VectorStore] JSON解析失败")
		return
	
	var data = json.get_data()
	if data is Dictionary:
		var entries_data = data.get("entries", [])
		_entries.clear()
		for entry in entries_data:
			if entry is Dictionary:
				_entries.append(entry)
		_knowledge_enabled[char_id] = data.get("enabled", true)
	elif data is Array:
		_entries.clear()
		for entry in data:
			if entry is Dictionary:
				_entries.append(entry)
		_knowledge_enabled[char_id] = true
	else:
		push_warning("[VectorStore] 数据格式错误")
		return
	
	var elapsed := Time.get_ticks_msec() - start_time
	print("[VectorStore] 加载了 %d 条知识库条目，用时 %d ms" % [_entries.size(), elapsed])

## 保存当前角色的知识库
func save_current_knowledge() -> void:
	if _current_char_id.is_empty():
		push_warning("[VectorStore] 当前角色ID为空，无法保存")
		return
	
	print("[VectorStore] 保存角色知识库：%s，保存用时开始计时" % _current_char_id)
	var start_time := Time.get_ticks_msec()
	
	var path := _get_knowledge_path(_current_char_id)
	var dir_path := path.get_base_dir()
	
	# 确保目录存在
	var dir := DirAccess.open("user://")
	if dir == null:
		push_warning("[VectorStore] 无法访问user://目录")
		return
	
	# 递归创建目录
	var parts := dir_path.replace("user://", "").split("/")
	var current_path := "user://"
	for part in parts:
		if part.is_empty():
			continue
		current_path += part + "/"
		if not DirAccess.dir_exists_absolute(current_path):
			dir.make_dir_recursive(current_path)
	
	var data := {
		"enabled": _knowledge_enabled.get(_current_char_id, true),
		"entries": _entries
	}
	
	var json_str := JSON.stringify(data, "\t")
	var data_file := FileAccess.open(path, FileAccess.WRITE)
	if data_file == null:
		push_warning("[VectorStore] 无法写入知识库文件: " + str(FileAccess.get_open_error()))
		return
	
	data_file.store_string(json_str)
	data_file.close()
	
	var elapsed := Time.get_ticks_msec() - start_time
	print("[VectorStore] 保存了 %d 条知识库条目，用时 %d ms" % [_entries.size(), elapsed])

## 获取当前角色ID
func get_current_char_id() -> String:
	return _current_char_id

## 获取所有条目数量
func get_count() -> int:
	return _entries.size()

## 获取所有条目（只读）
func get_all_entries() -> Array[Dictionary]:
	return _entries.duplicate()

## 检查知识库是否启用
func is_knowledge_enabled() -> bool:
	if _current_char_id.is_empty():
		return false
	return _knowledge_enabled.get(_current_char_id, true)

## 设置知识库开关
func set_knowledge_enabled(enabled: bool) -> void:
	if _current_char_id.is_empty():
		return
	_knowledge_enabled[_current_char_id] = enabled
	save_current_knowledge()
	print("[VectorStore] 知识库开关已%s" % ("开启" if enabled else "关闭"))

## 添加单个条目（需要先嵌入）
## entry: Dictionary 必须包含 id, text, embedding
func add_entry(entry: Dictionary) -> bool:
	if not entry.has("id") or not entry.has("text") or not entry.has("embedding"):
		push_warning("[VectorStore] 条目缺少必要字段（id, text, embedding）")
		return false

	_entries.append(entry)
	save_current_knowledge()
	return true

## 批量添加条目
## entries: Array[Dictionary] 条目数组
func add_entries(entries: Array[Dictionary]) -> int:
	var added := 0
	for entry in entries:
		if entry.has("id") and entry.has("text") and entry.has("embedding"):
			_entries.append(entry)
			added += 1
	if added > 0:
		save_current_knowledge()
	return added

## 删除条目
## entry_id: String 条目ID
func delete_entry(entry_id: String) -> bool:
	for i in range(_entries.size()):
		if _entries[i].get("id", "") == entry_id:
			_entries.remove_at(i)
			save_current_knowledge()
			return true
	return false

## 清空知识库
func clear_all() -> void:
	_entries.clear()
	save_current_knowledge()

## 检索最相似的条目
## query_embedding: Array 查询向量
## top_k: int 返回前k条最相似的条目
## threshold: float 相似度阈值（0-1），小于此值的条目不返回
func search(query_embedding: Array, top_k: int = 5, threshold: float = 0.0) -> Array[Dictionary]:
	print("[VectorStore] 开始检索，检索用时开始计时")
	var start_time := Time.get_ticks_msec()
	
	if query_embedding.is_empty():
		return []

	var results: Array[Dictionary] = []
	var all_vectors: Array = []

	# 提取所有嵌入向量用于批量计算
	for entry in _entries:
		all_vectors.append(entry.get("embedding", []))

	# 使用插件的批量计算功能（如果可用）
	if _plugin_initialized and _cosine_calc:
		var similarities = _cosine_calc.calculate_batch(query_embedding, all_vectors)
		for i in range(similarities.size()):
			var sim: float = similarities[i]
			if sim >= threshold:
				var result_entry: Dictionary = _entries[i].duplicate()
				result_entry["similarity"] = sim
				results.append(result_entry)
	else:
		# 回退到纯GDScript实现
		for i in range(_entries.size()):
			var embedding: Array = _entries[i].get("embedding", [])
			var sim: float = _calculate_cosine_similarity(query_embedding, embedding)
			if sim >= threshold:
				var result_entry: Dictionary = _entries[i].duplicate()
				result_entry["similarity"] = sim
				results.append(result_entry)

	# 按相似度降序排序
	results.sort_custom(func(a, b): return a.get("similarity", 0.0) > b.get("similarity", 0.0))

	# 截取top_k条
	if results.size() > top_k:
		results.resize(top_k)

	var elapsed := Time.get_ticks_msec() - start_time
	print("[VectorStore] 检索完成，找到 %d 条结果，用时 %d ms" % [results.size(), elapsed])
	
	return results

## 纯GDScript实现的余弦相似度计算（归一化向量，所以直接点积即可）
func _calculate_cosine_similarity(vec1: Array, vec2: Array) -> float:
	if vec1.size() != vec2.size() or vec1.size() == 0:
		return 0.0

	var dot_product := 0.0
	for i in range(vec1.size()):
		dot_product += vec1[i] * vec2[i]

	return float(dot_product)

## 获取条目数统计信息
func get_stats() -> Dictionary:
	return {
		"total_entries": _entries.size(),
		"is_plugin_loaded": _plugin_initialized
	}
