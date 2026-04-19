## ConfirmDialog.gd
## 通用确认对话框，带全屏半透明遮罩
## 信号：confirmed / cancelled

extends Control

signal confirmed
signal cancelled

@onready var overlay: ColorRect     = $Overlay
@onready var panel: PanelContainer  = $Panel
@onready var label: Label           = $Panel/VBox/ConfirmLabel
@onready var confirm_btn: Button    = $Panel/VBox/ButtonBox/ConfirmButton
@onready var cancel_btn: Button     = $Panel/VBox/ButtonBox/CancelButton

func _ready() -> void:
	confirm_btn.pressed.connect(_on_confirm)
	cancel_btn.pressed.connect(_on_cancel)
	overlay.gui_input.connect(_on_overlay_input)

## 设置提示文字后显示对话框
func show_dialog(message: String = "") -> void:
	if not message.is_empty():
		label.text = message
	visible = true

func hide_dialog() -> void:
	visible = false

func _on_confirm() -> void:
	hide_dialog()
	confirmed.emit()

func _on_cancel() -> void:
	hide_dialog()
	cancelled.emit()

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_cancel()
