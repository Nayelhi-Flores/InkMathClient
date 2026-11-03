class_name UiKit
extends RefCounted
## Estilos compartidos (misma paleta que la web) para construir UI por código.

const PRIMARY := Color("0984C6")
const PRIMARY_DARK := Color("076DA4")
const DANGER := Color("F87171")
const DANGER_DARK := Color("DC2626")
const SUCCESS := Color("10B981")
const SUCCESS_DARK := Color("047857")
const SURFACE := Color("F8FAFC")
const BORDER := Color("E2E8F0")
const TEXT := Color("2B3A4A")
const MUTED := Color("8292A1")


# Caja con borde inferior grueso (efecto 3D)
static func box3d(bg: Color, dark: Color, border_bottom: int = 4, pad_top: int = 8, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = dark
	s.border_width_bottom = border_bottom
	s.set_corner_radius_all(radius)
	s.content_margin_top = pad_top
	s.content_margin_bottom = 8
	s.content_margin_left = 12
	s.content_margin_right = 12
	return s


static func button3d(text: String, bg: Color = PRIMARY, dark: Color = PRIMARY_DARK) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, box3d(bg, dark, 4, 8))
	b.add_theme_stylebox_override("pressed", box3d(bg, dark, 1, 11))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_font_size_override("font_size", 15)
	return b


# Tarjeta plana redondeada
static func card(bg: Color = SURFACE, radius: int = 16, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(2)
	s.border_color = BORDER
	s.set_content_margin_all(margin)
	return s
