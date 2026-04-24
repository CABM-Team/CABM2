## BackgroundManagerController.gd
## 场景管理页面控制器：背景图片列表 + 缩略图缓存

extends Control

const BACKGROUND_THUMB_MAX_EDGE := 360

@onready var back_btn: Button = $VBox/Header/BackButton
@onready var image_tab_btn: Button = $VBox/TabBar/ImageTabButton
@onready var music_tab_btn: Button = $VBox/TabBar/MusicTabButton
@onready var new_background_btn: Button = $VBox/Toolbar/NewBackgroundButton
@onready var background_grid: GridContainer = $VBox/BackgroundScroll/BackgroundGrid

func _ready() -> void:
	back_btn.pressed.connect(_on_back_pressed)
	new_background_btn.pressed.connect(_on_new_background_pressed)
	image_tab_btn.disabled = true
	music_tab_btn.disabled = true
	_refresh_background_grid()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

func _on_new_background_pressed() -> void:
	# 占位按钮，后续再补“新建背景”功能
	pass

func _refresh_background_grid() -> void:
	for child in background_grid.get_children():
		child.queue_free()
	var backgrounds := _load_all_background_entries()
	for entry in backgrounds:
		background_grid.add_child(_create_background_card(entry))

func _load_all_background_entries() -> Array[Dictionary]:
	var merged: Dictionary = {}
	_load_backgrounds_from_source("res://assets/backgrounds.json", "res://assets/backgrounds/", merged)
	_load_backgrounds_from_source("user://backgrounds.json", "user://backgrounds/", merged)

	var list: Array[Dictionary] = []
	for key in merged.keys():
		list.append(merged[key])
	list.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.get("filename", "")) < String(b.get("filename", "")))
	return list

func _load_backgrounds_from_source(config_path: String, image_base: String, out_map: Dictionary) -> void:
	if not FileAccess.file_exists(config_path):
		return
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text().strip_edges()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("背景配置解析失败: " + config_path + " — " + json.get_error_message())
		return

	var root = json.get_data()
	if not (root is Dictionary):
		return
	for filename in root.keys():
		var item = root[filename]
		if not (item is Dictionary):
			continue
		var src_path: String = image_base + filename
		var entry: Dictionary = {
			"filename": String(filename),
			"name": String(item.get("name", filename)),
			"src_path": src_path
		}
		out_map[String(filename)] = entry

func _create_background_card(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 220)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.16, 0.26, 0.82)
	style.border_color = Color(0.32, 0.54, 0.88, 0.65)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(0, 160)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var thumb_path := _ensure_background_thumbnail(
		String(entry.get("filename", "")),
		String(entry.get("src_path", ""))
	)
	thumb.texture = _load_texture_any(thumb_path)
	box.add_child(thumb)

	var name_label := Label.new()
	name_label.text = String(entry.get("name", entry.get("filename", "")))
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(0, 28)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 24)
	box.add_child(name_label)

	return panel

func _ensure_background_thumbnail(filename: String, src_path: String) -> String:
	var cache_dir := "user://background_cache/"
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var thumb_path := cache_dir + filename
	if FileAccess.file_exists(thumb_path):
		return thumb_path

	var image := _load_image_any(src_path)
	if image == null or image.is_empty():
		return src_path

	var width := image.get_width()
	var height := image.get_height()
	var max_edge := maxi(width, height)
	if max_edge > BACKGROUND_THUMB_MAX_EDGE:
		var ratio := float(BACKGROUND_THUMB_MAX_EDGE) / float(max_edge)
		var new_w := maxi(1, int(round(width * ratio)))
		var new_h := maxi(1, int(round(height * ratio)))
		image.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)

	var ext := filename.get_extension().to_lower()
	var save_err := ERR_UNAVAILABLE
	match ext:
		"jpg", "jpeg":
			save_err = image.save_jpg(thumb_path, 0.86)
		"webp":
			save_err = image.save_webp(thumb_path, false, 0.86)
		_:
			save_err = image.save_png(thumb_path)

	if save_err != OK:
		push_warning("缩略图保存失败: " + thumb_path)
		return src_path
	return thumb_path

func _load_image_any(path: String) -> Image:
	var image := Image.new()
	if path.begins_with("user://"):
		if not FileAccess.file_exists(path):
			return null
		if image.load(path) == OK:
			return image
		return null

	if ResourceLoader.exists(path) and image.load(path) == OK:
		return image
	return null

func _load_texture_any(path: String) -> Texture2D:
	if path.begins_with("user://"):
		if not FileAccess.file_exists(path):
			return null
		var image := Image.new()
		if image.load(path) != OK:
			return null
		return ImageTexture.create_from_image(image)

	if ResourceLoader.exists(path):
		return load(path)
	return null
