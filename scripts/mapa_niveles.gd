extends Control
## Mapa de niveles estilo "camino": filtro por sección (grado), unidades como encabezados,
## nodos en zigzag y el nivel actual con burbuja. Autocontenido: no depende de Models ni de UiKit.

@export var column_ratio := 0.7
@export var niveles_container_path: NodePath
@export var quiz_scene: PackedScene

@onready var _niveles_container: VBoxContainer = get_node_or_null(niveles_container_path)
@onready var _label_monedas: Label = find_child("Monedas", true, false) as Label

const BUBBLE_SIZE := 76.0
const MAX_AMPLITUDE := 90.0
const WAVE_FREQUENCY := 0.9
const COL_WIDTH := 130.0   # ancho reservado por nodo (burbuja incluida)
const MENU_SCENE := "res://scenes/menu_inicio.tscn"

const C_PRIMARY := Color("0984C6")
const C_PRIMARY_DARK := Color("076DA4")
const C_TEXT := Color("2B3A4A")
const UNIT_COLORS := [Color("0984C6"), Color("10B981"), Color("F59E0B"), Color("A855F7")]

var _all: Array = []            # todos los niveles (Dictionary)
var _sections: Array = []       # nombres de sección, en orden
var _sel := ""                  # sección seleccionada
var _selector: OptionButton
var _current_btn: Control


func _ready() -> void:
	AudioManager.stop_music()
	var contenido := get_node_or_null("MainLayoutVBox") as Control
	if contenido:
		_limitar_ancho(contenido)
		get_viewport().size_changed.connect(func(): _limitar_ancho(contenido))

	# La navegación del menú ahora vive en menu_inicio
	for n in ["BtnSimulacion", "BtnFormulario"]:
		var b := find_child(n, true, false) as Control
		if b:
			b.hide()

	var back := find_child("BtnBack", true, false) as Button
	if back and not back.pressed.is_connected(_on_btn_back_pressed):
		back.pressed.connect(_on_btn_back_pressed)

	_resolver_contenedor()
	_setup_selector()

	if _label_monedas:
		GameManager.monedas_actualizadas.connect(_mostrar_monedas)
		_mostrar_monedas(GameManager.monedas)
		_cargar_monedas()

	get_viewport().size_changed.connect(func(): _render.call_deferred())
	_cargar_niveles()


# Garantiza un VBoxContainer dentro de un ScrollContainer, aunque la ruta del Inspector esté vacía o rota.
func _resolver_contenedor() -> void:
	if _niveles_container == null:
		push_warning("[MapaNiveles] 'Niveles Container Path' vacío o inválido; buscando un contenedor...")
		for scroll_node in find_children("*", "ScrollContainer", true, false):
			for ch in scroll_node.get_children():
				if ch is VBoxContainer:
					_niveles_container = ch
					break
			if _niveles_container != null:
				break

	if _niveles_container == null:
		var host := get_node_or_null("MainLayoutVBox") as Control
		var scroll := ScrollContainer.new()
		scroll.name = "NivelesScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var vb := VBoxContainer.new()
		scroll.add_child(vb)
		if host:
			host.add_child(scroll)
			host.move_child(scroll, mini(1, host.get_child_count() - 1))
		else:
			add_child(scroll)
			scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_niveles_container = vb
		push_warning("[MapaNiveles] No había contenedor de niveles: se creó uno por código.")

	# Sin estas banderas el contenedor puede quedar con ancho/alto 0 y no se ve nada
	_niveles_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var parent_ctrl := _niveles_container.get_parent() as Control
	if parent_ctrl:
		parent_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent_ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	print("[MapaNiveles] contenedor: %s" % _niveles_container.get_path())


func _limitar_ancho(nodo: Control) -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		return
	var w := minf(vp.x, vp.y * column_ratio)
	var m := (vp.x - w) / 2.0 / vp.x
	nodo.anchor_left = m
	nodo.anchor_right = 1.0 - m
	nodo.offset_left = 0
	nodo.offset_right = 0


# ---------- Estilos ----------
func _box(bg: Color, dark: Color, bottom: int, radius: int, pad_top: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = dark
	s.border_width_bottom = bottom
	s.set_corner_radius_all(radius)
	s.content_margin_top = pad_top
	s.content_margin_bottom = 6
	s.content_margin_left = 12
	s.content_margin_right = 12
	return s


# ---------- Selector de sección ----------
func _setup_selector() -> void:
	_selector = find_child("SeccionFiltro", true, false) as OptionButton
	if _selector == null:
		_selector = OptionButton.new()
		_selector.name = "SeccionFiltro"
		var header := get_node_or_null("MainLayoutVBox/TopHeaderMargin/TopHeaderHBox") as Control
		var host: Control = header if header else get_node_or_null("MainLayoutVBox") as Control
		if host == null:
			host = self
		host.add_child(_selector)
		if host != header and host != self:
			host.move_child(_selector, 0)
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector.custom_minimum_size = Vector2(0, 44)
	_selector.clip_text = true
	_selector.add_theme_font_size_override("font_size", 14)
	for st in ["normal", "hover", "pressed", "focus"]:
		_selector.add_theme_stylebox_override(st, _box(C_PRIMARY, C_PRIMARY_DARK, 4, 10, 8))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_selector.add_theme_color_override(c, Color.WHITE)
	_selector.item_selected.connect(_on_section_selected)


func _on_section_selected(idx: int) -> void:
	_sel = str(_sections[idx])
	GameManager.set("selected_section", _sel)   # recordar al volver del quiz
	_render()


# ---------- Monedas (solo si el mapa aún tiene la etiqueta) ----------
func _cargar_monedas() -> void:
	var res := await ApiService.obtener_saldo_async()
	if not is_inside_tree() or res[0] != 200:
		return
	var data = JSON.parse_string(res[1])
	if data is Dictionary and data.has("saldo"):
		GameManager.set_monedas(int(data["saldo"]))


func _mostrar_monedas(valor: int) -> void:
	if _label_monedas:
		_label_monedas.text = str(valor)


# ---------- Carga ----------
func _to_int(v: Variant) -> int:
	return int(v) if v != null else 0


func _cargar_niveles() -> void:
	_mensaje("Cargando niveles...")
	var res := await ApiService.obtener_mapa_niveles_async()
	if not is_inside_tree():
		return
	if res[0] != 200:
		push_warning("[MapaNiveles] HTTP %s" % res[0])
		_mensaje("No se pudieron cargar los niveles. Revisa tu conexión (código %s)." % res[0])
		return

	var data = JSON.parse_string(res[1])
	if not (data is Array) or data.is_empty():
		push_warning("[MapaNiveles] Respuesta vacía o con formato inesperado.")
		_mensaje("No hay niveles disponibles.")
		return

	_all.clear()
	for item in data:
		if not (item is Dictionary):
			continue
		_all.append({
			"id": _to_int(item.get("nivelId")),
			"test": _to_int(item.get("testId")),
			"titulo": str(item.get("titulo", "")),
			"cat": str(item.get("categoria", "")),
			"sec": str(item.get("seccion", "")),
			"sec_orden": _to_int(item.get("seccionOrden")),
			"orden": _to_int(item.get("orden")),
			"estado": str(item.get("estado", "No Iniciado")),
		})
	_all.sort_custom(func(a, b):
		if a["sec_orden"] != b["sec_orden"]:
			return a["sec_orden"] < b["sec_orden"]
		return a["orden"] < b["orden"])

	_sections.clear()
	for n in _all:
		if not _sections.has(n["sec"]):
			_sections.append(n["sec"])

	_selector.clear()
	for s in _sections:
		_selector.add_item(s if not str(s).is_empty() else "Niveles")
	_sel = _default_section()
	_selector.select(maxi(0, _sections.find(_sel)))
	print("[MapaNiveles] %d niveles, %d secciones, seleccionada: %s" % [_all.size(), _sections.size(), _sel])
	_render()


# Sección guardada, o la primera con progreso, o la primera sin terminar
func _default_section() -> String:
	var saved = GameManager.get("selected_section")
	if saved != null and _sections.has(str(saved)):
		return str(saved)
	for s in _sections:
		for n in _all:
			if n["sec"] == s and n["estado"] == "En Progreso":
				return s
	for s in _sections:
		for n in _all:
			if n["sec"] == s and n["estado"] != "Completado":
				return s
	return _sections[0]


# ---------- Dibujo ----------
func _mensaje(texto: String) -> void:
	if _niveles_container == null:
		return
	for c in _niveles_container.get_children():
		_niveles_container.remove_child(c)
		c.queue_free()
	var l := Label.new()
	l.text = texto
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color.WHITE)
	_niveles_container.add_child(l)


func _unit_header(texto: String, idx: int) -> Control:
	var col: Color = UNIT_COLORS[idx % UNIT_COLORS.size()]
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 8)
	wrap.add_theme_constant_override("margin_right", 8)
	wrap.add_theme_constant_override("margin_top", 16)
	wrap.add_theme_constant_override("margin_bottom", 6)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(col, col.darkened(0.25), 4, 14, 8))
	wrap.add_child(panel)
	var l := Label.new()
	l.text = texto
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(l)
	return wrap


# Burbuja "EMPEZAR / CONTINUAR": es un botón, así que se puede tocar o cliquear
func _start_bubble(texto: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size = Vector2(0, 36)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, _box(Color.WHITE, Color("CBD5E1"), 3, 10, 4))
	b.add_theme_stylebox_override("pressed", _box(Color.WHITE, Color("CBD5E1"), 1, 10, 6))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, C_PRIMARY)
	return b


func _node_button(num: int, estado: String, locked: bool, is_current: bool) -> Button:
	var bg := Color("6CB9E3")
	var dark := Color("4A9CC9")
	if locked:
		bg = Color("E5E7EB")
		dark = Color("CBD5E1")
	elif estado == "Completado":
		bg = Color("FBBF24")
		dark = Color("D97706")
	elif is_current:
		bg = C_PRIMARY
		dark = C_PRIMARY_DARK
	elif estado == "En Progreso":
		bg = Color("38BDF8")
		dark = Color("0284C7")

	var r := int(BUBBLE_SIZE / 2.0)
	var b := Button.new()
	b.text = str(num)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(BUBBLE_SIZE, BUBBLE_SIZE)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 26)
	for st in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _box(bg, dark, 6, r, 0))
	b.add_theme_stylebox_override("pressed", _box(bg, dark, 2, r, 0))
	var fc := Color("94A3B8") if locked else Color.WHITE
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, fc)
	b.disabled = locked
	return b


func _render() -> void:
	if _niveles_container == null or _all.is_empty() or not is_inside_tree():
		return
	for c in _niveles_container.get_children():
		_niveles_container.remove_child(c)
		c.queue_free()
	_niveles_container.add_theme_constant_override("separation", 8)
	_current_btn = null

	var lista := _all.filter(func(n): return n["sec"] == _sel)

	# Reglas: dentro de la sección, un nivel sin progreso se abre al completar el anterior.
	var prev_done := true
	var locked_list: Array = []
	var current_i := -1
	for i in lista.size():
		var n: Dictionary = lista[i]
		var lk: bool = (not prev_done and n["estado"] == "No Iniciado") or n["test"] <= 0
		locked_list.append(lk)
		if current_i == -1 and not lk and n["estado"] != "Completado":
			current_i = i
		prev_done = n["estado"] == "Completado"

	# El "Siguiente" del quiz avanza dentro de esta sección
	GameManager.ordered_test_ids.clear()
	for n in lista:
		GameManager.ordered_test_ids.append(n["test"])

	var ancho: float = _niveles_container.size.x
	if ancho <= 0.0:
		ancho = get_viewport_rect().size.x
	var col_w := minf(COL_WIDTH, maxf(BUBBLE_SIZE, ancho - 16.0))
	var centro := ancho / 2.0
	var amplitud := clampf(centro - BUBBLE_SIZE / 2.0 - 12.0, 0.0, MAX_AMPLITUDE)

	var unidad_actual := "\u0001"
	var unidad_idx := -1
	for i in lista.size():
		var n: Dictionary = lista[i]
		if n["cat"] != unidad_actual:
			unidad_actual = n["cat"]
			unidad_idx += 1
			if not unidad_actual.is_empty():
				_niveles_container.add_child(_unit_header(unidad_actual, unidad_idx))

		var is_current := i == current_i
		var wrapper := MarginContainer.new()
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cx := centro + sin(i * WAVE_FREQUENCY) * amplitud
		wrapper.add_theme_constant_override("margin_left", int(clampf(cx - col_w / 2.0, 0.0, maxf(0.0, ancho - col_w))))

		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(col_w, 0)
		box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_theme_constant_override("separation", 2)
		wrapper.add_child(box)

		if is_current:
			var bubble := _start_bubble("CONTINUAR" if n["estado"] == "En Progreso" else "EMPEZAR")
			bubble.pressed.connect(_on_level_selected.bind(n["test"], n["titulo"]))
			box.add_child(bubble)

		var btn := _node_button(i + 1, n["estado"], locked_list[i], is_current)
		if not locked_list[i]:
			btn.pressed.connect(_on_level_selected.bind(n["test"], n["titulo"]))
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.add_child(btn)
		if is_current:
			_current_btn = btn

		_niveles_container.add_child(wrapper)

	var pc := _niveles_container.get_parent() as Control
	print("[MapaNiveles] dibujados %d niveles en '%s' (padre %s)" % [lista.size(), _sel, pc.size if pc else "sin padre"])
	_scroll_to_current.call_deferred()


# Lleva la vista al nivel actual (como en Duolingo)
func _scroll_to_current() -> void:
	if _current_btn == null or not is_instance_valid(_current_btn):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if _current_btn == null or not is_instance_valid(_current_btn):
		return
	var sc := _niveles_container.get_parent() as ScrollContainer
	if sc:
		sc.ensure_control_visible(_current_btn)


func _on_level_selected(test_id: int, titulo: String) -> void:
	if test_id <= 0:
		return
	GameManager.return_scene = ""
	GameManager.selected_test_id = test_id
	GameManager.selected_test_title = titulo
	GameManager.set("selected_section", _sel)
	if quiz_scene:
		get_tree().change_scene_to_packed(quiz_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/quiz_scene.tscn")


func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
