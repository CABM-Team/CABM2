## ChatController.gd
## 对话主循环控制器，支持单角色和群聊模式

extends Control

# ── 节点引用 ──────────────────────────────────────────────────
@onready var background: TextureRect       = $Background
@onready var character_sprite: Sprite2D    = $CharacterSprite
@onready var character_sprite2: Sprite2D   = $CharacterSprite2
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
@onready var more_option_button: Button    = $ControlButtons/MoreOptionButton
@onready var more_options_overlay: Control = $MoreOptionsOverlay
@onready var more_options_menu: PanelContainer = $MoreOptionsOverlay/MoreOptionsMenu
@onready var more_options_click_area: ColorRect = $MoreOptionsOverlay/ClickArea
@onready var clear_history_btn: Button     = $MoreOptionsOverlay/MoreOptionsMenu/VBoxContainer/MenuGrid/ClearHistoryButton
@onready var confirm_dialog = $ConfirmDialog

# ── 输出速度 ──────────────────────────────────────────────────
var type_speed := 0.03

# ── 逐字显示状态 ──────────────────────────────────────────────
var _is_typing := false
var _full_text := ""
var _shown_chars := 0
var _type_timer: SceneTreeTimer
var _sentence_queue: Array[String] = []
var _waiting_for_advance := false

# ── 流式接收状态 ──────────────────────────────────────────────
var _stream_state := SentenceSplitter.StreamState.new()
var _stream_full_content := ""
var _stream_display_content := ""
var _is_receiving := false

# ── continue_hint 动画 ────────────────────────────────────────
var _hint_tween: Tween = null
var _hint_base_y := 183.0

# ── 呼吸动画 ──────────────────────────────────────────────────
var _breath_time := 0.0
var _breath_active := false
var _base_scale := 1.0
var _base_scale2 := 1.0

# ── 群聊状态 ──────────────────────────────────────────────────
# 当前屏幕上显示的角色（最多2个），每项为角色数据 Dictionary
var _displayed_chars: Array[Dictionary] = []
# 当前正在发言的角色 ID
var _current_speaker_id := ""
# 群聊待处理的发言队列：[{char_data, full_json}]
var _group_reply_queue: Array[Dictionary] = []
# 正在等待某个角色的 API 响应
var _group_waiting_char_id := ""
# 本轮群聊已发言轮数（每次用户发送后重置）
var _group_turn_count := 0
const GROUP_MAX_TURNS := 5

# ── 表情状态 ──────────────────────────────────────────────────
# 单角色：当前表情索引（0 = 默认）
var _current_mood := 0
# 群聊：各角色最后表情 { char_id: mood_index }
var _group_moods: Dictionary = {}

# ── 初始化 ────────────────────────────────────────────────────
func _ready() -> void:
	send_button.pressed.connect(_on_send_pressed)
	back_button.pressed.connect(_on_back_pressed)
	history_button.pressed.connect(_toggle_history)
	close_history_btn.pressed.connect(_toggle_history)
	message_input.gui_input.connect(_on_input_key)
	more_option_button.pressed.connect(_toggle_more_options)
	more_options_click_area.gui_input.connect(_on_more_options_overlay_input)
	clear_history_btn.pressed.connect(_show_clear_history_confirm)
	confirm_dialog.confirmed.connect(_on_clear_history_confirmed)
	confirm_dialog.cancelled.connect(_hide_confirm_dialog)

	ApiClient.stream_chunk.connect(_on_stream_chunk)
	ApiClient.stream_mood.connect(_on_stream_mood)
	ApiClient.stream_full_json.connect(_on_stream_full_json)
	ApiClient.stream_done.connect(_on_stream_done)
	ApiClient.stream_error.connect(_on_stream_error)

	character_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	character_sprite2.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	character_sprite2.visible = false

	if AppState.is_group_mode():
		_init_group_mode()
	else:
		_load_character(AppState.current_character)
	_start_breath_animation()

# ── 全局输入 ──────────────────────────────────────────────────
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

# ── 单角色模式：角色加载 ──────────────────────────────────────
func _load_character(char_data: Dictionary) -> void:
	if char_data.is_empty():
		_show_text("请先选择一个角色。")
		return

	var name_str: String = char_data.get("name", "未知角色")
	character_name_label.text = name_str
	speaker_label.text = name_str

	var color_str: String = char_data.get("color", "#ffffff")
	speaker_label.add_theme_color_override("font_color", Color.from_string(color_str, Color.WHITE))

	_load_sprite(character_sprite, char_data, "")

	var scale_rate: float = char_data.get("scale_rate", 100) / 100.0
	_base_scale = scale_rate
	character_sprite.scale = Vector2(scale_rate, scale_rate)
	character_sprite.position.y = 1080 + char_data.get("calib", 0)
	character_sprite2.visible = false

	var character_id: String = char_data.get("id", name_str)
	var save_data := HistoryManager.load_history(character_id)
	var loaded_history: Array[Dictionary] = save_data["history"]

	AppState.chat_history.clear()
	var prompt: String = char_data.get("prompt", "")
	if not prompt.is_empty():
		AppState.add_message("system", prompt)
	for msg in loaded_history:
		AppState.chat_history.append(msg)

	# 恢复最后表情
	_current_mood = int(save_data.get("last_mood", 0))
	if _current_mood > 0:
		_load_sprite(character_sprite, char_data, str(_current_mood))

	var welcome: String = char_data.get("welcome", "你好！")
	if loaded_history.is_empty():
		_show_text(welcome)
	else:
		for i in range(loaded_history.size() - 1, -1, -1):
			if loaded_history[i]["role"] == "assistant":
				_show_text(_extract_msg_from_json(loaded_history[i]["content"]))
				break

# ── 群聊模式：初始化 ──────────────────────────────────────────
func _init_group_mode() -> void:
	var group_data := AppState.current_group
	var chars := AppState.group_characters
	character_name_label.text = group_data.get("name", "群聊")

	# 加载历史
	var group_id: String = group_data.get("id", "")
	var save_data := HistoryManager.load_group_history(group_id)
	var loaded_history: Array[Dictionary] = save_data["history"]
	AppState.chat_history.clear()
	for msg in loaded_history:
		AppState.chat_history.append(msg)

	# 恢复表情状态
	var saved_moods = save_data.get("last_moods", {})
	_group_moods = saved_moods if saved_moods is Dictionary else {}

	# 恢复上次的屏幕布局，否则默认前两个
	_displayed_chars.clear()
	var saved_ids: Array = save_data.get("displayed_char_ids", [])
	if not saved_ids.is_empty():
		for sid in saved_ids:
			var cd := _get_char_data_by_id(sid)
			if not cd.is_empty():
				_displayed_chars.append(cd)
	if _displayed_chars.is_empty():
		for i in min(2, chars.size()):
			_displayed_chars.append(chars[i])
	_refresh_sprites()

	# 恢复各角色表情
	for cd in _displayed_chars:
		var cid: String = cd.get("id", "")
		var mood: int = int(_group_moods.get(cid, 0))
		if mood > 0:
			var sp := _get_sprite_for(cid)
			if sp:
				_load_sprite(sp, cd, str(mood))

	# 恢复高亮发言角色
	var saved_speaker: String = save_data.get("active_speaker_id", "")
	if not saved_speaker.is_empty():
		_set_active_speaker(saved_speaker)

	if loaded_history.is_empty():
		_show_text("已创建群聊")
	else:
		# 显示最后一条非 user/system 消息
		for i in range(loaded_history.size() - 1, -1, -1):
			var r: String = loaded_history[i].get("role", "")
			if r != "user" and r != "system":
				_set_speaker_by_id(r)
				_show_text(_extract_msg_from_json(loaded_history[i]["content"]))
				break

# ── 立绘管理 ──────────────────────────────────────────────────
## 按优先级查找图片：先 user://characters/<id>/，再 res://characters/<id>/
## mood 为空字符串时只找 1.png 回退
func _resolve_image_path(char_id: String, filename: String) -> String:
	for base in ["user://characters/", "res://characters/"]:
		var p: String = base + char_id + "/" + filename
		if ResourceLoader.exists(p):
			return p
	return ""

func _load_sprite(sprite: Sprite2D, char_data: Dictionary, mood: String) -> void:
	var char_id: String = char_data.get("id", "")
	if char_id.is_empty():
		return
	var candidates: Array[String] = []
	if not mood.is_empty():
		candidates.append(mood + ".png")
	candidates.append("1.png")
	for filename in candidates:
		var path := _resolve_image_path(char_id, filename)
		if not path.is_empty():
			sprite.texture = load(path)
			return

## 刷新双立绘显示（群聊模式）
func _refresh_sprites() -> void:
	var chars := _displayed_chars
	if chars.size() == 0:
		character_sprite.visible = false
		character_sprite2.visible = false
		return

	# 第一个角色：左侧
	var c0 := chars[0]
	character_sprite.visible = true
	_load_sprite(character_sprite, c0, "")
	var s0: float = c0.get("scale_rate", 100) / 100.0
	_base_scale = s0
	character_sprite.scale = Vector2(s0, s0)
	character_sprite.position = Vector2(550, 1080 + c0.get("calib", 0))

	if chars.size() >= 2:
		var c1 := chars[1]
		character_sprite2.visible = true
		_load_sprite(character_sprite2, c1, "")
		var s1: float = c1.get("scale_rate", 100) / 100.0
		_base_scale2 = s1
		character_sprite2.scale = Vector2(s1, s1)
		character_sprite2.position = Vector2(1150, 1080 + c1.get("calib", 0))
	else:
		character_sprite2.visible = false

	# 默认两个都灰色，等发言时高亮
	_set_active_speaker("")

## 设置高亮发言角色（其余变灰）
func _set_active_speaker(speaker_id: String) -> void:
	_current_speaker_id = speaker_id
	if not AppState.is_group_mode():
		return
	var gray := Color(0.45, 0.45, 0.45, 1.0)
	var normal := Color(1, 1, 1, 1)
	var chars := _displayed_chars

	if speaker_id.is_empty():
		character_sprite.modulate = normal
		character_sprite2.modulate = normal
		return

	if chars.size() >= 1:
		character_sprite.modulate = normal if chars[0].get("id", "") == speaker_id else gray
	if chars.size() >= 2:
		character_sprite2.modulate = normal if chars[1].get("id", "") == speaker_id else gray

## 确保某个角色在屏幕上，如果不在则随机替换一个
func _ensure_char_on_screen(char_data: Dictionary) -> void:
	var cid: String = char_data.get("id", "")
	for c in _displayed_chars:
		if c.get("id", "") == cid:
			return  # 已在屏幕上

	# 随机替换一个（0 或 1）
	var replace_idx := randi() % _displayed_chars.size()
	_displayed_chars[replace_idx] = char_data
	_refresh_sprites()

## 切换发言角色的立绘 mood
func _switch_mood_for(char_id: String, mood_index: int) -> void:
	var char_data := _get_char_data_by_id(char_id)
	if char_data.is_empty():
		return
	var moods: Array = char_data.get("moods", [])
	if moods.is_empty():
		return
	var idx := clampi(mood_index, 1, moods.size())
	_group_moods[char_id] = idx
	var sprite := _get_sprite_for(char_id)
	if sprite:
		_load_sprite(sprite, char_data, str(idx))
		_play_jump_animation(sprite)

func _get_sprite_for(char_id: String) -> Sprite2D:
	if _displayed_chars.size() >= 1 and _displayed_chars[0].get("id", "") == char_id:
		return character_sprite
	if _displayed_chars.size() >= 2 and _displayed_chars[1].get("id", "") == char_id:
		return character_sprite2
	return null

func _get_char_data_by_id(char_id: String) -> Dictionary:
	if AppState.is_group_mode():
		for c in AppState.group_characters:
			if c.get("id", "") == char_id:
				return c
	else:
		if AppState.current_character.get("id", "") == char_id:
			return AppState.current_character
	return {}

## 设置 speaker label 为某个角色 ID
func _set_speaker_by_id(char_id: String) -> void:
	var char_data := _get_char_data_by_id(char_id)
	if char_data.is_empty():
		return
	speaker_label.text = char_data.get("name", char_id)
	var color_str: String = char_data.get("color", "#ffffff")
	speaker_label.add_theme_color_override("font_color", Color.from_string(color_str, Color.WHITE))

# ── 单角色情绪切换 ────────────────────────────────────────────
func _switch_mood(mood_index: int) -> void:
	var char_data := AppState.current_character
	var moods: Array = char_data.get("moods", [])
	if moods.is_empty():
		return
	var idx := clampi(mood_index, 1, moods.size())
	_current_mood = idx
	_load_sprite(character_sprite, char_data, str(idx))
	_play_jump_animation(character_sprite)

func _play_jump_animation(sprite: Sprite2D) -> void:
	var base_y := sprite.position.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(sprite, "position:y", base_y - 40.0, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "position:y", base_y, 0.22).set_ease(Tween.EASE_IN)

# ── 逐字显示 ──────────────────────────────────────────────────
func _show_text(text: String) -> void:
	_stop_thinking_dots()
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

	var has_more_sentences := not _sentence_queue.is_empty() or _is_receiving
	var has_next_char := not _group_reply_queue.is_empty()

	if has_more_sentences or has_next_char:
		_waiting_for_advance = true
		_show_continue_hint()
	else:
		_unlock_input()

func _advance() -> void:
	_waiting_for_advance = false
	_hide_continue_hint()
	if not _sentence_queue.is_empty():
		var next: String = _sentence_queue.pop_front()
		_show_text(next)
	elif not _is_receiving and not _group_reply_queue.is_empty():
		# 当前角色说完，且没有更多句子，触发下一个角色请求
		_dispatch_next_group_char()

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
	_hint_tween.tween_property(continue_hint, "position:y", _hint_base_y - 4.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hint_tween.tween_property(continue_hint, "position:y", _hint_base_y, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var blink_tween := create_tween()
	blink_tween.set_loops()
	blink_tween.tween_property(continue_hint, "modulate:a", 0.2, 0.5)
	blink_tween.tween_property(continue_hint, "modulate:a", 1.0, 0.5)
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

# ── 等待动画 ──────────────────────────────────────────────────
var _dots_count := 0
var _dots_active := false
var _dots_gen := 0  # 版本号，防止旧循环残留

func _start_thinking_dots() -> void:
	_dots_gen += 1
	_dots_active = true
	_dots_count = 0
	dialog_text.text = ""
	_schedule_dots(_dots_gen)

func _schedule_dots(gen: int) -> void:
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(func(): _tick_dots(gen), CONNECT_ONE_SHOT)

func _tick_dots(gen: int) -> void:
	if not _dots_active or gen != _dots_gen:
		return
	_dots_count = (_dots_count + 1) % 4
	dialog_text.text = "·".repeat(_dots_count)
	_schedule_dots(gen)

func _stop_thinking_dots() -> void:
	_dots_active = false
	_dots_gen += 1  # 使所有旧循环失效

func _unlock_input() -> void:
	send_button.disabled = false
	message_input.editable = true
	message_input.placeholder_text = "输入消息…\nEnter 发送，Shift+Enter 换行"

# ── 发送消息 ──────────────────────────────────────────────────
func _on_send_pressed() -> void:
	var text := message_input.text.strip_edges()
	if text.is_empty() or _is_typing or _is_receiving or _waiting_for_advance:
		return
	_send_message(text)

func _send_message(text: String) -> void:
	message_input.text = ""
	send_button.disabled = true
	message_input.editable = false
	message_input.placeholder_text = "角色正在回复..."
	option_buttons.visible = false
	_hide_continue_hint()
	_waiting_for_advance = false

	AppState.add_message("user", text)

	_stream_state = SentenceSplitter.StreamState.new()
	_stream_full_content = ""
	_stream_display_content = ""
	_sentence_queue.clear()
	_is_receiving = true

	_start_thinking_dots()

	if AppState.is_group_mode():
		_start_group_replies()
	else:
		var messages := PromptBuilder.build_messages(
			AppState.get_messages_for_api(),
			AppState.current_character
		)
		ApiClient.chat_completion(messages)

func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			_on_send_pressed()
			get_viewport().set_input_as_handled()

# ── 群聊 AI 决定发言顺序 ──────────────────────────────────────
## 开始群聊回复：由 AI 决定第一个发言者
func _start_group_replies() -> void:
	_group_reply_queue.clear()
	_group_waiting_char_id = ""
	_group_turn_count = 0
	_ask_ai_next_speaker()

## 请求 AI 决定下一个发言的角色，然后发起该角色的对话请求
func _ask_ai_next_speaker() -> void:
	if _group_turn_count >= GROUP_MAX_TURNS:
		# 达到最大轮数，结束
		if not _is_typing and not _waiting_for_advance and _sentence_queue.is_empty():
			_unlock_input()
		return

	# 锁定输入，等待 AI 决策
	send_button.disabled = true
	message_input.editable = false
	print("【AI决策】排除："+_group_waiting_char_id)
	var chars := AppState.group_characters
	# 构建参与者 ID 列表（包含"user"，排除上一个发言者）
	var id_list: Array[String] = ["user"]
	for c in chars:
		var cid: String = c.get("id", "")
		if cid != _group_waiting_char_id:
			id_list.append(cid)

	# 构建最近上下文（最多取最后8条），用 id 标注发言者
	var recent: Array[Dictionary] = AppState.chat_history
	var start_idx := maxi(0, recent.size() - 8)
	var context_lines: Array[String] = []
	for i in range(start_idx, recent.size()):
		var msg := recent[i]
		var role: String = msg.get("role", "")
		if role == "system":
			continue
		var text := PromptBuilder._extract_msg(msg.get("content", ""))
		context_lines.append(role + "：" + text)

	var system_p := "你是一个专业的导演，根据对话上下文决定下一个最合适发言的人。\n参与者ID列表：%s\n只需回复一个ID，不要有任何其他内容。" % "、".join(id_list)
	var user_p := "最近的对话：\n%s\n\n下一个应该由谁发言？" % "\n".join(context_lines)

	EasyAI.ask(system_p, user_p, func(reply: String):
		var chosen_char := _match_char_by_id(reply)
		if chosen_char.is_empty():
			# AI 返回无效或选了"user"，结束本轮
			if not _is_typing and not _waiting_for_advance and _sentence_queue.is_empty():
				_unlock_input()
			return
		_group_turn_count += 1
		_request_group_char(chosen_char)
	)

## 根据 ID 匹配角色数据（返回空 dict 表示是"user"或未匹配）
func _match_char_by_id(char_id: String) -> Dictionary:
	var trimmed := char_id.strip_edges()
	for c in AppState.group_characters:
		if c.get("id", "") == trimmed:
			return c
	return {}

## 请求指定角色发言
func _request_group_char(char_data: Dictionary) -> void:
	var char_id: String = char_data.get("id", "")
	_group_waiting_char_id = char_id

	_ensure_char_on_screen(char_data)
	_set_active_speaker(char_id)
	_set_speaker_by_id(char_id)

	_stream_state = SentenceSplitter.StreamState.new()
	_stream_full_content = ""
	_stream_display_content = ""
	_is_receiving = true
	_start_thinking_dots()

	var messages := PromptBuilder.build_group_messages(
		char_data,
		AppState.group_characters,
		AppState.chat_history,
		AppState.current_group
	)
	ApiClient.chat_completion(messages)

# ── 流式接收 ──────────────────────────────────────────────────
func _enqueue_sentence(sentence: String) -> void:
	if not _is_typing and not _waiting_for_advance:
		_show_text(sentence)
	else:
		_sentence_queue.append(sentence)

func _on_stream_chunk(text: String) -> void:
	_stream_display_content += text
	var sentences := SentenceSplitter.split_stream(_stream_state, text)
	for s in sentences:
		_enqueue_sentence(s["text"])

func _on_stream_mood(mood: int) -> void:
	if AppState.is_group_mode():
		_switch_mood_for(_group_waiting_char_id, mood)
	else:
		_switch_mood(mood)

func _on_stream_full_json(json_str: String) -> void:
	_stream_full_content = json_str

func _on_stream_done() -> void:
	_is_receiving = false
	var sentences := SentenceSplitter.split_stream(_stream_state, "", true)
	for s in sentences:
		_enqueue_sentence(s["text"])

	if not _stream_full_content.is_empty():
		if AppState.is_group_mode():
			AppState.add_message(_group_waiting_char_id, _stream_full_content)
			_save_history()
			# 把"继续下一轮"放入队列，等当前文字显示完再触发
			_group_reply_queue.append({"ask_next": true})
		else:
			AppState.add_message("assistant", _stream_full_content)
			_save_history()

	# 如果当前没有在打字也没有在等待，手动触发 sentence_finished 逻辑
	if not _is_typing and not _waiting_for_advance and _sentence_queue.is_empty():
		var has_next_char := not _group_reply_queue.is_empty()
		if has_next_char:
			_waiting_for_advance = true
			_show_continue_hint()
		else:
			_unlock_input()

## 派发下一个群聊角色请求（由用户点击触发）
func _dispatch_next_group_char() -> void:
	if _group_reply_queue.is_empty():
		return
	_group_reply_queue.pop_front()
	_ask_ai_next_speaker()

func _on_stream_error(message: String) -> void:
	_is_receiving = false
	_is_typing = false
	_waiting_for_advance = false
	_group_reply_queue.clear()
	_group_waiting_char_id = ""
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
	if character_sprite2.visible:
		character_sprite2.scale.y = _base_scale2 + 0.003 * sin(_breath_time * PI / 2.0 + 0.5)

# ── 历史记录 ──────────────────────────────────────────────────
func _toggle_history() -> void:
	history_modal.visible = not history_modal.visible
	if history_modal.visible:
		_refresh_history()

func _refresh_history() -> void:
	for child in history_list.get_children():
		child.queue_free()

	var history_text := ""
	for msg in AppState.chat_history:
		var role: String = msg["role"]
		if role == "system":
			continue
		if role == "user":
			history_text += "[color=cyan]你[/color]：" + msg["content"] + "\n\n"
		else:
			# role 可能是 "assistant" 或 character_id
			var display_name := role
			var color_str := "#aaaaff"
			if AppState.is_group_mode():
				var cd := _get_char_data_by_id(role)
				if not cd.is_empty():
					display_name = cd.get("name", role)
					color_str = cd.get("color", "#aaaaff")
			else:
				display_name = AppState.current_character.get("name", "AI")
				color_str = AppState.current_character.get("color", "#aaaaff")
			var display_content := _extract_msg_from_json(msg["content"])
			history_text += "[color=%s]%s[/color]：%s\n\n" % [color_str, display_name, display_content]

	if history_text.is_empty():
		history_text = "[color=gray]暂无历史记录[/color]"

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = history_text
	history_list.add_child(label)

func _extract_msg_from_json(json_str: String) -> String:
	var json := JSON.new()
	if json.parse(json_str) == OK:
		var data: Dictionary = json.get_data()
		return data.get("msg", json_str)
	return json_str

func _save_history() -> void:
	if AppState.is_group_mode():
		var group_id: String = AppState.current_group.get("id", "")
		if not group_id.is_empty():
			var displayed_ids: Array = []
			for c in _displayed_chars:
				displayed_ids.append(c.get("id", ""))
			HistoryManager.save_group_history(group_id, AppState.chat_history,
				displayed_ids, _current_speaker_id, _group_moods)
	else:
		var character_id: String = AppState.current_character.get("id", AppState.current_character.get("name", ""))
		if not character_id.is_empty():
			HistoryManager.save_history(character_id, AppState.chat_history, _current_mood)

func delete_current_history() -> void:
	if AppState.is_group_mode():
		var group_id: String = AppState.current_group.get("id", "")
		HistoryManager.clear_group_history(group_id)
		AppState.chat_history.clear()
		# 重置群聊状态
		_group_moods.clear()
		_current_speaker_id = ""
		_displayed_chars.clear()
		var chars := AppState.group_characters
		for i in min(2, chars.size()):
			_displayed_chars.append(chars[i])
		_refresh_sprites()
	else:
		var character_id: String = AppState.current_character.get("id", AppState.current_character.get("name", ""))
		if HistoryManager.delete_history(character_id):
			AppState.chat_history.clear()
			var prompt: String = AppState.current_character.get("prompt", "")
			if not prompt.is_empty():
				AppState.add_message("system", prompt)
		# 重置单角色表情
		_current_mood = 0
		_load_sprite(character_sprite, AppState.current_character, "")
	AppState.history_updated.emit()
	_refresh_history()
	if AppState.is_group_mode():
		_show_text("群聊历史已清空。")
	else:
		_show_text(AppState.current_character.get("welcome", "你好！"))

# ── 更多选项 ──────────────────────────────────────────────────
func _toggle_more_options() -> void:
	more_options_overlay.visible = not more_options_overlay.visible
	if more_options_overlay.visible:
		history_modal.visible = false

func _on_more_options_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		more_options_overlay.visible = false

func _show_clear_history_confirm() -> void:
	more_options_overlay.visible = false
	confirm_dialog.show_dialog("⚠\n确定要清空历史记录吗？")

func _hide_confirm_dialog() -> void:
	confirm_dialog.hide_dialog()

func _on_clear_history_confirmed() -> void:
	delete_current_history()

# ── 导航 ──────────────────────────────────────────────────────
func _on_back_pressed() -> void:
	ApiClient.cancel()
	ApiClient.stream_chunk.disconnect(_on_stream_chunk)
	ApiClient.stream_mood.disconnect(_on_stream_mood)
	ApiClient.stream_full_json.disconnect(_on_stream_full_json)
	ApiClient.stream_done.disconnect(_on_stream_done)
	ApiClient.stream_error.disconnect(_on_stream_error)
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
