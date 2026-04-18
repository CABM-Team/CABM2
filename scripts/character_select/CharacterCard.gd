## CharacterCard.gd
## 角色卡片，由 CharacterSelectController 实例化后调用 setup()

extends PanelContainer

signal selected(char_data: Dictionary)

@onready var avatar: TextureRect = $HBox/Avatar
@onready var name_label: Label   = $HBox/VBox/NameLabel
@onready var desc_label: Label   = $HBox/VBox/DescLabel
@onready var click_area: Button  = $ClickArea

var _char_data: Dictionary = {}

func _ready() -> void:
	click_area.pressed.connect(func(): selected.emit(_char_data))

func setup(char_data: Dictionary) -> void:
	_char_data = char_data

	var color_str: String = char_data.get("color", "#ffffff")
	var base_color := Color.from_string(color_str, Color.WHITE)

	# 卡片背景样式（按角色主题色）
	var style := StyleBoxFlat.new()
	style.bg_color = Color(base_color.r, base_color.g, base_color.b, 0.15)
	style.border_color = Color(base_color.r, base_color.g, base_color.b, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	# 头像
	var image_dir: String = char_data.get("image", "")
	var extensions = ["png", "jpg", "jpeg", "webp"]
	for ext in extensions:
		var avatar_path = image_dir + "/avatar." + ext
		if ResourceLoader.exists(avatar_path):
			avatar.texture = load(avatar_path)
			break

	# 名字
	name_label.text = char_data.get("name", char_data.get("id", "???"))
	name_label.add_theme_color_override("font_color", base_color)

	# 简介
	desc_label.text = char_data.get("description", "")
