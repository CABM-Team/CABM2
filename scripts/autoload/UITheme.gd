## UITheme.gd
## 全局 UI 主题 autoload，统一美化按钮、面板等控件样式

extends Node

func _ready() -> void:
	var theme := _build_theme()
	# 应用到整个场景树
	get_tree().root.theme = theme

func _build_theme() -> Theme:
	var theme := Theme.new()

	# ── Button ────────────────────────────────────────────────
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.12, 0.12, 0.20, 0.85)
	btn_normal.border_color = Color(0.5, 0.4, 0.8, 0.7)
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(8)
	btn_normal.content_margin_left = 12
	btn_normal.content_margin_right = 12
	btn_normal.content_margin_top = 6
	btn_normal.content_margin_bottom = 6

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.22, 0.18, 0.38, 0.95)
	btn_hover.border_color = Color(0.7, 0.5, 1.0, 0.9)
	btn_hover.set_border_width_all(1)
	btn_hover.set_corner_radius_all(8)
	btn_hover.content_margin_left = 12
	btn_hover.content_margin_right = 12
	btn_hover.content_margin_top = 6
	btn_hover.content_margin_bottom = 6

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = Color(0.30, 0.20, 0.50, 1.0)
	btn_pressed.border_color = Color(0.8, 0.6, 1.0, 1.0)
	btn_pressed.set_border_width_all(2)
	btn_pressed.set_corner_radius_all(8)
	btn_pressed.content_margin_left = 12
	btn_pressed.content_margin_right = 12
	btn_pressed.content_margin_top = 6
	btn_pressed.content_margin_bottom = 6

	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("disabled", "Button", btn_normal)
	theme.set_color("font_color", "Button", Color(0.92, 0.88, 1.0))
	theme.set_color("font_hover_color", "Button", Color(1.0, 0.95, 1.0))
	theme.set_color("font_pressed_color", "Button", Color(1.0, 1.0, 1.0))
	theme.set_font_size("font_size", "Button", 16)

	# ── PanelContainer ────────────────────────────────────────
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.12, 0.82)
	panel_style.border_color = Color(0.4, 0.3, 0.6, 0.5)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 14
	panel_style.content_margin_right = 14
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 10
	theme.set_stylebox("panel", "PanelContainer", panel_style)

	# ── TextEdit ──────────────────────────────────────────────
	var textedit_style := StyleBoxFlat.new()
	textedit_style.bg_color = Color(0.08, 0.08, 0.16, 0.90)
	textedit_style.border_color = Color(0.45, 0.35, 0.7, 0.6)
	textedit_style.set_border_width_all(1)
	textedit_style.set_corner_radius_all(8)
	textedit_style.content_margin_left = 10
	textedit_style.content_margin_right = 10
	textedit_style.content_margin_top = 8
	textedit_style.content_margin_bottom = 8
	theme.set_stylebox("normal", "TextEdit", textedit_style)
	theme.set_stylebox("focus", "TextEdit", textedit_style)
	theme.set_color("font_color", "TextEdit", Color(0.95, 0.92, 1.0))
	theme.set_color("font_placeholder_color", "TextEdit", Color(0.55, 0.52, 0.65))
	theme.set_font_size("font_size", "TextEdit", 16)

	# ── Label ─────────────────────────────────────────────────
	theme.set_color("font_color", "Label", Color(0.92, 0.90, 1.0))
	theme.set_font_size("font_size", "Label", 15)

	# ── RichTextLabel ─────────────────────────────────────────
	theme.set_color("default_color", "RichTextLabel", Color(0.95, 0.93, 1.0))
	theme.set_font_size("normal_font_size", "RichTextLabel", 17)

	# ── ScrollContainer ───────────────────────────────────────
	var scroll_bg := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", scroll_bg)

	return theme
