## SettingsController.gd
## 设置页面控制器

extends Control

# ── 快速填充密钥 ──
@onready var master_key_input: LineEdit  = $MainLayout/ScrollContainer/VBox/FirstRunSection/MasterKeyRow/MasterKeyInput
@onready var fill_all_button: Button     = $MainLayout/ScrollContainer/VBox/FirstRunSection/MasterKeyRow/FillAllButton

# ── 对话模型 ──
@onready var chat_key_input: LineEdit    = $MainLayout/ScrollContainer/VBox/ChatKeyInput
@onready var chat_url_input: LineEdit    = $MainLayout/ScrollContainer/VBox/ChatUrlInput
@onready var chat_model_input: LineEdit  = $MainLayout/ScrollContainer/VBox/ChatModelInput

# ── 决策模型 ──
@onready var opt_key_input: LineEdit     = $MainLayout/ScrollContainer/VBox/OptKeyInput
@onready var opt_url_input: LineEdit     = $MainLayout/ScrollContainer/VBox/OptUrlInput
@onready var opt_model_input: LineEdit   = $MainLayout/ScrollContainer/VBox/OptModelInput

# ── TTS 模型 ──
@onready var tts_key_input: LineEdit     = $MainLayout/ScrollContainer/VBox/TtsKeyInput
@onready var tts_url_input: LineEdit     = $MainLayout/ScrollContainer/VBox/TtsUrlInput
@onready var tts_model_input: LineEdit   = $MainLayout/ScrollContainer/VBox/TtsModelInput

# ── 底部栏 ──
@onready var save_button: Button         = $MainLayout/BottomBar/SaveButton
@onready var back_button: Button         = $MainLayout/BottomBar/BackButton
@onready var skip_button: Button         = $MainLayout/BottomBar/SkipButton
@onready var status_label: Label         = $MainLayout/BottomBar/StatusLabel

var _is_first_run := false

func _ready() -> void:
	_is_first_run = ConfigManager.is_first_run()

	# 首次启动：隐藏"返回"，显示"跳过"
	back_button.visible = not _is_first_run
	skip_button.visible = _is_first_run

	fill_all_button.pressed.connect(_on_fill_all)
	save_button.pressed.connect(_on_save)
	back_button.pressed.connect(_on_back)
	skip_button.pressed.connect(_on_skip)

	_load_values()

func _load_values() -> void:
	chat_key_input.text   = ConfigManager.get_value("chat_api_key")
	chat_url_input.text   = ConfigManager.get_value("chat_api_base_url")
	chat_model_input.text = ConfigManager.get_value("chat_model")

	opt_key_input.text    = ConfigManager.get_value("option_api_key")
	opt_url_input.text    = ConfigManager.get_value("option_api_base_url")
	opt_model_input.text  = ConfigManager.get_value("option_model")

	tts_key_input.text    = ConfigManager.get_value("tts_api_key")
	tts_url_input.text    = ConfigManager.get_value("tts_api_base_url")
	tts_model_input.text  = ConfigManager.get_value("tts_model")

func _on_fill_all() -> void:
	var key := master_key_input.text.strip_edges()
	if key.is_empty():
		return
	chat_key_input.text = key
	opt_key_input.text  = key
	tts_key_input.text  = key

func _on_save() -> void:
	var chat_key := chat_key_input.text.strip_edges()
	if chat_key.is_empty():
		status_label.text = "⚠ 对话 API Key 不能为空"
		return

	ConfigManager.set_value("chat_api_key",       chat_key)
	ConfigManager.set_value("chat_api_base_url",  chat_url_input.text.strip_edges())
	ConfigManager.set_value("chat_model",         chat_model_input.text.strip_edges())
	ConfigManager.set_value("option_api_key",     opt_key_input.text.strip_edges())
	ConfigManager.set_value("option_api_base_url", opt_url_input.text.strip_edges())
	ConfigManager.set_value("option_model",       opt_model_input.text.strip_edges())
	ConfigManager.set_value("tts_api_key",        tts_key_input.text.strip_edges())
	ConfigManager.set_value("tts_api_base_url",   tts_url_input.text.strip_edges())
	ConfigManager.set_value("tts_model",          tts_model_input.text.strip_edges())

	if _is_first_run:
		# 首次保存后直接跳转
		get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
	else:
		status_label.text = "✓ 已保存"

func _on_skip() -> void:
	ConfigManager.set_value("chat_api_key", "")
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
