## CharacterSelectController.gd
## 角色选择页面控制器，支持单角色/群聊两个标签页

extends Control

const CharacterCardScene := preload("res://scenes/character_select/character_card.tscn")
const GroupCardScene     := preload("res://scenes/character_select/group_card.tscn")

@onready var character_grid: GridContainer  = $VBox/SinglePanel/CharacterGrid
@onready var single_panel: ScrollContainer  = $VBox/SinglePanel
@onready var group_panel: VBoxContainer     = $VBox/GroupPanel
@onready var group_grid: GridContainer      = $VBox/GroupPanel/GroupScrollContainer/GroupGrid
@onready var single_tab_btn: Button         = $VBox/TabBar/SingleTabButton
@onready var group_tab_btn: Button          = $VBox/TabBar/GroupTabButton
@onready var new_group_btn: Button          = $VBox/GroupPanel/NewGroupButton
@onready var settings_button: Button        = $VBox/BottomBar/SettingsButton
@onready var quit_button: Button            = $VBox/BottomBar/QuitButton
@onready var group_create_dialog: Control = $GroupCreateDialog

var _all_characters: Array[Dictionary] = []

func _ready() -> void:
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	single_tab_btn.pressed.connect(func(): _switch_tab(false))
	group_tab_btn.pressed.connect(func(): _switch_tab(true))
	new_group_btn.pressed.connect(_on_new_group_pressed)
	group_create_dialog.group_created.connect(_on_group_created)

	_all_characters = CharacterLoader.load_all()
	_populate_characters()
	_populate_groups()
	_switch_tab(AppState.last_tab_is_group)

func _switch_tab(is_group: bool) -> void:
	AppState.last_tab_is_group = is_group
	single_panel.visible = not is_group
	group_panel.visible = is_group
	single_tab_btn.disabled = not is_group
	group_tab_btn.disabled = is_group

func _populate_characters() -> void:
	for char_data in _all_characters:
		var card: PanelContainer = CharacterCardScene.instantiate()
		character_grid.add_child(card)
		card.setup(char_data)
		card.selected.connect(_on_character_selected)

func _populate_groups() -> void:
	for child in group_grid.get_children():
		child.queue_free()
	var groups= GroupManager.load_all()
	for group_data in groups:
		_add_group_card(group_data)

func _add_group_card(group_data: Dictionary) -> void:
	var card: PanelContainer = GroupCardScene.instantiate()
	group_grid.add_child(card)
	card.setup(group_data, _all_characters)
	card.selected.connect(_on_group_selected)

func _on_character_selected(char_data: Dictionary) -> void:
	AppState.set_character(char_data)
	AppState.current_group = {}
	get_tree().change_scene_to_file("res://scenes/chat/chat.tscn")

func _on_group_selected(group_data: Dictionary) -> void:
	var ids: Array = group_data.get("character_ids", [])
	var chars: Array[Dictionary] = []
	for cid in ids:
		for c in _all_characters:
			if c.get("id", "") == cid:
				chars.append(c)
				break
	AppState.set_group(group_data, chars)
	get_tree().change_scene_to_file("res://scenes/chat/chat.tscn")

func _on_new_group_pressed() -> void:
	group_create_dialog.open(_all_characters)

func _on_group_created(_group_data: Dictionary) -> void:
	_populate_groups()

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings/settings.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
