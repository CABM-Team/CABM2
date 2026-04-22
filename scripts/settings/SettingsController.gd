## SettingsController.gd
## 设置页面控制器

extends Control

# ── 内置密钥 ──
@onready var builtin_key_toggle: CheckButton = $MainLayout/TabContainer/API设置/VBox/BuiltinKeyRow/BuiltinKeyToggle

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
@onready var auto_play_tts_button: CheckButton = $MainLayout/TabContainer/聊天设置/HBoxAutoPlayTTS/AutoPlayTTSButton
@onready var option_gen_button: CheckButton    = $MainLayout/TabContainer/聊天设置/HBoxOptionGen/OptionGenButton

# ── 底部栏 ──
@onready var save_button: Button         = $MainLayout/BottomBar/SaveButton
@onready var back_button: Button         = $MainLayout/BottomBar/BackButton
@onready var skip_button: Button         = $MainLayout/BottomBar/SkipButton
@onready var status_label: Label         = $MainLayout/BottomBar/StatusLabel
@onready var confirm_dialog: Control     = $ConfirmDialog
@onready var data_cache_tab: Control     = $MainLayout/TabContainer/数据与缓存

var _is_first_run := false
var _saved_snapshot := {}

func _ready() -> void:
	_is_first_run = ConfigManager.is_first_run()

	back_button.visible = not _is_first_run
	skip_button.visible = _is_first_run

	fill_all_button.pressed.connect(_on_fill_all)
	save_button.pressed.connect(_on_save)
	back_button.pressed.connect(_on_back)
	skip_button.pressed.connect(_on_skip)
	max_context_slider.value_changed.connect(_on_max_context_changed)
	builtin_key_toggle.toggled.connect(_on_builtin_key_toggled)

	_load_values()
	_saved_snapshot = _take_snapshot()
	# 注入 confirm_dialog 给数据与缓存 tab
	data_cache_tab.confirm_dialog = confirm_dialog

func _load_values() -> void:
	builtin_key_toggle.button_pressed = ConfigManager.get_value("use_builtin_key")

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
	var v := int(ctx_chars)
	var formatted := "%d,%03d" % [v / 1000, v % 1000] if v >= 1000 else "%d" % v
	max_context_label.text = ("⚠"if ctx_chars>5000 else "📝")+ "记忆最大字符数：" + formatted
	_update_slider_color(ctx_chars)
	auto_play_tts_button.button_pressed = ConfigManager.get_value("auto_play_tts")
	option_gen_button.button_pressed    = ConfigManager.get_value("enable_option_generation")
	_on_builtin_key_toggled(builtin_key_toggle.button_pressed)

func _on_max_context_changed(value: float) -> void:
	var v := int(value)
	var formatted := "%d,%03d" % [v / 1000, v % 1000] if v >= 1000 else "%d" % v
	max_context_label.text = ("⚠" if value > 5000 else "📝") + "记忆最大字符数：" + formatted
	_update_slider_color(value)

func _update_slider_color(value: float) -> void:
	# 对数插值：与滑杆的 exp_edit 保持一致
	var log_min := log(max_context_slider.min_value)
	var log_max := log(max_context_slider.max_value)
	var t := (log(value) - log_min) / (log_max - log_min)
	t = clampf(t, 0.0, 1.0)

	# 深绿 → 橙红，饱和度高、亮度适中，避免中间黄绿色过淡
	var color := Color.from_hsv(0.33 * (1.0 - t), 0.9, 0.75)
	var color_bright := color.lightened(0.2)

	# 填充轨道
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.set_corner_radius_all(4)
	max_context_slider.add_theme_stylebox_override("fill", fill_style)

	# grabber 普通 + focus（highlight）状态都覆盖，避免 focus 时变回灰色
	for key in ["grabber_area", "grabber_area_highlight"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color_bright
		s.set_corner_radius_all(12)
		s.content_margin_left   = 12.0
		s.content_margin_right  = 12.0
		s.content_margin_top    = 12.0
		s.content_margin_bottom = 12.0
		max_context_slider.add_theme_stylebox_override(key, s)

	# label 文字颜色同步
	max_context_label.add_theme_color_override("font_color", color)

func _on_fill_all() -> void:
	var key := master_key_input.text.strip_edges()
	if key.is_empty():
		return
	chat_key_input.text = key
	opt_key_input.text  = key
	tts_key_input.text  = key

func _on_save() -> void:
	var use_builtin := builtin_key_toggle.button_pressed
	var chat_key := chat_key_input.text.strip_edges()
	if not use_builtin and chat_key.is_empty():
		status_label.text = "⚠ 对话 API Key 不能为空"
		return

	ConfigManager.set_value("use_builtin_key",    use_builtin)
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
	ConfigManager.set_value("auto_play_tts",             auto_play_tts_button.button_pressed)
	ConfigManager.set_value("enable_option_generation", option_gen_button.button_pressed)

	if _is_first_run:
		get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
	else:
		_saved_snapshot = _take_snapshot()
		status_label.text = "✓ 已保存"
		await get_tree().create_timer(3.0).timeout
		status_label.text = ""

func _on_skip() -> void:
	ConfigManager.set_value("use_builtin_key", false)
	ConfigManager.set_value("chat_api_key", "")
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

func _on_back() -> void:
	if _has_unsaved_changes():
		confirm_dialog.show_dialog("放弃未保存的更改？")
		if not confirm_dialog.confirmed.is_connected(_go_back):
			confirm_dialog.confirmed.connect(_go_back, CONNECT_ONE_SHOT)
	else:
		_go_back()

func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

func _take_snapshot() -> Dictionary:
	return {
		"use_builtin": builtin_key_toggle.button_pressed,
		"chat_key":   chat_key_input.text,
		"chat_url":   chat_url_input.text,
		"chat_model": chat_model_input.text,
		"opt_key":    opt_key_input.text,
		"opt_url":    opt_url_input.text,
		"opt_model":  opt_model_input.text,
		"tts_key":    tts_key_input.text,
		"tts_url":    tts_url_input.text,
		"tts_model":  tts_model_input.text,
		"username":   username_input.text,
		"max_ctx":    int(max_context_slider.value),
		"auto_tts":   auto_play_tts_button.button_pressed,
		"option_gen": option_gen_button.button_pressed,
	}

func _has_unsaved_changes() -> bool:
	return _take_snapshot() != _saved_snapshot

func _set_status(msg: String) -> void:
	status_label.text = msg
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if status_label.text == msg:
			status_label.text = ""
	)

func _on_builtin_key_toggled(enabled: bool) -> void:
	# 禁用/启用所有 API 输入框
	var inputs := [
		master_key_input, fill_all_button,
		chat_key_input, chat_url_input, chat_model_input,
		opt_key_input, opt_url_input, opt_model_input,
		tts_key_input, tts_url_input, tts_model_input,
	]
	for node in inputs:
		if node is Button:
			node.disabled = enabled
		elif node is LineEdit:
			node.editable = not enabled
	# 内置密钥时上下文限制为 2000
	if enabled:
		max_context_slider.value = 2000
		max_context_slider.editable = false
	else:
		max_context_slider.editable = true
