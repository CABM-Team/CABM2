## UIStateManager.gd
## 持久化 UI 状态（排序方式等）到 user://ui_state.json
## AutoLoad 单例

extends Node

const STATE_PATH := "user://ui_state.json"

# 排序字段：0=ID首字母, 1=名字首字母, 2=上次游玩时间
var sort_field: int = 2
# 排序方向：0=升序, 1=降序
var sort_order: int = 1
# 上次选中的标签页（false=单角色, true=群聊）
var last_tab_is_group: bool = false

func _ready() -> void:
	_load()

func save() -> void:
	var data := {
		"sort_field": sort_field,
		"sort_order": sort_order,
		"last_tab_is_group": last_tab_is_group,
	}
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func _load() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var file := FileAccess.open(STATE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.get_data()
		if data is Dictionary:
			sort_field = int(data.get("sort_field", sort_field))
			sort_order = int(data.get("sort_order", sort_order))
			last_tab_is_group = bool(data.get("last_tab_is_group", last_tab_is_group))
	file.close()
