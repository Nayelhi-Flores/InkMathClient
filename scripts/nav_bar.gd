class_name NavBar
extends PanelContainer
## Barra de navegación inferior (píldora redondeada, pestaña activa resaltada).
## Uso en cada escena principal:  NavBar.attach($MainLayoutVBox/BottomNavbarMargin, "jugar")
## Los iconos son opcionales: si el archivo no existe se muestra solo el texto.

const TABS := [
	{"id": "jugar",    "label": "Jugar",    "scene": "res://scenes/menu_inicio.tscn",      "icon": "res://assets/icons/chevron-left.svg"},
	{"id": "aulas",    "label": "Aulas",    "scene": "res://scenes/aulas.tscn",  "icon": "res://assets/icons/chevron-left.svg"},
	{"id": "arrecife", "label": "Arrecife", "scene": "res://scenes/arrecife.tscn",          "icon": "res://assets/icons/chevron-left.svg"},
	{"id": "perfil",   "label": "Perfil",   "scene": "res://scenes/perfil.tscn",            "icon": "res://assets/icons/chevron-left.svg"},
	{"id": "tienda",   "label": "Tienda",   "scene": "res://scenes/tienda_mascota.tscn",    "icon": "res://assets/icons/chevron-left.svg"},
]

const BAR_BG := Color(1, 1, 1, 0.94)
const SELECTED_BG := Color("BFD6EA")

var current := ""


# Oculta lo que hubiera en el contenedor (la barra vieja) y coloca esta.
static func attach(parent: Control, current_id: String) -> NavBar:
	for c in parent.get_children():
		c.hide()
	var nb := NavBar.new()
	nb.current = current_id
	parent.add_child(nb)
	return nb


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = BAR_BG
	sb.set_corner_radius_all(28)
	sb.set_border_width_all(2)
	sb.border_color = UiKit.BORDER
	sb.shadow_color = Color(0, 0, 0, 0.15)
	sb.shadow_size = 6
	sb.set_content_margin_all(6)
	add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for t in TABS:
		row.add_child(_make_tab(t))


func _make_tab(t: Dictionary) -> Button:
	var b := Button.new()
	b.text = t["label"]
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 58)
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", UiKit.TEXT)
	b.add_theme_color_override("font_hover_color", UiKit.TEXT)
	b.add_theme_color_override("font_pressed_color", UiKit.TEXT)

	if ResourceLoader.exists(t["icon"]):
		b.icon = load(t["icon"])
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_constant_override("icon_max_width", 28)

	var selected: bool = t["id"] == current
	var pill := StyleBoxFlat.new()
	pill.bg_color = SELECTED_BG if selected else Color(0, 0, 0, 0)
	pill.set_corner_radius_all(22)
	pill.set_content_margin_all(4)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, pill)

	b.pressed.connect(_on_tab.bind(t))
	return b


func _on_tab(t: Dictionary) -> void:
	if t["id"] == current:
		return
	if not ResourceLoader.exists(t["scene"]):
		push_warning("Escena aún no disponible: %s" % t["scene"])
		return
	get_tree().change_scene_to_file(t["scene"])
