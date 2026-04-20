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
@onready var option_buttons: VBoxContainer = $"../OptionButtons"
@onready var more_option_button: Button    = $"../ControlButtons/MoreOptionButton"
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

# ── 输出速度 ──────────────────────────────────────────────────
var type_speed := 0.03

# ── 逐字显示状态 ──────────────────────────────────────────────
var _is_typing := false
var _full_text := ""
var _shown_chars := 0
var _type_timer: SceneTreeTimer
var _sentence_queue: Array[String] = []
var _waiting_for_advance := false

# ── continue_hint 动画 ────────────────────────────────────────
var _hint_tween: Tween = null
var _hint_base_y := 183.0

# ── 呼吸动画 ──────────────────────────────────────────────────
var _breath_time := 0.0
var _breath_active := false
var _base_scale := 1.0
var _base_scale2 := 1.0

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
	message_input.gui_input.connect(_on_input_key)
	more_option_button.pressed.connect(func(): more_options_toggle_requested.emit())
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
	_displayed_chars = displayed_chars
	if _displayed_chars.size() == 0:
		character_sprite.visible = false
		character_sprite2.visible = false
		return
	var c0 := _displayed_chars[0]
	character_sprite.visible = true
	load_sprite(character_sprite, c0, "")
	var s0: float = c0.get("scale_rate", 100) / 100.0
	_base_scale = s0
	character_sprite.scale = Vector2(s0, s0)
	character_sprite.position = Vector2(550, 1080 + c0.get("calib", 0))
	if _displayed_chars.size() >= 2:
		var c1 := _displayed_chars[1]
		character_sprite2.visible = true
		load_sprite(character_sprite2, c1, "")
		var s1: float = c1.get("scale_rate", 100) / 100.0
		_base_scale2 = s1
		character_sprite2.scale = Vector2(s1, s1)
		character_sprite2.position = Vector2(1150, 1080 + c1.get("calib", 0))
	else:
		character_sprite2.visible = false
	set_active_speaker("")

func set_active_speaker(speaker_id: String) -> void:
	_current_speaker_id = speaker_id
	if not AppState.is_group_mode():
		return
	var gray := Color(0.45, 0.45, 0.45, 1.0)
	var normal := Color(1, 1, 1, 1)
	if speaker_id.is_empty():
		character_sprite.modulate = normal
		character_sprite2.modulate = normal
		return
	if _displayed_chars.size() >= 1:
		character_sprite.modulate = normal if _displayed_chars[0].get("id", "") == speaker_id else gray
	if _displayed_chars.size() >= 2:
		character_sprite2.modulate = normal if _displayed_chars[1].get("id", "") == speaker_id else gray

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

func get_sentence_queue() -> Array[String]:
	return _sentence_queue

func enqueue_sentence(sentence: String) -> void:
	if not _is_typing and not _waiting_for_advance:
		show_text(sentence)
	else:
		_sentence_queue.append(sentence)

func pop_next_sentence() -> String:
	if _sentence_queue.is_empty():
		return ""
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
	for child in history_list.get_children():
		child.queue_free()

	var history_text := ""
	for msg in chat_history:
		var role: String = msg["role"]
		if role == "system":
			continue
		if role == "user":
			history_text += "[color=cyan]你[/color]：" + msg["content"] + "\n\n"
		else:
			var display_name := role
			var color_str := "#aaaaff"
			if AppState.is_group_mode():
				var cd: Dictionary = get_char_data_fn.call(role)
				if not cd.is_empty():
					display_name = cd.get("name", role)
					color_str = cd.get("color", "#aaaaff")
			else:
				display_name = AppState.current_character.get("name", "AI")
				color_str = AppState.current_character.get("color", "#aaaaff")
			var display_content: String = extract_msg_fn.call(msg["content"])
			history_text += "[color=%s]%s[/color]：%s\n\n" % [color_str, display_name, display_content]

	if history_text.is_empty():
		history_text = "[color=gray]暂无历史记录[/color]"

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = history_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history_list.add_child(label)

	var scroll: ScrollContainer = $"../HistoryModal/HistoryVBox/HistoryScroll"
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

# ── 呼吸动画 ──────────────────────────────────────────────────
func start_breath_animation() -> void:
	_breath_time = 0.0
	_breath_active = true

func _process(delta: float) -> void:
	if not _breath_active:
		return
	_breath_time += delta
	character_sprite.scale.y = _base_scale + 0.003 * sin(_breath_time * PI / 2.0)
	if character_sprite2.visible:
		character_sprite2.scale.y = _base_scale2 + 0.003 * sin(_breath_time * PI / 2.0 + 0.5)
