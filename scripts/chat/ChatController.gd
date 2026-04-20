## ChatController.gd
## 对话主流程控制器：消息发送、群聊逻辑、流式接收、历史管理

extends Control

# ── UI 控制器引用 ─────────────────────────────────────────────
@onready var ui: Node = $ChatUIController
@onready var confirm_dialog = $ConfirmDialog

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

	confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)
	confirm_dialog.cancelled.connect(_hide_confirm_dialog)

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

	var character_id: String = char_data.get("id", char_data.get("name", ""))
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
		ui.show_text(welcome)
	else:
		for i in range(loaded_history.size() - 1, -1, -1):
			if loaded_history[i]["role"] == "assistant":
				ui.show_text(_extract_msg_from_json(loaded_history[i]["content"]))
				break

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
		ui.show_text("已创建群聊")
	else:
		for i in range(loaded_history.size() - 1, -1, -1):
			var r: String = loaded_history[i].get("role", "")
			if r != "user" and r != "system":
				_set_speaker_by_id(r)
				ui.show_text(_extract_msg_from_json(loaded_history[i]["content"]))
				break

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
	var id_list: Array[String] = ["user"]
	for c in chars:
		var cid: String = c.get("id", "")
		if cid == _group_waiting_char_id:
			id_list.append(cid+"（不允许再次选择）")
		else:
			id_list.append(cid)

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
	_idle_rounds[char_id] = 0

	_ensure_char_on_screen(char_data)
	ui.set_active_speaker(char_id)
	_set_speaker_by_id(char_id)

	_stream_state = SentenceSplitter.StreamState.new()
	_stream_full_content = ""
	_stream_display_content = ""
	_is_receiving = true
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
		ui.enqueue_sentence(s["text"])

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
		ui.enqueue_sentence(s["text"])

	if not _stream_full_content.is_empty():
		if AppState.is_group_mode():
			AppState.add_message(_group_waiting_char_id, _stream_full_content)
			_save_history()
			_group_reply_queue.append({"ask_next": true})
		else:
			AppState.add_message("assistant", _stream_full_content)
			_save_history()

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

func _advance() -> void:
	ui.set_waiting_for_advance(false)
	if ui.has_queued_sentences():
		var next: String = ui.pop_next_sentence()
		ui.show_text(next)
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

# ── 导航 ──────────────────────────────────────────────────────
func _on_back_pressed() -> void:
	ApiClient.cancel()
	ApiClient.stream_chunk.disconnect(_on_stream_chunk)
	ApiClient.stream_mood.disconnect(_on_stream_mood)
	ApiClient.stream_full_json.disconnect(_on_stream_full_json)
	ApiClient.stream_done.disconnect(_on_stream_done)
	ApiClient.stream_error.disconnect(_on_stream_error)
	get_tree().change_scene_to_file("res://scenes/character_select/character_select.tscn")
