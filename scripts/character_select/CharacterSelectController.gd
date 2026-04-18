## CharacterSelectController.gd
## 角色选择页面控制器

extends Control

const CharacterCardScene := preload("res://scenes/character_select/character_card.tscn")

@onready var character_grid: GridContainer = $VBox/ScrollContainer/CharacterGrid
@onready var settings_button: Button = $VBox/BottomBar/SettingsButton
@onready var quit_button: Button = $VBox/BottomBar/QuitButton

func _ready() -> void:
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	_populate_characters()

func _populate_characters() -> void:
	var characters := CharacterLoader.load_all()
	for char_data in characters:
		var card: PanelContainer = CharacterCardScene.instantiate()
		character_grid.add_child(card)
		card.setup(char_data)
		card.selected.connect(_on_character_selected)

func _on_character_selected(char_data: Dictionary) -> void:
	AppState.set_character(char_data)
	get_tree().change_scene_to_file("res://scenes/chat/chat.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings/settings.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
