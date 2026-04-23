## CropDialog.gd
## 图片裁剪对话框：显示图片，用户拖拽选择裁剪区域，确认后返回裁剪后的 Image

extends Control

signal crop_confirmed(cropped_image: Image)

@onready var overlay: ColorRect       = $Overlay
@onready var panel: PanelContainer    = $Panel
@onready var image_rect: TextureRect  = $Panel/VBox/ImageContainer/ImageRect
@onready var crop_overlay: Control    = $Panel/VBox/ImageContainer/CropOverlay
@onready var confirm_btn: Button      = $Panel/VBox/Buttons/ConfirmButton
@onready var cancel_btn: Button       = $Panel/VBox/Buttons/CancelButton
@onready var hint_label: Label        = $Panel/VBox/HintLabel

var _source_image: Image = null
var _drag_start := Vector2.ZERO
var _drag_end := Vector2.ZERO
var _is_dragging := false
var _crop_rect := Rect2()  # 在图片坐标系中的裁剪区域
var _force_square := false  # 头像模式：强制正方形裁剪

const DISPLAY_SIZE := Vector2(600, 600)

func _ready() -> void:
	visible = false
	confirm_btn.pressed.connect(_on_confirm)
	cancel_btn.pressed.connect(_on_cancel)
	crop_overlay.draw.connect(_on_crop_overlay_draw)
	crop_overlay.gui_input.connect(_on_crop_overlay_input)

## force_square=true 时只允许正方形裁剪（头像），false 时默认选中整张图片（立绘）
func open_image(path: String, force_square: bool = false) -> void:
	var img := Image.new()
	if img.load(path) != OK:
		return
	_source_image = img
	_force_square = force_square
	image_rect.texture = ImageTexture.create_from_image(img)
	if force_square:
		# 头像：默认居中正方形
		var min_side := minf(img.get_width(), img.get_height())
		var ox := (img.get_width() - min_side) / 2.0
		var oy := (img.get_height() - min_side) / 2.0
		_crop_rect = Rect2(ox, oy, min_side, min_side)
	else:
		# 立绘：默认选中整张图片
		_crop_rect = Rect2(0, 0, img.get_width(), img.get_height())
	crop_overlay.queue_redraw()
	visible = true

func _on_crop_overlay_draw() -> void:
	if _source_image == null:
		return
	var display_rect := _get_display_rect()
	if display_rect.size.x <= 0:
		return
	var scale_x := display_rect.size.x / _source_image.get_width()
	var scale_y := display_rect.size.y / _source_image.get_height()
	# 将图片坐标系的 _crop_rect 转换为显示坐标
	var dr := Rect2(
		display_rect.position.x + _crop_rect.position.x * scale_x,
		display_rect.position.y + _crop_rect.position.y * scale_y,
		_crop_rect.size.x * scale_x,
		_crop_rect.size.y * scale_y
	)
	# 半透明遮罩（四个矩形）
	var full := Rect2(Vector2.ZERO, crop_overlay.size)
	crop_overlay.draw_rect(Rect2(full.position, Vector2(full.size.x, dr.position.y)), Color(0, 0, 0, 0.5))
	crop_overlay.draw_rect(Rect2(Vector2(0, dr.position.y), Vector2(dr.position.x, dr.size.y)), Color(0, 0, 0, 0.5))
	crop_overlay.draw_rect(Rect2(Vector2(dr.end.x, dr.position.y), Vector2(full.size.x - dr.end.x, dr.size.y)), Color(0, 0, 0, 0.5))
	crop_overlay.draw_rect(Rect2(Vector2(0, dr.end.y), Vector2(full.size.x, full.size.y - dr.end.y)), Color(0, 0, 0, 0.5))
	# 裁剪框边线
	crop_overlay.draw_rect(dr, Color(1, 1, 1, 0.9), false, 2.0)

func _on_crop_overlay_input(event: InputEvent) -> void:
	if _source_image == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_start = event.position
				_drag_end = event.position
			else:
				_is_dragging = false
				_update_crop_from_drag()
	elif event is InputEventMouseMotion and _is_dragging:
		_drag_end = event.position
		_update_crop_from_drag()
		crop_overlay.queue_redraw()

func _update_crop_from_drag() -> void:
	var display_rect := _get_display_rect()
	if display_rect.size.x <= 0:
		return
	var scale_x := _source_image.get_width() / display_rect.size.x
	var scale_y := _source_image.get_height() / display_rect.size.y
	# 转换为图片坐标
	var p1 := Vector2(
		(_drag_start.x - display_rect.position.x) * scale_x,
		(_drag_start.y - display_rect.position.y) * scale_y
	)
	var p2 := Vector2(
		(_drag_end.x - display_rect.position.x) * scale_x,
		(_drag_end.y - display_rect.position.y) * scale_y
	)
	var rx := minf(p1.x, p2.x)
	var ry := minf(p1.y, p2.y)
	var rw := absf(p2.x - p1.x)
	var rh := absf(p2.y - p1.y)
	# 头像模式：强制正方形（取较小边）
	if _force_square:
		var side := minf(rw, rh)
		rw = side
		rh = side
	# 限制在图片范围内
	rx = clampf(rx, 0, _source_image.get_width())
	ry = clampf(ry, 0, _source_image.get_height())
	rw = clampf(rw, 1, _source_image.get_width() - rx)
	rh = clampf(rh, 1, _source_image.get_height() - ry)
	_crop_rect = Rect2(rx, ry, rw, rh)
	crop_overlay.queue_redraw()

func _get_display_rect() -> Rect2:
	# ImageRect 在 crop_overlay 坐标系中的实际显示区域（保持比例）
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

func _on_confirm() -> void:
	if _source_image == null or _crop_rect.size.x < 1 or _crop_rect.size.y < 1:
		return
	var cropped := _source_image.get_region(
		Rect2i(int(_crop_rect.position.x), int(_crop_rect.position.y),
			   int(_crop_rect.size.x), int(_crop_rect.size.y))
	)
	visible = false
	crop_confirmed.emit(cropped)

func _on_cancel() -> void:
	visible = false
