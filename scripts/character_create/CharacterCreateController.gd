## CharacterCreateController.gd
## 创建角色页面控制器
## 实时保存到 user://temp/，完成后写入 user://characters/<id>/

extends Control

const TEMP_DIR := "user://temp/"
const DEST_BASE := "user://characters/"

# 保留关键字（与 CharacterImporter 保持一致）
const RESERVED_IDS := ["user", "group", "groups", "saves", "settings", "system", "admin", "root", "temp"]

# ID 正则：仅字母（区分大小写）、数字、下划线
var _id_regex := RegEx.new()

# 立绘行数据：[{ "name": String, "file": String }]  file 为 temp 路径或空
var _mood_rows: Array[Dictionary] = []

# 头像 temp 路径
var _avatar_temp_path := ""
# 参考音频 temp 路径
var _ref_audio_temp_path := ""
# 当前颜色
var _current_color := Color.WHITE

# 裁剪相关
var _crop_source_path := ""   # 待裁剪的原始图片 temp 路径
var _crop_target_row := -1    # -1 = 头像，>=0 = 立绘行索引

# ── 节点引用 ──────────────────────────────────────────────────
const _ROWS := "Scroll/VBox/FormPanel/FormRows"
@onready var id_input: LineEdit              = $Scroll/VBox/FormPanel/FormRows/RowId/IdInput
@onready var id_error: Label                 = $Scroll/VBox/FormPanel/FormRows/IdError
@onready var name_input: LineEdit            = $Scroll/VBox/FormPanel/FormRows/RowName/NameInput
@onready var name_en_input: LineEdit         = $Scroll/VBox/FormPanel/FormRows/RowNameEn/NameEnInput
@onready var avatar_preview: TextureRect     = $Scroll/VBox/FormPanel/FormRows/RowAvatar/AvatarRow/AvatarPreview
@onready var avatar_btn: Button              = $Scroll/VBox/FormPanel/FormRows/RowAvatar/AvatarRow/AvatarButton
@onready var color_picker: ColorPickerButton = $Scroll/VBox/FormPanel/FormRows/RowColor/ColorPickerButton
@onready var desc_input: TextEdit            = $Scroll/VBox/FormPanel/FormRows/RowDesc/DescInput
@onready var prompt_input: TextEdit          = $Scroll/VBox/FormPanel/FormRows/RowPrompt/PromptInput
@onready var welcome_input: LineEdit         = $Scroll/VBox/FormPanel/FormRows/RowWelcome/WelcomeInput
@onready var mood_table: VBoxContainer       = $Scroll/VBox/FormPanel/FormRows/MoodTable
@onready var add_mood_btn: Button            = $Scroll/VBox/FormPanel/FormRows/AddMoodButton
@onready var calib_input: SpinBox            = $Scroll/VBox/FormPanel/FormRows/RowCalib/CalibInput
@onready var scale_input: SpinBox            = $Scroll/VBox/FormPanel/FormRows/RowScale/ScaleInput
@onready var ref_audio_btn: Button           = $Scroll/VBox/FormPanel/FormRows/RowRefAudio/RefAudioRow/RefAudioButton
@onready var ref_audio_label: Label          = $Scroll/VBox/FormPanel/FormRows/RowRefAudio/RefAudioRow/RefAudioLabel
@onready var ref_text_input: LineEdit        = $Scroll/VBox/FormPanel/FormRows/RowRefText/RefTextInput
@onready var reset_btn: Button               = $Scroll/VBox/BottomBar/ResetButton
@onready var back_btn: Button                = $Scroll/VBox/BottomBar/BackButton
@onready var create_btn: Button              = $Scroll/VBox/BottomBar/CreateButton
@onready var file_dialog: FileDialog         = $FileDialog
@onready var toast_label: Label              = $ToastLabel

var confirm_dialog: Control = null
const ConfirmDialogScene := preload("res://scenes/common/confirm_dialog.tscn")

# 当前确认对话框用途：:reset 或 :create
var _confirm_action := &""

var crop_dialog: Control = null
const CropDialogScene := preload("res://scenes/character_create/crop_dialog.tscn")

# 文件对话框当前用途
var _file_dialog_purpose := ""  # "avatar" | "mood_N" | "ref_audio"

func _ready() -> void:
	_id_regex.compile("^[a-zA-Z0-9_]+$")
	_ensure_temp_dir()
	# 动态实例化对话框
	crop_dialog = CropDialogScene.instantiate()
	add_child(crop_dialog)
	confirm_dialog = ConfirmDialogScene.instantiate()
	confirm_dialog.visible=false
	add_child(confirm_dialog)
	_init_default_moods()
	_connect_signals()
	_load_temp()

func _ensure_temp_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEMP_DIR):
		DirAccess.make_dir_recursive_absolute(TEMP_DIR)

# ── 默认四行立绘 ──────────────────────────────────────────────
func _init_default_moods() -> void:
	_mood_rows.clear()
	for mood_name in ["平静", "开心", "伤心", "生气"]:
		_mood_rows.append({"name": mood_name, "file": ""})
	_rebuild_mood_table()

# ── 信号连接 ──────────────────────────────────────────────────
func _connect_signals() -> void:
	id_input.text_changed.connect(_on_id_changed)
	avatar_btn.pressed.connect(_on_avatar_btn_pressed)
	color_picker.color_changed.connect(_on_color_changed)
	add_mood_btn.pressed.connect(_on_add_mood_pressed)
	ref_audio_btn.pressed.connect(_on_ref_audio_btn_pressed)
	reset_btn.pressed.connect(_on_reset_btn_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	create_btn.pressed.connect(_on_create_btn_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	crop_dialog.crop_confirmed.connect(_on_crop_confirmed)
	confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)
	confirm_dialog.cancelled.connect(func(): confirm_dialog.hide_dialog())

# ── 立绘表格 ──────────────────────────────────────────────────
func _rebuild_mood_table() -> void:
	for child in mood_table.get_children():
		child.queue_free()
	# 表头
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	for col in [["序号", 60], ["表情名", 220], ["立绘", 160], ["操作", 260]]:
		var lbl := Label.new()
		lbl.text = col[0]
		lbl.custom_minimum_size.x = col[1]
		lbl.add_theme_font_size_override("font_size", 22)
		header.add_child(lbl)
	mood_table.add_child(header)
	# 数据行
	for i in _mood_rows.size():
		mood_table.add_child(_make_mood_row(i))

func _make_mood_row(idx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "MoodRow_%d" % idx
	row.add_theme_constant_override("separation", 8)

	# 序号
	var num_lbl := Label.new()
	num_lbl.text = str(idx + 1)
	num_lbl.custom_minimum_size.x = 60
	num_lbl.add_theme_font_size_override("font_size", 22)
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(num_lbl)

	# 表情名输入
	var name_edit := LineEdit.new()
	name_edit.text = _mood_rows[idx]["name"]
	name_edit.custom_minimum_size = Vector2(220, 40)
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.text_changed.connect(func(t): _mood_rows[idx]["name"] = t; _save_temp())
	row.add_child(name_edit)

	# 立绘预览 + 上传按钮
	var img_vbox := VBoxContainer.new()
	img_vbox.custom_minimum_size.x = 160
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.custom_minimum_size = Vector2(80, 80)
	preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var file_path: String = _mood_rows[idx]["file"]
	if not file_path.is_empty() and FileAccess.file_exists(file_path):
		preview.texture = _load_texture(file_path)
	img_vbox.add_child(preview)
	var upload_btn := Button.new()
	upload_btn.text = "上传立绘"
	upload_btn.add_theme_font_size_override("font_size", 20)
	upload_btn.pressed.connect(func(): _on_mood_image_btn_pressed(idx))
	img_vbox.add_child(upload_btn)
	row.add_child(img_vbox)

	# 操作按钮
	var op_box := HBoxContainer.new()
	op_box.add_theme_constant_override("separation", 6)
	var del_btn := Button.new()
	del_btn.text = "删除"
	del_btn.add_theme_font_size_override("font_size", 20)
	del_btn.pressed.connect(func(): _on_mood_delete(idx))
	op_box.add_child(del_btn)
	var up_btn := Button.new()
	up_btn.text = "↑"
	up_btn.add_theme_font_size_override("font_size", 20)
	up_btn.disabled = idx == 0
	up_btn.pressed.connect(func(): _on_mood_move(idx, -1))
	op_box.add_child(up_btn)
	var down_btn := Button.new()
	down_btn.text = "↓"
	down_btn.add_theme_font_size_override("font_size", 20)
	down_btn.disabled = idx == _mood_rows.size() - 1
	down_btn.pressed.connect(func(): _on_mood_move(idx, 1))
	op_box.add_child(down_btn)
	row.add_child(op_box)

	return row

func _on_add_mood_pressed() -> void:
	_mood_rows.append({"name": "", "file": ""})
	_rebuild_mood_table()
	_save_temp()

func _on_mood_delete(idx: int) -> void:
	if _mood_rows.size() <= 1:
		_show_toast("至少保留一行立绘")
		return
	_mood_rows.remove_at(idx)
	_rebuild_mood_table()
	_save_temp()

func _on_mood_move(idx: int, delta: int) -> void:
	var new_idx := idx + delta
	if new_idx < 0 or new_idx >= _mood_rows.size():
		return
	var tmp := _mood_rows[idx]
	_mood_rows[idx] = _mood_rows[new_idx]
	_mood_rows[new_idx] = tmp
	_rebuild_mood_table()
	_save_temp()

# ── 文件选择 ──────────────────────────────────────────────────
func _on_avatar_btn_pressed() -> void:
	AndroidPermissions.request_for_file_pick(func(granted: bool):
		if not granted:
			_show_toast("需要存储权限才能选择文件")
			return
		_file_dialog_purpose = "avatar"
		file_dialog.filters = ["*.png,*.jpg,*.jpeg,*.webp ; 图片文件"]
		file_dialog.use_native_dialog = true
		file_dialog.popup_centered(Vector2i(900, 700))
	)

func _on_mood_image_btn_pressed(idx: int) -> void:
	AndroidPermissions.request_for_file_pick(func(granted: bool):
		if not granted:
			_show_toast("需要存储权限才能选择文件")
			return
		_file_dialog_purpose = "mood_%d" % idx
		file_dialog.filters = ["*.png,*.jpg,*.jpeg,*.webp ; 图片文件"]
		file_dialog.use_native_dialog = true
		file_dialog.popup_centered(Vector2i(900, 700))
	)

func _on_ref_audio_btn_pressed() -> void:
	AndroidPermissions.request_for_file_pick(func(granted: bool):
		if not granted:
			_show_toast("需要存储权限才能选择文件")
			return
		_file_dialog_purpose = "ref_audio"
		file_dialog.filters = ["*.wav,*.mp3,*.ogg ; 音频文件"]
		file_dialog.use_native_dialog = true
		file_dialog.popup_centered(Vector2i(900, 700))
	)

func _on_file_selected(path: String) -> void:
	if _file_dialog_purpose == "avatar":
		_handle_avatar_file(path)
	elif _file_dialog_purpose.begins_with("mood_"):
		var idx := int(_file_dialog_purpose.substr(5))
		_handle_mood_file(path, idx)
	elif _file_dialog_purpose == "ref_audio":
		_handle_ref_audio_file(path)

func _handle_avatar_file(path: String) -> void:
	# 复制到 temp，然后打开裁剪对话框
	var ext := path.get_extension().to_lower()
	var dest := TEMP_DIR + "avatar_src." + ext
	_copy_file(path, dest)
	_crop_source_path = dest
	_crop_target_row = -1
	crop_dialog.open_image(dest, true)  # 头像：强制正方形

func _handle_mood_file(path: String, idx: int) -> void:
	var ext := path.get_extension().to_lower()
	var dest := TEMP_DIR + "mood_%d_src.%s" % [idx, ext]
	_copy_file(path, dest)
	_crop_source_path = dest
	_crop_target_row = idx
	crop_dialog.open_image(dest, false)  # 立绘：默认选中整张图片

func _handle_ref_audio_file(path: String) -> void:
	var ext := path.get_extension().to_lower()
	var dest := TEMP_DIR + "ref." + ext
	_copy_file(path, dest)
	_ref_audio_temp_path = dest
	ref_audio_label.text = path.get_file()
	_save_temp()

# ── 裁剪回调 ──────────────────────────────────────────────────
func _on_crop_confirmed(cropped_image: Image) -> void:
	if _crop_target_row == -1:
		# 头像：缩放到 150x150
		cropped_image.resize(150, 150, Image.INTERPOLATE_LANCZOS)
		var dest := TEMP_DIR + "avatar.png"
		cropped_image.save_png(dest)
		_avatar_temp_path = dest
		avatar_preview.texture = ImageTexture.create_from_image(cropped_image)
	else:
		# 立绘：保持原始裁剪比例，保存为 png
		var dest := TEMP_DIR + "mood_%d.png" % _crop_target_row
		cropped_image.save_png(dest)
		_mood_rows[_crop_target_row]["file"] = dest
		_rebuild_mood_table()
	_save_temp()

# ── 颜色 ──────────────────────────────────────────────────────
func _on_color_changed(color: Color) -> void:
	_current_color = color
	_save_temp()

# ── ID 校验 ───────────────────────────────────────────────────
func _on_id_changed(_text: String) -> void:
	_validate_id()
	_save_temp()

func _validate_id() -> bool:
	var id := id_input.text.strip_edges()
	if id.is_empty():
		id_error.text = "ID 不能为空"
		return false
	if not _id_regex.search(id):
		id_error.text = "ID 只允许字母、数字、下划线"
		return false
	if id in RESERVED_IDS:
		id_error.text = "ID '%s' 是保留关键字" % id
		return false
	# 检查冲突
	for base in ["res://characters/", "user://characters/"]:
		if FileAccess.file_exists(base + id + "/" + id + ".json"):
			id_error.text = "ID '%s' 已存在" % id
			return false
	id_error.text = ""
	return true

# ── 实时保存 temp ─────────────────────────────────────────────
func _save_temp() -> void:
	var data := _collect_form_data()
	var f := FileAccess.open(TEMP_DIR + "draft.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func _load_temp() -> void:
	var path := TEMP_DIR + "draft.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		return
	f.close()
	var data = json.get_data()
	if not data is Dictionary:
		return
	_apply_form_data(data)

func _apply_form_data(data: Dictionary) -> void:
	id_input.text = data.get("id", "")
	name_input.text = data.get("name", "")
	name_en_input.text = data.get("name_en", "")
	desc_input.text = data.get("description", "")
	prompt_input.text = data.get("prompt", "")
	welcome_input.text = data.get("welcome", "")
	calib_input.value = float(data.get("calib", 0))
	scale_input.value = float(data.get("scale_rate", 100))

	var color_str: String = data.get("color", "#ffffff")
	_current_color = Color.from_string(color_str, Color.WHITE)
	color_picker.color = _current_color

	_avatar_temp_path = data.get("_avatar_temp", "")
	if not _avatar_temp_path.is_empty() and FileAccess.file_exists(_avatar_temp_path):
		avatar_preview.texture = _load_texture(_avatar_temp_path)

	_ref_audio_temp_path = data.get("_ref_audio_temp", "")
	if not _ref_audio_temp_path.is_empty():
		ref_audio_label.text = _ref_audio_temp_path.get_file()

	var moods_raw = data.get("_mood_rows", [])
	if moods_raw is Array and not moods_raw.is_empty():
		_mood_rows.clear()
		for m in moods_raw:
			_mood_rows.append({"name": m.get("name", ""), "file": m.get("file", "")})
		_rebuild_mood_table()

func _collect_form_data() -> Dictionary:
	var moods_export: Array = []
	for m in _mood_rows:
		moods_export.append({"name": m["name"], "file": m["file"]})
	return {
		"id": id_input.text.strip_edges(),
		"name": name_input.text.strip_edges(),
		"name_en": name_en_input.text.strip_edges(),
		"color": "#" + _current_color.to_html(false),
		"description": desc_input.text.strip_edges(),
		"prompt": prompt_input.text.strip_edges(),
		"welcome": welcome_input.text.strip_edges(),
		"calib": int(calib_input.value),
		"scale_rate": int(scale_input.value),
		"_avatar_temp": _avatar_temp_path,
		"_ref_audio_temp": _ref_audio_temp_path,
		"_mood_rows": moods_export,
	}

# ── 重置 ──────────────────────────────────────────────────────
func _on_reset_btn_pressed() -> void:
	_confirm_action = &"reset"
	confirm_dialog.show_dialog("确定要重置所有内容吗？")

# ── 返回 ──────────────────────────────────────────────────────
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

# ── 创建 ──────────────────────────────────────────────────────
func _on_create_btn_pressed() -> void:
	if not _validate_all():
		return
	_confirm_action = &"create"
	confirm_dialog.show_dialog("确定要创建角色吗？")

func _on_confirm_dialog_confirmed() -> void:
	match _confirm_action:
		&"reset":
			_do_reset()
		&"create":
			_do_create()

func _do_reset() -> void:
	id_input.text = ""
	id_error.text = ""
	name_input.text = ""
	name_en_input.text = ""
	desc_input.text = ""
	prompt_input.text = ""
	welcome_input.text = ""
	calib_input.value = 0
	scale_input.value = 100
	_current_color = Color.WHITE
	color_picker.color = Color.WHITE
	_avatar_temp_path = ""
	_ref_audio_temp_path = ""
	avatar_preview.texture = null
	ref_audio_label.text = "未选择"
	_init_default_moods()
	if FileAccess.file_exists(TEMP_DIR + "draft.json"):
		DirAccess.remove_absolute(TEMP_DIR + "draft.json")

func _validate_all() -> bool:
	if not _validate_id():
		_show_toast("请检查角色 ID")
		return false
	if name_input.text.strip_edges().is_empty():
		_show_toast("角色名不能为空")
		return false
	if _avatar_temp_path.is_empty() or not FileAccess.file_exists(_avatar_temp_path):
		_show_toast("请上传头像")
		return false
	if desc_input.text.strip_edges().is_empty():
		_show_toast("描述不能为空")
		return false
	if prompt_input.text.strip_edges().is_empty():
		_show_toast("基础提示词不能为空")
		return false
	if welcome_input.text.strip_edges().is_empty():
		_show_toast("欢迎词不能为空")
		return false
	if _mood_rows.is_empty():
		_show_toast("至少需要一行立绘")
		return false
	if not _ref_audio_temp_path.is_empty() and ref_text_input.text.strip_edges().is_empty():
		_show_toast("上传了参考音频，请填写参考音频文本")
		return false
	return true

func _do_create() -> void:
	var char_id: String = id_input.text.strip_edges()
	var dest_dir := DEST_BASE + char_id + "/"
	DirAccess.make_dir_recursive_absolute(dest_dir)

	# 复制头像
	_copy_file(_avatar_temp_path, dest_dir + "avatar.png")

	# 复制立绘（按序号命名 1.png, 2.png ...）
	var mood_names: Array = []
	for i in _mood_rows.size():
		var row: Dictionary = _mood_rows[i]
		mood_names.append(row["name"])
		if not row["file"].is_empty() and FileAccess.file_exists(row["file"]):
			_copy_file(row["file"], dest_dir + "%d.png" % (i + 1))

	# 复制参考音频
	if not _ref_audio_temp_path.is_empty() and FileAccess.file_exists(_ref_audio_temp_path):
		var ext := _ref_audio_temp_path.get_extension()
		_copy_file(_ref_audio_temp_path, dest_dir + "ref." + ext)
		# 写参考文本
		var ref_text := ref_text_input.text.strip_edges()
		if not ref_text.is_empty():
			var tf := FileAccess.open(dest_dir + "ref.txt", FileAccess.WRITE)
			if tf:
				tf.store_string(ref_text)
				tf.close()

	# 写 JSON
	var json_data := {
		"id": char_id,
		"name": name_input.text.strip_edges(),
		"name_en": name_en_input.text.strip_edges(),
		"color": "#" + _current_color.to_html(false),
		"description": desc_input.text.strip_edges(),
		"prompt": prompt_input.text.strip_edges(),
		"welcome": welcome_input.text.strip_edges(),
		"calib": int(calib_input.value),
		"scale_rate": int(scale_input.value),
		"moods": mood_names,
	}
	var jf := FileAccess.open(dest_dir + char_id + ".json", FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(json_data, "\t"))
		jf.close()

	# 清除 temp draft
	if FileAccess.file_exists(TEMP_DIR + "draft.json"):
		DirAccess.remove_absolute(TEMP_DIR + "draft.json")

	_show_toast("角色创建成功！")
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

# ── 工具函数 ──────────────────────────────────────────────────
func _copy_file(src: String, dst: String) -> void:
	var data := FileAccess.get_file_as_bytes(src)
	if data.is_empty():
		push_warning("CharacterCreate: 无法读取文件 " + src)
		return
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f:
		f.store_buffer(data)
		f.close()

func _load_texture(path: String) -> ImageTexture:
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)

func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.visible = true
	await get_tree().create_timer(2.5).timeout
	toast_label.visible = false
