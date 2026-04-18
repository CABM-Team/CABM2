## CharacterSelectController.gd
## 角色选择页面控制器

extends Control

@onready var character_grid: GridContainer = $VBox/ScrollContainer/CharacterGrid
@onready var settings_button: Button = $VBox/SettingsButton

func _ready() -> void:
	settings_button.pressed.connect(_on_settings_pressed)
	_populate_characters()

func _populate_characters() -> void:
	var characters := CharacterLoader.load_all()
	for char_data in characters:
		var card := _make_character_card(char_data)
		character_grid.add_child(card)

func _make_character_card(char_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 260)

	# 半透明背景样式
	var style := StyleBoxFlat.new()
	var color_str: String = char_data.get("color", "#ffffff")
	var base_color := Color.from_string(color_str, Color.WHITE)
	style.bg_color = Color(base_color.r, base_color.g, base_color.b, 0.15)
	style.border_color = Color(base_color.r, base_color.g, base_color.b, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# 头像
	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(0, 140)
	avatar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var image_dir: String = char_data.get("image", "")
	var avatar_path := image_dir + "/avatar.png"
	if ResourceLoader.exists(avatar_path):
		avatar.texture = load(avatar_path)
	vbox.add_child(avatar)

	# 角色名
	var name_label := Label.new()
	name_label.text = char_data.get("name", char_data.get("id", "???"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color.from_string(color_str, Color.WHITE))
	vbox.add_child(name_label)

	# 简介
	var desc_label := Label.new()
	desc_label.text = char_data.get("description", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_label)

	# 点击整个卡片进入聊天
	var btn := Button.new()
	btn.flat = true
	btn.anchor_right = 1.0
	btn.anchor_bottom = 1.0
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_character_selected.bind(char_data))
	# 透明按钮覆盖在卡片上
	panel.add_child(btn)

	return panel

func _on_character_selected(char_data: Dictionary) -> void:
	AppState.set_character(char_data)
	get_tree().change_scene_to_file("res://scenes/chat/chat.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings/settings.tscn")
