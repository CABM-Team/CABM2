## CharacterCreateController.gd
## 创建角色页面控制器
## 实时暂存到 user://temp/draft/（标准角色目录结构），确认创建时直接重命名文件夹

extends Control

# 暂存目录：与标准角色目录结构完全一致，创建时直接 rename
const DRAFT_DIR := "user://temp/"
const DEST_BASE := "user://characters/"

# 保留关键字（与 CharacterImporter 保持一致）
const RESERVED_IDS := ["user", "group", "groups", "saves", "settings", "system", "admin", "root", "temp"]

# ID 正则：仅字母（区分大小写）、数字、下划线
var _id_regex := RegEx.new()

# 立绘行数据：[{ "name": String, "file": String }]  file 为 draft 目录内路径或空
var _mood_rows: Array[Dictionary] = []

# 当前颜色
var _current_color := Color.WHITE

# 裁剪相关
var _crop_source_path := ""   # 待裁剪的原始图片路径
var _crop_target_row := -1    # -1 = 头像，>=0 = 立绘行索引

# ── 节点引用 ──────────────────────────────────────────────────
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
@onready var back_btn: Button                = $BackButton
@onready var create_btn: Button              = $Scroll/VBox/BottomBar/CreateButton
@onready var file_dialog: FileDialog         = $FileDialog
@onready var toast_label: Label              = $ToastLabel

var confirm_dialog: Control = null
const ConfirmDialogScene := preload("res://scenes/common/confirm_dialog.tscn")

var _confirm_action := &""

var crop_dialog: Control = null
const CropDialogScene := preload("res://scenes/character_create/crop_dialog.tscn")

var _file_dialog_purpose := ""  # "avatar" | "mood_N" | "ref_audio"

func _ready() -> void:
	_id_regex.compile("^[a-zA-Z0-9_]+$")
	DirAccess.make_dir_recursive_absolute(DRAFT_DIR)
	crop_dialog = CropDialogScene.instantiate()
	add_child(crop_dialog)
	confirm_dialog = ConfirmDialogScene.instantiate()
	confirm_dialog.visible = false
	add_child(confirm_dialog)
	_init_default_moods()
	_connect_signals()
	_load_draft()

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
	ref_text_input.text_changed.connect(_on_ref_text_changed)
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
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	for col in [["  序号", 150], ["表情名", 260], ["立绘", 240], ["操作", 120]]:
		var lbl := Label.new()
		lbl.text = col[0]
		lbl.custom_minimum_size.x = col[1]
		lbl.add_theme_font_size_override("font_size", 22)
		header.add_child(lbl)
	mood_table.add_child(header)
	for i in _mood_rows.size():
		mood_table.add_child(_make_mood_row(i))

func _make_mood_row(idx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "MoodRow_%d" % idx
	row.add_theme_constant_override("separation", 30)

	var num_lbl := Label.new()
	num_lbl.text = str(idx + 1)
	num_lbl.custom_minimum_size.x = 60
	num_lbl.add_theme_font_size_override("font_size", 22)
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(num_lbl)

	var name_edit := LineEdit.new()
	name_edit.text = _mood_rows[idx]["name"]
	name_edit.custom_minimum_size = Vector2(220, 40)
	name_edit.add_theme_font_size_override("font_size", 32)
	name_edit.text_changed.connect(func(t): _mood_rows[idx]["name"] = t; _save_draft_json())
	row.add_child(name_edit)

	var img_hbox := HBoxContainer.new()
	img_hbox.custom_minimum_size.x = 160
	img_hbox.add_theme_constant_override("separation", 8)
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.custom_minimum_size = Vector2(120, 80)
	preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var file_path: String = _mood_rows[idx]["file"]
	if not file_path.is_empty() and FileAccess.file_exists(file_path):
		preview.texture = _load_texture(file_path)
	img_hbox.add_child(preview)
	var upload_btn := Button.new()
	upload_btn.text = "上传立绘"
	upload_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	upload_btn.add_theme_font_size_override("font_size", 26)
	upload_btn.pressed.connect(func(): _on_mood_image_btn_pressed(idx))
	img_hbox.add_child(upload_btn)
	row.add_child(img_hbox)

	row.add_child(VSeparator.new())
	var op_box := HBoxContainer.new()
	op_box.add_theme_constant_override("separation", 6)
	var del_btn := Button.new()
	del_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	del_btn.text = "删除"
	del_btn.add_theme_font_size_override("font_size", 26)
	del_btn.pressed.connect(func(): _on_mood_delete(idx))
	op_box.add_child(del_btn)
	row.add_child(op_box)

	return row

func _on_add_mood_pressed() -> void:
	_mood_rows.append({"name": "", "file": ""})
	_rebuild_mood_table()
	_save_draft_json()

func _on_mood_delete(idx: int) -> void:
	if _mood_rows.size() <= 1:
		_show_toast("至少保留一行立绘")
		return
	# 删除该行的图片文件
	var del_path := DRAFT_DIR + "%d.png" % (idx + 1)
	if FileAccess.file_exists(del_path):
		DirAccess.open(DRAFT_DIR).remove("%d.png" % (idx + 1))
	_mood_rows.remove_at(idx)
	# 把后续图片依次前移重命名（idx+2 -> idx+1, idx+3 -> idx+2, ...）
	var dir := DirAccess.open(DRAFT_DIR)
	for i in range(idx + 1, _mood_rows.size() + 1):
		var old_name := "%d.png" % (i + 1)
		var new_name := "%d.png" % i
		if FileAccess.file_exists(DRAFT_DIR + old_name):
			dir.rename(old_name, new_name)
		# 更新内存中的路径
		_mood_rows[i - 1]["file"] = DRAFT_DIR + new_name if FileAccess.file_exists(DRAFT_DIR + new_name) else ""
	_rebuild_mood_table()
	_save_draft_json()

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
	var ext := path.get_extension().to_lower()
	var src := DRAFT_DIR + "avatar_src." + ext
	_copy_file(path, src)
	_crop_source_path = src
	_crop_target_row = -1
	crop_dialog.open_image(src, true)

func _handle_mood_file(path: String, idx: int) -> void:
	var ext := path.get_extension().to_lower()
	var src := DRAFT_DIR + "mood_%d_src.%s" % [idx, ext]
	_copy_file(path, src)
	_crop_source_path = src
	_crop_target_row = idx
	crop_dialog.open_image(src, false)

func _handle_ref_audio_file(path: String) -> void:
	var ext := path.get_extension().to_lower()
	# 清理旧的参考音频文件
	var dir := DirAccess.open(DRAFT_DIR)
	if dir:
		for f in ["ref.wav", "ref.mp3", "ref.ogg"]:
			if FileAccess.file_exists(DRAFT_DIR + f):
				dir.remove(f)
	var dest := DRAFT_DIR + "ref." + ext
	_copy_file(path, dest)
	ref_audio_label.text = path.get_file()
	_save_draft_json()

# ── 裁剪回调 ──────────────────────────────────────────────────
func _on_crop_confirmed(cropped_image: Image) -> void:
	# 删除原始临时文件
	if not _crop_source_path.is_empty() and FileAccess.file_exists(_crop_source_path):
		DirAccess.open(_crop_source_path.get_base_dir()).remove(_crop_source_path.get_file())
	_crop_source_path = ""

	if _crop_target_row == -1:
		cropped_image.resize(150, 150, Image.INTERPOLATE_LANCZOS)
		cropped_image.save_png(DRAFT_DIR + "avatar.png")
		avatar_preview.texture = ImageTexture.create_from_image(cropped_image)
	else:
		cropped_image.save_png(DRAFT_DIR + "%d.png" % (_crop_target_row + 1))
		_mood_rows[_crop_target_row]["file"] = DRAFT_DIR + "%d.png" % (_crop_target_row + 1)
		_rebuild_mood_table()
	_save_draft_json()

# ── 颜色 ──────────────────────────────────────────────────────
func _on_color_changed(color: Color) -> void:
	_current_color = color
	_save_draft_json()

# ── 参考文本 ──────────────────────────────────────────────────
func _on_ref_text_changed(text: String) -> void:
	var f := FileAccess.open(DRAFT_DIR + "ref.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()

# ── ID 校验 ───────────────────────────────────────────────────
func _on_id_changed(_text: String) -> void:
	_validate_id()
	_save_draft_json()

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
	for base in ["res://characters/", "user://characters/"]:
		if FileAccess.file_exists(base + id + "/" + id + ".json"):
			id_error.text = "ID '%s' 已存在" % id
			return false
	id_error.text = ""
	return true

# ── 暂存（只写 JSON，文件已在 draft 目录） ────────────────────
func _save_draft_json() -> void:
	var char_id := id_input.text.strip_edges()
	var mood_names: Array = []
	for m in _mood_rows:
		mood_names.append(m["name"])
	var data := {
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
	# 用占位 id "draft" 作为文件名，创建时再重命名
	var f := FileAccess.open(DRAFT_DIR + "draft.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func _load_draft() -> void:
	var path := DRAFT_DIR + "draft.json"
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

	# 恢复头像预览
	if FileAccess.file_exists(DRAFT_DIR + "avatar.png"):
		avatar_preview.texture = _load_texture(DRAFT_DIR + "avatar.png")

	# 恢复参考音频标签
	for ext: String in ["wav", "mp3", "ogg"]:
		var ap: String = DRAFT_DIR + "ref." + ext
		if FileAccess.file_exists(ap):
			ref_audio_label.text = "ref." + ext
			break

	# 恢复参考文本
	var ref_txt_path := DRAFT_DIR + "ref.txt"
	if FileAccess.file_exists(ref_txt_path):
		var rf := FileAccess.open(ref_txt_path, FileAccess.READ)
		if rf:
			ref_text_input.text = rf.get_as_text()
			rf.close()


	# 恢复立绘行
	var moods_raw = data.get("moods", [])
	if moods_raw is Array and not moods_raw.is_empty():
		_mood_rows.clear()
		for i in moods_raw.size():
			var mood_file := DRAFT_DIR + "%d.png" % (i + 1)
			_mood_rows.append({
				"name": moods_raw[i] if moods_raw[i] is String else "",
				"file": mood_file if FileAccess.file_exists(mood_file) else ""
			})
		_rebuild_mood_table()

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
	_do_create()

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
	avatar_preview.texture = null
	ref_audio_label.text = "未选择"
	_init_default_moods()
	# 清空 draft 目录
	var dir := DirAccess.open(DRAFT_DIR)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				dir.remove(entry)
			entry = dir.get_next()

func _validate_all() -> bool:
	if not _validate_id():
		_show_toast("请检查角色 ID")
		return false
	if name_input.text.strip_edges().is_empty():
		_show_toast("角色名不能为空")
		return false
	if not FileAccess.file_exists(DRAFT_DIR + "avatar.png"):
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
	var has_ref_audio := false
	for ext in ["wav", "mp3", "ogg"]:
		if FileAccess.file_exists(DRAFT_DIR + "ref." + ext):
			has_ref_audio = true
			break
	if has_ref_audio and ref_text_input.text.strip_edges().is_empty():
		_show_toast("上传了参考音频，请填写参考音频文本")
		return false
	return true

func _do_create() -> void:
	var char_id: String = id_input.text.strip_edges()

	# 写最终 JSON（用真实 id 命名）
	var mood_names: Array = []
	for m in _mood_rows:
		mood_names.append(m["name"])
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
	var jf := FileAccess.open(DRAFT_DIR + char_id + ".json", FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(json_data, "\t"))
		jf.close()

	# 删除临时占位文件
	if FileAccess.file_exists(DRAFT_DIR + "draft.json"):
		DirAccess.open(DRAFT_DIR).remove("draft.json")

	# 确保目标父目录存在
	DirAccess.make_dir_recursive_absolute(DEST_BASE)

	# 直接重命名 draft 目录为最终角色目录
	var dest_dir := DEST_BASE + char_id
	# DRAFT_DIR 末尾有 /，去掉再 rename
	var draft_path := DRAFT_DIR.trim_suffix("/")
	var err := DirAccess.rename_absolute(draft_path, dest_dir)
	if err != OK:
		_show_toast("创建失败，无法移动文件夹（错误 %d）" % err)
		return

	# 重建 draft 目录供下次使用
	DirAccess.make_dir_recursive_absolute(DRAFT_DIR)

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
