class_name PauseOverlay
extends Control

signal resumed
signal exit_requested

const C_PRIMARY := Color("0984C6")
const C_PRIMARY_DARK := Color("076DA4")
const C_DANGER := Color("F87171")
const C_DANGER_DARK := Color("DC2626")
const C_SURFACE := Color("F8FAFC")
const C_BORDER := Color("E2E8F0")
const C_TEXT := Color("2B3A4A")
const C_MUTED := Color("8292A1")


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # bloquea toques al juego mientras está abierto

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(2)
	sb.border_color = C_BORDER
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Pausa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", C_TEXT)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Tómate tu tiempo para pensar."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", C_MUTED)
	box.add_child(sub)

	var b_resume := _make_button("Continuar", C_PRIMARY, C_PRIMARY_DARK)
	b_resume.pressed.connect(close)
	box.add_child(b_resume)

	var b_exit := _make_button("Salir", C_DANGER, C_DANGER_DARK)
	b_exit.pressed.connect(func():
		visible = false
		exit_requested.emit())
	box.add_child(b_exit)


func open() -> void:
	visible = true
	move_to_front()


func close() -> void:
	if not visible:
		return
	visible = false
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Botón con borde inferior grueso (efecto 3D), igual que el resto del juego.
func _make_button(text: String, bg: Color, bg_dark: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, _box(bg, bg_dark, 4, 8))
	b.add_theme_stylebox_override("pressed", _box(bg, bg_dark, 1, 11))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_font_size_override("font_size", 16)
	return b


func _box(bg: Color, dark: Color, border_bottom: int, pad_top: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = dark
	s.border_width_bottom = border_bottom
	s.set_corner_radius_all(10)
	s.content_margin_top = pad_top
	s.content_margin_bottom = 8
	s.content_margin_left = 12
	s.content_margin_right = 12
	return s
