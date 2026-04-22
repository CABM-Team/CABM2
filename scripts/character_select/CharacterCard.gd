## CharacterCard.gd
## 角色卡片，由 CharacterSelectController 实例化后调用 setup()

extends PanelContainer

signal selected(char_data: Dictionary)

@onready var avatar: TextureRect = $HBox/Avatar
@onready var name_label: Label   = $HBox/VBox/NameLabel
@onready var desc_label: Label   = $HBox/VBox/DescLabel
@onready var last_message_label: Label = $HBox/VBox/LastMessageLabel
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
	#style.bg_color = Color(base_color.r, base_color.g, base_color.b, 0.15)
	style.bg_color = Color(0.2, 0.2, 0.3, 0.7)
	style.border_color = Color(base_color.r, base_color.g, base_color.b, 0.7)
	style.set_border_width_all(4)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	# 头像：按 ID 查找，先 user:// 后 res://
	var char_id: String = char_data.get("id", "")
	var extensions = ["png", "jpg", "jpeg", "webp"]
	var avatar_loaded := false
	for base in ["user://characters/", "res://characters/"]:
		if avatar_loaded:
			break
		for ext in extensions:
			var avatar_path: String = base + char_id + "/avatar." + ext
			var tex := _load_image_texture(avatar_path)
			if tex:
				avatar.texture = tex
				avatar_loaded = true
				break

	# 名字
	name_label.text = char_data.get("name", char_data.get("id", "???"))
	name_label.add_theme_color_override("font_color", base_color)

	# 简介
	desc_label.text = char_data.get("description", "")

	# 加载最近一次对话
	_load_last_message(char_data)

## 加载并显示最近一次对话
func _load_last_message(char_data: Dictionary) -> void:
	var character_id: String = char_data.get("id", char_data.get("name", ""))
	if character_id.is_empty():
		last_message_label.text = "暂无对话记录"
		return
	
	var history: Array = HistoryManager.load_history(character_id).get("history", [])
	if history.is_empty():
		last_message_label.text = "暂无对话记录"
		return
	
	# 找到最后一条消息（优先显示 assistant 的回复）
	var last_msg := ""
	var last_role := ""
	
	for i in range(history.size() - 1, -1, -1):
		var msg: Dictionary = history[i]
		var role: String = msg.get("role", "")
		var content: String = msg.get("content", "")
		
		if role == "assistant":
			last_msg = content
			last_role = "assistant"
			break
		elif role == "user" and last_msg.is_empty():
			last_msg = content
			last_role = "user"
	if last_msg.is_empty():
		last_message_label.text = "暂无对话记录"
	else:
		var prefix := "" #"你: " if last_role == "user" else "TA: "
		# 如果是 assistant 消息，从 JSON 中提取 msg 字段
		var display_text := last_msg
		if last_role == "assistant":
			display_text = _extract_msg_from_json(last_msg)
		# 限制显示长度，避免过长
		# if display_text.length() > 60:
		# 	display_text = display_text.substr(0, 60) + "..."
		last_message_label.text = prefix + display_text

## 从 JSON 字符串中提取 msg 字段
func _extract_msg_from_json(json_str: String) -> String:
	var json := JSON.new()
	if json.parse(json_str) == OK:
		var data: Dictionary = json.get_data()
		return data.get("msg", json_str)
	return json_str

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
