## CropDialog.gd
## 图片裁剪对话框 - 重写版
## 支持自定义比例裁剪/自由裁剪，支持拖拽移动裁剪框，支持调整裁剪框大小

extends Control

signal crop_confirmed(cropped_image: Image)

enum DragHandle {
	NONE,
	MOVE,
	TOP_LEFT, TOP, TOP_RIGHT,
	LEFT, RIGHT,
	BOTTOM_LEFT, BOTTOM, BOTTOM_RIGHT
}

@onready var overlay: ColorRect = $Overlay
@onready var panel: PanelContainer = $Panel
@onready var image_rect: TextureRect = $Panel/VBox/ImageContainer/ImageRect
@onready var crop_overlay: Control = $Panel/VBox/ImageContainer/CropOverlay
@onready var confirm_btn: Button = $Panel/VBox/Buttons/ConfirmButton
@onready var cancel_btn: Button = $Panel/VBox/Buttons/CancelButton
@onready var hint_label: Label = $Panel/VBox/HintLabel

var _source_image: Image = null
var _crop_rect := Rect2()           # 裁剪区域（图片坐标系）
var _aspect_ratio := 0.0            # 宽高比约束，0表示自由裁剪，>0表示固定比例
var _dragging_handle := DragHandle.NONE
var _drag_start_mouse := Vector2.ZERO
var _drag_start_rect := Rect2()

const HANDLE_SIZE := 8.0            # 拖拽手柄大小（屏幕像素）
const MIN_CROP_SIZE := 20.0         # 最小裁剪尺寸（图片像素）

func _ready() -> void:
	visible = false
	confirm_btn.pressed.connect(_on_confirm)
	cancel_btn.pressed.connect(_on_cancel)
	
	crop_overlay.draw.connect(_on_crop_overlay_draw)
	crop_overlay.gui_input.connect(_on_crop_overlay_input)
	crop_overlay.mouse_default_cursor_shape = Control.CURSOR_CROSS
	
	# 双击重置到最大符合比例的区域
	crop_overlay.gui_input.connect(_on_crop_overlay_double_click)

func open_image(path: String, aspect_ratio: float = 0.0) -> void:
	"""
	打开图片进行裁剪
	参数:
		path: 图片路径
		aspect_ratio: 宽高比约束，0表示自由裁剪，>0表示固定比例（如 1.0 为正方形，16.0/9.0 为 16:9）
	"""
	var img := Image.new()
	if img.load(path) != OK:
		push_error("Failed to load image: ", path)
		return
	
	_source_image = img
	_aspect_ratio = aspect_ratio
	image_rect.texture = ImageTexture.create_from_image(img)
	
	# 设置初始裁剪区域
	_crop_rect = _get_initial_crop_rect()
	
	# 更新提示文本
	var ratio_text := "自由裁剪" if _aspect_ratio == 0 else "比例 %.2f:1" % _aspect_ratio
	hint_label.text = "拖拽移动裁剪区域" + (" | 拖拽边缘调整大小" if _aspect_ratio == 0 else "") + " | 双击重置到最大区域"
	
	crop_overlay.queue_redraw()
	visible = true

func _get_initial_crop_rect() -> Rect2:
	"""获取初始裁剪区域"""
	var img_w := _source_image.get_width()
	var img_h := _source_image.get_height()
	
	if _aspect_ratio > 0:
		# 固定比例：取图片内最大符合比例的区域
		return _get_max_aspect_rect(img_w, img_h, _aspect_ratio)
	else:
		# 自由裁剪：全选
		return Rect2(0, 0, img_w, img_h)

func _get_max_aspect_rect(img_w: int, img_h: int, target_ratio: float) -> Rect2:
	"""获取图片内最大的目标比例矩形（居中）"""
	var img_ratio = img_w / float(img_h)
	
	if img_ratio > target_ratio:
		# 图片更宽，以高度为基准
		var new_w = img_h * target_ratio
		var x = (img_w - new_w) / 2.0
		return Rect2(x, 0, new_w, img_h)
	else:
		# 图片更高，以宽度为基准
		var new_h = img_w / target_ratio
		var y = (img_h - new_h) / 2.0
		return Rect2(0, y, img_w, new_h)

func _reset_to_max_rect() -> void:
	"""重置裁剪区域到最大符合比例的区域"""
	if _source_image == null:
		return
	
	_crop_rect = _get_initial_crop_rect()
	crop_overlay.queue_redraw()

func _get_display_rect() -> Rect2:
	"""获取图片在 crop_overlay 中的显示区域（保持比例居中）"""
	if _source_image == null:
		return Rect2()
	
	var container_size := crop_overlay.size
	var img_w := float(_source_image.get_width())
	var img_h := float(_source_image.get_height())
	var img_scale := minf(container_size.x / img_w, container_size.y / img_h)
	var disp_w := img_w * img_scale
	var disp_h := img_h * img_scale
	var ox := (container_size.x - disp_w) / 2.0
	var oy := (container_size.y - disp_h) / 2.0
	
	return Rect2(ox, oy, disp_w, disp_h)

func _to_image_coord(pos: Vector2) -> Vector2:
	"""将 overlay 坐标转换为图片坐标"""
	var display_rect := _get_display_rect()
	var scale_x := _source_image.get_width() / display_rect.size.x
	var scale_y := _source_image.get_height() / display_rect.size.y
	
	return Vector2(
		(pos.x - display_rect.position.x) * scale_x,
		(pos.y - display_rect.position.y) * scale_y
	)

func _to_overlay_coord(pos: Vector2) -> Vector2:
	"""将图片坐标转换为 overlay 坐标"""
	var display_rect := _get_display_rect()
	var scale_x := display_rect.size.x / _source_image.get_width()
	var scale_y := display_rect.size.y / _source_image.get_height()
	
	return Vector2(
		display_rect.position.x + pos.x * scale_x,
		display_rect.position.y + pos.y * scale_y
	)

func _get_handle_at(pos: Vector2) -> DragHandle:
	"""检测鼠标下方的手柄（overlay 坐标）"""
	if _source_image == null:
		return DragHandle.NONE
	
	# 转换到图片坐标判断是否在裁剪区域内
	var img_pos := _to_image_coord(pos)
	if not _crop_rect.has_point(img_pos):
		return DragHandle.NONE
	
	# 计算裁剪框四个角在 overlay 坐标中的位置
	var top_left := _to_overlay_coord(_crop_rect.position)
	var bottom_right := _to_overlay_coord(_crop_rect.end)
	
	# 检测8个手柄区域
	if _aspect_ratio > 0:
		# 固定比例模式只允许移动
		return DragHandle.MOVE
	
	# 边角
	if pos.distance_to(top_left) <= HANDLE_SIZE:
		return DragHandle.TOP_LEFT
	if pos.distance_to(Vector2(bottom_right.x, top_left.y)) <= HANDLE_SIZE:
		return DragHandle.TOP_RIGHT
	if pos.distance_to(Vector2(top_left.x, bottom_right.y)) <= HANDLE_SIZE:
		return DragHandle.BOTTOM_LEFT
	if pos.distance_to(bottom_right) <= HANDLE_SIZE:
		return DragHandle.BOTTOM_RIGHT
	
	# 边缘
	if abs(pos.y - top_left.y) <= HANDLE_SIZE:
		return DragHandle.TOP
	if abs(pos.y - bottom_right.y) <= HANDLE_SIZE:
		return DragHandle.BOTTOM
	if abs(pos.x - top_left.x) <= HANDLE_SIZE:
		return DragHandle.LEFT
	if abs(pos.x - bottom_right.x) <= HANDLE_SIZE:
		return DragHandle.RIGHT
	
	# 内部移动
	return DragHandle.MOVE

func _apply_aspect_constraint(rect: Rect2, handle: DragHandle, start_rect: Rect2, start_mouse: Vector2, current_mouse: Vector2) -> Rect2:
	"""应用宽高比约束（中心点不变策略）"""
	var center = start_rect.get_center()
	var size = start_rect.size
	var target_ratio = _aspect_ratio
	
	# 根据拖拽手柄计算新的尺寸，保持宽高比
	var new_size = size
	
	match handle:
		DragHandle.TOP_LEFT, DragHandle.TOP, DragHandle.LEFT:
			# 拖拽左上角
			var delta = current_mouse - start_mouse
			var new_width = size.x - delta.x
			var new_height = size.y - delta.y
			# 取两者中变化最大的方向来确定新尺寸
			if abs(delta.x / size.x) > abs(delta.y / size.y):
				new_height = new_width / target_ratio
			else:
				new_width = new_height * target_ratio
			new_size = Vector2(new_width, new_height)
		
		DragHandle.TOP_RIGHT, DragHandle.RIGHT:
			var delta = current_mouse - start_mouse
			var new_width = size.x + delta.x
			var new_height = size.y - delta.y
			if abs(delta.x / size.x) > abs(delta.y / size.y):
				new_height = new_width / target_ratio
			else:
				new_width = new_height * target_ratio
			new_size = Vector2(new_width, new_height)
		
		DragHandle.BOTTOM_LEFT, DragHandle.BOTTOM:
			var delta = current_mouse - start_mouse
			var new_width = size.x - delta.x
			var new_height = size.y + delta.y
			if abs(delta.x / size.x) > abs(delta.y / size.y):
				new_height = new_width / target_ratio
			else:
				new_width = new_height * target_ratio
			new_size = Vector2(new_width, new_height)
		
		DragHandle.BOTTOM_RIGHT:
			var delta = current_mouse - start_mouse
			var new_width = size.x + delta.x
			var new_height = size.y + delta.y
			if abs(delta.x / size.x) > abs(delta.y / size.y):
				new_height = new_width / target_ratio
			else:
				new_width = new_height * target_ratio
			new_size = Vector2(new_width, new_height)
		
		_:
			return rect
	
	# 确保最小尺寸
	if new_size.x < MIN_CROP_SIZE:
		new_size.x = MIN_CROP_SIZE
		new_size.y = MIN_CROP_SIZE / target_ratio
	if new_size.y < MIN_CROP_SIZE:
		new_size.y = MIN_CROP_SIZE
		new_size.x = MIN_CROP_SIZE * target_ratio
	
	# 以中心点计算新位置
	var new_pos = center - new_size / 2
	
	return Rect2(new_pos, new_size)

func _clamp_crop_rect(rect: Rect2) -> Rect2:
	"""限制裁剪区域在图片范围内"""
	var img_w := _source_image.get_width()
	var img_h := _source_image.get_height()
	
	var result := rect
	
	# 限制位置和尺寸
	if result.position.x < 0:
		result.size.x += result.position.x
		result.position.x = 0
	if result.position.y < 0:
		result.size.y += result.position.y
		result.position.y = 0
	if result.end.x > img_w:
		result.size.x = img_w - result.position.x
	if result.end.y > img_h:
		result.size.y = img_h - result.position.y
	
	# 确保最小尺寸
	if result.size.x < MIN_CROP_SIZE:
		result.size.x = MIN_CROP_SIZE
		result.position.x = clampf(result.position.x, 0, img_w - MIN_CROP_SIZE)
	if result.size.y < MIN_CROP_SIZE:
		result.size.y = MIN_CROP_SIZE
		result.position.y = clampf(result.position.y, 0, img_h - MIN_CROP_SIZE)
	
	# 固定比例模式：强制保持比例
	if _aspect_ratio > 0:
		var target_ratio = _aspect_ratio
		var current_ratio = result.size.x / result.size.y
		
		if abs(current_ratio - target_ratio) > 0.01:
			# 调整尺寸以符合比例
			if current_ratio > target_ratio:
				# 太宽，缩小宽度
				var new_w = result.size.y * target_ratio
				var delta = result.size.x - new_w
				result.position.x += delta / 2
				result.size.x = new_w
			else:
				# 太高，缩小高度
				var new_h = result.size.x / target_ratio
				var delta = result.size.y - new_h
				result.position.y += delta / 2
				result.size.y = new_h
		
		# 再次检查边界
		if result.position.x < 0:
			result.position.x = 0
		if result.position.y < 0:
			result.position.y = 0
		if result.end.x > img_w:
			result.position.x = img_w - result.size.x
		if result.end.y > img_h:
			result.position.y = img_h - result.size.y
	
	return result

func _update_crop_rect(handle: DragHandle, mouse_delta: Vector2) -> Rect2:
	"""根据拖拽手柄和鼠标位移更新裁剪区域"""
	var new_rect := _drag_start_rect
	var img_w := _source_image.get_width()
	var img_h := _source_image.get_height()
	
	match handle:
		DragHandle.MOVE:
			# 移动整个区域
			new_rect.position += mouse_delta
		
		DragHandle.TOP_LEFT:
			new_rect.position.x += mouse_delta.x
			new_rect.size.x -= mouse_delta.x
			new_rect.position.y += mouse_delta.y
			new_rect.size.y -= mouse_delta.y
		
		DragHandle.TOP:
			new_rect.position.y += mouse_delta.y
			new_rect.size.y -= mouse_delta.y
		
		DragHandle.TOP_RIGHT:
			new_rect.size.x += mouse_delta.x
			new_rect.position.y += mouse_delta.y
			new_rect.size.y -= mouse_delta.y
		
		DragHandle.LEFT:
			new_rect.position.x += mouse_delta.x
			new_rect.size.x -= mouse_delta.x
		
		DragHandle.RIGHT:
			new_rect.size.x += mouse_delta.x
		
		DragHandle.BOTTOM_LEFT:
			new_rect.position.x += mouse_delta.x
			new_rect.size.x -= mouse_delta.x
			new_rect.size.y += mouse_delta.y
		
		DragHandle.BOTTOM:
			new_rect.size.y += mouse_delta.y
		
		DragHandle.BOTTOM_RIGHT:
			new_rect.size.x += mouse_delta.x
			new_rect.size.y += mouse_delta.y
	
	# 确保尺寸不为负
	if new_rect.size.x < 0:
		new_rect.position.x += new_rect.size.x
		new_rect.size.x = -new_rect.size.x
	if new_rect.size.y < 0:
		new_rect.position.y += new_rect.size.y
		new_rect.size.y = -new_rect.size.y
	
	# 固定比例模式特殊处理
	if _aspect_ratio > 0 and handle != DragHandle.MOVE:
		var current_mouse = _drag_start_mouse + mouse_delta
		return _apply_aspect_constraint(new_rect, handle, _drag_start_rect, _drag_start_mouse, current_mouse)
	
	return _clamp_crop_rect(new_rect)

func _on_crop_overlay_input(event: InputEvent) -> void:
	if _source_image == null:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 开始拖拽
				_dragging_handle = _get_handle_at(event.position)
				_drag_start_mouse = _to_image_coord(event.position)
				_drag_start_rect = _crop_rect
				crop_overlay.mouse_default_cursor_shape = Control.CURSOR_ARROW
			else:
				# 结束拖拽
				_dragging_handle = DragHandle.NONE
				crop_overlay.mouse_default_cursor_shape = Control.CURSOR_CROSS
	
	elif event is InputEventMouseMotion and _dragging_handle != DragHandle.NONE:
		# 拖拽更新
		var current_mouse = _to_image_coord(event.position)
		var delta = current_mouse - _drag_start_mouse
		_crop_rect = _update_crop_rect(_dragging_handle, delta)
		crop_overlay.queue_redraw()
	
	elif event is InputEventMouseMotion:
		# 更新鼠标样式（固定比例模式下不显示调整大小手柄）
		var handle = _get_handle_at(event.position)
		var cursor = Control.CURSOR_CROSS
		
		if _aspect_ratio > 0:
			# 固定比例模式只允许移动
			if handle == DragHandle.MOVE:
				cursor = Control.CURSOR_MOVE
			else:
				cursor = Control.CURSOR_CROSS
		else:
			match handle:
				DragHandle.TOP_LEFT, DragHandle.BOTTOM_RIGHT:
					cursor = Control.CURSOR_FDIAGSIZE
				DragHandle.TOP_RIGHT, DragHandle.BOTTOM_LEFT:
					cursor = Control.CURSOR_BDIAGSIZE
				DragHandle.TOP, DragHandle.BOTTOM:
					cursor = Control.CURSOR_VSIZE
				DragHandle.LEFT, DragHandle.RIGHT:
					cursor = Control.CURSOR_HSIZE
				DragHandle.MOVE:
					cursor = Control.CURSOR_MOVE
				_:
					cursor = Control.CURSOR_CROSS
		
		crop_overlay.mouse_default_cursor_shape = cursor

func _on_crop_overlay_double_click(event: InputEvent) -> void:
	"""双击重置到最大符合比例的区域（自由裁剪模式下为全选）"""
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click):
		return
	
	if _source_image == null:
		return
	
	_reset_to_max_rect()

func _on_crop_overlay_draw() -> void:
	if _source_image == null:
		return
	
	var display_rect := _get_display_rect()
	if display_rect.size.x <= 0:
		return
	
	# 绘制裁剪框（屏幕坐标）
	var top_left := _to_overlay_coord(_crop_rect.position)
	var bottom_right := _to_overlay_coord(_crop_rect.end)
	var crop_display_rect := Rect2(top_left, bottom_right - top_left)
	
	# 半透明遮罩
	var full := Rect2(Vector2.ZERO, crop_overlay.size)
	crop_overlay.draw_rect(Rect2(full.position, Vector2(full.size.x, crop_display_rect.position.y)), Color(0, 0, 0, 0.6))
	crop_overlay.draw_rect(Rect2(Vector2(0, crop_display_rect.position.y), Vector2(crop_display_rect.position.x, crop_display_rect.size.y)), Color(0, 0, 0, 0.6))
	crop_overlay.draw_rect(Rect2(Vector2(crop_display_rect.end.x, crop_display_rect.position.y), Vector2(full.size.x - crop_display_rect.end.x, crop_display_rect.size.y)), Color(0, 0, 0, 0.6))
	crop_overlay.draw_rect(Rect2(Vector2(0, crop_display_rect.end.y), Vector2(full.size.x, full.size.y - crop_display_rect.end.y)), Color(0, 0, 0, 0.6))
	
	# 绘制裁剪框边框
	crop_overlay.draw_rect(crop_display_rect, Color(1, 1, 1, 0.9), false, 2.0)
	
	# 自由裁剪模式下绘制手柄
	if _aspect_ratio == 0:
		var handles := [
			top_left,                                                    # 左上
			Vector2(bottom_right.x, top_left.y),                        # 右上
			Vector2(top_left.x, bottom_right.y),                        # 左下
			bottom_right,                                                # 右下
			Vector2((top_left.x + bottom_right.x) / 2, top_left.y),     # 上中
			Vector2((top_left.x + bottom_right.x) / 2, bottom_right.y), # 下中
			Vector2(top_left.x, (top_left.y + bottom_right.y) / 2),     # 左中
			Vector2(bottom_right.x, (top_left.y + bottom_right.y) / 2)  # 右中
		]
		for handle in handles:
			crop_overlay.draw_rect(Rect2(handle - Vector2(HANDLE_SIZE/2, HANDLE_SIZE/2), Vector2(HANDLE_SIZE, HANDLE_SIZE)), Color(1, 1, 1, 0.8), true)
			crop_overlay.draw_rect(Rect2(handle - Vector2(HANDLE_SIZE/2, HANDLE_SIZE/2), Vector2(HANDLE_SIZE, HANDLE_SIZE)), Color(0, 0, 0, 0.5), false, 1.0)

func _on_confirm() -> void:
	if _source_image == null or _crop_rect.size.x < 1 or _crop_rect.size.y < 1:
		return
	
	var cropped := _source_image.get_region(Rect2i(
		int(_crop_rect.position.x), int(_crop_rect.position.y),
		int(_crop_rect.size.x), int(_crop_rect.size.y)
	))
	
	visible = false
	crop_confirmed.emit(cropped)

func _on_cancel() -> void:
	visible = false
