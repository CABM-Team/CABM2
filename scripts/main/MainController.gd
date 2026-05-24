## MainController.gd
## 主场景控制器，负责初始启动路由

extends Node

func _ready() -> void:
	var heartbeat = preload("res://scripts/main/HeartBeat.gd").new()
	add_child(heartbeat)
	if ConfigManager.is_configured():
		_go_to_character_select.call_deferred()
	else:
		_go_to_settings.call_deferred()

func _go_to_character_select() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

func _go_to_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/settings/settings.tscn")
