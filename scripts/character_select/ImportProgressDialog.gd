## 导入进度面板：先扫描 ZIP 获取角色总数，再逐个导入并更新进度条

extends Control

signal import_finished(results: Array)

@onready var status_label: Label       = $Panel/VBox/StatusLabel
@onready var progress_bar: ProgressBar = $Panel/VBox/ProgressBar

var _zip_path: String = ""
var _folders: Array = []
var _folder_files: Dictionary = {}
var _current_index: int = 0
var _results: Array[Dictionary] = []

func start_import(zip_path: String) -> void:
	_zip_path = zip_path
	_results.clear()
	_current_index = 0

	var char_folders: Dictionary = CharacterImporter.scan_zip(zip_path)
	if char_folders.is_empty():
		visible = false
		import_finished.emit([{ "id": "?", "ok": false, "message": "压缩包内未找到角色文件夹" }])
		return

	_folders = char_folders.keys()
	_folder_files = char_folders

	progress_bar.min_value = 0
	progress_bar.max_value = _folders.size()
	progress_bar.value = 0
	progress_bar.indeterminate = false
	_update_status()
	visible = true
	call_deferred("_import_next")

func _update_status() -> void:
	status_label.text = "正在导入 %d / %d…" % [_current_index, _folders.size()]

func _import_next() -> void:
	if _current_index >= _folders.size():
		visible = false
		import_finished.emit(_results)
		return

	var folder_name: String = _folders[_current_index]
	var result: Dictionary = CharacterImporter._import_one(_zip_path, folder_name, _folder_files[folder_name])
	_results.append(result)

	_current_index += 1
	progress_bar.value = _current_index
	_update_status()
	_import_next()