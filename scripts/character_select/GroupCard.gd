## GroupCard.gd
## 群聊卡片，显示群名、成员头像列表

extends PanelContainer

signal selected(group_data: Dictionary)

@onready var name_label: Label = $HBox/VBox/NameLabel
@onready var members_label: Label = $HBox/VBox/MembersLabel
@onready var avatar_row: HBoxContainer = $HBox/AvatarRow
@onready var click_area: Button = $ClickArea

var _group_data: Dictionary = {}

func _ready() -> void:
	click_area.pressed.connect(func(): selected.emit(_group_data))

func setup(group_data: Dictionary, all_characters: Array[Dictionary]) -> void:
	_group_data = group_data

	name_label.text = group_data.get("name", "未命名群聊")

	var ids: Array = group_data.get("character_ids", [])
	members_label.text = "成员：%d 人" % ids.size()

	# 清空旧头像
	for c in avatar_row.get_children():
		c.queue_free()

	# 显示前 5 个成员头像
	var shown := 0
	for char_id in ids:
		if shown >= 5:
			break
		var char_data := _find_char(char_id, all_characters)
		if char_data.is_empty():
			continue
		var tex := _load_avatar(char_data)
		var rect := TextureRect.new()
		rect.custom_minimum_size = Vector2(64, 64)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture = tex
		avatar_row.add_child(rect)
		shown += 1

	# 卡片样式
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.35, 0.6)
	style.border_color = Color(0.5, 0.5, 0.8, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

func _find_char(char_id: String, all_characters: Array[Dictionary]) -> Dictionary:
	for c in all_characters:
		if c.get("id", "") == char_id:
			return c
	return {}

func _load_avatar(char_data: Dictionary) -> Texture2D:
	var image_dir: String = char_data.get("image", "")
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var p: String = image_dir + "/avatar." + ext
		if ResourceLoader.exists(p):
			return load(p)
	return null
