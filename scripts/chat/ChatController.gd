## ChatController.gd
## 对话主流程控制器：消息发送、群聊逻辑、流式接收、历史管理

extends Control

# ── UI 控制器引用 ─────────────────────────────────────────────
@onready var ui: Node = $ChatUIController
@onready var confirm_dialog = $ConfirmDialog
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer

# 当前确认对话框的用途：:clear_history 或 :delete
var _confirm_action := &""

# ── 流式接收状态 ──────────────────────────────────────────────
var _stream_state := SentenceSplitter.StreamState.new()
var _stream_full_content := ""
var _stream_display_content := ""
var _is_receiving := false

# ── 群聊状态 ──────────────────────────────────────────────────
var _displayed_chars: Array[Dictionary] = []
var _current_speaker_id := ""
var _group_reply_queue: Array[Dictionary] = []
var _group_waiting_char_id := ""
var _group_turn_count := 0
const GROUP_MAX_TURNS := 5

# ── 活跃度机制 ────────────────────────────────────────────────
var _idle_rounds: Dictionary = {}
const IDLE_FORCE_THRESHOLD := 3
const IDLE_FORCE_PROB_PER_ROUND := 0.35

# ── 表情状态 ──────────────────────────────────────────────────
var _current_mood := 0
var _group_moods: Dictionary = {}

# ── TTS 发言者追踪（群聊用）──────────────────────────────────
var _current_tts_speaker_id := ""
var _current_sentence_no_tts := false

# ── 自动播放 TTS 状态 ─────────────────────────────────────────
# 每个句子对应一条记录：{ "text": String, "no_tts": bool, "audio_path": String, "pending": bool }
# pending=true 表示 TTS 请求已发出但尚未完成
var _auto_tts_queue: Array[Dictionary] = []
var _auto_tts_playing_idx := -1   # 当前正在播放/等待播放的队列索引
var _manual_tts_pending := false  # 手动点"播放语音"按钮时置 true

# ── 初始化 ────────────────────────────────────────────────────
func _ready() -> void:
	ui.send_requested.connect(_on_send_pressed)
	ui.back_requested.connect(_on_back_pressed)
	ui.history_toggle_requested.connect(_toggle_history)
	ui.more_options_toggle_requested.connect(_toggle_more_options)
	ui.clear_history_confirm_requested.connect(_show_clear_history_confirm)
	ui.delete_confirm_requested.connect(_show_delete_confirm)
	ui.advance_requested.connect(_advance)
	ui.input_key_enter.connect(_on_send_pressed)
	ui.sentence_finished.connect(_on_sentence_finished)
	ui.sentence_started.connect(_on_sentence_started)

	confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)
	confirm_dialog.cancelled.connect(_hide_confirm_dialog)

	TTSManager.tts_done.connect(_on_tts_done)
	TTSManager.tts_error.connect(_on_tts_error)
	ui.tts_requested.connect(_on_tts_requested)
	ui.history_tts_requested.connect(_on_history_tts_requested)
	ui.option_selected.connect(_on_option_selected)

	ApiClient.stream_chunk.connect(_on_stream_chunk)
	ApiClient.stream_mood.connect(_on_stream_mood)
	ApiClient.stream_full_json.connect(_on_stream_full_json)
	ApiClient.stream_done.connect(_on_stream_done)
	ApiClient.stream_error.connect(_on_stream_error)

	if AppState.is_group_mode():
		_init_group_mode()
	else:
		_load_character(AppState.current_character)
	ui.start_breath_animation()

# ── 单角色模式：角色加载 ──────────────────────────────────────
func _load_character(char_data: Dictionary) -> void:
	if char_data.is_empty():
		ui.show_text("请先选择一个角色。")
		return

	ui.setup_single_character(char_data)

	# 异步确保参考音频已上传（不阻塞界面）
	var char_id: String = char_data.get("id", char_data.get("name", ""))
	if not char_id.is_empty() and ConfigManager.get_value("enable_tts"):
		VoiceUploadManager.ensure_voice_uploaded(char_id, func(uri: String, error: String):
			if not error.is_empty():
				print("[TTS] 参考音频上传失败：", error)
			else:
				print("[TTS] 参考音频 URI：", uri)
		)

	var character_id: String = char_id
	var save_data := HistoryManager.load_history(character_id)
	var loaded_history: Array[Dictionary] = save_data["history"]

	AppState.chat_history.clear()
	var prompt: String = char_data.get("prompt", "")
	if not prompt.is_empty():
		AppState.add_message("system", prompt)
	for msg in loaded_history:
		AppState.chat_history.append(msg)

	_current_mood = int(save_data.get("last_mood", 0))
	if _current_mood > 0:
		ui.load_sprite(ui.character_sprite, char_data, str(_current_mood))

	var welcome: String = char_data.get("welcome", "你好！")
	if loaded_history.is_empty():
		ui.show_text_instant(welcome)
	else:
		for i in range(loaded_history.size() - 1, -1, -1):
			if loaded_history[i]["role"] == "assistant":
				var full_text := _extract_msg_from_json(loaded_history[i]["content"])
				ui.show_text_instant(_last_sentence(full_text))
				break
	_try_generate_options()

# ── 群聊模式：初始化 ──────────────────────────────────────────
func _init_group_mode() -> void:
	var group_data := AppState.current_group
	var chars := AppState.group_characters
	ui.setup_group_header(group_data)

	var group_id: String = group_data.get("id", "")
	var save_data := HistoryManager.load_group_history(group_id)
	var loaded_history: Array[Dictionary] = save_data["history"]
	AppState.chat_history.clear()
	for msg in loaded_history:
		AppState.chat_history.append(msg)

	var saved_moods = save_data.get("last_moods", {})
	_group_moods = saved_moods if saved_moods is Dictionary else {}

	var saved_idle = save_data.get("idle_rounds", {})
	_idle_rounds = saved_idle if saved_idle is Dictionary else {}

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
	ui.refresh_sprites(_displayed_chars)

	for cd in _displayed_chars:
		var cid: String = cd.get("id", "")
		var mood: int = int(_group_moods.get(cid, 0))
		if mood > 0:
			var sp: Sprite2D = ui.get_sprite_for(cid)
			if sp:
				ui.load_sprite(sp, cd, str(mood))

	var saved_speaker: String = save_data.get("active_speaker_id", "")
	if not saved_speaker.is_empty():
		ui.set_active_speaker(saved_speaker)

	if loaded_history.is_empty():
		ui.show_text_instant("已创建群聊")
	else:
		for i in range(loaded_history.size() - 1, -1, -1):
			var r: String = loaded_history[i].get("role", "")
			if r != "user" and r != "system":
				_current_tts_speaker_id = r
				_set_speaker_by_id(r)
				ui.show_text_instant(_last_sentence(_extract_msg_from_json(loaded_history[i]["content"])))
				break
	_try_generate_options()

	# 异步预上传所有群聊角色的参考音频
	if ConfigManager.get_value("enable_tts"):
		for c in chars:
			var cid: String = c.get("id", "")
			if not cid.is_empty():
				VoiceUploadManager.ensure_voice_uploaded(cid, func(uri: String, error: String):
					if not error.is_empty():
						print("[TTS] 角色 %s 参考音频上传失败：%s" % [cid, error])
					else:
						print("[TTS] 角色 %s URI：%s" % [cid, uri])
				)

func _get_char_data_by_id(char_id: String) -> Dictionary:
	if AppState.is_group_mode():
		for c in AppState.group_characters:
			if c.get("id", "") == char_id:
				return c
	else:
		if AppState.current_character.get("id", "") == char_id:
			return AppState.current_character
	return {}

func _set_speaker_by_id(char_id: String) -> void:
	var char_data := _get_char_data_by_id(char_id)
	if char_data.is_empty():
		return
	ui.set_speaker_label(char_data)

# ── 发送消息 ──────────────────────────────────────────────────
func _on_send_pressed() -> void:
	var text: String = ui.get_input_text()
	if text.is_empty() or ui.is_typing() or _is_receiving or ui.is_waiting_for_advance():
		return
	_send_message(text)

func _send_message(text: String) -> void:
	ui.clear_input()
	ui.lock_input()
	ui.hide_option_buttons()
	ui.set_waiting_for_advance(false)

	AppState.add_message("user", text)

	_stream_state = SentenceSplitter.StreamState.new()
	_stream_full_content = ""
	_stream_display_content = ""
	ui.clear_sentence_queue()
	_is_receiving = true
	_auto_tts_queue.clear()
	_auto_tts_playing_idx = -1
	_manual_tts_pending = false
	audio_player.stop()

	ui.start_thinking_dots()

	if AppState.is_group_mode():
		_start_group_replies()
	else:
		var messages := PromptBuilder.build_messages(
			AppState.get_messages_for_api(),
			AppState.current_character
		)
		ApiClient.chat_completion(messages)

# ── 群聊 AI 决定发言顺序 ──────────────────────────────────────
func _start_group_replies() -> void:
	_group_reply_queue.clear()
	_group_waiting_char_id = ""
	_group_turn_count = 0
	for c in AppState.group_characters:
		var cid: String = c.get("id", "")
		_idle_rounds[cid] = int(_idle_rounds.get(cid, 0)) + 1
	_ask_ai_next_speaker()

func _ask_ai_next_speaker() -> void:
	if _group_turn_count >= GROUP_MAX_TURNS:
		if not ui.is_typing() and not ui.is_waiting_for_advance() and not ui.has_queued_sentences():
			ui.unlock_input()
			_try_generate_options()
		return

	ui.lock_input()

	var forced_char := _try_force_inactive_speaker()
	if not forced_char.is_empty():
		print("【活跃度】强制选中：" + forced_char.get("id", ""))
		_group_turn_count += 1
		_request_group_char(forced_char)
		return

	print("【AI决策】排除："+_group_waiting_char_id)
	var chars := AppState.group_characters
	var id_list: Array[String] = []
	
	# 检查上一条消息是否是 user
	var last_was_user := false
	if not AppState.chat_history.is_empty():
		var last_msg := AppState.chat_history[AppState.chat_history.size() - 1]
		last_was_user = last_msg.get("role", "") == "user"
	
	# 构建 ID 列表（系统提示词用）
	if _group_waiting_char_id.is_empty():
		id_list.append("~~user~~（不允许再次选择）")
	else:
		id_list.append("user")
	
	for c in chars:
		var cid: String = c.get("id", "")
		if cid == _group_waiting_char_id:
			id_list.append("~~"+cid+"~~（不允许再次选择）")
		else:
			id_list.append(cid)

	# 构建聊天记录（使用名字+ID格式）
	var recent: Array[Dictionary] = AppState.chat_history
	var start_idx := maxi(0, recent.size() - 8)
	var context_lines: Array[String] = []
	for i in range(start_idx, recent.size()):
		var msg := recent[i]
		var role: String = msg.get("role", "")
		if role == "system":
			continue
		var text := PromptBuilder._extract_msg(msg.get("content", ""))
		var display_name := ""
		if role == "user":
			display_name = "user(%s)" % ConfigManager.get_value("username")
		else:
			var char_data := _get_char_data_by_id(role)
			if not char_data.is_empty():
				display_name = "%s（%s）" % [char_data.get("name", role), role]
			else:
				display_name = role
		context_lines.append(display_name + "：" + text)

	var system_p := "你是一个专业的导演，根据对话上下文决定下一个最合适发言的人。\n参与者ID列表：%s\n要求：只需回复一个ID，不要有任何其他内容" % "、".join(id_list)
	var user_p := "最近的对话：\n%s\n\n下一个应该由谁发言？" % "\n".join(context_lines)

	EasyAI.ask(system_p, user_p, func(reply: String):
		var chosen_char := _match_char_by_id(reply)
		
		# 如果上一个是 user 但 AI 仍然选择了 user，强制随机选择角色
		if chosen_char.is_empty() or (last_was_user and reply.strip_edges() == "user"):
			if last_was_user and reply.strip_edges() == "user":
				print("【AI决策】上一个是user但AI选择了user，强制随机选择角色")
				var available_chars: Array[Dictionary] = []
				for c in chars:
					if c.get("id", "") != _group_waiting_char_id:
						available_chars.append(c)
				if not available_chars.is_empty():
					chosen_char = available_chars[randi() % available_chars.size()]
			
			if chosen_char.is_empty():
				if not ui.is_typing() and not ui.is_waiting_for_advance() and not ui.has_queued_sentences():
					ui.unlock_input()
				return
		
		_group_turn_count += 1
		_request_group_char(chosen_char)
	)

func _try_force_inactive_speaker() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for c in AppState.group_characters:
		var cid: String = c.get("id", "")
		if cid == _group_waiting_char_id:
			continue
		var idle: int = int(_idle_rounds.get(cid, 0))
		if idle <= IDLE_FORCE_THRESHOLD:
			continue
		var prob := minf((idle - IDLE_FORCE_THRESHOLD) * IDLE_FORCE_PROB_PER_ROUND, 1.0)
		if randf() < prob:
			candidates.append(c)

	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b):
		return int(_idle_rounds.get(a.get("id",""), 0)) > int(_idle_rounds.get(b.get("id",""), 0))
	)
	return candidates[0]

func _match_char_by_id(char_id: String) -> Dictionary:
	var trimmed := char_id.strip_edges()
	for c in AppState.group_characters:
		if c.get("id", "") == trimmed:
			return c
	return {}

func _request_group_char(char_data: Dictionary) -> void:
	var char_id: String = char_data.get("id", "")
	_group_waiting_char_id = char_id
	_current_tts_speaker_id = char_id
	_idle_rounds[char_id] = 0

	_ensure_char_on_screen(char_data)
	ui.set_active_speaker(char_id)
	_set_speaker_by_id(char_id)

	_stream_state = SentenceSplitter.StreamState.new()
	_stream_full_content = ""
	_stream_display_content = ""
	_is_receiving = true
	_auto_tts_queue.clear()
	_auto_tts_playing_idx = -1
	audio_player.stop()
	ui.start_thinking_dots()

	var messages := PromptBuilder.build_group_messages(
		char_data,
		AppState.group_characters,
		AppState.chat_history,
		AppState.current_group
	)
	ApiClient.chat_completion(messages)

func _ensure_char_on_screen(char_data: Dictionary) -> void:
	var cid: String = char_data.get("id", "")
	for c in _displayed_chars:
		if c.get("id", "") == cid:
			return
	var replace_idx := randi() % _displayed_chars.size()
	_displayed_chars[replace_idx] = char_data
	ui.refresh_sprites(_displayed_chars)

# ── 流式接收 ──────────────────────────────────────────────────
func _on_stream_chunk(text: String) -> void:
	_stream_display_content += text
	var sentences := SentenceSplitter.split_stream(_stream_state, text)
	for s in sentences:
		if not ui.is_typing() and not ui.is_waiting_for_advance() and not ui.has_queued_sentences():
			_current_sentence_no_tts = s.get("no_tts", false)
		_auto_tts_prefetch(s)
		ui.enqueue_sentence(s)

func _on_stream_mood(mood: int) -> void:
	if AppState.is_group_mode():
		var char_data := _get_char_data_by_id(_group_waiting_char_id)
		if not char_data.is_empty():
			_group_moods[_group_waiting_char_id] = mood
			ui.switch_mood_for(char_data, mood)
	else:
		_current_mood = mood
		ui.switch_mood_single(AppState.current_character, mood)

func _on_stream_full_json(json_str: String) -> void:
	_stream_full_content = json_str

func _on_stream_done() -> void:
	_is_receiving = false
	var sentences := SentenceSplitter.split_stream(_stream_state, "", true)
	for s in sentences:
		_auto_tts_prefetch(s)
		ui.enqueue_sentence(s)

	if not _stream_full_content.is_empty():
		if AppState.is_group_mode():
			AppState.add_message(_group_waiting_char_id, _stream_full_content)
			_save_history()
			_group_reply_queue.append({"ask_next": true})
		else:
			AppState.add_message("assistant", _stream_full_content)
			_save_history()

	if ConfigManager.get_value("enable_tts") and not _current_sentence_no_tts:
		ui.set_tts_enabled(true)

	if not ui.is_typing() and not ui.is_waiting_for_advance() and not ui.has_queued_sentences():
		var has_next_char := not _group_reply_queue.is_empty()
		if has_next_char:
			ui.set_waiting_for_advance(true)
		else:
			ui.unlock_input()

func _on_stream_error(message: String) -> void:
	_is_receiving = false
	_group_reply_queue.clear()
	_group_waiting_char_id = ""
	ui.stop_thinking_dots()
	ui.unlock_input()
	ui.show_text("⚠ " + message)

# ── 逐字显示完成回调 ──────────────────────────────────────────
func _on_sentence_finished() -> void:
	var has_more_sentences: bool = ui.has_queued_sentences() or _is_receiving
	var has_next_char := not _group_reply_queue.is_empty()

	if has_more_sentences or has_next_char:
		ui.set_waiting_for_advance(true)
	else:
		ui.unlock_input()
		_try_generate_options()

func _advance() -> void:
	ui.set_waiting_for_advance(false)
	if ui.has_queued_sentences():
		var next: Dictionary = ui.pop_next_sentence()
		_current_sentence_no_tts = next.get("no_tts", false)
		# 自动播放模式：停止当前播放，准备播放下一句
		if ConfigManager.get_value("auto_play_tts") and ConfigManager.get_value("enable_tts"):
			audio_player.stop()
		ui.show_text(next.get("text", ""))
		if ConfigManager.get_value("enable_tts"):
			ui.set_tts_enabled(not _current_sentence_no_tts)
	elif not _is_receiving and not _group_reply_queue.is_empty():
		_dispatch_next_group_char()

func _dispatch_next_group_char() -> void:
	if _group_reply_queue.is_empty():
		return
	_group_reply_queue.pop_front()
	_ask_ai_next_speaker()

# ── 历史记录 ──────────────────────────────────────────────────
func _toggle_history() -> void:
	ui.toggle_history()
	if ui.is_history_visible():
		_refresh_history()

func _refresh_history() -> void:
	ui.refresh_history(AppState.chat_history, _get_char_data_by_id, _extract_msg_from_json)

func _extract_msg_from_json(json_str: String) -> String:
	var json := JSON.new()
	if json.parse(json_str) == OK:
		var data: Dictionary = json.get_data()
		return data.get("msg", json_str)
	return json_str

## 用分句器取文本的最后一句（不含 no_tts 括号内容）
func _last_sentence(text: String) -> String:
	var sentences := SentenceSplitter.split_text(text)
	for i in range(sentences.size() - 1, -1, -1):
		var s: Dictionary = sentences[i]
		if not s.get("no_tts", false) and not s.get("text", "").is_empty():
			return s.get("text", "")
	return text

func _save_history() -> void:
	if AppState.is_group_mode():
		var group_id: String = AppState.current_group.get("id", "")
		if not group_id.is_empty():
			var displayed_ids: Array = []
			for c in _displayed_chars:
				displayed_ids.append(c.get("id", ""))
			HistoryManager.save_group_history(group_id, AppState.chat_history,
				displayed_ids, _current_speaker_id, _group_moods, _idle_rounds)
	else:
		var character_id: String = AppState.current_character.get("id", AppState.current_character.get("name", ""))
		if not character_id.is_empty():
			HistoryManager.save_history(character_id, AppState.chat_history, _current_mood)

func delete_current_history() -> void:
	if AppState.is_group_mode():
		var group_id: String = AppState.current_group.get("id", "")
		HistoryManager.clear_group_history(group_id)
		AppState.chat_history.clear()
		_group_moods.clear()
		_current_speaker_id = ""
		_displayed_chars.clear()
		var chars := AppState.group_characters
		for i in min(2, chars.size()):
			_displayed_chars.append(chars[i])
		ui.refresh_sprites(_displayed_chars)
	else:
		var character_id: String = AppState.current_character.get("id", AppState.current_character.get("name", ""))
		if HistoryManager.delete_history(character_id):
			AppState.chat_history.clear()
			var prompt: String = AppState.current_character.get("prompt", "")
			if not prompt.is_empty():
				AppState.add_message("system", prompt)
		_current_mood = 0
		ui.load_sprite(ui.character_sprite, AppState.current_character, "")
	AppState.history_updated.emit()
	_refresh_history()
	if AppState.is_group_mode():
		ui.show_text("群聊历史已清空。")
	else:
		ui.show_text(AppState.current_character.get("welcome", "你好！"))

# ── 更多选项 ──────────────────────────────────────────────────
func _toggle_more_options() -> void:
	ui.toggle_more_options()
	if ui.more_options_overlay.visible:
		ui.hide_history()
		_update_delete_button()

func _update_delete_button() -> void:
	if AppState.is_group_mode():
		ui.update_delete_button(true, "")
	else:
		var char_id: String = AppState.current_character.get("id", "")
		ui.update_delete_button(false, char_id)

func _show_clear_history_confirm() -> void:
	ui.hide_more_options()
	_confirm_action = &"clear_history"
	confirm_dialog.show_dialog("⚠\n确定要清空历史记录吗？")

func _show_delete_confirm() -> void:
	ui.hide_more_options()
	_confirm_action = &"delete"
	if AppState.is_group_mode():
		var group_name: String = AppState.current_group.get("name", "该群聊")
		confirm_dialog.show_dialog("⚠\n确定要删除群聊 %s 吗？（包括历史）\n此操作不可撤销！" % group_name)
	else:
		var char_name: String = AppState.current_character.get("name", "该角色")
		confirm_dialog.show_dialog("⚠\n确定要删除角色 %s 吗？（真的很久）\n此操作不可撤销！" % char_name)

func _hide_confirm_dialog() -> void:
	confirm_dialog.hide_dialog()

func _on_confirm_dialog_confirmed() -> void:
	if _confirm_action == &"clear_history":
		delete_current_history()
	elif _confirm_action == &"delete":
		_do_delete()
	_confirm_action = &""

func _do_delete() -> void:
	if AppState.is_group_mode():
		var group_id: String = AppState.current_group.get("id", "")
		GroupManager.delete_group(group_id)
	else:
		var char_id: String = AppState.current_character.get("id", "")
		var char_dir := "user://characters/%s" % char_id
		_delete_dir_recursive(char_dir)
	_on_back_pressed()

func _delete_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full := path + "/" + fname
			if dir.current_is_dir():
				_delete_dir_recursive(full)
				DirAccess.remove_absolute(full)
			else:
				DirAccess.remove_absolute(full)
		fname = dir.get_next()
	DirAccess.remove_absolute(path)

# ── 选项生成 ──────────────────────────────────────────────────
func _try_generate_options() -> void:
	if not ConfigManager.get_value("enable_option_generation"):
		return
	if EasyAI._busy:
		return
	ui.show_option_buttons_loading()

	# 构建上下文：取最近几条对话
	var recent := AppState.chat_history
	var start_idx := maxi(0, recent.size() - 6)
	var context_lines: Array[String] = []
	var username: String = ConfigManager.get_value("username")
	for i in range(start_idx, recent.size()):
		var msg := recent[i]
		var role: String = msg.get("role", "")
		if role == "system":
			continue
		var text := _extract_msg_from_json(msg.get("content", ""))
		if role == "user":
			context_lines.append(username + "：" + text)
		else:
			var char_data := _get_char_data_by_id(role)
			var name_str: String = char_data.get("name", role) if not char_data.is_empty() else role
			context_lines.append(name_str + "：" + text)

	var system_p := "你是%s，根据当前对话上下文，生成3句你可能会说的话。\n要求：\n- 每句话一行，不加编号或符号前缀\n- 每句不超过20个字\n- 风格贴合对话语境\n- 只输出3行，不要有其他内容" % username
	var user_p := "当前对话：\n%s\n\n请生成3句你可能会说的话：" % "\n".join(context_lines)

	EasyAI.ask(system_p, user_p, func(reply: String):
		if reply.is_empty():
			ui.hide_option_buttons()
			return
		var lines := reply.split("\n", false)
		# 过滤空行，取前3条
		var options: Array[String] = []
		for line in lines:
			var trimmed := line.strip_edges()
			if not trimmed.is_empty():
				options.append(trimmed)
			if options.size() >= 3:
				break
		while options.size() < 3:
			options.append("…")
		ui.fill_option_buttons(options)
	)

func _on_option_selected(text: String) -> void:
	if text.is_empty() or text == "…" or text == "⏳":
		return
	if ui.is_typing() or _is_receiving or ui.is_waiting_for_advance():
		return
	ui.message_input.text = text
	_on_send_pressed()

# ── 导航 ──────────────────────────────────────────────────────
func _on_back_pressed() -> void:
	ApiClient.cancel()
	ApiClient.stream_chunk.disconnect(_on_stream_chunk)
	ApiClient.stream_mood.disconnect(_on_stream_mood)
	ApiClient.stream_full_json.disconnect(_on_stream_full_json)
	ApiClient.stream_done.disconnect(_on_stream_done)
	ApiClient.stream_error.disconnect(_on_stream_error)
	TTSManager.tts_done.disconnect(_on_tts_done)
	TTSManager.tts_error.disconnect(_on_tts_error)
	ui.history_tts_requested.disconnect(_on_history_tts_requested)
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")

# ── TTS ───────────────────────────────────────────────────────
func _on_history_tts_requested(text: String, char_id: String) -> void:
	if text.is_empty():
		return
	var char_data := _get_char_data_by_id(char_id)
	if char_data.is_empty():
		return
	_manual_tts_pending = true
	TTSManager.request(char_id, text)

func _on_tts_requested(text: String) -> void:
	if text.is_empty() or _current_sentence_no_tts:
		return
	var char_data: Dictionary
	if AppState.is_group_mode():
		char_data = _get_char_data_by_id(_current_tts_speaker_id)
	else:
		char_data = AppState.current_character
	if char_data.is_empty():
		return
	var char_id: String = char_data.get("id", char_data.get("name", ""))
	ui.set_tts_loading(true)
	_manual_tts_pending = true
	TTSManager.request(char_id, text)

func _on_tts_done(audio_path: String) -> void:
	# 手动请求优先处理
	if _manual_tts_pending:
		_manual_tts_pending = false
		ui.set_tts_loading(false)
		var stream := _load_audio_stream(audio_path)
		if stream == null:
			return
		audio_player.stream = stream
		audio_player.play()
		return
	# 自动播放模式：交给队列处理
	if ConfigManager.get_value("auto_play_tts") and ConfigManager.get_value("enable_tts"):
		_auto_tts_on_ready(audio_path)
		return
	ui.set_tts_loading(false)
	var stream2 := _load_audio_stream(audio_path)
	if stream2 == null:
		return
	audio_player.stream = stream2
	audio_player.play()

func _on_tts_error(message: String) -> void:
	ui.set_tts_loading(false)
	print("[TTS] 错误：", message)

func _load_audio_stream(path: String) -> AudioStream:
	var ext := path.get_extension().to_lower()
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		return null
	match ext:
		"mp3":
			var stream := AudioStreamMP3.new()
			stream.data = data
			return stream
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(data)
		"wav":
			# WAV 需要通过 ResourceLoader 或 Image 方式，直接用 load
			return load(path)
	return null

# ── 自动播放 TTS ──────────────────────────────────────────────
## 每个句子入队时预发起 TTS 请求
func _auto_tts_prefetch(sentence: Dictionary) -> void:
	if not ConfigManager.get_value("auto_play_tts") or not ConfigManager.get_value("enable_tts"):
		return
	var no_tts: bool = sentence.get("no_tts", false)
	var text: String = sentence.get("text", "")
	var entry := {"text": text, "no_tts": no_tts, "audio_path": "", "pending": false}
	_auto_tts_queue.append(entry)
	var idx := _auto_tts_queue.size() - 1
	if no_tts or text.is_empty():
		return
	# 获取当前发言角色
	var char_data: Dictionary
	if AppState.is_group_mode():
		char_data = _get_char_data_by_id(_current_tts_speaker_id)
	else:
		char_data = AppState.current_character
	if char_data.is_empty():
		return
	var char_id: String = char_data.get("id","")
	# 若缓存已有，直接记录路径
	if TTSManager.has_cache(char_id, text):
		_auto_tts_queue[idx]["audio_path"] = TTSManager._cache_path(char_id, text)
	else:
		_auto_tts_queue[idx]["pending"] = true
		TTSManager.request(char_id, text)

## 句子开始输出时触发（来自 sentence_started 信号）
func _on_sentence_started(text: String) -> void:
	if not ConfigManager.get_value("auto_play_tts") or not ConfigManager.get_value("enable_tts"):
		return
	# 找到对应队列项
	for i in _auto_tts_queue.size():
		var entry := _auto_tts_queue[i]
		if entry["text"] == text:
			_auto_tts_playing_idx = i
			if entry["no_tts"]:
				audio_player.stop()
				return
			if not entry["audio_path"].is_empty():
				# 音频已就绪，立即播放
				_auto_tts_play(entry["audio_path"])
			# else: pending=true，等 _auto_tts_on_ready 回调
			return

## TTS 完成回调（自动播放模式）
func _auto_tts_on_ready(audio_path: String) -> void:
	# 找到对应队列项，填入路径
	for i in _auto_tts_queue.size():
		var entry := _auto_tts_queue[i]
		if entry["pending"] and entry["audio_path"].is_empty():
			# 通过缓存路径匹配（TTSManager 返回的就是缓存路径）
			# 用文本反查：检查缓存路径是否匹配
			var char_data: Dictionary
			if AppState.is_group_mode():
				char_data = _get_char_data_by_id(_current_tts_speaker_id)
			else:
				char_data = AppState.current_character
			if char_data.is_empty():
				return
			var char_id: String = char_data.get("id", char_data.get("name", ""))
			var expected_path := TTSManager._cache_path(char_id, entry["text"])
			if expected_path == audio_path:
				_auto_tts_queue[i]["audio_path"] = audio_path
				_auto_tts_queue[i]["pending"] = false
				# 如果这正是当前正在显示的句子，立即播放
				if i == _auto_tts_playing_idx:
					_auto_tts_play(audio_path)
				return

func _auto_tts_play(audio_path: String) -> void:
	var stream := _load_audio_stream(audio_path)
	if stream == null:
		return
	audio_player.stream = stream
	audio_player.play()
