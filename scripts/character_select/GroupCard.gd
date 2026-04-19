## GroupCard.gd
## 群聊卡片，显示群名、成员头像列表
##
## 头像拼图规则（保持正方形，容器 80×80）：
##   1 人：整块
##   2 人：左右各 1/2
##   3 人：左 1/2，右侧上下各 1/4（即右列两个 1/4）
##   4 人：田字形，各 1/4
##   5 人以上：只取前 4 人，田字形

extends PanelContainer

signal selected(group_data: Dictionary)

@onready var name_label: Label    = $HBox/VBox/NameLabel
@onready var members_label: Label = $HBox/VBox/MembersLabel
@onready var desc_label: Label    = $HBox/VBox/DescLabel
@onready var avatar_row: Control  = $HBox/AvatarRow
@onready var click_area: Button   = $ClickArea

const AVATAR_SIZE := 150.0  # 容器边长（与场景 custom_minimum_size 一致）

var _group_data: Dictionary = {}

func _ready() -> void:
	click_area.pressed.connect(func(): selected.emit(_group_data))

func setup(group_data: Dictionary, all_characters: Array[Dictionary]) -> void:
	_group_data = group_data

	name_label.text = group_data.get("name", "未命名群聊")

	var ids: Array = group_data.get("character_ids", [])
	members_label.text = "成员：%d 人" % ids.size()

	var des: String = group_data.get("des", "")
	desc_label.text = des
	desc_label.visible = not des.is_empty()

	# 清空旧头像
	for c in avatar_row.get_children():
		c.queue_free()

	# 收集最多 4 个头像纹理
	var textures: Array[Texture2D] = []
	for char_id in ids:
		if textures.size() >= 4:
			break
		var char_data := _find_char(char_id, all_characters)
		if char_data.is_empty():
			continue
		var tex := _load_avatar(char_data)
		textures.append(tex)  # tex 可能为 null，占位用

	_build_avatar_layout(textures)

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

## 根据头像数量构建布局，所有 rect 坐标均相对于 avatar_row
func _build_avatar_layout(textures: Array[Texture2D]) -> void:
	var n := textures.size()
	var s := AVATAR_SIZE
	var h := s * 0.5  # 半格

	# rects: Array of {tex, x, y, w, h}
	var rects: Array[Dictionary] = []

	match n:
		0:
			pass
		1:
			rects.append({tex=textures[0], x=0.0, y=0.0, w=s, h=s})
		2:
			rects.append({tex=textures[0], x=0.0,  y=0.0, w=h, h=s})
			rects.append({tex=textures[1], x=h,    y=0.0, w=h, h=s})
		3:
			rects.append({tex=textures[0], x=0.0,  y=0.0, w=h, h=s})
			rects.append({tex=textures[1], x=h,    y=0.0, w=h, h=h})
			rects.append({tex=textures[2], x=h,    y=h,   w=h, h=h})
		_:  # 4+
			rects.append({tex=textures[0], x=0.0,  y=0.0, w=h, h=h})
			rects.append({tex=textures[1], x=h,    y=0.0, w=h, h=h})
			rects.append({tex=textures[2], x=0.0,  y=h,   w=h, h=h})
			rects.append({tex=textures[3], x=h,    y=h,   w=h, h=h})

	for r in rects:
		var rect := TextureRect.new()
		rect.texture = r.tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.position = Vector2(r.x, r.y)
		rect.size = Vector2(r.w, r.h)
		avatar_row.add_child(rect)

func _find_char(char_id: String, all_characters: Array[Dictionary]) -> Dictionary:
	for c in all_characters:
		if c.get("id", "") == char_id:
			return c
	return {}

func _load_avatar(char_data: Dictionary) -> Texture2D:
	var char_id: String = char_data.get("id", "")
	for base in ["user://characters/", "res://characters/"]:
		for ext in ["png", "jpg", "jpeg", "webp"]:
			var p: String = base + char_id + "/avatar." + ext
			var tex := _load_image_texture(p)
			if tex:
				return tex
	return null

## 兼容 user:// 运行时写入文件的图片加载（绕过 ResourceLoader 缓存）
static func _load_image_texture(path: String) -> ImageTexture:
	if path.begins_with("user://"):
		if not FileAccess.file_exists(path):
			return null
		var img := Image.new()
		if img.load(path) != OK:
			return null
		return ImageTexture.create_from_image(img)
	else:
		if ResourceLoader.exists(path):
			return load(path)
		return null
