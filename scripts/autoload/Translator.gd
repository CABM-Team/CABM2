extends Node
## AI智能翻译客户端
## 封装uapis.cn的翻译API，提供简单的文本翻译接口

const API_URL := "https://uapis.cn/api/v1/ai/translate"

# 语言名称到语言代码的映射表
const LANG_MAP := {
	"汉语": "zh",
	"英语": "en",
	"日语": "ja",
	"韩语": "ko",
	"粤语": "zh-TW",
	"文言文": "zh-lzh"
}

## 公开翻译方法
## @param source_text: 原始文本（源语言固定为zh汉语）
## @param target_lang_name: 目标语言名称，如"英语"、"日语"
## @return: 翻译后的文本，失败返回空字符串
func translate(source_text: String, target_lang_name: String) -> String:
	if source_text.is_empty():
		print("[Translator] 错误：原始文本为空")
		return ""
	
	# 获取目标语言代码
	var target_code: String = _get_lang_code(target_lang_name)
	if target_code.is_empty():
		print("[Translator] 错误：不支持的目标语言 '%s'" % target_lang_name)
		return ""
	
	# 构建请求URL（包含查询参数）
	var url = "%s?target_lang=%s" % [API_URL, target_code]
	
	# 构建请求体
	var body = {
		"text": source_text,
		"source_lang": "zh",  # 固定源语言为汉语
		"style": "casual",
		"context": "general",      # 通用场景
		"preserve_format": true    # 保留格式
	}
	
	# 创建HTTP请求
	var http = HTTPRequest.new()
	add_child(http)
	
	# 准备请求头
	var headers = [
		"Content-Type: application/json",
		"Accept: application/json"
	]
	
	# 发送POST请求
	var json_body = JSON.stringify(body)
	var error = http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	
	if error != OK:
		print("[Translator] 请求发送失败，错误码: %d" % error)
		http.queue_free()
		return ""
	
	# 等待响应
	var result = await http.request_completed
	http.queue_free()
	
	# 解析响应
	var response_code = result[1]
	var response_data = result[3]
	
	if response_code != 200:
		print("[Translator] HTTP错误 %d" % response_code)
		return ""
	
	# 解析JSON
	var json = JSON.new()
	var parse_result = json.parse(response_data.get_string_from_utf8())
	if parse_result != OK:
		print("[Translator] JSON解析失败")
		return ""
	
	var response_dict = json.data
	if response_dict.has("data") and response_dict["data"].has("translated_text"):
		return response_dict["data"]["translated_text"]
	else:
		print("[Translator] 响应格式异常: %s" % response_dict)
		return ""


## 将语言名称转换为API所需的语言代码
## @param lang_name: 语言名称，如"英语"
## @return: 语言代码，如"en"，未找到返回空字符串
func _get_lang_code(lang_name: String) -> String:
	# 直接匹配
	if LANG_MAP.has(lang_name):
		return LANG_MAP[lang_name]
	
	# 尝试模糊匹配（去除空格、大小写归一化）
	var normalized = lang_name.strip_edges().to_lower()
	for name in LANG_MAP.keys():
		if name.to_lower() == normalized:
			return LANG_MAP[name]
	
	# 如果传入的已经是语言代码（如"en"），检查是否在映射值中
	if LANG_MAP.values().has(lang_name):
		return lang_name
	
	return ""