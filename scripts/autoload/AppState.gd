## AppState.gd
## 全局应用状态，管理当前角色、对话历史等运行时状态
## AutoLoad 单例

extends Node

signal character_changed(character_data: Dictionary)
signal history_updated

# 当前角色数据
var current_character: Dictionary = {}

# 对话历史 [{role, content}, ...]
var chat_history: Array[Dictionary] = []

# 当前场景标识
var current_scene: String = ""

func set_character(data: Dictionary) -> void:
	current_character = data
	chat_history.clear()
	character_changed.emit(data)

func add_message(role: String, content: String) -> void:
	chat_history.append({"role": role, "content": content})
	var max_len: int = ConfigManager.get_value("max_history_length")
	# 保留 system 消息，裁剪超出部分
	var system_msgs: Array[Dictionary] = []
	var other_msgs: Array[Dictionary] = []
	for m in chat_history:
		if m["role"] == "system":
			system_msgs.append(m)
		else:
			other_msgs.append(m)
	if other_msgs.size() > max_len:
		other_msgs = other_msgs.slice(other_msgs.size() - max_len)
	chat_history = system_msgs + other_msgs
	history_updated.emit()

func clear_history() -> void:
	var kept: Array[Dictionary] = []
	for m in chat_history:
		if m["role"] == "system":
			kept.append(m)
	chat_history = kept
	history_updated.emit()

func get_messages_for_api() -> Array[Dictionary]:
	return chat_history
