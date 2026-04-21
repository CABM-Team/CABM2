## ChatUIController.gd
## 聊天界面 UI 控制器：立绘、表情、逐字显示、动画、历史弹窗等

extends Node

# ── 节点引用（从父节点 Chat 出发）────────────────────────────
@onready var background: TextureRect       = $"../Background"
@onready var background_overlay: ColorRect = $"../BackgroundOverlay"
@onready var character_sprite: Sprite2D    = $"../CharacterSprite"
@onready var character_sprite2: Sprite2D   = $"../CharacterSprite2"
@onready var character_name_label: Label   = $"../Header/CharacterName"
@onready var speaker_label: Label          = $"../DialogArea/VBox/SpeakerLabel"
@onready var dialog_text: RichTextLabel    = $"../DialogArea/VBox/DialogText"
@onready var continue_hint: Label          = $"../DialogArea/ContinueHint"
@onready var message_input: TextEdit       = $"../InputArea/MessageInput"
@onready var send_button: Button           = $"../InputArea/SendButton"
@onready var back_button: Button           = $"../Header/BackButton"
@onready var history_button: Button        = $"../ControlButtons/HistoryButton"
@onready var history_modal: PanelContainer = $"../HistoryModal"
@onready var history_list: VBoxContainer   = $"../HistoryModal/HistoryVBox/HistoryScroll/HistoryList"
@onready var close_history_btn: Button     = $"../HistoryModal/HistoryVBox/HistoryHeader/CloseHistoryButton"
@onready var prev_page_btn: Button         = $"../HistoryModal/HistoryVBox/HistoryHeader/PrevPageButton"
@onready var next_page_btn: Button         = $"../HistoryModal/HistoryVBox/HistoryHeader/NextPageButton"
@onready var page_label: Label             = $"../HistoryModal/HistoryVBox/HistoryHeader/PageLabel"
@onready var option_buttons: VBoxContainer = $"../OptionButtons"
@onready var more_option_button: Button    = $"../ControlButtons/MoreOptionButton"
@onready var tts_button: Button            = $"../ControlButtons/TTSButton"
@onready var more_options_overlay: Control = $"../MoreOptionsOverlay"
@onready var more_options_menu: PanelContainer = $"../MoreOptionsOverlay/MoreOptionsMenu"
@onready var more_options_click_area: ColorRect = $"../MoreOptionsOverlay/ClickArea"
@onready var clear_history_btn: Button     = $"../MoreOptionsOverlay/MoreOptionsMenu/VBoxContainer/MenuGrid/ClearHistoryButton"
@onready var delete_btn: Button            = $"../MoreOptionsOverlay/MoreOptionsMenu/VBoxContainer/MenuGrid/DeleteButton"

# ── 信号（通知主控制器）────────────────────────────────────────
signal send_requested
signal back_requested
signal history_toggle_requested
signal more_options_toggle_requested
signal clear_history_confirm_requested
signal delete_confirm_requested
signal advance_requested
signal input_key_enter
signal tts_requested(text: String)
signal history_tts_requested(text: String, char_id: String)

# ── 历史分页 ──────────────────────────────────────────────────
const HISTORY_PAGE_SIZE := 40
var _history_page := 1
var _history_data: Array = []
var _history_get_char_fn: Callable
var _history_extract_fn: Callable


var type_speed := 0.03

# ── 逐字显示状态 ──────────────────────────────────────────────
var _is_typing := false
var _full_text := ""
var _shown_chars := 0
var _type_timer: SceneTreeTimer
var _sentence_queue: Array[Dictionary] = []
var _waiting_for_advance := false

# ── continue_hint 动画 ────────────────────────────────────────
var _hint_tween: Tween = null
var _hint_base_y := 183.0

# ── 呼吸动画 ──────────────────────────────────────────────────
var _breath_time := 0.0
var _breath_active := false
var _base_scale := 1.0
var _base_scale2 := 1.0
var _breath_offset2 := 0.0

# ── 群聊立绘状态 ──────────────────────────────────────────────
var _displayed_chars: Array[Dictionary] = []
var _current_speaker_id := ""

# ── 等待动画 ──────────────────────────────────────────────────
var _dots_count := 0
var _dots_active := false
var _dots_gen := 0

# ── 初始化 ────────────────────────────────────────────────────
func _ready() -> void:
	send_button.pressed.connect(func(): send_requested.emit())
	back_button.pressed.connect(func(): back_requested.emit())
	history_button.pressed.connect(func(): history_toggle_requested.emit())
	close_history_btn.pressed.connect(func(): history_toggle_requested.emit())
	prev_page_btn.pressed.connect(_on_prev_page)
	next_page_btn.pressed.connect(_on_next_page)
	message_input.gui_input.connect(_on_input_key)
	more_option_button.pressed.connect(func(): more_options_toggle_requested.emit())
	tts_button.pressed.connect(_on_tts_button_pressed)
	more_options_click_area.gui_input.connect(_on_more_options_overlay_input)
	clear_history_btn.pressed.connect(func(): clear_history_confirm_requested.emit())
	delete_btn.pressed.connect(func(): delete_confirm_requested.emit())
	background.gui_input.connect(_on_background_input)
	background_overlay.gui_input.connect(_on_background_input)

	character_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	character_sprite2.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	character_sprite2.visible = false

# ── 全局输入 ──────────────────────────────────────────────────
func _on_background_input(event: InputEvent) -> void:
	if not _waiting_for_advance:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		advance_requested.emit()

func _input(event: InputEvent) -> void:
	if not _waiting_for_advance:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_F, KEY_SPACE]:
			get_viewport().set_input_as_handled()
			advance_requested.emit()

func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			input_key_enter.emit()
			get_viewport().set_input_as_handled()

func _on_more_options_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		more_options_overlay.visible = false

# ── 立绘管理 ──────────────────────────────────────────────────
func _resolve_image_path(char_id: String, filename: String) -> String:
	for base in ["user://characters/", "res://characters/"]:
		var p: String = base + char_id + "/" + filename
		if base.begins_with("user://"):
			if FileAccess.file_exists(p):
				return p
		elif ResourceLoader.exists(p):
			return p
	return ""

func _load_image_texture(path: String) -> ImageTexture:
	if path.begins_with("user://"):
		var img := Image.new()
		if img.load(path) != OK:
			return null
		return ImageTexture.create_from_image(img)
	else:
		if ResourceLoader.exists(path):
			return load(path)
		return null

func load_sprite(sprite: Sprite2D, char_data: Dictionary, mood: String) -> void:
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
			sprite.texture = _load_image_texture(path)
			return

func setup_single_character(char_data: Dictionary) -> void:
	var name_str: String = char_data.get("name", "未知角色")
	character_name_label.text = name_str
	speaker_label.text = name_str
	var color_str: String = char_data.get("color", "#ffffff")
	speaker_label.add_theme_color_override("font_color", Color.from_string(color_str, Color.WHITE))
	load_sprite(character_sprite, char_data, "")
	var scale_rate: float = char_data.get("scale_rate", 100) / 100.0
	_base_scale = scale_rate
	character_sprite.scale = Vector2(scale_rate, scale_rate)
	character_sprite.position.y = 1080 + char_data.get("calib", 0)
	character_sprite2.visible = false

func setup_group_header(group_data: Dictionary) -> void:
	character_name_label.text = group_data.get("name", "群聊")

func refresh_sprites(displayed_chars: Array[Dictionary]) -> void:
	# 记录哪些槽位是新角色（需要淡入）
	var slot0_new: bool = displayed_chars.size() >= 1 and (
		_displayed_chars.size() < 1 or
		_displayed_chars[0].get("id", "") != displayed_chars[0].get("id", "")
	)
	var slot1_new: bool = displayed_chars.size() >= 2 and (
		_displayed_chars.size() < 2 or
		_displayed_chars[1].get("id", "") != displayed_chars[1].get("id", "")
	)

	_displayed_chars = displayed_chars
	if _displayed_chars.size() == 0:
		character_sprite.visible = false
		character_sprite2.visible = false
		return

	var c0 := _displayed_chars[0]
	character_sprite.visible = true
	var s0: float = c0.get("scale_rate", 100) / 100.0
	_base_scale = s0
	character_sprite.scale = Vector2(s0, s0)
	character_sprite.position = Vector2(550, 1080 + c0.get("calib", 0))
	if slot0_new:
		character_sprite.modulate = Color(1, 1, 1, 0)
		load_sprite(character_sprite, c0, "")
		var tw0 := create_tween()
		tw0.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw0.tween_property(character_sprite, "modulate:a", 1.0, 0.4)
	else:
		load_sprite(character_sprite, c0, "")

	if _displayed_chars.size() >= 2:
		var c1 := _displayed_chars[1]
		character_sprite2.visible = true
		var s1: float = c1.get("scale_rate", 100) / 100.0
		_base_scale2 = s1
		character_sprite2.scale = Vector2(s1, s1)
		character_sprite2.position = Vector2(1150, 1080 + c1.get("calib", 0))
		if slot1_new:
			character_sprite2.modulate = Color(1, 1, 1, 0)
			load_sprite(character_sprite2, c1, "")
			var tw1 := create_tween()
			tw1.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw1.tween_property(character_sprite2, "modulate:a", 1.0, 0.4)
		else:
			load_sprite(character_sprite2, c1, "")
	else:
		character_sprite2.visible = false
	set_active_speaker("")

func set_active_speaker(speaker_id: String) -> void:
	_current_speaker_id = speaker_id
	if not AppState.is_group_mode():
		return
	var gray := Color(0.45, 0.45, 0.45, 1.0)
	var normal := Color(1, 1, 1, 1)
	# 活跃角色 z_index 高于后台角色（但低于 UI 层，UI 默认在 CanvasLayer 上）
	const Z_ACTIVE := -1
	const Z_INACTIVE := -2
	if speaker_id.is_empty():
		_tween_modulate(character_sprite, normal)
		_tween_modulate(character_sprite2, normal)
		character_sprite.z_index = Z_INACTIVE
		character_sprite2.z_index = Z_INACTIVE
		return
	if _displayed_chars.size() >= 1:
		var is_active0: bool = _displayed_chars[0].get("id", "") == speaker_id
		_tween_modulate(character_sprite, normal if is_active0 else gray)
		character_sprite.z_index = Z_ACTIVE if is_active0 else Z_INACTIVE
	if _displayed_chars.size() >= 2:
		var is_active1: bool = _displayed_chars[1].get("id", "") == speaker_id
		_tween_modulate(character_sprite2, normal if is_active1 else gray)
		character_sprite2.z_index = Z_ACTIVE if is_active1 else Z_INACTIVE

func _tween_modulate(sprite: Sprite2D, target: Color) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate", target, 0.3)

func get_sprite_for(char_id: String) -> Sprite2D:
	if _displayed_chars.size() >= 1 and _displayed_chars[0].get("id", "") == char_id:
		return character_sprite
	if _displayed_chars.size() >= 2 and _displayed_chars[1].get("id", "") == char_id:
		return character_sprite2
	return null

func set_speaker_label(char_data: Dictionary) -> void:
	speaker_label.text = char_data.get("name", "")
	var color_str: String = char_data.get("color", "#ffffff")
	speaker_label.add_theme_color_override("font_color", Color.from_string(color_str, Color.WHITE))

# ── 情绪切换 ──────────────────────────────────────────────────
func switch_mood_single(char_data: Dictionary, mood_index: int) -> void:
	var moods: Array = char_data.get("moods", [])
	if moods.is_empty():
		return
	var idx := clampi(mood_index, 1, moods.size())
	load_sprite(character_sprite, char_data, str(idx))
	play_jump_animation(character_sprite)

func switch_mood_for(char_data: Dictionary, mood_index: int) -> void:
	var moods: Array = char_data.get("moods", [])
	if moods.is_empty():
		return
	var idx := clampi(mood_index, 1, moods.size())
	var sprite := get_sprite_for(char_data.get("id", ""))
	if sprite:
		load_sprite(sprite, char_data, str(idx))
		play_jump_animation(sprite)

func play_jump_animation(sprite: Sprite2D) -> void:
	var base_y := sprite.position.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(sprite, "position:y", base_y - 40.0, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "position:y", base_y, 0.22).set_ease(Tween.EASE_IN)

# ── 逐字显示 ──────────────────────────────────────────────────
func show_text(text: String) -> void:
	stop_thinking_dots()
	_full_text = text
	_shown_chars = 0
	_is_typing = true
	_waiting_for_advance = false
	_hide_continue_hint()
	dialog_text.text = ""
	sentence_started.emit(text)
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
	# 通知主控制器句子显示完毕，由主控制器决定是否等待推进
	sentence_finished.emit()

signal sentence_finished
signal sentence_started(text: String)

func set_waiting_for_advance(value: bool) -> void:
	_waiting_for_advance = value
	if value:
		_show_continue_hint()
	else:
		_hide_continue_hint()

func skip_typing() -> void:
	if _is_typing:
		_is_typing = false
		dialog_text.text = _full_text
		_on_sentence_finished()

func is_typing() -> bool:
	return _is_typing

func is_waiting_for_advance() -> bool:
	return _waiting_for_advance

func get_sentence_queue() -> Array[Dictionary]:
	return _sentence_queue

func enqueue_sentence(sentence: Dictionary) -> void:
	if not _is_typing and not _waiting_for_advance:
		show_text(sentence.get("text", ""))
	else:
		_sentence_queue.append(sentence)

func pop_next_sentence() -> Dictionary:
	if _sentence_queue.is_empty():
		return {}
	return _sentence_queue.pop_front()

func has_queued_sentences() -> bool:
	return not _sentence_queue.is_empty()

func clear_sentence_queue() -> void:
	_sentence_queue.clear()

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
func start_thinking_dots() -> void:
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

func stop_thinking_dots() -> void:
	_dots_active = false
	_dots_gen += 1

# ── 输入区控制 ────────────────────────────────────────────────
func unlock_input() -> void:
	send_button.disabled = false
	message_input.editable = true
	message_input.placeholder_text = "输入消息…\nEnter 发送，Shift+Enter 换行"

func lock_input(placeholder: String = "角色正在回复...") -> void:
	send_button.disabled = true
	message_input.editable = false
	message_input.placeholder_text = placeholder

func get_input_text() -> String:
	return message_input.text.strip_edges()

func clear_input() -> void:
	message_input.text = ""

func hide_option_buttons() -> void:
	option_buttons.visible = false

# ── 更多选项 ──────────────────────────────────────────────────
func toggle_more_options() -> void:
	more_options_overlay.visible = not more_options_overlay.visible
	if more_options_overlay.visible:
		history_modal.visible = false

func hide_more_options() -> void:
	more_options_overlay.visible = false

func update_delete_button(is_group: bool, char_id: String) -> void:
	if is_group:
		delete_btn.text = "❌删除群聊"
		delete_btn.disabled = false
	else:
		var is_builtin := FileAccess.file_exists("res://characters/%s/%s.json" % [char_id, char_id])
		delete_btn.text = "❌删除角色"
		delete_btn.disabled = is_builtin

# ── 历史弹窗 ──────────────────────────────────────────────────
func toggle_history() -> void:
	history_modal.visible = not history_modal.visible

func is_history_visible() -> bool:
	return history_modal.visible

func hide_history() -> void:
	history_modal.visible = false

func refresh_history(chat_history: Array, get_char_data_fn: Callable, extract_msg_fn: Callable) -> void:
	# 过滤掉 system 消息，缓存数据，重置到第1页
	_history_get_char_fn = get_char_data_fn
	_history_extract_fn = extract_msg_fn
	_history_data = chat_history.filter(func(m): return m["role"] != "system")
	_history_page = 1
	_render_history_page()

func _on_prev_page() -> void:
	_history_page += 1
	_render_history_page()

func _on_next_page() -> void:
	_history_page -= 1
	_render_history_page()

func _render_history_page() -> void:
	var total: int = _history_data.size()
	var total_pages: int = max(1, ceili(float(total) / HISTORY_PAGE_SIZE))
	_history_page = clampi(_history_page, 1, total_pages)

	# 第1页 = 最新的40条（末尾），第2页 = 倒数41~80条，以此类推
	var end_idx: int = total - (_history_page - 1) * HISTORY_PAGE_SIZE
	var start_idx: int = max(0, end_idx - HISTORY_PAGE_SIZE)
	var page_msgs: Array = _history_data.slice(start_idx, end_idx)

	# 更新翻页按钮状态
	prev_page_btn.disabled = (_history_page >= total_pages)  # ◀ 上一页（更旧）
	next_page_btn.disabled = (_history_page <= 1)            # ▶ 下一页（更新）
	page_label.text = "%d" % _history_page

	# 清空列表
	for child in history_list.get_children():
		child.queue_free()

	if page_msgs.is_empty():
		var empty := RichTextLabel.new()
		empty.bbcode_enabled = true
		empty.fit_content = true
		empty.text = "[color=gray]暂无历史记录[/color]"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		history_list.add_child(empty)
	else:
		for msg in page_msgs:
			var role: String = msg["role"]
			var is_user := role == "user"
			var display_name := ""
			var color_str := "#aaaaff"
			var char_id := ""
			var display_content := ""

			if is_user:
				display_name = "你"
				color_str = "#00ffff"
				display_content = msg["content"]
			else:
				if AppState.is_group_mode():
					var cd: Dictionary = _history_get_char_fn.call(role)
					if not cd.is_empty():
						display_name = cd.get("name", role)
						color_str = cd.get("color", "#aaaaff")
						char_id = cd.get("id", role)
					else:
						display_name = role
						char_id = role
				else:
					display_name = AppState.current_character.get("name", "AI")
					color_str = AppState.current_character.get("color", "#aaaaff")
					char_id = AppState.current_character.get("id", "")
				display_content = _history_extract_fn.call(msg["content"])

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			history_list.add_child(row)
			history_list.add_child(HSeparator.new())

			var btn := Button.new()
			btn.text = "💬" if is_user else "🔊"
			btn.flat = true
			btn.add_theme_font_size_override("font_size", 25)
			btn.focus_mode = Control.FOCUS_NONE
			btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			if is_user:
				btn.disabled = true
				btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				var captured_text := display_content
				var captured_id := char_id
				btn.pressed.connect(func(): history_tts_requested.emit(captured_text, captured_id))
			row.add_child(btn)

			var label := RichTextLabel.new()
			label.bbcode_enabled = true
			label.fit_content = true
			label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.text = "[color=%s]%s[/color]：%s" % [color_str, display_name, display_content]
			row.add_child(label)

	var scroll: ScrollContainer = $"../HistoryModal/HistoryVBox/HistoryScroll"
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

# ── 呼吸动画 ──────────────────────────────────────────────────
func start_breath_animation() -> void:
	_breath_time = 0.0
	_breath_active = true
	_breath_offset2 = randf_range(0.8, 2.4)

func _process(delta: float) -> void:
	if not _breath_active:
		return
	_breath_time += delta
	character_sprite.scale.y = _base_scale + 0.003 * sin(_breath_time * PI / 2.0)
	if character_sprite2.visible:
		character_sprite2.scale.y = _base_scale2 + 0.003 * sin(_breath_time * PI / 2.0 + _breath_offset2)

# ── TTS 按钮 ──────────────────────────────────────────────────
func set_tts_enabled(enabled: bool) -> void:
	tts_button.disabled = not enabled

func set_tts_loading(loading: bool) -> void:
	if loading:
		tts_button.text = "⏳ 播放语音"
		tts_button.disabled = true
	else:
		tts_button.text = "🔊 播放语音"
		tts_button.disabled = false

func _on_tts_button_pressed() -> void:
	tts_requested.emit(dialog_text.text)
