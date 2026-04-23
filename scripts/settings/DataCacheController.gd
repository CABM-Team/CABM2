## DataCacheController.gd
## 数据与缓存选项卡控制器

extends Control

# ── 语音缓存 ──
@onready var btn_del_all:    Button = $ScrollContainer/VBox/SectionSpeech/BtnRow/BtnDelAll
@onready var btn_del_7d:     Button = $ScrollContainer/VBox/SectionSpeech/BtnRow/BtnDel7d
@onready var btn_del_1m:     Button = $ScrollContainer/VBox/SectionSpeech/BtnRow/BtnDel1m

# ── 音色URI ──
@onready var btn_clear_uri:  Button = $ScrollContainer/VBox/SectionVoiceUri/BtnClearUri

# ── 导出日志 ──
@onready var btn_export_log: Button = $ScrollContainer/VBox/SectionLog/BtnExportLog

# ── 导出角色 ──
@onready var char_list:      GridContainer = $ScrollContainer/VBox/SectionChar/CharList
@onready var btn_export_char:Button = $ScrollContainer/VBox/SectionChar/BtnExportChar

# 由父节点 SettingsController 注入
var confirm_dialog: Control = null

const SPEECH_CACHE_DIR := "user://speech_cache"
const VOICE_URL_PATH   := "user://voice_uri.json"
const LOG_DIR          := "user://logs"

# 当前待执行的删除操作
var _pending_action: Callable = func(): pass

func _ready() -> void:
	btn_del_all.pressed.connect(_ask_delete_speech.bind("all"))
	btn_del_7d.pressed.connect(_ask_delete_speech.bind("7d"))
	btn_del_1m.pressed.connect(_ask_delete_speech.bind("1m"))
	btn_clear_uri.pressed.connect(_ask_clear_uri)
	btn_export_log.pressed.connect(_export_logs)
	btn_export_char.pressed.connect(_export_characters)
	_refresh_speech_sizes()
	_populate_char_list()

# ════════════════════════════════════════════════
# 语音缓存
# ════════════════════════════════════════════════

func _refresh_speech_sizes() -> void:
	var now := Time.get_unix_time_from_system()
	var all_size := _calc_speech_size(0)
	var size_7d  := _calc_speech_size(now - 7 * 86400)
	var size_1m  := _calc_speech_size(now - 30 * 86400)
	btn_del_all.text = "🗑 删除全部（%s）" % _fmt_size(all_size)
	btn_del_7d.text  = "🗑 删除7天前（%s）" % _fmt_size(size_7d)
	btn_del_1m.text  = "🗑 删除一个月前（%s）" % _fmt_size(size_1m)

## 计算 speech_cache 中修改时间早于 before_unix 的文件总大小
## before_unix == 0 表示全部
func _calc_speech_size(before_unix: float) -> int:
	var dir := DirAccess.open(SPEECH_CACHE_DIR)
	if dir == null:
		return 0
	var total := 0
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var path := SPEECH_CACHE_DIR + "/" + f
			if before_unix == 0 or FileAccess.get_modified_time(path) < before_unix:
				total += FileAccess.get_file_as_bytes(path).size()
		f = dir.get_next()
	return total

func _ask_delete_speech(mode: String) -> void:
	if confirm_dialog == null:
		return
	var label := {"all": "删除全部语音缓存？", "7d": "删除7天前的语音缓存？", "1m": "删除一个月前的语音缓存？"}
	_pending_action = func(): _do_delete_speech(mode)
	confirm_dialog.show_dialog(label[mode])
	if not confirm_dialog.confirmed.is_connected(_on_confirmed):
		confirm_dialog.confirmed.connect(_on_confirmed, CONNECT_ONE_SHOT)

func _do_delete_speech(mode: String) -> void:
	var now := Time.get_unix_time_from_system()
	var before: float = 0.0
	if mode == "7d":
		before = now - 7 * 86400
	elif mode == "1m":
		before = now - 30 * 86400

	var dir := DirAccess.open(SPEECH_CACHE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var path := SPEECH_CACHE_DIR + "/" + f
			if before == 0.0 or FileAccess.get_modified_time(path) < before:
				dir.remove(f)
		f = dir.get_next()
	_refresh_speech_sizes()

# ════════════════════════════════════════════════
# 音色 URI
# ════════════════════════════════════════════════

func _ask_clear_uri() -> void:
	if confirm_dialog == null:
		return
	_pending_action = func(): _do_clear_uri()
	confirm_dialog.show_dialog("清除音色URI缓存？\n下次使用时将重新上传参考音频。")
	if not confirm_dialog.confirmed.is_connected(_on_confirmed):
		confirm_dialog.confirmed.connect(_on_confirmed, CONNECT_ONE_SHOT)

func _do_clear_uri() -> void:
	if FileAccess.file_exists(VOICE_URL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(VOICE_URL_PATH))

# ════════════════════════════════════════════════
# 导出日志
# ════════════════════════════════════════════════

func _export_logs() -> void:
	var zip_data := _zip_directory(LOG_DIR)
	if zip_data.is_empty():
		_show_status("⚠ 没有找到日志文件")
		return
	_save_file_to_downloads("logs.zip", zip_data)

# ════════════════════════════════════════════════
# 导出角色
# ════════════════════════════════════════════════

func _populate_char_list() -> void:
	for c in char_list.get_children():
		c.queue_free()
	var characters := CharacterLoader.load_all()
	for ch in characters:
		var cid: String       = ch.get("id", "")
		var name_: String     = ch.get("name", cid)
		var color_str: String = ch.get("color", "#ffffff")
		if cid.is_empty():
			continue
		# 只显示 user:// 下存在的角色，跳过纯内置角色
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://characters/" + cid)):
			continue
		var cb := CheckBox.new()
		cb.text = name_
		cb.name = cid
		cb.add_theme_font_size_override("font_size", 35)
		var col := Color.from_string(color_str, Color.WHITE)
		cb.add_theme_color_override("font_color",               col)
		cb.add_theme_color_override("font_hover_color",         col.lightened(0.2))
		cb.add_theme_color_override("font_pressed_color",       col)
		cb.add_theme_color_override("font_hover_pressed_color", col.lightened(0.2))
		cb.add_theme_color_override("font_focus_color",         col)
		char_list.add_child(cb)

func _export_characters() -> void:
	var selected: Array[String] = []
	for cb in char_list.get_children():
		if cb is CheckBox and cb.button_pressed:
			selected.append(cb.name)
	if selected.is_empty():
		_show_status("⚠ 请先选择要导出的角色")
		return

	var zip_writer := ZIPPacker.new()
	var tmp_path := "user://export_chars_tmp.zip"
	if zip_writer.open(tmp_path) != OK:
		_show_status("⚠ 无法创建 ZIP 文件")
		return

	for cid in selected:
		var char_dir := "user://characters/" + cid + "/"
		_add_dir_to_zip(zip_writer, char_dir, cid + "/")

	zip_writer.close()

	var zip_data := FileAccess.get_file_as_bytes(tmp_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))

	if zip_data.is_empty():
		_show_status("⚠ 导出失败")
		return
	_save_file_to_downloads("characters_export.zip", zip_data)

func _add_dir_to_zip(zip: ZIPPacker, dir_path: String, zip_prefix: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + entry
		if dir.current_is_dir():
			_add_dir_to_zip(zip, full + "/", zip_prefix + entry + "/")
		else:
			var data := FileAccess.get_file_as_bytes(full)
			zip.start_file(zip_prefix + entry)
			zip.write_file(data)
			zip.close_file()
		entry = dir.get_next()

# ════════════════════════════════════════════════
# 工具函数
# ════════════════════════════════════════════════

## 把目录打包为 ZIP bytes（用于日志导出）
func _zip_directory(dir_path: String) -> PackedByteArray:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return PackedByteArray()
	var tmp := "user://export_log_tmp.zip"
	var zip := ZIPPacker.new()
	if zip.open(tmp) != OK:
		return PackedByteArray()
	_add_dir_to_zip(zip, dir_path + "/", "logs/")
	zip.close()
	var data := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	return data

## 保存文件到下载目录（安卓/桌面通用）
func _save_file_to_downloads(filename: String, data: PackedByteArray) -> void:
	if OS.get_name() == "Android":
		_save_android(filename, data)
	else:
		_show_save_dialog(filename, data)

func _save_android(filename: String, data: PackedByteArray) -> void:
	# Android 10+ (API 29+) 写 Downloads 无需任何权限，直接写入即可。
	# Android 9- 需要 WRITE_EXTERNAL_STORAGE，但先尝试直接写，失败再请求。
	var dl_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var path := dl_dir + "/" + filename
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(data)
		f.close()
		_show_status("✓ 已保存到下载目录：" + filename)
		return

	# 直接写失败，说明可能是 Android 9-，尝试请求权限后重试
	AndroidPermissions.request(
		["android.permission.WRITE_EXTERNAL_STORAGE"],
		func(granted: bool) -> void:
			if not granted:
				_show_status("⚠ 需要存储权限才能导出文件")
				return
			var f2 := FileAccess.open(path, FileAccess.WRITE)
			if f2 == null:
				_show_status("⚠ 写入失败：" + path)
				return
			f2.store_buffer(data)
			f2.close()
			_show_status("✓ 已保存到下载目录：" + filename)
	)

func _show_save_dialog(filename: String, data: PackedByteArray) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_file = filename
	dialog.filters = PackedStringArray(["*.zip ; ZIP 文件"])
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)
	dialog.file_selected.connect(func(path: String) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(data)
			f.close()
			_show_status("✓ 已导出：" + path.get_file())
		else:
			_show_status("⚠ 写入失败")
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())

func _show_status(msg: String) -> void:
	# 向上冒泡给 SettingsController 的 status_label
	var ctrl := get_parent()
	while ctrl != null:
		if ctrl.has_method("_set_status"):
			ctrl._set_status(msg)
			return
		ctrl = ctrl.get_parent()

func _fmt_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	else:
		return "%.1f MB" % (bytes / 1024.0 / 1024.0)

func _on_confirmed() -> void:
	_pending_action.call()
