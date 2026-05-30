## PromptBuilder.gd
## 负责构建完整的 API 请求提示词（message 字段）

class_name PromptBuilder
extends RefCounted

## 对消息数组进行字符数截断，保留 system 消息，从最旧的非 system 消息开始丢弃
## 直到总字符数 <= max_context_chars（从 ConfigManager 读取）
static func _trim_to_limit(messages: Array[Dictionary]) -> Array[Dictionary]:
	var MAX_CONTEXT_CHARS: int = ConfigManager.get_effective_value("max_context_chars")
	var total := 0
	for msg in messages:
		total += (msg.get("content", "") as String).length()
	if total <= MAX_CONTEXT_CHARS:
		return messages

	# 分离 system 和非 system
	var system_msgs: Array[Dictionary] = []
	var other_msgs: Array[Dictionary] = []
	for msg in messages:
		if msg.get("role", "") == "system":
			system_msgs.append(msg)
		else:
			other_msgs.append(msg)

	# 计算 system 占用
	var system_chars := 0
	for msg in system_msgs:
		system_chars += (msg.get("content", "") as String).length()

	# 从最旧的非 system 消息开始丢弃
	var budget := MAX_CONTEXT_CHARS - system_chars
	var trimmed: Array[Dictionary] = []
	for i in range(other_msgs.size() - 1, -1, -1):
		var msg_len := (other_msgs[i].get("content", "") as String).length()
		if budget >= msg_len:
			trimmed.insert(0, other_msgs[i])
			budget -= msg_len
		else:
			break  # 预算不足则停止，优先保留最新消息

	var result: Array[Dictionary] = []
	result.append_array(system_msgs)
	result.append_array(trimmed)
	return result

## 构建 Markdown 格式的系统提示词内容
static func _build_system_content(
	character_data: Dictionary,
	knowledge_context: String = "",
	context_info: Dictionary = {}
) -> String:
	var sections: Array[String] = []
	
	# 1. 身份设定
	var prompt: String = character_data.get("prompt", "")
	if not prompt.is_empty():
		sections.append("## 身份设定\n" + prompt)
	
	# 2. 相关知识（如果有）
	if not knowledge_context.is_empty():
		sections.append("## 相关知识\n" + knowledge_context)
	
	# 3. 对话背景/上下文（群聊专用）
	if context_info.has("group_des") and not context_info.group_des.is_empty():
		sections.append("## 对话背景\n" + context_info.group_des)
	
	if context_info.has("user_name") and not context_info.user_name.is_empty():
		sections.append("## 对话对象\n" + context_info.user_name + "正在与你聊天。")

	if context_info.has("other_names") and not context_info.other_names.is_empty():
		sections.append("## 对话对象\n你正在和" + "、".join(context_info.other_names) + "一起对话。")
	
	# 4. 输出要求
	var moods: Array = character_data.get("moods", [])
	var mood_list := ""
	for i in moods.size():
		mood_list += "%d:%s " % [i + 1, moods[i]]
	
	var output_requirements: String = "## 输出要求\n"
	output_requirements += "你必须严格以 JSON 格式按顺序输出两个字段：\n"
	output_requirements += "  - `\"mood\"`: <int> 当前情绪的序号，必须是以下之一：%s\n" % mood_list
	output_requirements += "  - `\"msg\"`: <string> 你要说的话，1-6句话，使用中文标点，禁止使用markdown或换行符\n"
	sections.append(output_requirements)

	return "\n\n".join(sections)

## 构建带有情绪格式要求的消息数组（单角色模式）
static func build_messages(
	messages: Array[Dictionary],
	character_data: Dictionary,
	knowledge_context: String = ""
) -> Array[Dictionary]:
	var context_info: Dictionary = {
		"user_name": ConfigManager.get_effective_value("username")
	}
	var system_content = _build_system_content(character_data, knowledge_context, context_info)
	
	var result: Array[Dictionary] = [{"role": "system", "content": system_content}]
	for msg in messages:
		if msg.get("role", "") != "system":
			result.append(msg)
	
	return _trim_to_limit(result)

## 构建群聊模式下某个角色的请求消息数组
## speaking_char: 本次发言的角色数据
## all_chars: 群聊中所有角色数据列表
## history: 群聊历史 [{role, content}]，role 可以是 "user" / <character_id>
## group_data: 群聊配置（可选），用于注入群聊描述
## knowledge_context: 知识库检索结果（可选）
static func build_group_messages(
	speaking_char: Dictionary,
	all_chars: Array[Dictionary],
	history: Array[Dictionary],
	group_data: Dictionary = {},
	knowledge_context: String = ""
) -> Array[Dictionary]:
	var speaking_id: String = speaking_char.get("id", "")
	
	# 构建其他角色名字列表（包含用户名）
	var other_names: Array[String] = []
	other_names.append(ConfigManager.get_effective_value("username"))
	for c in all_chars:
		if c.get("id", "") != speaking_id:
			other_names.append(c.get("name", c.get("id", "")))
	
	# 构建上下文信息
	var context_info: Dictionary = {
		"other_names": other_names,
		"group_des": group_data.get("des", "")
	}
	
	var system_content = _build_system_content(speaking_char, knowledge_context, context_info)
	
	var result: Array[Dictionary] = [{"role": "system", "content": system_content}]
	
	# 将群聊历史转换为二人对话格式（user / assistant）
	# speaking_char 的发言 → assistant
	# 其他所有内容（user 输入 + 其他角色发言）→ user
	# 规则：连续的 user 侧消息合并为一条
	var pending_user_lines: Array[String] = []
	
	for msg in history:
		var role: String = msg.get("role", "")
		var content: String = msg.get("content", "")
		if role == "system":
			continue
		
		if role == speaking_id:
			# 先 flush 待合并的 user 消息
			if not pending_user_lines.is_empty():
				result.append({"role": "user", "content": "\n".join(pending_user_lines)})
				pending_user_lines.clear()
			result.append({"role": "assistant", "content": content})
		else:
			# user 输入或其他角色发言，都归入 user 侧
			var display_name := _role_display_name(role, all_chars)
			if role == "user":
				pending_user_lines.append(ConfigManager.get_effective_value("username") + "：" + content)
			else:
				# 其他角色的发言，从 JSON 中提取 msg 字段
				var msg_text := _extract_msg(content)
				pending_user_lines.append(display_name + "：" + msg_text)
	
	# flush 剩余
	if not pending_user_lines.is_empty():
		result.append({"role": "user", "content": "\n".join(pending_user_lines)})
	
	# 确保最后一条是 user（API 要求）
	if not result.is_empty() and result.back().get("role", "") == "assistant":
		result.append({"role": "user", "content": ""})
	
	return _trim_to_limit(result)

## 从 JSON 字符串中提取 msg 字段，失败则返回原文
static func _extract_msg(json_str: String) -> String:
	var json := JSON.new()
	if json.parse(json_str) == OK:
		var data = json.get_data()
		if data is Dictionary:
			return data.get("msg", json_str)
	return json_str

## 根据 role 获取显示名（user → 用户名，角色 id → 角色名）
static func _role_display_name(role: String, all_chars: Array[Dictionary]) -> String:
	if role == "user":
		return ConfigManager.get_effective_value("username")
	for c in all_chars:
		if c.get("id", "") == role:
			return c.get("name", role)
	return role
