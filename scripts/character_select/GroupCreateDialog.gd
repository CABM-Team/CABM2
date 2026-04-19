## GroupCreateDialog.gd
## 新建群聊对话框：左侧选择角色，右侧填群名和描述

extends Control

signal group_created(group_data: Dictionary)

const CharacterCardScene := preload("res://scenes/character_select/character_card.tscn")

@onready var name_input: LineEdit     = $Panel/VBox/HSplit/RightPanel/NameInput
@onready var desc_input: TextEdit     = $Panel/VBox/HSplit/RightPanel/DescInput
@onready var char_grid: GridContainer = $Panel/VBox/HSplit/LeftPanel/ScrollContainer/CharGrid
@onready var confirm_btn: Button      = $Panel/VBox/HSplit/RightPanel/ButtonRow/ConfirmButton
@onready var cancel_btn: Button       = $Panel/VBox/HSplit/RightPanel/ButtonRow/CancelButton
@onready var error_label: Label       = $Panel/VBox/HSplit/RightPanel/ErrorLabel
@onready var selected_label: Label    = $Panel/VBox/HSplit/LeftPanel/SelectedLabel

var _selected_ids: Array[String] = []
var _all_characters: Array[Dictionary] = []

func _ready() -> void:
	confirm_btn.pressed.connect(_on_confirm)
	cancel_btn.pressed.connect(func(): visible = false)

func open(all_characters: Array[Dictionary]) -> void:
	_all_characters = all_characters
	_selected_ids.clear()
	name_input.text = ""
	desc_input.text = ""
	error_label.text = ""
	_populate_chars()
	_refresh_selected_label()
	visible = true

func _populate_chars() -> void:
	for c in char_grid.get_children():
		c.queue_free()

	for char_data in _all_characters:
		var cid: String = char_data.get("id", "")
		var card: PanelContainer = CharacterCardScene.instantiate()
		char_grid.add_child(card)
		card.setup(char_data)
		card.get_node("HBox/VBox/LastMessageLabel").visible = false

		var click_area: Button = card.get_node("ClickArea")
		click_area.pressed.disconnect(click_area.pressed.get_connections()[0]["callable"])
		click_area.pressed.connect(func(): _toggle_select(cid, card))

func _toggle_select(char_id: String, card: PanelContainer) -> void:
	if char_id in _selected_ids:
		_selected_ids.erase(char_id)
		card.modulate = Color.WHITE
	else:
		_selected_ids.append(char_id)
		card.modulate = Color(0.5, 0.5, 0.5, 0.6)
	error_label.text = ""
	_refresh_selected_label()

func _refresh_selected_label() -> void:
	if _selected_ids.is_empty():
		selected_label.text = "已选择：（无）"
		return
	var names: Array[String] = []
	for cid in _selected_ids:
		for c in _all_characters:
			if c.get("id", "") == cid:
				names.append(c.get("name", cid))
				break
	selected_label.text = "已选择：" + "、".join(names)

func _on_confirm() -> void:
	var gname := name_input.text.strip_edges()
	if gname.is_empty():
		error_label.text = "请输入群聊名称"
		return
	if _selected_ids.size() < 2:
		error_label.text = "请至少选择 2 个角色"
		return

	var group_data := {
		"id": GroupManager.generate_id(),
		"name": gname,
		"des": desc_input.text.strip_edges(),
		"character_ids": _selected_ids.duplicate()
	}
	GroupManager.save_group(group_data)
	visible = false
	group_created.emit(group_data)
