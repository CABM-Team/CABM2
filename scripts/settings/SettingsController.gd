## SettingsController.gd
## 设置页面控制器

extends Control

@onready var api_key_input: LineEdit    = $ScrollContainer/VBox/ApiKeyInput
@onready var base_url_input: LineEdit   = $ScrollContainer/VBox/BaseUrlInput
@onready var model_input: LineEdit      = $ScrollContainer/VBox/ModelInput
@onready var memory_key_input: LineEdit = $ScrollContainer/VBox/MemoryKeyInput
@onready var memory_url_input: LineEdit = $ScrollContainer/VBox/MemoryUrlInput
@onready var embed_model_input: LineEdit = $ScrollContainer/VBox/EmbedModelInput
@onready var save_button: Button        = $ScrollContainer/VBox/SaveButton
@onready var back_button: Button        = $ScrollContainer/VBox/BackButton
@onready var status_label: Label        = $ScrollContainer/VBox/StatusLabel

func _ready() -> void:
	save_button.pressed.connect(_on_save)
	back_button.pressed.connect(_on_back)
	_load_values()

func _load_values() -> void:
	api_key_input.text    = ConfigManager.get_value("chat_api_key")
	base_url_input.text   = ConfigManager.get_value("chat_api_base_url")
	model_input.text      = ConfigManager.get_value("chat_model")
	memory_key_input.text = ConfigManager.get_value("memory_api_key")
	memory_url_input.text = ConfigManager.get_value("memory_api_base_url")
	embed_model_input.text = ConfigManager.get_value("embedding_model")

func _on_save() -> void:
	var api_key := api_key_input.text.strip_edges()
	if api_key.is_empty():
		status_label.text = "⚠ API Key 不能为空"
		return

	ConfigManager.set_value("chat_api_key", api_key)
	ConfigManager.set_value("chat_api_base_url", base_url_input.text.strip_edges())
	ConfigManager.set_value("chat_model", model_input.text.strip_edges())
	ConfigManager.set_value("memory_api_key", memory_key_input.text.strip_edges())
	ConfigManager.set_value("memory_api_base_url", memory_url_input.text.strip_edges())
	ConfigManager.set_value("embedding_model", embed_model_input.text.strip_edges())

	status_label.text = "✓ 已保存"
	await get_tree().create_timer(1.0).timeout
	_on_back()

func _on_back() -> void:
	if ConfigManager.is_configured():
		get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
	else:
		status_label.text = "请先填写 API Key"
