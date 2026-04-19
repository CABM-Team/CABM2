## AndroidPermissions.gd
## 安卓权限管理单例
## 非安卓平台所有方法直接执行回调，无需任何改动。
##
## 用法示例：
##   AndroidPermissions.request_for_file_pick(func(granted): if granted: _open_file_dialog())
##   AndroidPermissions.request(["android.permission.CAMERA"], func(granted): ...)
##
## 注意：权限还需要在 export_presets.cfg 的 permissions 段中声明，
##       否则 OS.request_permissions() 不会弹出系统授权窗口。
##
## AutoLoad 单例名：AndroidPermissions

extends Node

# 请求权限后等待系统响应的时间（秒）
const PERMISSION_WAIT_SEC := 1.5

# ── 公共 API ──────────────────────────────────────────────────────────────

## 请求一组权限，全部授予后执行 on_done(true)，任意拒绝执行 on_done(false)
## on_done: Callable(granted: bool)
func request(permissions: Array[String], on_done: Callable) -> void:
	if OS.get_name() != "Android":
		on_done.call(true)
		return

	if _all_granted(permissions):
		on_done.call(true)
		return

	# 触发系统权限弹窗（Godot 4 不接受参数，权限须在 export_presets 中声明）
	OS.request_permissions()

	# 等待系统响应后再检查
	await get_tree().create_timer(PERMISSION_WAIT_SEC).timeout

	var granted := _all_granted(permissions)
	if OS.get_name() == "Android":
		print("AndroidPermissions: %s -> granted=%s" % [str(permissions), granted])
		print("AndroidPermissions: 当前已授予权限: ", OS.get_granted_permissions())
	on_done.call(granted)

## 请求读取外部存储权限（用于文件选择/导入）
## 兼容 Android 10 ~ 13+
func request_for_file_pick(on_done: Callable) -> void:
	if OS.get_name() != "Android":
		on_done.call(true)
		return

	# 只要有任意一种存储权限即可
	if _has_any_storage_permission():
		on_done.call(true)
		return

	OS.request_permissions()
	await get_tree().create_timer(PERMISSION_WAIT_SEC).timeout

	var granted := _has_any_storage_permission()
	print("AndroidPermissions: 文件读取权限 -> granted=%s" % granted)
	print("AndroidPermissions: 当前已授予权限: ", OS.get_granted_permissions())
	on_done.call(granted)

## 请求相机权限
func request_camera(on_done: Callable) -> void:
	request(["android.permission.CAMERA"], on_done)

## 请求麦克风权限
func request_microphone(on_done: Callable) -> void:
	request(["android.permission.RECORD_AUDIO"], on_done)

## 检查单个权限是否已授予
func has_permission(permission: String) -> bool:
	if OS.get_name() != "Android":
		return true
	return permission in OS.get_granted_permissions()

# ── 内部工具 ──────────────────────────────────────────────────────────────

func _all_granted(permissions: Array[String]) -> bool:
	var granted := OS.get_granted_permissions()
	for p in permissions:
		if not (p in granted):
			return false
	return true

## 检查是否有任意一种存储读取权限（兼容各 Android 版本）
func _has_any_storage_permission() -> bool:
	var granted := OS.get_granted_permissions()
	return (
		"android.permission.READ_EXTERNAL_STORAGE"  in granted or
		"android.permission.WRITE_EXTERNAL_STORAGE" in granted or
		"android.permission.MANAGE_EXTERNAL_STORAGE" in granted or
		"android.permission.READ_MEDIA_IMAGES"      in granted or
		"android.permission.READ_MEDIA_VIDEO"       in granted or
		"android.permission.READ_MEDIA_AUDIO"       in granted
	)
