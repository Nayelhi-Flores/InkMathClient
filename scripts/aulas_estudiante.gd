extends Control
## Aulas del estudiante: ver mis aulas, unirme con un código, tests de la clase,
## recursos, ranking de compañeros, ir al Arrecife y salir del aula (baja lógica en el servidor).

@export var column_ratio := 0.7

const QUIZ_SCENE := "res://scenes/quiz_scene.tscn"
const ARRECIFE_SCENE := "res://scenes/arrecife.tscn"
const SELF_SCENE := "res://scenes/aulas.tscn"

const C_TEXT := Color("2B3A4A")
const C_MUTED := Color("8292A1")
const C_PRIMARY := Color("0984C6")
const C_PRIMARY_DARK := Color("076DA4")
const C_GREEN := Color("10B981")
const C_GREEN_DARK := Color("047857")
const C_RED := Color("F87171")
const C_RED_DARK := Color("DC2626")
const C_GRAY := Color("94A3B8")
const C_GRAY_DARK := Color("64748B")
const C_SOFT := Color("E2E8F0")
const TIPOS_RECURSO := {1: "Documento", 2: "Enlace", 3: "Video"}

var _aulas: Array = []
var _aula: Dictionary = {}
var _tab := "tests"
var _mobile := false
var _overlay: Control
var _toast: PanelContainer
var _toast_label: Label
var _tab_buttons: Dictionary = {}

@onready var _column: Control = _fn("Column")
@onready var _title_label: Label = _fn("TitleLabel")
@onready var _btn_join: Button = _fn("BtnJoin")
@onready var _detail_header: Control = _fn("DetailHeader")
@onready var _btn_back: Button = _fn("BtnBack")
@onready var _aula_title: Label = _fn("AulaTitle")
@onready var _tabs: HBoxContainer = _fn("Tabs")
@onready var _scroll: ScrollContainer = _fn("Scroll")
@onready var _content: VBoxContainer = _fn("Content")
@onready var _actions: HBoxContainer = _fn("Actions")


func _fn(nombre: String) -> Node:
	var n := find_child(nombre, true, false)
	if n == null:
		push_error("No se encontró el nodo '%s' (revisa el nombre)." % nombre)
	return n


func _ready() -> void:
	AudioManager.stop_music()
	_limitar_ancho(_column)
	get_viewport().size_changed.connect(func(): _limitar_ancho(_column))
	_mobile = OS.has_feature("web") and bool(JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches"))

	_style_button(_btn_join, C_GREEN, C_GREEN_DARK)
	_btn_join.pressed.connect(_join_overlay)
	_style_button(_btn_back, C_GRAY, C_GRAY_DARK)
	_btn_back.pressed.connect(_show_list)

	for t in [["tests", "Tests"], ["recursos", "Recursos"], ["ranking", "Ranking"]]:
		var b := _btn(t[1], C_GRAY, C_GRAY_DARK, 40, 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_tab.bind(t[0]))
		_tabs.add_child(b)
		_tab_buttons[t[0]] = b

	var arrecife := _btn("Arrecife de ayuda", C_PRIMARY, C_PRIMARY_DARK, 44, 14)
	arrecife.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arrecife.pressed.connect(_go_arrecife)
	_actions.add_child(arrecife)
	var salir := _btn("Salir del aula", C_RED, C_RED_DARK, 44, 14)
	salir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	salir.pressed.connect(_confirm_leave)
	_actions.add_child(salir)

	_show_list()
	_load_aulas()


func _limitar_ancho(nodo: Control) -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or nodo == null:
		return
	var w := minf(vp.x, vp.y * column_ratio)
	var m := (vp.x - w) / 2.0 / vp.x
	nodo.anchor_left = m
	nodo.anchor_right = 1.0 - m
	nodo.offset_left = 0
	nodo.offset_right = 0


# ---------- Estilos ----------
func _box(bg: Color, border: Color, radius: int = 14, margin: int = 12, bottom: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_bottom = bottom
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _style_button(b: Button, bg: Color, dark: Color, fuente: int = 14) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", fuente)
	for st in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _box(bg, dark, 10, 8, 4))
	b.add_theme_stylebox_override("pressed", _box(bg, dark, 10, 8, 1))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, Color.WHITE)


func _btn(texto: String, bg: Color, dark: Color, altura: float = 40.0, fuente: int = 14) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(0, altura)
	_style_button(b, bg, dark, fuente)
	return b


func _label(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l


func _msg(res: Array) -> String:
	var d = JSON.parse_string(res[1])
	if d is Dictionary and d.has("mensaje"):
		return str(d["mensaje"])
	return "No se pudo completar la acción." if res[0] != 0 else "Sin conexión."


func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


func _note(texto: String) -> void:
	_clear()
	_content.add_child(_label(texto, 15, Color.WHITE))


func _card() -> Array:    # [panel, vbox]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color.WHITE, C_SOFT, 14, 12, 3))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return [p, v]


# ---------- Vistas ----------
func _show_list() -> void:
	_aula = {}
	_detail_header.hide()
	_tabs.hide()
	_actions.hide()
	_title_label.show()
	_btn_join.show()
	_render_aulas()


func _show_detail() -> void:
	_title_label.hide()
	_btn_join.hide()
	_detail_header.show()
	_tabs.show()
	_actions.show()
	_aula_title.text = str(_aula.get("nombre", "Aula"))


# ---------- Lista de aulas ----------
func _load_aulas() -> void:
	_note("Cargando tus aulas...")
	var res := await ApiService.mis_aulas_async()
	if not is_inside_tree():
		return
	if res[0] != 200:
		_note("No se pudieron cargar tus aulas. " + _msg(res))
		return
	var data = JSON.parse_string(res[1])
	_aulas = data if data is Array else []

	# Al volver de resolver un test de la clase, se reabre esa aula
	var reabrir: int = GameManager.reopen_aula_id
	if reabrir > 0:
		GameManager.reopen_aula_id = 0
		for a in _aulas:
			if int(a["id"]) == reabrir:
				_open_aula(a)
				return
	_render_aulas()


func _render_aulas() -> void:
	if not _aula.is_empty():
		return
	if _aulas.is_empty():
		_note("Todavía no estás en ningún aula. Pide el código a tu maestro y toca «Unirme».")
		return
	_clear()
	for a in _aulas:
		var c := _card()
		var v: VBoxContainer = c[1]
		v.add_child(_label(str(a["nombre"]), 18, C_TEXT))
		v.add_child(_label("%d estudiantes" % int(a.get("totalEstudiantes", 0)), 13, C_MUTED))
		var abrir := _btn("Abrir", C_PRIMARY, C_PRIMARY_DARK, 40, 14)
		abrir.pressed.connect(_open_aula.bind(a))
		v.add_child(abrir)
		_content.add_child(c[0])


func _open_aula(a: Dictionary) -> void:
	_aula = a
	GameManager.selected_aula_id = int(a["id"])
	_show_detail()
	_set_tab("tests")


# ---------- Pestañas ----------
func _set_tab(tab: String) -> void:
	_tab = tab
	for k in _tab_buttons:
		var sel: bool = k == tab
		_style_button(_tab_buttons[k], C_PRIMARY if sel else C_GRAY, C_PRIMARY_DARK if sel else C_GRAY_DARK)
	match tab:
		"tests": _load_tests()
		"recursos": _load_recursos()
		"ranking": _load_ranking()
	_scroll.scroll_vertical = 0


func _still(id: int, tab: String) -> bool:
	return is_inside_tree() and int(_aula.get("id", 0)) == id and _tab == tab


# ---------- Tests ----------
func _load_tests() -> void:
	var id := int(_aula["id"])
	_note("Cargando tests...")
	var res := await ApiService.aula_tests_async(id)
	if not _still(id, "tests"):
		return
	if res[0] != 200:
		_note(_msg(res))
		return
	var data = JSON.parse_string(res[1])
	if not (data is Array) or data.is_empty():
		_note("Tu maestro aún no ha asignado tests a esta aula.")
		return
	_clear()
	for t in data:
		_content.add_child(_test_card(t))


func _fmt(s: Variant) -> String:
	if s == null:
		return ""
	var t := str(s)
	return "%s/%s" % [t.substr(8, 2), t.substr(5, 2)] if t.length() >= 10 else ""


func _disp_text(t: Dictionary) -> String:
	var desde = t.get("disponibleDesde")
	var hasta = t.get("disponibleHasta")
	if bool(t.get("disponible", false)):
		return "Disponible" + (" hasta el " + _fmt(hasta) if hasta != null else "")
	if desde != null:
		var hoy := Time.get_datetime_string_from_system(true).substr(0, 10)
		if str(desde).substr(0, 10) > hoy:
			return "Disponible desde el " + _fmt(desde)
	return "Cerrado" + (" desde el " + _fmt(hasta) if hasta != null else "")


func _test_card(t: Dictionary) -> Control:
	var c := _card()
	var v: VBoxContainer = c[1]
	var ok := bool(t.get("disponible", false))
	v.add_child(_label(str(t["nombre"]), 17, C_TEXT))
	var intentos := int(t.get("intentos", 0))
	var info := "%d preguntas" % int(t.get("totalPreguntas", 0))
	info += "  ·  Mejor: %d%%" % int(t.get("mejorPuntaje", 0)) if intentos > 0 else "  ·  Sin intentos"
	v.add_child(_label(info, 13, C_MUTED))
	v.add_child(_label(_disp_text(t), 13, C_GREEN_DARK if ok else C_RED_DARK))
	var b := _btn("Resolver" if intentos == 0 else "Intentar de nuevo", C_GREEN if ok else C_GRAY, C_GREEN_DARK if ok else C_GRAY_DARK, 40, 14)
	b.disabled = not ok
	b.pressed.connect(_start_test.bind(t))
	v.add_child(b)
	return c[0]


func _start_test(t: Dictionary) -> void:
	GameManager.selected_test_id = int(t["testId"])
	GameManager.selected_test_title = str(t["nombre"])
	GameManager.ordered_test_ids.clear()          # sin botón «Siguiente»: es un test de clase
	GameManager.return_scene = SELF_SCENE
	GameManager.reopen_aula_id = int(_aula["id"])
	get_tree().change_scene_to_file(QUIZ_SCENE)


# ---------- Recursos ----------
func _load_recursos() -> void:
	var id := int(_aula["id"])
	_note("Cargando recursos...")
	var res := await ApiService.aula_recursos_async(id)
	if not _still(id, "recursos"):
		return
	if res[0] != 200:
		_note(_msg(res))
		return
	var data = JSON.parse_string(res[1])
	if not (data is Array) or data.is_empty():
		_note("Tu maestro aún no ha compartido recursos en esta aula.")
		return
	_clear()
	for r in data:
		var c := _card()
		var v: VBoxContainer = c[1]
		v.add_child(_label(TIPOS_RECURSO.get(int(r["tipoRecursoId"]), "Recurso"), 12, C_MUTED))
		v.add_child(_label(str(r["titulo"]), 16, C_TEXT))
		var abrir := _btn("Abrir", C_PRIMARY, C_PRIMARY_DARK, 40, 14)
		abrir.pressed.connect(_open_recurso.bind(r))
		v.add_child(abrir)
		_content.add_child(c[0])


func _open_recurso(r: Dictionary) -> void:
	var id := int(_aula["id"])
	if int(r["tipoRecursoId"]) == 1:
		# Documento: el servidor solo lo entrega a quien pertenece al aula (la cookie viaja sola)
		OS.shell_open("%sAulas/%d/recursos/%d/archivo" % [ApiService.base_url, id, int(r["id"])])
		return
	var url := str(r["referencia"])
	if url.begins_with("https://"):
		OS.shell_open(url)
	else:
		_toast_msg("Este enlace no es seguro y no se puede abrir.")


# ---------- Ranking ----------
func _load_ranking() -> void:
	var id := int(_aula["id"])
	_note("Cargando ranking...")
	var res := await ApiService.aula_ranking_async(id)
	if not _still(id, "ranking"):
		return
	if res[0] != 200:
		_note(_msg(res))
		return
	var data = JSON.parse_string(res[1])
	if not (data is Array) or data.is_empty():
		_note("Aún no hay puntajes en esta aula.")
		return
	_clear()
	for f in data:
		var mio := bool(f.get("esMio", false))
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(Color("EBF8FF") if mio else Color.WHITE, C_PRIMARY if mio else C_SOFT, 12, 10, 3))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		p.add_child(h)
		var pos := _label("#%d" % int(f["posicion"]), 16, C_PRIMARY_DARK)
		pos.custom_minimum_size.x = 44
		h.add_child(pos)
		var nombre := _label(str(f["nombre"]) + (" (tú)" if mio else ""), 15, C_TEXT)
		nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nombre)
		h.add_child(_label("%d pts" % int(f["puntaje"]), 14, C_MUTED))
		_content.add_child(p)


# ---------- Arrecife ----------
func _go_arrecife() -> void:
	GameManager.selected_aula_id = int(_aula["id"])
	get_tree().change_scene_to_file(ARRECIFE_SCENE)


# ---------- Unirse ----------
func _join_overlay() -> void:
	var le := LineEdit.new()
	le.placeholder_text = "Código de tu aula"
	le.max_length = 6
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.custom_minimum_size = Vector2(0, 48)
	le.add_theme_font_size_override("font_size", 20)
	if _mobile:        # el teclado de Godot puede fallar en móvil web: se usa el cuadro nativo del navegador
		le.editable = false
		le.gui_input.connect(_on_code_gui.bind(le))
	_choice_overlay("Escribe el código que te dio tu maestro", [
		{"texto": "Unirme", "cb": _do_join.bind(le)},
	], le)


func _on_code_gui(ev: InputEvent, le: LineEdit) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var r = JavaScriptBridge.eval("window.prompt('Escribe el código de tu aula', '')")
	if r != null:
		le.text = str(r).strip_edges().to_upper().left(6)


func _do_join(le: LineEdit) -> void:
	var code := le.text.strip_edges().to_upper()
	if code.length() < 4:
		_toast_msg("Escribe el código completo.")
		return
	_close_overlay()
	var res := await ApiService.aula_vincular_async(code)
	if not is_inside_tree():
		return
	_toast_msg(_msg(res))
	if res[0] == 200:
		_load_aulas()


# ---------- Salir ----------
func _confirm_leave() -> void:
	var nota := _label("Tu progreso y tus puntajes se conservan. Podrás volver a entrar con el mismo código.", 13, C_MUTED)
	_choice_overlay("¿Salir de «%s»?" % str(_aula.get("nombre", "esta aula")), [
		{"texto": "Sí, salir", "cb": _do_leave, "peligro": true},
	], nota)


func _do_leave() -> void:
	_close_overlay()
	var res := await ApiService.aula_salir_async(int(_aula["id"]))
	if not is_inside_tree():
		return
	_toast_msg(_msg(res))
	if res[0] == 200:
		_aula = {}
		_show_list()
		_load_aulas()


# ---------- Ventana de opciones ----------
func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _choice_overlay(titulo: String, opciones: Array, extra: Control = null) -> void:
	_close_overlay()
	_overlay = Control.new()
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	_overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var centro := CenterContainer.new()
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(centro)
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(290, 0)
	panel.add_theme_stylebox_override("panel", _box(Color("F8FAFC"), C_SOFT, 16, 16, 2))
	centro.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label(titulo, 16, C_TEXT))
	if extra != null:
		v.add_child(extra)
	for o in opciones:
		var peligro := bool(o.get("peligro", false))
		var b := _btn(str(o["texto"]), C_RED if peligro else C_PRIMARY, C_RED_DARK if peligro else C_PRIMARY_DARK, 44)
		b.pressed.connect(o["cb"])
		v.add_child(b)
	var cancelar := _btn("Cancelar", C_GRAY, C_GRAY_DARK, 44)
	cancelar.pressed.connect(_close_overlay)
	v.add_child(cancelar)


# ---------- Aviso breve ----------
func _toast_msg(texto: String) -> void:
	if texto.is_empty():
		return
	if _toast == null:
		_toast = PanelContainer.new()
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast.add_theme_stylebox_override("panel", _box(Color("00182E"), Color("0F3556"), 12, 10, 2))
		add_child(_toast)
		_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_toast.offset_left = 16
		_toast.offset_right = -16
		_toast.offset_top = 72
		_toast_label = _label("", 14, Color.WHITE)
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.add_child(_toast_label)
	_toast_label.text = texto
	_toast.show()
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree() and _toast_label.text == texto:
		_toast.hide()
