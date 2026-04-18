## ChatController.gd
## 对话页面主控制器

extends Control

# ── 节点引用 ──────────────────────────────────────────────────
@onready var background: TextureRect       = $Background
@onready var character_sprite: Sprite2D = $CharacterSprite
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
@onready var tween_node: Node              = $CharacterSprite  # 用于呼吸动画

# ── 固定回复池（跳过 AI，用于 UI 调试）────────────────────────
const DUMMY_REPLIES := [
	"嗯……你说的很有意思呢♪",
	"哈哈，人家才不会告诉你呢～",
	"这个问题嘛……妖精小姐需要想一想。",
	"你真的很有趣，人家喜欢和你聊天♪",
	"唔……这样啊，人家明白了。",
]

# ── 状态 ──────────────────────────────────────────────────────
var _is_typing := false          # 正在逐字显示中
var _full_text := ""             # 当前句子完整文本
var _shown_chars := 0            # 已显示字符数
var _type_timer: SceneTreeTimer  # 逐字计时器
var _breath_time := 0.0          # 呼吸动画累计时间
var _breath_active := false      # 呼吸动画开关
var _base_scale := 1.0           # 角色初始缩放（来自 scale_rate）

# ── 初始化 ────────────────────────────────────────────────────
func _ready() -> void:
	send_button.pressed.connect(_on_send_pressed)
	back_button.pressed.connect(_on_back_pressed)
	history_button.pressed.connect(_toggle_history)
	close_history_btn.pressed.connect(_toggle_history)
	message_input.gui_input.connect(_on_input_key)
	dialog_text.gui_input.connect(_on_dialog_clicked)
	continue_hint.visible = false

	character_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_load_character(AppState.current_character)
	_start_breath_animation()

# ── 角色加载 ──────────────────────────────────────────────────
func _load_character(char_data: Dictionary) -> void:
	if char_data.is_empty():
		_show_text("请先选择一个角色。")
		return

	var name_str: String = char_data.get("name", "未知角色")
	character_name_label.text = name_str
	speaker_label.text = name_str

	# 角色名颜色
	var color_str: String = char_data.get("color", "#ffffff")
	speaker_label.add_theme_color_override("font_color", Color.from_string(color_str, Color.WHITE))

	_load_sprite(char_data, "")

	# 应用 scale_rate（百分比 → 缩放系数）和 calib（垂直偏移，像素）
	var scale_rate: float = char_data.get("scale_rate", 100) / 100.0
	_base_scale = scale_rate
	character_sprite.scale = Vector2(scale_rate, scale_rate)
	character_sprite.position.y = 1080+char_data.get("calib", 0)

	var welcome: String = char_data.get("welcome", "你好！")
	_show_text(welcome)

	# 注入系统提示词
	var prompt: String = char_data.get("prompt", "")
	if not prompt.is_empty():
		AppState.chat_history.clear()
		AppState.add_message("system", prompt)

func _load_sprite(char_data: Dictionary, mood: String) -> void:
	var image_dir: String = char_data.get("image", "")
	if image_dir.is_empty():
		return
	var candidates: Array[String] = [
		image_dir + "/" + mood + ".png",
		image_dir + "/1.png"
	]
	for path in candidates:
		if ResourceLoader.exists(path):
			character_sprite.texture = load(path)
			return

# ── 逐字显示 ──────────────────────────────────────────────────
func _show_text(text: String) -> void:
	_full_text = text
	_shown_chars = 0
	_is_typing = true
	continue_hint.visible = false
	dialog_text.text = ""
	_type_next_char()

func _type_next_char() -> void:
	if not _is_typing:
		return
	if _shown_chars >= _full_text.length():
		_finish_typing()
		return
	_shown_chars += 1
	dialog_text.text = _full_text.substr(0, _shown_chars)
	_type_timer = get_tree().create_timer(0.03)
	_type_timer.timeout.connect(_type_next_char, CONNECT_ONE_SHOT)

func _finish_typing() -> void:
	_is_typing = false
	dialog_text.text = _full_text
	continue_hint.visible = true
	send_button.disabled = false

func _skip_typing() -> void:
	if _is_typing:
		_is_typing = false
		dialog_text.text = _full_text
		continue_hint.visible = true
		send_button.disabled = false

func _on_dialog_clicked(_event: InputEvent) -> void:
	if _event is InputEventMouseButton and _event.pressed:
		_skip_typing()

# ── 发送消息 ──────────────────────────────────────────────────
func _on_send_pressed() -> void:
	var text := message_input.text.strip_edges()
	if text.is_empty() or _is_typing:
		return
	_send_message(text)

func _send_message(text: String) -> void:
	message_input.text = ""
	send_button.disabled = true
	option_buttons.visible = false
	continue_hint.visible = false

	AppState.add_message("user", text)

	# 固定回复（跳过 AI）
	var reply := _get_dummy_reply()
	AppState.add_message("assistant", reply)
	_show_text(reply)

func _get_dummy_reply() -> String:
	var idx := randi() % DUMMY_REPLIES.size()
	return DUMMY_REPLIES[idx]

func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			_on_send_pressed()
			get_viewport().set_input_as_handled()

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

	for msg in AppState.chat_history:
		var role: String = msg["role"]
		if role == "system":
			continue

		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if role == "user":
			label.text = "[color=cyan]你[/color]：" + msg["content"]
		else:
			label.text = "[color=%s]%s[/color]：%s" % [color_str, char_name, msg["content"]]

		history_list.add_child(label)

		# 分隔线
		var sep := HSeparator.new()
		history_list.add_child(sep)

# ── 导航 ──────────────────────────────────────────────────────
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
