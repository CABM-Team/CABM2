## KnowledgeRetriever.gd
## 知识库检索辅助类
## 负责从知识库检索相关内容，并格式化为可加入提示词的文本

class_name KnowledgeRetriever
extends RefCounted

## 知识库内容最大字符数（超过此长度会截断）
const MAX_KNOWLEDGE_CHARS := 2000

## 从知识库检索相关内容并格式化为文本
## query_text: String 用户查询文本
## max_results: int 最大返回条数
## threshold: float 相似度阈值（0-1）
## on_done: Callable(result_text: String) - 检索完成回调
func retrieve_and_format(query_text: String, on_done: Callable, max_results: int = 8, threshold: float = 0.5) -> void:
	if not EmbedService.is_configured():
		on_done.call("")
		return

	var count := VectorStore.get_count()
	if count == 0:
		on_done.call("")
		return

	EmbedService.embed_text(query_text, func(embeddings: Array, error: String):
		if not error.is_empty() or embeddings.is_empty() or embeddings[0].is_empty():
			on_done.call("")
			return

		var results := VectorStore.search(embeddings[0], max_results, threshold)
		var formatted := _format_results(results)
		on_done.call(formatted)
	)

## 仅检索返回结果数组（同步）
## query_embedding: Array 查询向量
## max_results: int 最大返回条数
## threshold: float 相似度阈值
func search_only(query_embedding: Array, max_results: int = 5, threshold: float = 0.6) -> Array[Dictionary]:
	return VectorStore.search(query_embedding, max_results, threshold)

## 将检索结果格式化为字符串
func _format_results(results: Array[Dictionary]) -> String:
	if results.is_empty():
		return ""

	var sb := ""
	sb += "【以下是与当前对话相关的知识库内容，供参考】\n"

	var total_chars := 0
	var entry_count := 0

	for result in results:
		var text: String = result.get("text", "")
		# var sim: float = result.get("similarity", 0.0)

		if total_chars + text.length() > MAX_KNOWLEDGE_CHARS:
			break

		if entry_count > 0:
			sb += "\n"

		# sb += "[相似度 %.2f] %s" % [sim, text]
		sb += "- " + text
		total_chars += text.length()
		entry_count += 1

	return sb

## 检查知识库是否可用（已配置且有数据）
func is_available() -> bool:
	return EmbedService.is_configured() and VectorStore.get_count() > 0

## 获取知识库统计信息
func get_stats() -> Dictionary:
	return {
		"count": VectorStore.get_count(),
		"configured": EmbedService.is_configured(),
		"available": is_available()
	}