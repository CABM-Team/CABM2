## PromptBuilder.gd
## 负责构建完整的 API 请求提示词（message 字段）

class_name PromptBuilder
extends RefCounted

## 构建带有情绪格式要求的消息数组
## messages: 原始消息数组
## character_data: 角色数据（包含 moods 等信息）
## 返回: 注入了格式要求的消息数组
static func build_messages(messages: Array[Dictionary], character_data: Dictionary) -> Array[Dictionary]:
	var moods: Array = character_data.get("moods", [])
	var mood_list := ""
	for i in moods.size():
		mood_list += "%d:%s " % [i + 1, moods[i]]
	
	var system_prompt_suffix := "\n你必须严格以JSON格式输出，包含以下字段：\n\"mood\": <int> 当前情绪序号，必须是以下之一：%s\n\"msg\": <string> 回复内容，1-6句话，禁止换行和markdown" % mood_list
	
	# 注入 mood 格式要求到 system 消息
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
	
	return patched_messages
