## ImportResultDialog.gd
## 显示角色导入结果的对话框

extends Control

signal closed

@onready var result_list: RichTextLabel = $Panel/VBox/ResultList
@onready var close_btn: Button          = $Panel/VBox/CloseButton

func _ready() -> void:
	close_btn.pressed.connect(_on_close)

func show_results(results: Array[Dictionary]) -> void:
	visible = true
	var lines: Array[String] = []
	for r in results:
		var icon := "[color=lime]✔[/color]" if r.get("ok", false) else "[color=red]✘[/color]"
		lines.append("%s  [b]%s[/b]  —  %s" % [icon, r.get("id", "?"), r.get("message", "")])
	result_list.bbcode_enabled = true
	result_list.text = "\n".join(lines)

func _on_close() -> void:
	visible = false
	closed.emit()
