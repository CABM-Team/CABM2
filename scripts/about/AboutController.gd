## AboutController.gd
## 关于页面控制器

extends Control

@onready var back_button: Button = $VBox/BottomBar/BackButton
@onready var version_label: Label = $VBox/ContentScroll/Content/VersionLabel

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	version_label.text = "版本：%s" % AppInfo.VERSION

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
