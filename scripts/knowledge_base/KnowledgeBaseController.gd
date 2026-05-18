## KnowledgeBaseController.gd
## 知识库页面控制器，负责处理知识库的增删改查和UI交互

extends Control

# UI节点引用
@onready var status_label: Label = $MainLayout/StatusLabel
@onready var tab_container: TabContainer = $MainLayout/TabContainer
@onready var file_dialog: FileDialog = $FileDialog
@onready var confirm_dialog: ConfirmationDialog = $ConfirmDialog

# 知识库管理Tab节点
@onready var label_count: Label = $MainLayout/TabContainer/知识库管理/VBox/SectionInfo/LabelCount
@onready var button_clear: Button = $MainLayout/TabContainer/知识库管理/VBox/SectionInfo/ButtonClear
@onready var label_file_path: Label = $MainLayout/TabContainer/知识库管理/VBox/ImportSection/ImportRow/LabelFilePath
@onready var button_build: Button = $MainLayout/TabContainer/知识库管理/VBox/ImportSection/ImportRow/ButtonBuild
@onready var item_list: VBoxContainer = $MainLayout/TabContainer/知识库管理/VBox/ScrollList/ItemList

# 手动添加Tab节点
@onready var textedit_input: TextEdit = $MainLayout/TabContainer/手动添加/VBox/TextEditInput
@onready var button_add: Button = $MainLayout/TabContainer/手动添加/VBox/AddButtonRow/ButtonAdd

# 检索测试Tab节点
@onready var textedit_query: TextEdit = $MainLayout/TabContainer/检索测试/VBox/QueryInput
@onready var threshold_slider: HSlider = $MainLayout/TabContainer/检索测试/VBox/SearchRow/ThresholdSlider
@onready var label_threshold: Label = $MainLayout/TabContainer/检索测试/VBox/SearchRow/LabelThresholdValue
@onready var button_search: Button = $MainLayout/TabContainer/检索测试/VBox/SearchRow/ButtonSearch
@onready var results_list: VBoxContainer = $MainLayout/TabContainer/检索测试/VBox/ResultsScroll/ResultsList

# 底部栏
@onready var button_back: Button = $MainLayout/BottomBar/BackButton

var _selected_file_path := ""
var _is_building := false
var _is_searching := false

func _ready() -> void:
	_init_connections()
	_init_ui()
	_update_list()

func _init_connections() -> void:
	button_back.pressed.connect(_on_back)
	button_clear.pressed.connect(_on_clear_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	button_build.pressed.connect(_on_build_pressed)
	button_add.pressed.connect(_on_add_pressed)
	button_search.pressed.connect(_on_search_pressed)
	threshold_slider.value_changed.connect(_on_threshold_changed)

func _init_ui() -> void:
	button_build.disabled = true
	threshold_slider.value = 0.5

func _show_status(message: String, duration: float = 3.0) -> void:
	status_label.text = message
	if duration > 0:
		await get_tree().create_timer(duration).timeout
		status_label.text = ""

func _update_list() -> void:
	var count := VectorStore.get_count()
	label_count.text = "条目数量：%d" % count
	_refresh_item_list()

func _refresh_item_list() -> void:
	for child in item_list.get_children():
		child.queue_free()

	var entries := VectorStore.get_all_entries()
	for entry in entries:
		var item := _create_list_item(entry)
		item_list.add_child(item)

func _create_list_item(entry: Dictionary) -> Control:
	var container := HBoxContainer.new()
	container.custom_minimum_size = Vector2(0, 50)

	var label := Label.new()
	label.text = entry.get("text", "").substr(0, 50)
	if entry.get("text", "").length() > 50:
		label.text += "..."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 24)
	label.tooltip_text = entry.get("text", "")

	var delete_btn := Button.new()
	delete_btn.text = "🗑"
	delete_btn.custom_minimum_size = Vector2(50, 40)
	delete_btn.pressed.connect(func(): _delete_entry(entry.get("id", "")))

	container.add_child(label)
	container.add_child(delete_btn)

	return container

func _delete_entry(entry_id: String) -> void:
	if VectorStore.delete_entry(entry_id):
		_show_status("✓ 已删除条目")
		_update_list()
	else:
		_show_status("✗ 删除失败")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/settings/settings.tscn")

func _on_clear_pressed() -> void:
	confirm_dialog.dialog_text = "确定要清空所有知识库条目吗？此操作不可撤销。"
	confirm_dialog.confirmed.connect(_clear_all, CONNECT_ONE_SHOT)
	confirm_dialog.popup_centered()

func _clear_all() -> void:
	VectorStore.clear_all()
	_show_status("✓ 已清空知识库")
	_update_list()

func _on_file_selected(path: String) -> void:
	_selected_file_path = path
	label_file_path.text = path.get_file()
	button_build.disabled = false
	_show_status("已选择文件：%s" % path.get_file())

func _on_build_pressed() -> void:
	if _is_building:
		return
	if _selected_file_path.is_empty():
		_show_status("✗ 请先选择TXT文件")
		return

	_is_building = true
	button_build.disabled = true
	_show_status("正在读取文件...")

	var file := FileAccess.open(_selected_file_path, FileAccess.READ)
	if file == null:
		_show_status("✗ 无法打开文件")
		_is_building = false
		button_build.disabled = false
		return

	var content := file.get_as_text()
	file.close()

	var lines := content.split("\n", true)
	var texts: Array[String] = []
	for line in lines:
		var trimmed := line.strip_edges()
		if not trimmed.is_empty():
			texts.append(trimmed)

	if texts.is_empty():
		_show_status("✗ 文件内容为空")
		_is_building = false
		button_build.disabled = false
		return

	_show_status("正在构建 %d 条目..." % texts.size())

	EmbedService.embed_batch(texts, func(embeddings: Array, error: String):
		if not error.is_empty():
			_show_status("✗ 嵌入失败: " + error)
			_is_building = false
			button_build.disabled = false
			return

		var entries: Array[Dictionary] = []
		for i in range(texts.size()):
			if i < embeddings.size():
				entries.append({
					"id": UUIDUtil.generate_uuid(),
					"text": texts[i],
					"embedding": embeddings[i]
				})

		var added := VectorStore.add_entries(entries)
		_show_status("✓ 已添加 %d 条目" % added)
		_update_list()

		_is_building = false
		button_build.disabled = false
		_selected_file_path = ""
		label_file_path.text = "未选择文件"
	)

func _on_add_pressed() -> void:
	var text := textedit_input.text.strip_edges()
	if text.is_empty():
		_show_status("✗ 请输入知识内容")
		return

	_show_status("正在添加...")
	EmbedService.embed_text(text, func(embeddings: Array, error: String):
		if not error.is_empty():
			_show_status("✗ 嵌入失败: " + error)
			return

		if embeddings.is_empty() or embeddings[0].is_empty():
			_show_status("✗ 嵌入结果为空")
			return

		var entry := {
			"id": UUIDUtil.generate_uuid(),
			"text": text,
			"embedding": embeddings[0]
		}

		if VectorStore.add_entry(entry):
			_show_status("✓ 已添加条目")
			textedit_input.text = ""
			_update_list()
		else:
			_show_status("✗ 添加失败")
	)

func _on_search_pressed() -> void:
	if _is_searching:
		return

	var query := textedit_query.text.strip_edges()
	if query.is_empty():
		_show_status("✗ 请输入查询文本")
		return

	_is_searching = true
	button_search.disabled = true
	_show_status("正在检索...")

	EmbedService.embed_text(query, func(embeddings: Array, error: String):
		if not error.is_empty():
			_show_status("✗ 嵌入失败: " + error)
			_is_searching = false
			button_search.disabled = false
			return

		if embeddings.is_empty() or embeddings[0].is_empty():
			_show_status("✗ 嵌入结果为空")
			_is_searching = false
			button_search.disabled = false
			return

		var threshold := threshold_slider.value
		var results := VectorStore.search(embeddings[0], 10, threshold)

		_refresh_results(results)
		_show_status("✓ 找到 %d 条相关结果" % results.size())

		_is_searching = false
		button_search.disabled = false
	)

func _refresh_results(results: Array[Dictionary]) -> void:
	for child in results_list.get_children():
		child.queue_free()

	if results.is_empty():
		var empty_label := Label.new()
		empty_label.text = "未找到匹配的条目"
		empty_label.add_theme_font_size_override("font_size", 28)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		results_list.add_child(empty_label)
		return

	for result in results:
		var item := _create_result_item(result)
		results_list.add_child(item)

func _create_result_item(result: Dictionary) -> Control:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(0, 80)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)

	var vbox := VBoxContainer.new()

	var header := HBoxContainer.new()
	var similarity := Label.new()
	similarity.text = "相似度: %.2f" % result.get("similarity", 0.0)
	similarity.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
	similarity.add_theme_font_size_override("font_size", 24)

	header.add_child(similarity)

	var text := Label.new()
	text.text = result.get("text", "")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 22)

	vbox.add_child(header)
	vbox.add_child(text)

	margin.add_child(vbox)
	container.add_child(margin)

	return container

func _on_threshold_changed(value: float) -> void:
	label_threshold.text = "%.2f" % value