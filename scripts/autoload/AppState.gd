## AppState.gd
## 全局应用状态，管理当前角色、对话历史等运行时状态
## AutoLoad 单例

extends Node

signal character_changed(character_data: Dictionary)
signal history_updated

# 当前角色数据（单角色模式）
var current_character: Dictionary = {}

# 当前群聊数据（群聊模式时使用）
# { id, name, character_ids: [] }
var current_group: Dictionary = {}

# 群聊角色数据列表（群聊模式时填充）
var group_characters: Array[Dictionary] = []

# 对话历史 [{role, content}, ...]
# 注意：system 消息不应直接存储在 history 中，应由 PromptBuilder 统一构建
var chat_history: Array[Dictionary] = []

# 当前知识库上下文（由 VectorStore 检索得到，供 PromptBuilder 使用）
var knowledge_context: String = ""

# 当前场景标识
var current_scene: String = ""

# 编辑模式：要编辑的角色 ID（空字符串表示创建模式）
var edit_char_id: String = ""

# 编辑完成后自动返回的角色 ID（空字符串表示不自动跳转）
var return_to_char_id: String = ""

## 是否处于群聊模式
func is_group_mode() -> bool:
	return not current_group.is_empty()

## 设置当前角色（单角色模式）
func set_character(data: Dictionary) -> void:
	current_character = data
	current_group = {}
	group_characters.clear()
	chat_history.clear()
	knowledge_context = ""
	character_changed.emit(data)

## 设置群聊模式
func set_group(group_data: Dictionary, characters: Array[Dictionary]) -> void:
	current_group = group_data
	current_character = {}
	group_characters = characters
	chat_history.clear()
	knowledge_context = ""

## 添加消息到历史记录
## role 可以是 "user" / "assistant" / <character_id>
func add_message(role: String, content: String) -> void:
	chat_history.append({"role": role, "content": content})
	var max_len: int = ConfigManager.get_effective_value("max_history_length")
	if chat_history.size() > max_len:
		chat_history = chat_history.slice(chat_history.size() - max_len)
	history_updated.emit()

## 清空历史记录
func clear_history() -> void:
	chat_history.clear()
	history_updated.emit()

## 获取用于 API 请求的消息数组（单角色模式）
func get_messages_for_api() -> Array[Dictionary]:
	return chat_history
