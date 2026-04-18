## ConfigManager.gd
## 全局配置管理，负责读写 API Key 等用户配置
## AutoLoad 单例

extends Node

const CONFIG_PATH := "user://config.cfg"

var _config := ConfigFile.new()

# 默认配置
var defaults := {
	"chat_api_key": "",
	"chat_api_base_url": "https://api.siliconflow.cn/v1",
	"chat_model": "deepseek-ai/DeepSeek-V3",
	"option_model": "Qwen/Qwen3-8B",
	"memory_api_key": "",
	"memory_api_base_url": "",
	"embedding_model": "",
	"reranker_model": "",
	"tts_api_key": "",
	"max_history_length": 8,
	"enable_option_generation": true,
	"enable_memory": false,
	"enable_tts": false,
}

func _ready() -> void:
	_load()

func _load() -> void:
	var err := _config.load(CONFIG_PATH)
	if err != OK:
		# 首次运行，写入默认值
		_save()

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
