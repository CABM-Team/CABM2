## PatchManager.gd
## 补丁管理器，在所有其他 AutoLoad 之前加载 patch PCK
## 支持 Godot 4.6 delta-encoded patch PCKs
## ⚠️ 必须在 AutoLoad 列表中排在最前面
## ⚠️ 目前不使用此功能
extends Node

const PATCH_DIR := "user://patches/"
const PATCH_MANIFEST := "user://patches/manifest.json"
const UPDATE_CHECK_URL := "https://shasnow.top/s/api/cabm/patch"

signal patch_loaded(version: String)
signal patch_failed(reason: String)
signal update_available(version: String, url: String, size: int)
signal update_progress(bytes_loaded: int, bytes_total: int)
signal update_finished(success: bool)

var _http_check: HTTPRequest
var _http_download: HTTPRequest
var _applied_patches: Array[String] = []

func _ready() -> void:
	_apply_all_patches()

func _apply_all_patches() -> void:
	if not DirAccess.dir_exists_absolute(PATCH_DIR):
		DirAccess.make_dir_recursive_absolute(PATCH_DIR)
		return

	var dir := DirAccess.open(PATCH_DIR)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	var patch_files: Array[String] = []
	while file_name != "":
		if file_name.ends_with(".pck"):
			patch_files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	patch_files.sort()

	for pf in patch_files:
		var full_path := PATCH_DIR + pf
		var ok := ProjectSettings.load_resource_pack(full_path, false)
		if ok:
			_applied_patches.append(pf)
			print("[PatchManager] 已加载补丁：", pf)
		else:
			print("[PatchManager] 加载失败：", pf)
			patch_failed.emit("无法加载：" + pf)

	if not _applied_patches.is_empty():
		patch_loaded.emit(_applied_patches[-1])

func get_applied_patches() -> Array[String]:
	return _applied_patches

func check_for_update() -> void:
	if _http_check != null:
		return
	_http_check = HTTPRequest.new()
	add_child(_http_check)
	_http_check.request_completed.connect(_on_check_completed)

	var payload := {
		"appId": AppInfo.APP_NAME,
		"currentVersion": AppInfo.VERSION,
		"platform": OS.get_name(),
	}
	var headers := ["Content-Type: application/json"]
	var err := _http_check.request(
		UPDATE_CHECK_URL,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		print("[PatchManager] 检查更新请求失败：", err)
		_cleanup_http(_http_check)
		_http_check = null

func _on_check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_cleanup_http(_http_check)
	_http_check = null

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[PatchManager] 检查更新失败，code：", code)
		return

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		return

	var data: Dictionary = json.data
	if data.get("hasUpdate", false):
		var ver: String = data.get("version", "")
		var url: String = data.get("downloadUrl", "")
		var size: int = data.get("patchSize", 0)
		print("[PatchManager] 发现新版本：", ver)
		update_available.emit(ver, url, size)

func download_patch(url: String) -> void:
	if _http_download != null:
		return
	_http_download = HTTPRequest.new()
	add_child(_http_download)
	_http_download.use_threads = true
	_http_download.download_file = PATCH_DIR + url.get_file()
	_http_download.request_completed.connect(_on_download_completed)

	var err := _http_download.request(url)
	if err != OK:
		print("[PatchManager] 下载请求失败：", err)
		_cleanup_http(_http_download)
		_http_download = null
		update_finished.emit(false)

func _on_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_cleanup_http(_http_download)
	_http_download = null

	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		print("[PatchManager] 补丁下载完成")
		update_finished.emit(true)
	else:
		print("[PatchManager] 补丁下载失败，code：", code)
		update_finished.emit(false)

func remove_all_patches() -> void:
	var dir := DirAccess.open(PATCH_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".pck"):
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	_applied_patches.clear()
	print("[PatchManager] 已清除所有补丁")

func _cleanup_http(http: HTTPRequest) -> void:
	if http == null:
		return
	if http.get_parent() == self:
		remove_child(http)
	http.queue_free()
