## BackgroundManagerController.gd
## 场景管理页面控制器：背景列表 + 创建/详情统一面板

extends Control

const BACKGROUND_THUMB_MAX_EDGE := 360
const BACKGROUND_CONFIG_RES := "res://assets/backgrounds.json"
const BACKGROUND_CONFIG_USER := "user://backgrounds.json"
const BACKGROUND_RES_DIR := "res://assets/backgrounds/"
const BACKGROUND_USER_DIR := "user://backgrounds/"
const BACKGROUND_CACHE_DIR := "user://background_cache/"
const TEMP_EDIT_DIR := "user://temp/background_edit/"
const CROP_RATIO := 16.0 / 9.0

const ConfirmDialogScene := preload("res://scenes/common/confirm_dialog.tscn")
const CropDialogScene := preload("res://scenes/character_create/crop_dialog.tscn")

@onready var back_btn: Button = $VBox/Header/BackButton
@onready var image_tab_btn: Button = $VBox/TabBar/ImageTabButton
@onready var music_tab_btn: Button = $VBox/TabBar/MusicTabButton
@onready var new_background_btn: Button = $VBox/Toolbar/NewBackgroundButton
@onready var background_grid: GridContainer = $VBox/BackgroundScroll/BackgroundGrid
@onready var file_dialog: FileDialog = $FileDialog

@onready var detail_layer: Control = $DetailLayer
@onready var detail_overlay: ColorRect = $DetailLayer/Overlay
@onready var detail_title: Label = $DetailLayer/Panel/HBoxContainer/RightVBox/Title
@onready var detail_preview: TextureRect = $DetailLayer/Panel/HBoxContainer/LeftVBox/Preview
@onready var detail_upload_btn: Button = $DetailLayer/Panel/HBoxContainer/LeftVBox/UploadButton
@onready var detail_name_input: LineEdit = $DetailLayer/Panel/HBoxContainer/RightVBox/NameRow/NameInput
@onready var detail_desc_input: TextEdit = $DetailLayer/Panel/HBoxContainer/RightVBox/DescBox/DescInput
@onready var detail_prompt_input: TextEdit = $DetailLayer/Panel/HBoxContainer/RightVBox/PromptBox/PromptInput
@onready var detail_back_btn: Button = $DetailLayer/Panel/HBoxContainer/RightVBox/Buttons/BackButton
@onready var detail_delete_btn: Button = $DetailLayer/Panel/HBoxContainer/RightVBox/Buttons/DeleteButton
@onready var detail_confirm_btn: Button = $DetailLayer/Panel/HBoxContainer/RightVBox/Buttons/ConfirmButton

var confirm_dialog: Control = null
var crop_dialog: Control = null

var _confirm_action := &""
var _is_create_mode := true
var _editing_entry: Dictionary = {}
var _initial_form_state: Dictionary = {}
var _selected_upload_path := ""
var _crop_source_path := ""
var _pending_cropped_image: Image = null
var _entries: Array[Dictionary] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(BACKGROUND_USER_DIR)
	DirAccess.make_dir_recursive_absolute(BACKGROUND_CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(TEMP_EDIT_DIR)

	crop_dialog = CropDialogScene.instantiate()
	add_child(crop_dialog)
	confirm_dialog = ConfirmDialogScene.instantiate()
	confirm_dialog.visible = false
	add_child(confirm_dialog)

	back_btn.pressed.connect(_on_back_pressed)
	new_background_btn.pressed.connect(_on_new_background_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	detail_upload_btn.pressed.connect(_on_upload_image_pressed)
	detail_back_btn.pressed.connect(_on_detail_back_pressed)
	detail_confirm_btn.pressed.connect(_on_detail_confirm_pressed)
	detail_delete_btn.pressed.connect(_on_detail_delete_pressed)
	detail_overlay.gui_input.connect(_on_detail_overlay_input)
	crop_dialog.crop_confirmed.connect(_on_crop_confirmed)
	confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)
	confirm_dialog.cancelled.connect(func(): confirm_dialog.hide_dialog())

	image_tab_btn.disabled = true
	music_tab_btn.disabled = true
	detail_layer.visible = false
	_refresh_background_grid()

func _on_back_pressed() -> void:
	if detail_layer.visible:
		_on_detail_back_pressed()
		return
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

func _on_new_background_pressed() -> void:
	_open_detail_panel_create()

func _on_detail_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_detail_back_pressed()

func _refresh_background_grid() -> void:
	for child in background_grid.get_children():
		child.queue_free()
	_entries = _load_all_background_entries()
	for entry in _entries:
		background_grid.add_child(_create_background_card(entry))

func _load_all_background_entries() -> Array[Dictionary]:
	var builtin_root := _load_background_root(BACKGROUND_CONFIG_RES)
	var user_root := _load_background_root(BACKGROUND_CONFIG_USER)

	var merged: Dictionary = {}
	for filename in builtin_root.keys():
		var item: Dictionary = builtin_root[filename]
		merged[String(filename)] = {
			"id": String(item.get("id", String(filename).get_basename())),
			"filename": String(filename),
			"name": String(item.get("name", String(filename).get_basename())),
			"desc": String(item.get("desc", "")),
			"prompt": String(item.get("prompt", "")),
			"src_path": BACKGROUND_RES_DIR + String(filename),
			"is_builtin": true,
			"deletable": false
		}

	for filename in user_root.keys():
		var item: Dictionary = user_root[filename]
		var key := String(filename)
		var user_src := BACKGROUND_USER_DIR + key
		var has_user_image := FileAccess.file_exists(user_src)
		if merged.has(key):
			var base_entry: Dictionary = merged[key]
			base_entry["id"] = String(item.get("id", base_entry.get("id", key.get_basename())))
			base_entry["name"] = String(item.get("name", base_entry.get("name", key.get_basename())))
			base_entry["desc"] = String(item.get("desc", base_entry.get("desc", "")))
			base_entry["prompt"] = String(item.get("prompt", base_entry.get("prompt", "")))
			if has_user_image:
				base_entry["src_path"] = user_src
			merged[key] = base_entry
			continue

		merged[key] = {
			"id": String(item.get("id", key.get_basename())),
			"filename": key,
			"name": String(item.get("name", key.get_basename())),
			"desc": String(item.get("desc", "")),
			"prompt": String(item.get("prompt", "")),
			"src_path": user_src,
			"is_builtin": false,
			"deletable": true
		}

	var list: Array[Dictionary] = []
	for key in merged.keys():
		list.append(merged[key])
	list.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.get("filename", "")) < String(b.get("filename", "")))
	return list

func _load_background_root(config_path: String) -> Dictionary:
	if not FileAccess.file_exists(config_path):
		return {}
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text().strip_edges()
	file.close()
	if text.is_empty():
		return {}

	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("背景配置解析失败: " + config_path + " — " + json.get_error_message())
		return {}
	var root = json.get_data()
	if root is Dictionary:
		return root
	return {}

func _create_background_card(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 220)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

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

	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_open_detail_panel_edit(entry)
	)
	return panel

func _open_detail_panel_create() -> void:
	_is_create_mode = true
	_editing_entry = {}
	_pending_cropped_image = null
	_selected_upload_path = ""
	_crop_source_path = ""

	detail_title.text = "创建背景"
	detail_name_input.text = ""
	detail_desc_input.text = ""
	detail_prompt_input.text = ""
	detail_preview.texture = null
	detail_delete_btn.visible = false
	detail_layer.visible = true

	_initial_form_state = _capture_form_state()

func _open_detail_panel_edit(entry: Dictionary) -> void:
	_is_create_mode = false
	_editing_entry = entry.duplicate(true)
	_pending_cropped_image = null
	_selected_upload_path = ""
	_crop_source_path = ""

	detail_title.text = "背景详情"
	detail_name_input.text = String(entry.get("name", ""))
	detail_desc_input.text = String(entry.get("desc", ""))
	detail_prompt_input.text = String(entry.get("prompt", ""))
	detail_preview.texture = _load_texture_any(String(entry.get("src_path", "")))
	detail_delete_btn.visible = bool(entry.get("deletable", false))
	detail_layer.visible = true

	_initial_form_state = _capture_form_state()

func _capture_form_state() -> Dictionary:
	return {
		"name": detail_name_input.text.strip_edges(),
		"desc": detail_desc_input.text.strip_edges(),
		"prompt": detail_prompt_input.text.strip_edges(),
		"has_pending_image": _pending_cropped_image != null
	}

func _is_detail_dirty() -> bool:
	var current := _capture_form_state()
	return (
		String(current.get("name", "")) != String(_initial_form_state.get("name", "")) or
		String(current.get("desc", "")) != String(_initial_form_state.get("desc", "")) or
		String(current.get("prompt", "")) != String(_initial_form_state.get("prompt", "")) or
		bool(current.get("has_pending_image", false))
	)

func _on_upload_image_pressed() -> void:
	AndroidPermissions.request_for_file_pick(func(granted: bool):
		if not granted:
			push_warning("需要存储权限才能选择背景图片")
			return
		file_dialog.use_native_dialog = true
		file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片文件"])
		file_dialog.popup_centered(Vector2i(1200, 800))
	)

func _on_file_selected(path: String) -> void:
	_selected_upload_path = path
	var ext := path.get_extension().to_lower()
	if ext.is_empty():
		ext = "png"
	var temp_src := TEMP_EDIT_DIR + "upload_src." + ext
	_copy_file(path, temp_src)
	_crop_source_path = temp_src
	crop_dialog.open_image(temp_src, CROP_RATIO)

func _on_crop_confirmed(cropped_image: Image) -> void:
	if not _crop_source_path.is_empty() and FileAccess.file_exists(_crop_source_path):
		DirAccess.remove_absolute(_crop_source_path)
	_crop_source_path = ""
	_pending_cropped_image = cropped_image.duplicate()
	detail_preview.texture = ImageTexture.create_from_image(_pending_cropped_image)

func _on_detail_back_pressed() -> void:
	if not detail_layer.visible:
		return
	if _is_detail_dirty():
		_confirm_action = &"discard"
		confirm_dialog.show_dialog("放弃所有更改？")
		return
	_close_detail_panel()

func _on_detail_confirm_pressed() -> void:
	if detail_name_input.text.strip_edges().is_empty():
		push_warning("背景名字不能为空")
		return
	if _is_create_mode and _pending_cropped_image == null:
		push_warning("请先上传并裁剪背景图片")
		return

	_confirm_action = &"save"
	confirm_dialog.show_dialog("确定保存背景吗？")

func _on_detail_delete_pressed() -> void:
	if not detail_layer.visible:
		return
	if not bool(_editing_entry.get("deletable", false)):
		return
	_confirm_action = &"delete"
	confirm_dialog.show_dialog("确定删除该背景吗？")

func _on_confirm_dialog_confirmed() -> void:
	match _confirm_action:
		&"save":
			_save_detail()
		&"delete":
			_delete_current_entry()
		&"discard":
			_close_detail_panel()
		_:
			pass
	_confirm_action = &""

func _save_detail() -> void:
	var name := detail_name_input.text.strip_edges()
	var desc := detail_desc_input.text.strip_edges()
	var prompt := detail_prompt_input.text.strip_edges()
	var user_root := _load_background_root(BACKGROUND_CONFIG_USER)
	var filename := ""
	var id := ""

	if _is_create_mode:
		id = _generate_background_id(name, desc, prompt, _selected_upload_path)
		filename = id + ".png"
	else:
		filename = String(_editing_entry.get("filename", ""))
		id = String(_editing_entry.get("id", ""))
		if id.is_empty():
			id = _generate_background_id(name, desc, prompt, filename)

	if filename.is_empty():
		push_warning("保存失败：缺少背景文件名")
		return

	if _pending_cropped_image != null:
		var user_image_path := BACKGROUND_USER_DIR + filename
		var save_err := _pending_cropped_image.save_png(user_image_path)
		if save_err != OK:
			push_warning("保存背景图片失败: " + user_image_path)
			return

	user_root[filename] = {
		"id": id,
		"name": name,
		"desc": desc,
		"prompt": prompt
	}
	_save_background_root(BACKGROUND_CONFIG_USER, user_root)

	_rebuild_thumbnail(filename)
	_close_detail_panel()
	_refresh_background_grid()

func _delete_current_entry() -> void:
	var filename := String(_editing_entry.get("filename", ""))
	if filename.is_empty():
		return

	var user_root := _load_background_root(BACKGROUND_CONFIG_USER)
	if user_root.has(filename):
		user_root.erase(filename)
	else:
		var target_id := String(_editing_entry.get("id", ""))
		for key in user_root.keys():
			var item = user_root[key]
			if item is Dictionary and String(item.get("id", "")) == target_id:
				user_root.erase(key)
				filename = String(key)
				break
	_save_background_root(BACKGROUND_CONFIG_USER, user_root)

	var user_image_path := BACKGROUND_USER_DIR + filename
	if FileAccess.file_exists(user_image_path):
		DirAccess.remove_absolute(user_image_path)
	var thumb_path := BACKGROUND_CACHE_DIR + filename
	if FileAccess.file_exists(thumb_path):
		DirAccess.remove_absolute(thumb_path)

	_close_detail_panel()
	_refresh_background_grid()

func _close_detail_panel() -> void:
	detail_layer.visible = false
	_pending_cropped_image = null
	_selected_upload_path = ""
	if not _crop_source_path.is_empty() and FileAccess.file_exists(_crop_source_path):
		DirAccess.remove_absolute(_crop_source_path)
	_crop_source_path = ""

func _generate_background_id(name: String, desc: String, prompt: String, seed: String) -> String:
	var raw := "%s|%s|%s|%s|%d" % [
		name,
		desc,
		prompt,
		seed,
		Time.get_unix_time_from_system()
	]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(raw.to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)

func _save_background_root(config_path: String, root: Dictionary) -> void:
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		push_warning("无法写入背景配置: " + config_path)
		return
	file.store_string(JSON.stringify(root, "\t"))
	file.close()

func _copy_file(src: String, dst: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(src)
	if bytes.is_empty() and not FileAccess.file_exists(src):
		return false
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true

func _rebuild_thumbnail(filename: String) -> void:
	var thumb_path := BACKGROUND_CACHE_DIR + filename
	if FileAccess.file_exists(thumb_path):
		DirAccess.remove_absolute(thumb_path)

func _ensure_background_thumbnail(filename: String, src_path: String) -> String:
	var thumb_path := BACKGROUND_CACHE_DIR + filename
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
