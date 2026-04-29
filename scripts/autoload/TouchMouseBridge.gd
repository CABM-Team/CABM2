## TouchMouseBridge.gd
## 触屏长按 -> 右键事件桥接（主要用于移动端无右键场景）

extends Node

const LONG_PRESS_SECONDS := 0.45
const MOVE_CANCEL_THRESHOLD := 24.0

var _tracking_touch := false
var _touch_index := -1
var _start_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _start_time_ms := 0
var _right_pressed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_track(touch.index, touch.position)
		else:
			_end_track(touch.index, touch.position)
		return

	var drag := event as InputEventScreenDrag
	if not _tracking_touch or drag.index != _touch_index:
		return
	_last_pos = drag.position
	if not _right_pressed and _start_pos.distance_to(_last_pos) > MOVE_CANCEL_THRESHOLD:
		_cancel_track()

func _process(_delta: float) -> void:
	if not _tracking_touch or _right_pressed:
		return
	var elapsed_sec := float(Time.get_ticks_msec() - _start_time_ms) / 1000.0
	if elapsed_sec >= LONG_PRESS_SECONDS:
		_emit_right_mouse(_last_pos, true)
		_right_pressed = true

func _begin_track(index: int, position: Vector2) -> void:
	_tracking_touch = true
	_touch_index = index
	_start_pos = position
	_last_pos = position
	_start_time_ms = Time.get_ticks_msec()
	_right_pressed = false

func _end_track(index: int, position: Vector2) -> void:
	if not _tracking_touch or index != _touch_index:
		return
	if _right_pressed:
		_emit_right_mouse(position, false)
	_cancel_track()

func _cancel_track() -> void:
	_tracking_touch = false
	_touch_index = -1
	_right_pressed = false

func _emit_right_mouse(position: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = pressed
	mb.position = position
	mb.global_position = position
	Input.parse_input_event(mb)
