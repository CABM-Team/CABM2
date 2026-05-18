## VectorStore.gd
## 知识库向量存储管理器
## 负责知识库的增删改查和向量检索
## AutoLoad 单例

extends Node

# 向量数据库文件路径
const KNOWLEDGE_BASE_PATH := "user://knowledge_base/data.json"

# cosine_calculator插件实例（通过GDExtension调用C++实现的余弦相似度计算）
var _cosine_calc: RefCounted = null

# 内存中的知识库数据
var _entries: Array[Dictionary] = []

# 插件初始化标志
var _plugin_initialized := false

func _ready() -> void:
	# 尝试加载cosine_calculator插件
	_init_cosine_calculator()
	# 加载知识库数据
	_load()

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

## 加载知识库数据
func _load() -> void:
	var file := FileAccess.file_exists(KNOWLEDGE_BASE_PATH)
	if not file:
		_entries = []
		return

	var data_file := FileAccess.open(KNOWLEDGE_BASE_PATH, FileAccess.READ)
	if data_file == null:
		push_warning("[VectorStore] 无法打开知识库文件: " + str(FileAccess.get_open_error()))
		_entries = []
		return

	var json_str := data_file.get_as_text()
	data_file.close()

	var json := JSON.new()
	if json.parse(json_str) != OK:
		push_warning("[VectorStore] JSON解析失败")
		_entries = []
		return

	var data = json.get_data()
	if data is Array:
		_entries = Array(data)
	else:
		push_warning("[VectorStore] 数据格式错误，期望Array类型")
		_entries = []

	print("[VectorStore] 加载了 %d 条知识库条目" % _entries.size())

## 保存知识库数据
func _save() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		push_warning("[VectorStore] 无法访问user://目录")
		return

	if not dir.dir_exists("knowledge_base"):
		dir.make_dir("knowledge_base")

	var json_str := JSON.stringify(_entries, "\t")
	var data_file := FileAccess.open(KNOWLEDGE_BASE_PATH, FileAccess.WRITE)
	if data_file == null:
		push_warning("[VectorStore] 无法写入知识库文件: " + str(FileAccess.get_open_error()))
		return

	data_file.store_string(json_str)
	data_file.close()
	print("[VectorStore] 保存了 %d 条知识库条目" % _entries.size())

## 获取所有条目数量
func get_count() -> int:
	return _entries.size()

## 获取所有条目（只读）
func get_all_entries() -> Array[Dictionary]:
	return _entries.duplicate()

## 添加单个条目（需要先嵌入）
## entry: Dictionary 必须包含 id, text, embedding
func add_entry(entry: Dictionary) -> bool:
	if not entry.has("id") or not entry.has("text") or not entry.has("embedding"):
		push_warning("[VectorStore] 条目缺少必要字段（id, text, embedding）")
		return false

	_entries.append(entry)
	_save()
	return true

## 批量添加条目
## entries: Array[Dictionary] 条目数组
func add_entries(entries: Array[Dictionary]) -> int:
	var added := 0
	for entry in entries:
		if add_entry(entry):
			added += 1
	return added

## 删除条目
## entry_id: String 条目ID
func delete_entry(entry_id: String) -> bool:
	for i in range(_entries.size()):
		if _entries[i].get("id", "") == entry_id:
			_entries.remove_at(i)
			_save()
			return true
	return false

## 清空知识库
func clear_all() -> void:
	_entries.clear()
	_save()

## 检索最相似的条目
## query_text: String 查询文本（需要先嵌入）
## top_k: int 返回前k条最相似的条目
## threshold: float 相似度阈值（0-1），小于此值的条目不返回
func search(query_embedding: Array, top_k: int = 5, threshold: float = 0.0) -> Array[Dictionary]:
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