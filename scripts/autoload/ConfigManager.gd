## ConfigManager.gd
## 全局配置管理，负责读写 API Key 等用户配置
## AutoLoad 单例

extends Node

const CONFIG_PATH := "user://config.cfg"

var _config := ConfigFile.new()

# 默认配置
var defaults := {
	# 对话模型
	"chat_api_key": "",
	"chat_api_base_url": "https://api.siliconflow.cn/v1",
	"chat_model": "deepseek-ai/DeepSeek-V3.2",
	# 决策模型
	"option_api_key": "",
	"option_api_base_url": "https://api.siliconflow.cn/v1",
	"option_model": "Qwen/Qwen3-8B",
	# 语音（TTS）模型
	"tts_api_key": "",
	"tts_api_base_url": "https://api.siliconflow.cn/v1",
	"tts_model": "IndexTeam/IndexTTS-2",
	# 聊天设置
	"username": "用户",
	"max_context_chars": 2000,
	"auto_play_tts": true,
	"enable_option_generation": true,
	# 功能开关（用户不可见）
	"max_history_length": 100,
	"enable_tts": true
}

func _ready() -> void:
	_load()

func _load() -> void:
	_config.load(CONFIG_PATH)  # 首次运行时文件不存在，不写入默认值，保持空白

func _save() -> void:
	for key in defaults:
		if not _config.has_section_key("app", key):
			_config.set_value("app", key, defaults[key])
	_config.save(CONFIG_PATH)

func get_value(key: String) -> Variant:
	return _config.get_value("app", key, defaults.get(key))

func set_value(key: String, value: Variant) -> void:
	_config.set_value("app", key, value)
	_config.save(CONFIG_PATH)

func is_configured() -> bool:
	return get_value("chat_api_key") != ""

## 是否首次运行（从未保存过 chat_api_key）
func is_first_run() -> bool:
	return not _config.has_section_key("app", "chat_api_key")
