## ChatController.gd
## 对话页面主控制器

extends Control

# ── 节点引用 ──────────────────────────────────────────────────
@onready var background: TextureRect       = $Background
@onready var character_sprite: Sprite2D    = $CharacterSprite
@onready var character_name_label: Label   = $Header/CharacterName
@onready var speaker_label: Label          = $DialogArea/VBox/SpeakerLabel
@onready var dialog_text: RichTextLabel    = $DialogArea/VBox/DialogText
@onready var continue_hint: Label          = $DialogArea/ContinueHint
@onready var message_input: TextEdit       = $InputArea/MessageInput
@onready var send_button: Button           = $InputArea/SendButton
@onready var back_button: Button           = $Header/BackButton
@onready var history_button: Button        = $ControlButtons/HistoryButton
@onready var history_modal: PanelContainer = $HistoryModal
@onready var history_list: VBoxContainer   = $HistoryModal/HistoryVBox/HistoryScroll/HistoryList
@onready var close_history_btn: Button     = $HistoryModal/HistoryVBox/HistoryHeader/CloseHistoryButton
@onready var option_buttons: VBoxContainer = $OptionButtons

# ── 输出速度（秒/字），可在运行时调整 ────────────────────────
var type_speed := 0.03

# ── 逐字显示状态 ──────────────────────────────────────────────
var _is_typing := false          # 正在逐字输出中
var _full_text := ""             # 当前句子完整文本
var _shown_chars := 0            # 已显示字符数
var _type_timer: SceneTreeTimer  # 逐字计时器

# 句子队列（显示进程从这里取，接收进程往这里写，两者独立）
var _sentence_queue: Array[String] = []

# 等待用户确认继续（句子打完后暂停）
var _waiting_for_advance := false

# ── 流式接收状态（独立于显示进程）────────────────────────────
var _stream_state := SentenceSplitter.StreamState.new()  # 流式分句状态
var _stream_full_content := ""   # 本轮完整 content（存历史用）
var _is_receiving := false       # 是否正在接收流

# ── continue_hint 动画 ────────────────────────────────────────
var _hint_tween: Tween = null
var _hint_base_y := 183.0          # continue_hint 初始 Y（相对父节点）

# ── 呼吸动画 ──────────────────────────────────────────────────
var _breath_time := 0.0
var _breath_active := false
var _base_scale := 1.0

# ── 初始化 ────────────────────────────────────────────────────
func _ready() -> void:
	send_button.pressed.connect(_on_send_pressed)
	back_button.pressed.connect(_on_back_pressed)
	history_button.pressed.connect(_toggle_history)
	close_history_btn.pressed.connect(_toggle_history)
	message_input.gui_input.connect(_on_input_key)

	# 连接 ApiClient 信号
	ApiClient.stream_chunk.connect(_on_stream_chunk)
	ApiClient.stream_mood.connect(_on_stream_mood)
	ApiClient.stream_done.connect(_on_stream_done)
	ApiClient.stream_error.connect(_on_stream_error)

	character_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_load_character(AppState.current_character)
	_start_breath_animation()

# ── 全局输入（继续对话：点击/Enter/F/Space）──────────────────
func _input(event: InputEvent) -> void:
	if not _waiting_for_advance:
		return
	var triggered := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		triggered = true
	elif event is InputEventKey and event.pressed and not event.echo:
		triggered = event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_F, KEY_SPACE]
	if triggered:
		get_viewport().set_input_as_handled()
		_advance()

# ── 角色加载 ──────────────────────────────────────────────────
func _load_character(char_data: Dictionary) -> void:
	if char_data.is_empty():
		_show_text("请先选择一个角色。")
		return

	var name_str: String = char_data.get("name", "未知角色")
	character_name_label.text = name_str
	speaker_label.text = name_str

	var color_str: String = char_data.get("color", "#ffffff")
	speaker_label.add_theme_color_override("font_color", Color.from_string(color_str, Color.WHITE))

	_load_sprite(char_data, "")

	var scale_rate: float = char_data.get("scale_rate", 100) / 100.0
	_base_scale = scale_rate
	character_sprite.scale = Vector2(scale_rate, scale_rate)
	character_sprite.position.y = 1080 + char_data.get("calib", 0)

	# 加载历史记录
	var character_id: String = char_data.get("id", name_str)
	var loaded_history := HistoryManager.load_history(character_id)
	
	# 添加 system prompt
	var prompt: String = char_data.get("prompt", "")
	if not prompt.is_empty():
		AppState.add_message("system", prompt)
	
	# 恢复历史消息到 AppState
	for msg in loaded_history:
		AppState.chat_history.append(msg)
	
	# 显示欢迎语或最后一条消息
	var welcome: String = char_data.get("welcome", "你好！")
	if loaded_history.is_empty():
		_show_text(welcome)
	else:
		# 如果有历史记录，显示最后一条 AI 消息
		for i in range(loaded_history.size() - 1, -1, -1):
			if loaded_history[i]["role"] == "assistant":
				_show_text(loaded_history[i]["content"])
				break

func _load_sprite(char_data: Dictionary, mood: String) -> void:
	var image_dir: String = char_data.get("image", "")
	if image_dir.is_empty():
		return
	var candidates: Array[String] = [
		image_dir + "/" + mood + ".png",
		image_dir + "/1.png",
	]
	for path in candidates:
		if ResourceLoader.exists(path):
			character_sprite.texture = load(path)
			return

# ── 情绪立绘切换 ──────────────────────────────────────────────
func _switch_mood(mood_index: int) -> void:
	var char_data := AppState.current_character
	var moods: Array = char_data.get("moods", [])
	if moods.is_empty():
		return
	var idx := clampi(mood_index, 1, moods.size())
	_load_sprite(char_data, str(idx))
	_play_jump_animation()

func _play_jump_animation() -> void:
	var base_y := character_sprite.position.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(character_sprite, "position:y", base_y - 40.0, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(character_sprite, "position:y", base_y, 0.22).set_ease(Tween.EASE_IN)

# ── 逐字显示（显示进程）──────────────────────────────────────
func _show_text(text: String) -> void:
	_stop_thinking_dots()   # 第一个字符要输出了，停掉 dots
	_full_text = text
	_shown_chars = 0
	_is_typing = true
	_waiting_for_advance = false
	_hide_continue_hint()
	dialog_text.text = ""
	_type_next_char()

func _type_next_char() -> void:
	if not _is_typing:
		return
	if _shown_chars >= _full_text.length():
		_on_sentence_finished()
		return
	_shown_chars += 1
	dialog_text.text = _full_text.substr(0, _shown_chars)
	_type_timer = get_tree().create_timer(type_speed)
	_type_timer.timeout.connect(_type_next_char, CONNECT_ONE_SHOT)

func _on_sentence_finished() -> void:
	_is_typing = false
	dialog_text.text = _full_text

	# 是否还有更多内容
	var has_more := not _sentence_queue.is_empty() or _is_receiving
	if has_more:
		# 2. 中间句：显示 hint，等用户点击
		_waiting_for_advance = true
		_show_continue_hint()
	else:
		# 2. 最后一句：不显示 hint，直接解锁输入
		_unlock_input()

# 用户触发"继续"
func _advance() -> void:
	_waiting_for_advance = false
	_hide_continue_hint()

	if not _sentence_queue.is_empty():
		var next: String = _sentence_queue.pop_front()
		_show_text(next)
	elif not _is_receiving:
		# 队列空且流结束，已在 _on_sentence_finished 里解锁了 send_button
		pass

# 跳过当前句子的逐字动画（直接显示完整文本，然后触发 finished）
func _skip_typing() -> void:
	if _is_typing:
		_is_typing = false
		dialog_text.text = _full_text
		_on_sentence_finished()

# ── continue_hint 动画 ────────────────────────────────────────
func _show_continue_hint() -> void:
	continue_hint.visible = true
	continue_hint.modulate.a = 1.0
	continue_hint.position.y = _hint_base_y

	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.set_loops()
	# 上下浮动 4px，周期 1.2s
	_hint_tween.tween_property(continue_hint, "position:y", _hint_base_y - 4.0, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hint_tween.tween_property(continue_hint, "position:y", _hint_base_y, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 闪烁（独立 tween）
	var blink_tween := create_tween()
	blink_tween.set_loops()
	blink_tween.tween_property(continue_hint, "modulate:a", 0.2, 0.5)
	blink_tween.tween_property(continue_hint, "modulate:a", 1.0, 0.5)
	# 把闪烁 tween 存起来方便 kill
	continue_hint.set_meta("blink_tween", blink_tween)

func _hide_continue_hint() -> void:
	if _hint_tween:
		_hint_tween.kill()
		_hint_tween = null
	if continue_hint.has_meta("blink_tween"):
		var bt: Tween = continue_hint.get_meta("blink_tween")
		bt.kill()
		continue_hint.remove_meta("blink_tween")
	continue_hint.visible = false
	continue_hint.modulate.a = 1.0
	continue_hint.position.y = _hint_base_y

# ── 等待动画（"." ".." "..."）────────────────────────────────
var _dots_timer: SceneTreeTimer = null
var _dots_count := 0
var _dots_active := false

func _start_thinking_dots() -> void:
	_dots_active = true
	_dots_count = 0
	dialog_text.text = "."
	_schedule_dots()

func _schedule_dots() -> void:
	_dots_timer = get_tree().create_timer(0.5)
	_dots_timer.timeout.connect(_tick_dots, CONNECT_ONE_SHOT)

func _tick_dots() -> void:
	if not _dots_active:
		return
	_dots_count = (_dots_count + 1) % 4
	dialog_text.text = ".".repeat(_dots_count)
	_schedule_dots()

func _stop_thinking_dots() -> void:
	_dots_active = false
	_dots_timer = null

func _unlock_input() -> void:
	send_button.disabled = false
	message_input.editable = true
	message_input.placeholder_text = "输入消息…
Enter 发送，Shift+Enter 换行"

# ── 发送消息 ──────────────────────────────────────────────────
func _on_send_pressed() -> void:
	var text := message_input.text.strip_edges()
	if text.is_empty() or _is_typing or _is_receiving or _waiting_for_advance:
		return
	_send_message(text)

func _send_message(text: String) -> void:
	message_input.text = ""
	send_button.disabled = true
	message_input.editable = false   # 1. 禁用输入框
	var char_name: String = AppState.current_character.get("name", "AI")
	message_input.placeholder_text = char_name + "正在说话..."
	option_buttons.visible = false
	_hide_continue_hint()
	_waiting_for_advance = false

	AppState.add_message("user", text)

	_stream_state = SentenceSplitter.StreamState.new()
	_stream_full_content = ""
	_sentence_queue.clear()
	_is_receiving = true

	# 3. 启动等待动画（"." → ".." → "..."）
	_start_thinking_dots()

	ApiClient.chat_completion(AppState.get_messages_for_api())

func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			_on_send_pressed()
			get_viewport().set_input_as_handled()

# ── 流式接收（接收进程，独立于显示进程）──────────────────────
func _enqueue_sentence(sentence: String) -> void:
	# 接收进程：只往队列写，或在显示进程空闲时直接启动显示
	if not _is_typing and not _waiting_for_advance:
		_show_text(sentence)
	else:
		_sentence_queue.append(sentence)

func _on_stream_chunk(text: String) -> void:
	_stream_full_content += text
	var sentences := SentenceSplitter.split_stream(_stream_state, text)
	for s in sentences:
		_enqueue_sentence(s["text"])

func _on_stream_mood(mood: int) -> void:
	_switch_mood(mood)

func _on_stream_done() -> void:
	_is_receiving = false
	var sentences := SentenceSplitter.split_stream(_stream_state, "", true)
	for s in sentences:
		_enqueue_sentence(s["text"])
	if not _stream_full_content.is_empty():
		AppState.add_message("assistant", _stream_full_content)
		# AI 回复结束，保存历史记录
		_save_history()
	# 流结束时，如果显示进程正在等待且队列已空，说明刚才显示的是最后一句
	# 但当时 has_more 误判为 true（流还在），现在补救：撤掉 hint，解锁输入
	if _waiting_for_advance and _sentence_queue.is_empty() and not _is_typing:
		_waiting_for_advance = false
		_hide_continue_hint()
		_unlock_input()

func _on_stream_error(message: String) -> void:
	_is_receiving = false
	_is_typing = false
	_waiting_for_advance = false
	_stop_thinking_dots()
	_unlock_input()
	_show_text("⚠ " + message)

# ── 呼吸动画 ──────────────────────────────────────────────────
func _start_breath_animation() -> void:
	_breath_time = 0.0
	_breath_active = true

func _process(delta: float) -> void:
	if not _breath_active:
		return
	_breath_time += delta
	character_sprite.scale.y = _base_scale + 0.003 * sin(_breath_time * PI / 2.0)

# ── 历史记录 ──────────────────────────────────────────────────
func _toggle_history() -> void:
	history_modal.visible = not history_modal.visible
	if history_modal.visible:
		_refresh_history()

func _refresh_history() -> void:
	for child in history_list.get_children():
		child.queue_free()

	var char_name: String = AppState.current_character.get("name", "AI")
	var color_str: String = AppState.current_character.get("color", "#aaaaff")

	# 优化：使用单个 RichTextLabel 显示所有历史，避免大量节点导致卡顿
	var history_text := ""
	for msg in AppState.chat_history:
		var role: String = msg["role"]
		if role == "system":
			continue

		if role == "user":
			history_text += "[color=cyan]你[/color]：" + msg["content"] + "\n\n"
		else:
			history_text += "[color=%s]%s[/color]：%s\n\n" % [color_str, char_name, msg["content"]]

	if history_text.is_empty():
		history_text = "[color=gray]暂无历史记录[/color]"
	
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = history_text
	
	history_list.add_child(label)

## 保存当前对话历史到磁盘
func _save_history() -> void:
	var character_id: String = AppState.current_character.get("id", AppState.current_character.get("name", ""))
	if character_id.is_empty():
		push_warning("ChatController: 无法保存历史，角色 ID 为空")
		return
	HistoryManager.save_history(character_id, AppState.chat_history)

## 删除当前角色的历史记录（公开接口）
func delete_current_history() -> void:
	var character_id: String = AppState.current_character.get("id", AppState.current_character.get("name", ""))
	if character_id.is_empty():
		push_warning("ChatController: 无法删除历史，角色 ID 为空")
		return
	if HistoryManager.delete_history(character_id):
		AppState.clear_history()
		_refresh_history()
		_show_text("历史记录已清空。")

## 清空历史按钮回调
func _on_clear_history_pressed() -> void:
	delete_current_history()

# ── 导航 ──────────────────────────────────────────────────────
func _on_back_pressed() -> void:
	ApiClient.cancel()
	ApiClient.stream_chunk.disconnect(_on_stream_chunk)
	ApiClient.stream_mood.disconnect(_on_stream_mood)
	ApiClient.stream_done.disconnect(_on_stream_done)
	ApiClient.stream_error.disconnect(_on_stream_error)
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
