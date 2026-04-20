## PromptBuilder.gd
## 负责构建完整的 API 请求提示词（message 字段）

class_name PromptBuilder
extends RefCounted

const MAX_CONTEXT_CHARS := 1200

## 对消息数组进行字符数截断，保留 system 消息，从最旧的非 system 消息开始丢弃
## 直到总字符数 <= MAX_CONTEXT_CHARS
static func _trim_to_limit(messages: Array[Dictionary]) -> Array[Dictionary]:
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
		# 预算不足则跳过（丢弃旧消息）

	var result: Array[Dictionary] = []
	result.append_array(system_msgs)
	result.append_array(trimmed)
	return result

## 构建带有情绪格式要求的消息数组（单角色模式）
static func build_messages(messages: Array[Dictionary], character_data: Dictionary) -> Array[Dictionary]:
	var moods: Array = character_data.get("moods", [])
	var mood_list := ""
	for i in moods.size():
		mood_list += "%d:%s " % [i + 1, moods[i]]

	var system_prompt_suffix := "\n你必须严格以JSON格式输出，包含以下字段：\n\"mood\": <int> 当前情绪序号，必须是以下之一：%s\n\"msg\": <string> 回复内容，1-6句话，禁止换行和markdown" % mood_list

	var patched_messages: Array[Dictionary] = []
	var has_system := false
	for msg in messages:
		if msg["role"] == "system":
			patched_messages.append({"role": "system", "content": msg["content"] + system_prompt_suffix})
			has_system = true
		else:
			patched_messages.append(msg)

	if not has_system:
		patched_messages.insert(0, {"role": "system", "content": system_prompt_suffix})

	return _trim_to_limit(patched_messages)

## 构建群聊模式下某个角色的请求消息数组
## speaking_char: 本次发言的角色数据
## all_chars: 群聊中所有角色数据列表
## history: 群聊历史 [{role, content}]，role 可以是 "user" / <character_id>
## group_data: 群聊配置（可选），用于注入群聊描述
static func build_group_messages(
	speaking_char: Dictionary,
	all_chars: Array[Dictionary],
	history: Array[Dictionary],
	group_data: Dictionary = {}
) -> Array[Dictionary]:
	var speaking_id: String = speaking_char.get("id", "")
	var moods: Array = speaking_char.get("moods", [])
	var mood_list := ""
	for i in moods.size():
		mood_list += "%d:%s " % [i + 1, moods[i]]

	# 构建其他角色名字列表
	var other_names: Array[String] = []
	for c in all_chars:
		if c.get("id", "") != speaking_id:
			other_names.append(c.get("name", c.get("id", "")))

	var system_content: String = speaking_char.get("prompt", "")
	if not other_names.is_empty():
		system_content += "\n你正在和%s等人一起对话。" % "、".join(other_names)
	var group_des: String = group_data.get("des", "")
	if not group_des.is_empty():
		system_content += "\n对话背景：%s" % group_des
	system_content += "\n你必须严格以JSON格式，按顺序输出以下字段：\n\"mood\": <int> 当前情绪序号，必须是以下之一：%s\n\"msg\": <string> 回复内容，1-6句话，禁止换行和markdown" % mood_list

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
				pending_user_lines.append("用户：" + content)
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

## 根据 role 获取显示名（user → "用户"，角色 id → 角色名）
static func _role_display_name(role: String, all_chars: Array[Dictionary]) -> String:
	if role == "user":
		return "用户"
	for c in all_chars:
		if c.get("id", "") == role:
			return c.get("name", role)
	return role
