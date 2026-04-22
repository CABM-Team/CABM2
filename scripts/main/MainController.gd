## MainController.gd
## 主场景控制器，负责初始启动路由

extends Node

const UUID_FILE := "user://uuid.txt"

func _ready() -> void:
	_report_launch.call_deferred()
	if ConfigManager.is_configured():
		_go_to_character_select.call_deferred()
	else:
		_go_to_settings.call_deferred()

## 获取或生成设备 UUID
func _get_device_id() -> String:
	if FileAccess.file_exists(UUID_FILE):
		var rf := FileAccess.open(UUID_FILE, FileAccess.READ)
		if rf:
			var id := rf.get_as_text().strip_edges()
			rf.close()
			if not id.is_empty():
				return id
	# 生成新 UUID v4
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var b := PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = rng.randi() % 256
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var uuid := "%s-%s-%s-%s-%s" % [
		b.slice(0, 4).hex_encode(),
		b.slice(4, 6).hex_encode(),
		b.slice(6, 8).hex_encode(),
		b.slice(8, 10).hex_encode(),
		b.slice(10, 16).hex_encode()
	]
	var f := FileAccess.open(UUID_FILE, FileAccess.WRITE)
	if f:
		f.store_string(uuid)
		f.close()
	return uuid

## 异步上报启动事件，不阻塞游戏
func _report_launch() -> void:
	var payload := {
		"deviceId": _get_device_id(),
		"eventType": "login",
		"eventData": null,
		"appId": AppInfo.APP_NAME,
		"appVersion": AppInfo.VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
		"sessionDuration": 0
	}
	var http := HTTPRequest.new()
	get_tree().root.add_child(http)
	http.request_completed.connect(func(result, code, _headers, _body):
		if result == HTTPRequest.RESULT_SUCCESS:
			print("[Report] 上报成功，状态码：", code)
		else:
			print("[Report] 上报失败，result：", result)
		http.queue_free()
	)
	var headers := ["Content-Type: application/json"]
	var err := http.request(
		"https://shasnow.top/s/api/report",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		print("[Report] 请求发起失败，错误码：", err)
		http.queue_free()

func _go_to_character_select() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

func _go_to_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/settings/settings.tscn")
