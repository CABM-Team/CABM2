## AndroidPermissions.gd
## 安卓权限管理单例
## 非安卓平台所有方法直接执行回调，无需任何改动。
##
## 用法示例：
##   AndroidPermissions.request_for_file_pick(func(granted): if granted: _open_file_dialog())
##   AndroidPermissions.request(["android.permission.CAMERA"], func(granted): ...)
##
## AutoLoad 单例名：AndroidPermissions

extends Node

## 权限请求完成信号（granted: bool）
signal permission_result(permission: String, granted: bool)

# 等待回调队列：{ permission_name -> Array[Callable] }
var _pending: Dictionary = {}

func _ready() -> void:
	if OS.get_name() == "Android":
		# 连接系统回调
		# Godot 4 在主循环发出此信号
		if Engine.has_singleton("MainLoop"):
			pass  # 通过 _on_request_permissions_result 接收
		# Godot 4.x：重写 _on_request_permissions_result 即可接收结果
		pass

## 系统回调入口（Godot 4 自动调用）
func _on_request_permissions_result(permission: String, granted: bool) -> void:
	permission_result.emit(permission, granted)
	if _pending.has(permission):
		var callbacks: Array = _pending[permission]
		_pending.erase(permission)
		for cb in callbacks:
			cb.call(granted)

# ── 公共 API ──────────────────────────────────────────────────────────────

## 请求一组权限，全部授予后执行 on_done(true)，任意拒绝执行 on_done(false)
## on_done: Callable(granted: bool)
func request(permissions: Array[String], on_done: Callable) -> void:
	if OS.get_name() != "Android":
		on_done.call(true)
		return

	# 过滤掉已授予的权限
	var needed: Array[String] = []
	for p in permissions:
		if not OS.has_feature("android") or not _has_permission(p):
			needed.append(p)

	if needed.is_empty():
		on_done.call(true)
		return

	# 用引用计数跟踪多权限结果
	var state := { "remaining": needed.size(), "all_granted": true }
	for p in needed:
		if not _pending.has(p):
			_pending[p] = []
		_pending[p].append(func(granted: bool) -> void:
			if not granted:
				state["all_granted"] = false
			state["remaining"] -= 1
			if state["remaining"] == 0:
				on_done.call(state["all_granted"])
		)
	OS.request_permissions()

## 请求读取外部存储权限（用于文件选择/导入）
## Android 10 及以下需要 READ_EXTERNAL_STORAGE
## Android 11+ 使用分区存储，FileDialog 通常不需要额外权限，但仍请求以兼容旧版本
func request_for_file_pick(on_done: Callable) -> void:
	if OS.get_name() != "Android":
		on_done.call(true)
		return

	var sdk := _get_android_sdk_version()
	if sdk >= 33:
		# Android 13+：READ_MEDIA_* 替代旧权限
		request([
			"android.permission.READ_MEDIA_IMAGES",
			"android.permission.READ_MEDIA_VIDEO",
			"android.permission.READ_MEDIA_AUDIO",
		], on_done)
	elif sdk >= 30:
		# Android 11-12：分区存储，FileDialog 访问应用沙盒不需要权限
		# 但访问公共目录仍需 READ_EXTERNAL_STORAGE（已废弃但仍有效）
		request(["android.permission.READ_EXTERNAL_STORAGE"], on_done)
	else:
		# Android 10 及以下
		request([
			"android.permission.READ_EXTERNAL_STORAGE",
			"android.permission.WRITE_EXTERNAL_STORAGE",
		], on_done)

## 请求相机权限
func request_camera(on_done: Callable) -> void:
	request(["android.permission.CAMERA"], on_done)

## 请求麦克风权限
func request_microphone(on_done: Callable) -> void:
	request(["android.permission.RECORD_AUDIO"], on_done)

## 请求网络权限（通常在 Manifest 声明即可，无需运行时请求，此处仅做检查）
func check_internet(on_done: Callable) -> void:
	on_done.call(true)  # INTERNET 权限无需运行时请求

## 检查单个权限是否已授予
func has_permission(permission: String) -> bool:
	if OS.get_name() != "Android":
		return true
	return _has_permission(permission)

# ── 内部工具 ──────────────────────────────────────────────────────────────

func _has_permission(permission: String) -> bool:
	# Godot 4：OS.has_feature 不检查权限，用 OS.get_granted_permissions()
	var granted := OS.get_granted_permissions()
	return permission in granted

func _get_android_sdk_version() -> int:
	# 通过 Engine 版本信息无法直接获取 SDK，使用 OS.get_model_name 也不可靠
	# 最可靠方式是通过 Java 单例，此处用保守值 29 作为回退
	if Engine.has_singleton("AndroidRuntime"):
		var _runtime = Engine.get_singleton("AndroidRuntime")
		# AndroidRuntime 是 Godot Android 插件提供的，不一定存在
		# 如果存在可调用 getActivity().getApplicationInfo().targetSdkVersion
		pass
	# 回退：假设 Android 10（SDK 29），请求完整存储权限，安全兼容
	return 29
