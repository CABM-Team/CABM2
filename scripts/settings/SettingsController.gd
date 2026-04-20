## SettingsController.gd
## 设置页面控制器

extends Control

# ── 快速填充密钥 ──
@onready var master_key_input: LineEdit  = $MainLayout/TabContainer/API设置/VBox/FirstRunSection/MasterKeyRow/MasterKeyInput
@onready var fill_all_button: Button     = $MainLayout/TabContainer/API设置/VBox/FirstRunSection/MasterKeyRow/FillAllButton

# ── 对话模型 ──
@onready var chat_key_input: LineEdit    = $MainLayout/TabContainer/API设置/VBox/ChatKeyInput
@onready var chat_url_input: LineEdit    = $MainLayout/TabContainer/API设置/VBox/ChatUrlInput
@onready var chat_model_input: LineEdit  = $MainLayout/TabContainer/API设置/VBox/ChatModelInput

# ── 决策模型 ──
@onready var opt_key_input: LineEdit     = $MainLayout/TabContainer/API设置/VBox/OptKeyInput
@onready var opt_url_input: LineEdit     = $MainLayout/TabContainer/API设置/VBox/OptUrlInput
@onready var opt_model_input: LineEdit   = $MainLayout/TabContainer/API设置/VBox/OptModelInput

# ── TTS 模型 ──
@onready var tts_key_input: LineEdit     = $MainLayout/TabContainer/API设置/VBox/TtsKeyInput
@onready var tts_url_input: LineEdit     = $MainLayout/TabContainer/API设置/VBox/TtsUrlInput
@onready var tts_model_input: LineEdit   = $MainLayout/TabContainer/API设置/VBox/TtsModelInput

# ── 聊天设置 ──
@onready var username_input: LineEdit    = $MainLayout/TabContainer/聊天设置/HBoxContainer/UsernameInput
@onready var max_context_label: Label    = $MainLayout/TabContainer/聊天设置/HBoxContainer2/LabelMaxContext
@onready var max_context_slider: HSlider = $MainLayout/TabContainer/聊天设置/HBoxContainer2/MaxContextSlider

# ── 底部栏 ──
@onready var save_button: Button         = $MainLayout/BottomBar/SaveButton
@onready var back_button: Button         = $MainLayout/BottomBar/BackButton
@onready var skip_button: Button         = $MainLayout/BottomBar/SkipButton
@onready var status_label: Label         = $MainLayout/BottomBar/StatusLabel

var _is_first_run := false

func _ready() -> void:
	_is_first_run = ConfigManager.is_first_run()

	back_button.visible = not _is_first_run
	skip_button.visible = _is_first_run

	fill_all_button.pressed.connect(_on_fill_all)
	save_button.pressed.connect(_on_save)
	back_button.pressed.connect(_on_back)
	skip_button.pressed.connect(_on_skip)
	max_context_slider.value_changed.connect(_on_max_context_changed)

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

	username_input.text         = ConfigManager.get_value("username")
	var ctx_chars: int          = ConfigManager.get_value("max_context_chars")
	max_context_slider.value    = ctx_chars
	max_context_label.text      = "记忆最大字符数：%d" % ctx_chars

func _on_max_context_changed(value: float) -> void:
	max_context_label.text = "记忆最大字符数：%d" % int(value)

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

	var uname := username_input.text.strip_edges()
	ConfigManager.set_value("username",          uname if not uname.is_empty() else "用户")
	ConfigManager.set_value("max_context_chars", int(max_context_slider.value))

	if _is_first_run:
		get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
	else:
		status_label.text = "✓ 已保存"

func _on_skip() -> void:
	ConfigManager.set_value("chat_api_key", "")
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
