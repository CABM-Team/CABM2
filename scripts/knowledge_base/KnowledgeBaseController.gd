## KnowledgeBaseController.gd
## 知识库页面控制器，负责处理知识库的增删改查和UI交互
## 支持每个角色独立的知识库

extends Control

# UI节点引用
@onready var header_label: Label = $MainLayout/HeaderLabel
@onready var status_label: Label = $MainLayout/StatusLabel
@onready var tab_container: TabContainer = $MainLayout/TabContainer
@onready var file_dialog: FileDialog = $FileDialog
@onready var confirm_dialog: Control = $ConfirmDialog

# 知识库管理Tab节点
@onready var knowledge_toggle: CheckBox = $MainLayout/TabContainer/知识库管理/VBox/SectionInfo/ToggleRow/KnowledgeToggle
@onready var disable_indicator: Label = $MainLayout/TabContainer/知识库管理/VBox/SectionInfo/ToggleRow/DisableIndicator
@onready var label_count: Label = $MainLayout/TabContainer/知识库管理/VBox/SectionInfo/InfoRow/LabelCount
@onready var button_clear: Button = $MainLayout/TabContainer/知识库管理/VBox/SectionInfo/InfoRow/ButtonClear
@onready var plugin_warning: Label = $MainLayout/TabContainer/知识库管理/VBox/PluginWarning
@onready var label_file_path: Label = $MainLayout/TabContainer/知识库管理/VBox/ImportSection/ImportRow/LabelFilePath
@onready var button_build: Button = $MainLayout/TabContainer/知识库管理/VBox/ImportSection/ImportRow/ButtonBuild
@onready var file_dialog_button: Button = $MainLayout/TabContainer/知识库管理/VBox/ImportSection/ImportRow/FileDialogButton
# 手动添加Tab节点
@onready var textedit_input: TextEdit = $MainLayout/TabContainer/手动添加/VBox/TextEditInput
@onready var button_add: Button = $MainLayout/TabContainer/手动添加/VBox/AddButtonRow/ButtonAdd

# 检索测试Tab节点
@onready var textedit_query: TextEdit = $MainLayout/TabContainer/检索测试/VBox/QueryInput
@onready var threshold_slider: HSlider = $MainLayout/TabContainer/检索测试/VBox/SearchRow/ThresholdSlider
@onready var label_threshold: Label = $MainLayout/TabContainer/检索测试/VBox/SearchRow/LabelThresholdValue
@onready var button_search: Button = $MainLayout/TabContainer/检索测试/VBox/SearchRow/ButtonSearch
@onready var button_match_search: Button = $MainLayout/TabContainer/检索测试/VBox/SearchRow/ButtonMatchSearch
@onready var results_list: VBoxContainer = $MainLayout/TabContainer/检索测试/VBox/ResultsScroll/ResultsList

# 底部栏
@onready var button_back: Button = $MainLayout/BottomBar/BackButton

var _selected_file_path := ""
var _is_building := false
var _is_searching := false
var _char_id := ""
var _char_name := ""
var _current_query := ""
var red_button_theme = preload("res://assets/theme/red_button.tres")

func _ready() -> void:
	# 从AppState获取当前角色信息
	# 连接确认信号，使用 CONNECT_ONE_SHOT 确保只触发一次
	confirm_dialog.confirmed.connect(_clear_all, CONNECT_ONE_SHOT)
	if AppState.is_group_mode():
		push_warning("[KnowledgeBase] 群聊模式不支持知识库")
		_on_back()
		return
	
	_char_id = AppState.current_character.get("id", "")
	_char_name = AppState.current_character.get("name", "未知角色")
	
	if _char_id.is_empty():
		push_warning("[KnowledgeBase] 角色ID为空")
		_on_back()
		return
	
	# 加载该角色的知识库
	VectorStore.load_character_knowledge(_char_id)
	_init_connections()
	_init_ui()
	_update_list()
	_check_plugin_status()

func _init_connections() -> void:
	button_back.pressed.connect(_on_back)
	button_clear.pressed.connect(_on_clear_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog_button.pressed.connect(_on_file_dialog_button_pressed)
	button_build.pressed.connect(_on_build_pressed)
	button_add.pressed.connect(_on_add_pressed)
	button_search.pressed.connect(_on_search_pressed)
	button_match_search.pressed.connect(_on_match_search_pressed)
	threshold_slider.value_changed.connect(_on_threshold_changed)
	knowledge_toggle.toggled.connect(_on_knowledge_toggled)

func _init_ui() -> void:
	header_label.text = "知识库 - " + _char_name
	button_build.disabled = true
	threshold_slider.value = 0.5
	knowledge_toggle.button_pressed = VectorStore.is_knowledge_enabled()
	_update_disable_indicator()

func _check_plugin_status() -> void:
	var stats := VectorStore.get_stats()
	if not stats.get("is_plugin_loaded", false):
		plugin_warning.visible = true
		plugin_warning.text = "⚠ 未检测到余弦相似插件，知识库功能已自动关闭\n请编译并安装cosine_calculator插件后重启"
		knowledge_toggle.button_pressed = false
		knowledge_toggle.disabled = true
		VectorStore.set_knowledge_enabled(false)
	else:
		plugin_warning.visible = false
		knowledge_toggle.disabled = false

func _update_disable_indicator() -> void:
	var is_enabled := VectorStore.is_knowledge_enabled()
	disable_indicator.visible = not is_enabled
	disable_indicator.text = "⚠ 知识库已禁用" if not is_enabled else ""

func _show_status(message: String, duration: float = 3.0, color: Color = Color(0, 0.8, 0.4)) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color)
	if duration > 0:
		await get_tree().create_timer(duration).timeout
		if not _is_building and not _is_searching:
			status_label.text = ""

func _update_list() -> void:
	var count := VectorStore.get_count()
	label_count.text = "条目数量：%d" % count

func _delete_entry(entry_id: String) -> void:
	if VectorStore.delete_entry(entry_id):
		_show_status("✓ 已删除条目", 2.0, Color(0, 0.8, 0.4))
		_update_list()
	else:
		_show_status("删除失败", 3.0, Color(1, 0.3, 0.3))

func _on_back() -> void:
	# 返回到聊天页面
	get_tree().change_scene_to_file("res://scenes/chat/chat.tscn")

func _on_knowledge_toggled(enabled: bool) -> void:
	VectorStore.set_knowledge_enabled(enabled)
	_update_disable_indicator()
	_show_status("知识库已%s" % ("启用" if enabled else "禁用"), 2.0, Color(0.3, 0.7, 1))

func _on_clear_pressed() -> void:
	# 使用 confirm_dialog 的自定义方法，传入提示文本
	confirm_dialog.show_dialog("确定要清空所有知识库条目吗？\n此操作不可撤销！")

func _clear_all() -> void:
	VectorStore.clear_all()
	_show_status("✓ 已清空知识库", 3.0, Color(1, 0.7, 0))
	_update_list()

func _on_file_selected(path: String) -> void:
	_selected_file_path = path
	label_file_path.text = path.get_file()
	button_build.disabled = false
	_show_status("已选择文件：%s" % path.get_file(), 2.0, Color(0.3, 0.7, 1))

func _on_file_dialog_button_pressed() -> void:
	AndroidPermissions.request_for_file_pick(func(granted: bool):
		if not granted:
			_show_status("需要存储权限才能选择文件", 3.0, Color(1, 0.3, 0.3))
			return
		file_dialog.filters = ["*.txt ; 文本文件"]
		file_dialog.use_native_dialog = true
		file_dialog.popup_centered(Vector2i(900, 700))
	)

func _on_build_pressed() -> void:
	if _is_building:
		return
	if _selected_file_path.is_empty():
		_show_status("请先选择TXT文件", 3.0, Color(1, 0.3, 0.3))
		return

	print("[KnowledgeBase] 开始构建知识库，嵌入用时开始计时")
	var embed_start_time := Time.get_ticks_msec()
	
	_is_building = true
	button_build.disabled = true
	_show_status("正在读取文件...", 0, Color(0.3, 0.7, 1))

	var file := FileAccess.open(_selected_file_path, FileAccess.READ)
	if file == null:
		_show_status("无法打开文件", 3.0, Color(1, 0.3, 0.3))
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
		_show_status("文件内容为空", 3.0, Color(1, 0.3, 0.3))
		_is_building = false
		button_build.disabled = false
		return

	var total_batches := ceili(float(texts.size()) / 16.0)
	_show_status("正在构建 %d 条目 (共 %d 批)..." % [texts.size(), total_batches], 0, Color(0.3, 0.7, 1))

	EmbedService.embed_batch(texts, 
		func(embeddings: Array, error: String):
			var embed_elapsed := Time.get_ticks_msec() - embed_start_time
			print("[KnowledgeBase] 嵌入完成，用时 %d ms" % embed_elapsed)
			
			if not error.is_empty():
				_show_status("嵌入失败: " + error, 3.0, Color(1, 0.3, 0.3))
				_is_building = false
				button_build.disabled = false
				return

			_show_status("正在存储条目...", 0, Color(0.3, 0.7, 1))

			var entries: Array[Dictionary] = []
			for i in range(texts.size()):
				if i < embeddings.size():
					entries.append({
						"id": UUIDUtil.v4(),
						"text": texts[i],
						"embedding": embeddings[i]
					})

			var added := VectorStore.add_entries(entries)
			_show_status("✓ 已添加 %d 条目" % added, 3.0, Color(0, 0.8, 0.4))
			_update_list()

			_is_building = false
			button_build.disabled = false
			_selected_file_path = ""
			label_file_path.text = "未选择文件",
		func(current: int, total: int):
			_show_status("正在嵌入... (进度：%d/%d)" % [current, total], 0, Color(0.3, 0.7, 1))
	)

func _on_add_pressed() -> void:
	var text := textedit_input.text.strip_edges()
	if text.is_empty():
		_show_status("请输入知识内容", 3.0, Color(1, 0.3, 0.3))
		return

	_show_status("正在添加...", 0, Color(0.3, 0.7, 1))
	EmbedService.embed_text(text, func(embeddings: Array, error: String):
		if not error.is_empty():
			_show_status("嵌入失败: " + error, 3.0, Color(1, 0.3, 0.3))
			return

		if embeddings.is_empty() or embeddings[0].is_empty():
			_show_status("嵌入结果为空", 3.0, Color(1, 0.3, 0.3))
			return

		var entry := {
			"id": UUIDUtil.v4(),
			"text": text,
			"embedding": embeddings[0]
		}

		if VectorStore.add_entry(entry):
			_show_status("✓ 已添加条目", 2.0, Color(0, 0.8, 0.4))
			textedit_input.text = ""
			_update_list()
		else:
			_show_status("添加失败", 3.0, Color(1, 0.3, 0.3))
	)

func _on_search_pressed() -> void:
	if _is_searching:
		return

	var query := textedit_query.text.strip_edges()
	if query.is_empty():
		_show_status("请输入查询文本", 3.0, Color(1, 0.3, 0.3))
		return

	print("[KnowledgeBase] 开始检索测试，嵌入用时开始计时")
	var embed_start_time := Time.get_ticks_msec()
	
	_is_searching = true
	button_search.disabled = true
	_current_query = ""
	_show_status("正在检索...", 0, Color(0.3, 0.7, 1))

	EmbedService.embed_text(query, func(embeddings: Array, error: String):
		var embed_elapsed := Time.get_ticks_msec() - embed_start_time
		print("[KnowledgeBase] 查询嵌入完成，用时 %d ms" % embed_elapsed)
		
		if not error.is_empty():
			_show_status("嵌入失败: " + error, 3.0, Color(1, 0.3, 0.3))
			_is_searching = false
			button_search.disabled = false
			return

		if embeddings.is_empty() or embeddings[0].is_empty():
			_show_status("嵌入结果为空", 3.0, Color(1, 0.3, 0.3))
			_is_searching = false
			button_search.disabled = false
			return

		var threshold := threshold_slider.value
		var results := VectorStore.search(embeddings[0], 20, threshold)

		_refresh_results(results)
		_show_status("✓ 找到 %d 条相关结果" % results.size(), 3.0, Color(0, 0.8, 0.4))

		_is_searching = false
		button_search.disabled = false
	)

func _on_match_search_pressed() -> void:
	if _is_searching:
		return

	var query := textedit_query.text.strip_edges()
	if query.is_empty():
		_show_status("请输入查询文本", 3.0, Color(1, 0.3, 0.3))
		return

	_is_searching = true
	button_match_search.disabled = true
	_current_query = query
	_show_status("正在匹配检索...", 0, Color(0.3, 0.7, 1))

	var all_entries := VectorStore.get_all_entries()
	var matched_results: Array[Dictionary] = []

	for entry in all_entries:
		var text: String = entry.get("text", "")
		if text.to_lower().contains(query.to_lower()):
			matched_results.append(entry)

	_refresh_results_with_highlight(matched_results, query)
	_show_status("✓ 匹配到 %d 条结果" % matched_results.size(), 3.0, Color(0, 0.8, 0.4))

	_is_searching = false
	button_match_search.disabled = false

func _refresh_results_with_highlight(results: Array[Dictionary], query: String) -> void:
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
		var item := _create_result_item_with_highlight(result, query)
		results_list.add_child(item)

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

	var hbox := HBoxContainer.new()

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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

	var delete_btn := Button.new()
	delete_btn.text = "🗑删除"
	delete_btn.theme = red_button_theme
	delete_btn.custom_minimum_size = Vector2(60, 50)
	delete_btn.pressed.connect(func():
		var entry_id: String = result.get("id", "")
		if VectorStore.delete_entry(entry_id):
			_show_status("✓ 已删除条目", 2.0, Color(0, 0.8, 0.4))
			_update_list()
			container.queue_free()
		else:
			_show_status("删除失败", 3.0, Color(1, 0.3, 0.3))
	)

	hbox.add_child(vbox)
	hbox.add_child(delete_btn)

	margin.add_child(hbox)
	container.add_child(margin)

	return container

func _create_result_item_with_highlight(result: Dictionary, query: String) -> Control:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(0, 80)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)

	var hbox := HBoxContainer.new()

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var text_label := RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.add_theme_font_size_override("normal_font_size", 22)

	var full_text: String = result.get("text", "")
	var highlighted_text := _highlight_keyword(full_text, query)
	text_label.text = highlighted_text

	vbox.add_child(text_label)

	var delete_btn := Button.new()
	delete_btn.text = "🗑删除"
	delete_btn.theme = red_button_theme
	delete_btn.custom_minimum_size = Vector2(60, 50)
	delete_btn.pressed.connect(func():
		var entry_id: String = result.get("id", "")
		if VectorStore.delete_entry(entry_id):
			_show_status("✓ 已删除条目", 2.0, Color(0, 0.8, 0.4))
			_update_list()
			container.queue_free()
		else:
			_show_status("删除失败", 3.0, Color(1, 0.3, 0.3))
	)

	hbox.add_child(vbox)
	hbox.add_child(delete_btn)

	margin.add_child(hbox)
	container.add_child(margin)

	return container

func _highlight_keyword(text: String, keyword: String) -> String:
	if keyword.is_empty():
		return text

	var regex := RegEx.new()
	var escaped := keyword
	for special_char in [".", "*", "+", "?", "(", ")", "[", "]", "{", "}", "^", "$", "|", "\\"]:
		escaped = escaped.replace(special_char, "\\" + special_char)
	regex.compile("(?i)(" + escaped + ")")
	return regex.sub(text, "[color=yellow]$1[/color]", true)

func _on_threshold_changed(value: float) -> void:
	label_threshold.text = "%.2f" % value
