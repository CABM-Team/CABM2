## CharacterSelectController.gd
## 角色选择页面控制器，支持单角色/群聊两个标签页，以及排序功能

extends Control

const CharacterCardScene := preload("res://scenes/character_select/character_card.tscn")
const GroupCardScene     := preload("res://scenes/character_select/group_card.tscn")

# 排序字段常量
const SORT_ID    := 0
const SORT_NAME  := 1
const SORT_TIME  := 2

@onready var character_grid: GridContainer  = $VBox/SinglePanel/CharacterGrid
@onready var single_panel: ScrollContainer  = $VBox/SinglePanel
@onready var group_panel: VBoxContainer     = $VBox/GroupPanel
@onready var group_grid: GridContainer      = $VBox/GroupPanel/GroupScrollContainer/GroupGrid
@onready var single_tab_btn: Button         = $VBox/TabBar/SingleTabButton
@onready var group_tab_btn: Button          = $VBox/TabBar/GroupTabButton
@onready var new_group_btn: Button          = $VBox/GroupPanel/NewGroupButton
@onready var settings_button: Button        = $VBox/BottomBar/SettingsButton
@onready var quit_button: Button            = $VBox/BottomBar/QuitButton
@onready var group_create_dialog: Control   = $GroupCreateDialog
@onready var sort_field_btn: Button         = $VBox/SortBar/SortFieldButton
@onready var sort_order_btn: Button         = $VBox/SortBar/SortOrderButton

var _all_characters: Array[Dictionary] = []

func _ready() -> void:
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	single_tab_btn.pressed.connect(func(): _switch_tab(false))
	group_tab_btn.pressed.connect(func(): _switch_tab(true))
	new_group_btn.pressed.connect(_on_new_group_pressed)
	group_create_dialog.group_created.connect(_on_group_created)
	sort_field_btn.pressed.connect(_on_sort_field_pressed)
	sort_order_btn.pressed.connect(_on_sort_order_pressed)

	_all_characters = CharacterLoader.load_all()
	_update_sort_buttons()
	_populate_characters()
	_populate_groups()
	_switch_tab(UIStateManager.last_tab_is_group)

func _switch_tab(is_group: bool) -> void:
	UIStateManager.last_tab_is_group = is_group
	UIStateManager.save()
	single_panel.visible = not is_group
	group_panel.visible = is_group
	single_tab_btn.disabled = not is_group
	group_tab_btn.disabled = is_group

# ── 排序 ──────────────────────────────────────────────

func _on_sort_field_pressed() -> void:
	UIStateManager.sort_field = (UIStateManager.sort_field + 1) % 3
	UIStateManager.save()
	_update_sort_buttons()
	_repopulate_all()

func _on_sort_order_pressed() -> void:
	UIStateManager.sort_order = 1 - UIStateManager.sort_order
	UIStateManager.save()
	_update_sort_buttons()
	_repopulate_all()

func _update_sort_buttons() -> void:
	var field_labels := ["排序：ID", "排序：名字", "排序：时间"]
	sort_field_btn.text = field_labels[UIStateManager.sort_field]
	sort_order_btn.text = "↑ 升序" if UIStateManager.sort_order == 0 else "↓ 降序"

func _repopulate_all() -> void:
	_populate_characters()
	_populate_groups()

func _sort_key_for_char(char_data: Dictionary) -> String:
	match UIStateManager.sort_field:
		SORT_ID:
			return char_data.get("id", "").to_lower()
		SORT_NAME:
			return char_data.get("name", char_data.get("id", "")).to_lower()
		SORT_TIME:
			var t := HistoryManager.get_last_play_time(char_data.get("id", ""))
			# 用固定宽度字符串保证数字排序正确
			return "%020d" % t
	return ""

func _sort_key_for_group(group_data: Dictionary) -> String:
	match UIStateManager.sort_field:
		SORT_ID:
			return group_data.get("id", "").to_lower()
		SORT_NAME:
			return group_data.get("name", group_data.get("id", "")).to_lower()
		SORT_TIME:
			var t := HistoryManager.get_group_last_play_time(group_data.get("id", ""))
			return "%020d" % t
	return ""

func _sorted_array(arr: Array, key_func: Callable, invert_order: bool = false) -> Array:
	var pairs: Array = []
	for item in arr:
		pairs.append([key_func.call(item), item])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	var descending := UIStateManager.sort_order == 1
	if invert_order:
		descending = not descending
	if descending:
		pairs.reverse()
	var result: Array = []
	for p in pairs:
		result.append(p[1])
	return result# ── 填充卡片 ──────────────────────────────────────────

func _populate_characters() -> void:
	for child in character_grid.get_children():
		child.queue_free()
	var is_time := UIStateManager.sort_field == SORT_TIME
	var sorted := _sorted_array(_all_characters, _sort_key_for_char, is_time)
	for char_data in sorted:
		var card: PanelContainer = CharacterCardScene.instantiate()
		character_grid.add_child(card)
		card.setup(char_data)
		card.selected.connect(_on_character_selected)

func _populate_groups() -> void:
	for child in group_grid.get_children():
		child.queue_free()
	var groups := GroupManager.load_all()
	var is_time := UIStateManager.sort_field == SORT_TIME
	var sorted := _sorted_array(groups, _sort_key_for_group, is_time)
	for group_data in sorted:
		_add_group_card(group_data)

func _add_group_card(group_data: Dictionary) -> void:
	var card: PanelContainer = GroupCardScene.instantiate()
	group_grid.add_child(card)
	card.setup(group_data, _all_characters)
	card.selected.connect(_on_group_selected)

# ── 事件处理 ──────────────────────────────────────────

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
