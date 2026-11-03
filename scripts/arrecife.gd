extends Control
## Arrecife de Ayuda: preguntas y respuestas entre compañeros del aula, con voto "útil".
## Preprimaria (4 a 6 años): solo frases y emojis fijos que entrega el servidor.

@export var column_ratio := 0.7

const REFRESH_SECONDS := 15.0
const C_TEXT := Color("2B3A4A")
const C_MUTED := Color("8292A1")
const C_PRIMARY := Color("0984C6")
const C_PRIMARY_DARK := Color("076DA4")
const C_GREEN := Color("10B981")
const C_GREEN_DARK := Color("047857")
const C_RED := Color("F87171")
const C_RED_DARK := Color("DC2626")
const C_SOFT := Color("E2E8F0")

var _perfil: Dictionary = {}
var _aula_id := 0
var _mensajes: Array = []
var _thread_id := 0          # 0 = lista de preguntas; >0 = hilo abierto
var _busy := false
var _mobile := false
var _overlay: Control
var _toast: PanelContainer
var _toast_label: Label
var _timer: Timer

@onready var _column: Control = _fn("Column")
@onready var _aula_selector: OptionButton = _fn("AulaSelector")
@onready var _thread_header: Control = _fn("ThreadHeader")
@onready var _btn_back_thread: Button = _fn("BtnBackThread")
@onready var _thread_title: Label = _fn("ThreadTitle")
@onready var _scroll: ScrollContainer = _fn("Scroll")
@onready var _messages: VBoxContainer = _fn("Messages")
@onready var _composer: Control = _fn("Composer")
@onready var _mode_label: Label = _fn("ModeLabel")
@onready var _text_row: Control = _fn("TextRow")
@onready var _input: LineEdit = _fn("MessageInput")
@onready var _send_btn: Button = _fn("SendBtn")
@onready var _quick_box: HFlowContainer = _fn("QuickBox")


func _fn(nombre: String) -> Node:
	var n := find_child(nombre, true, false)
	if n == null:
		push_error("No se encontró el nodo '%s' (revisa el nombre)." % nombre)
	return n


func _ready() -> void:
	AudioManager.stop_music()

	_limitar_ancho(_column)
	get_viewport().size_changed.connect(func(): _limitar_ancho(_column))

	_aula_selector.item_selected.connect(_on_aula_selected)
	_btn_back_thread.pressed.connect(_close_thread)
	_send_btn.pressed.connect(_on_send_pressed)
	_input.text_submitted.connect(func(_t): _on_send_pressed())
	_input.max_length = 250
	_thread_header.hide()

	# En móvil web el teclado de Godot puede fallar: se usa el cuadro de texto nativo del navegador
	_mobile = OS.has_feature("web") and bool(JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches"))
	if _mobile:
		_input.editable = false
		_input.placeholder_text = "Toca para escribir..."
		_input.gui_input.connect(_on_input_gui)

	_timer = Timer.new()
	_timer.wait_time = REFRESH_SECONDS
	_timer.timeout.connect(_load_messages)
	add_child(_timer)

	_load_perfil()


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


func _btn(texto: String, bg: Color, dark: Color, altura: float = 40.0, fuente: int = 14) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, altura)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", fuente)
	for st in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _box(bg, dark, 10, 8, 4))
	b.add_theme_stylebox_override("pressed", _box(bg, dark, 10, 8, 1))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	return b


func _label(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l


# ---------- Carga ----------
func _msg(res: Array) -> String:
	var d = JSON.parse_string(res[1])
	if d is Dictionary and d.has("mensaje"):
		return str(d["mensaje"])
	return "No se pudo completar la acción." if res[0] != 0 else "Sin conexión."


func _clear_messages() -> void:
	for c in _messages.get_children():
		_messages.remove_child(c)
		c.queue_free()


func _empty(texto: String) -> void:
	_clear_messages()
	_composer.hide()
	_messages.add_child(_label(texto, 15, Color.WHITE))


func _load_perfil() -> void:
	_clear_messages()
	_messages.add_child(_label("Cargando el Arrecife...", 15, Color.WHITE))
	var res := await ApiService.arrecife_perfil_async()
	if not is_inside_tree():
		return
	var data = JSON.parse_string(res[1]) if res[0] == 200 else null
	if not (data is Dictionary):
		_empty("No se pudo cargar el Arrecife. Revisa tu conexión.")
		return
	_perfil = data

	var aulas: Array = data.get("aulas", [])
	if aulas.is_empty():
		_aula_selector.hide()
		_empty("Todavía no perteneces a ninguna aula. Únete a una desde la pestaña Aulas.")
		return

	_aula_selector.clear()
	var guardada = GameManager.get("selected_aula_id")
	var sel := 0
	for i in aulas.size():
		_aula_selector.add_item(str(aulas[i]["nombre"]))
		_aula_selector.set_item_metadata(i, int(aulas[i]["id"]))
		if guardada != null and int(guardada) == int(aulas[i]["id"]):
			sel = i
	_aula_selector.select(sel)
	_aula_selector.show()
	_aula_id = int(_aula_selector.get_item_metadata(sel))

	_build_quick()
	_composer.show()
	_apply_composer_mode()
	_load_messages()
	_timer.start()


func _on_aula_selected(idx: int) -> void:
	_aula_id = int(_aula_selector.get_item_metadata(idx))
	GameManager.set("selected_aula_id", _aula_id)
	_thread_id = 0
	_thread_header.hide()
	_apply_composer_mode()
	_load_messages()


func _load_messages() -> void:
	if _aula_id <= 0 or _overlay != null:
		return
	var res := await ApiService.arrecife_mensajes_async(_aula_id)
	if not is_inside_tree():
		return
	if res[0] == 200:
		var data = JSON.parse_string(res[1])
		if data is Array:
			_mensajes = data
			_render()
	elif res[0] != 0:
		_toast_msg(_msg(res))


# ---------- Dibujo ----------
func _render() -> void:
	var keep := _scroll.scroll_vertical
	_clear_messages()

	var raices: Array = []
	var respuestas: Dictionary = {}
	for m in _mensajes:
		var pid = m.get("mensajePadreId")
		if pid == null:
			raices.append(m)
		else:
			var k := int(pid)
			if not respuestas.has(k):
				respuestas[k] = []
			respuestas[k].append(m)
	raices.sort_custom(func(a, b): return str(a["enviadoEn"]) > str(b["enviadoEn"]))

	if _thread_id == 0:
		_render_lista(raices, respuestas)
	else:
		_render_hilo(raices, respuestas)
	_restore_scroll.call_deferred(keep)


func _restore_scroll(valor: int) -> void:
	await get_tree().process_frame
	if is_inside_tree():
		_scroll.scroll_vertical = valor


func _render_lista(raices: Array, respuestas: Dictionary) -> void:
	if raices.is_empty():
		_messages.add_child(_label("Aún no hay preguntas. ¡Haz la primera!", 15, Color.WHITE))
		return
	for m in raices:
		var id := int(m["id"])
		var n: int = respuestas.get(id, []).size()
		var card := _card(m, false)
		var abrir := _btn("Ver respuestas (%d)" % n if n > 0 else "Responder", C_PRIMARY, C_PRIMARY_DARK, 36, 13)
		abrir.pressed.connect(_open_thread.bind(id))
		card.get_child(0).add_child(abrir)
		_messages.add_child(card)


func _render_hilo(raices: Array, respuestas: Dictionary) -> void:
	var raiz = null
	for m in raices:
		if int(m["id"]) == _thread_id:
			raiz = m
	if raiz == null:      # la pregunta ya no existe (borrada o reportada)
		_close_thread()
		return

	_thread_title.text = "Pregunta de %s" % str(raiz["nombreEstudiante"])
	_messages.add_child(_card(raiz, false, true))

	var lista: Array = respuestas.get(_thread_id, [])
	lista.sort_custom(func(a, b):
		if int(a["votosUtiles"]) != int(b["votosUtiles"]):
			return int(a["votosUtiles"]) > int(b["votosUtiles"])
		return str(a["enviadoEn"]) < str(b["enviadoEn"]))

	if lista.is_empty():
		_messages.add_child(_label("Todavía nadie respondió. ¡Sé el primero!", 14, Color.WHITE))
		return
	_messages.add_child(_label("Respuestas (%d)" % lista.size(), 14, Color.WHITE))
	var mejor := int(lista[0]["votosUtiles"])
	for r in lista:
		_messages.add_child(_card(r, true, false, mejor > 0 and int(r["votosUtiles"]) == mejor))


# Tarjeta de un mensaje. El primer hijo es el VBox donde se agregan los botones.
func _card(m: Dictionary, es_respuesta: bool, resaltar: bool = false, mejor: bool = false) -> PanelContainer:
	var es_mio := bool(m.get("esMio", false))
	var bg := Color("EBF8FF") if es_mio else Color.WHITE
	var borde := C_GREEN if mejor else C_SOFT
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(bg, borde, 14, 12, 4 if (mejor or resaltar) else 2))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	var nombre := str(m.get("nombreEstudiante", "Usuario")) + (" (tú)" if es_mio else "")
	v.add_child(_label(nombre + ("  ·  Respuesta más útil" if mejor else ""), 12, C_GREEN_DARK if mejor else C_MUTED))
	v.add_child(_label(str(m.get("contenido", "")), 20 if bool(m.get("esEmoji", false)) else 15, C_TEXT))

	if es_respuesta:
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 6)
		var voto := _btn("Útil (%d)" % int(m["votosUtiles"]),
				C_GREEN if bool(m.get("yaVote", false)) else Color("94A3B8"),
				C_GREEN_DARK if bool(m.get("yaVote", false)) else Color("64748B"), 36, 13)
		voto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		voto.disabled = es_mio                      # el servidor tampoco deja votar el propio mensaje
		voto.pressed.connect(_on_vote.bind(int(m["id"])))
		fila.add_child(voto)
		fila.add_child(_accion_secundaria(m, es_mio))
		v.add_child(fila)
	elif resaltar:
		v.add_child(_accion_secundaria(m, es_mio))
	return card


func _accion_secundaria(m: Dictionary, es_mio: bool) -> Button:
	var b := _btn("Borrar" if es_mio else "Reportar", C_RED, C_RED_DARK, 36, 13)
	if es_mio:
		b.pressed.connect(_confirm_delete.bind(int(m["id"])))
	else:
		b.pressed.connect(_choose_report.bind(int(m["id"])))
	return b


# ---------- Hilos ----------
func _open_thread(id: int) -> void:
	_thread_id = id
	_thread_header.show()
	_apply_composer_mode()
	_render()
	_scroll.scroll_vertical = 0


func _close_thread() -> void:
	_thread_id = 0
	_thread_header.hide()
	_apply_composer_mode()
	_render()


# ---------- Redactar ----------
func _build_quick() -> void:
	for c in _quick_box.get_children():
		_quick_box.remove_child(c)
		c.queue_free()
	if not bool(_perfil.get("esPreprimaria", false)):
		return
	for f in _perfil.get("frases", []):
		var b := _btn(str(f), C_PRIMARY, C_PRIMARY_DARK, 44, 14)
		b.pressed.connect(_enviar.bind(str(f), false))
		_quick_box.add_child(b)
	for e in _perfil.get("emojis", []):
		var b2 := _btn(str(e), Color("F59E0B"), Color("D97706"), 44, 18)
		b2.custom_minimum_size.x = 52
		b2.pressed.connect(_enviar.bind(str(e), true))
		_quick_box.add_child(b2)


func _apply_composer_mode() -> void:
	var pre := bool(_perfil.get("esPreprimaria", false))
	_text_row.visible = not pre
	_quick_box.visible = pre
	_mode_label.text = "Escribe tu respuesta" if _thread_id > 0 else "Haz una pregunta a tu clase"


func _on_input_gui(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var r = JavaScriptBridge.eval("window.prompt('Escribe tu mensaje (máximo 250 letras)', '')")
	if r != null:
		_input.text = str(r).strip_edges().left(250)


func _on_send_pressed() -> void:
	var txt := _input.text.strip_edges()
	if txt.is_empty():
		return
	_enviar(txt, false)


func _enviar(contenido: String, es_emoji: bool) -> void:
	if _busy or _aula_id <= 0:
		return
	_busy = true
	_send_btn.disabled = true
	var res := await ApiService.arrecife_enviar_async(_aula_id, contenido, es_emoji, _thread_id)
	_busy = false
	if not is_inside_tree():
		return
	_send_btn.disabled = false
	if res[0] == 200:
		_input.text = ""
		_load_messages()
	else:
		_toast_msg(_msg(res))


# ---------- Votar, reportar, borrar ----------
func _on_vote(id: int) -> void:
	if _busy:
		return
	_busy = true
	var res := await ApiService.arrecife_votar_async(id)
	_busy = false
	if not is_inside_tree():
		return
	_toast_msg(_msg(res))
	_load_messages()


func _choose_report(id: int) -> void:
	_choice_overlay("¿Por qué reportas este mensaje?", [
		{"texto": "Lenguaje inapropiado", "cb": _do_report.bind(id, "Lenguaje inapropiado")},
		{"texto": "Comparte datos personales", "cb": _do_report.bind(id, "Comparte datos personales")},
		{"texto": "Otro motivo", "cb": _do_report.bind(id, "Otro motivo")},
	])


func _do_report(id: int, motivo: String) -> void:
	_close_overlay()
	var res := await ApiService.arrecife_reportar_async(id, motivo)
	if not is_inside_tree():
		return
	_toast_msg(_msg(res))
	_load_messages()


func _confirm_delete(id: int) -> void:
	_choice_overlay("¿Borrar tu mensaje?", [
		{"texto": "Sí, borrar", "cb": _do_delete.bind(id), "peligro": true},
	])


func _do_delete(id: int) -> void:
	_close_overlay()
	var res := await ApiService.arrecife_eliminar_async(id)
	if not is_inside_tree():
		return
	_toast_msg(_msg(res))
	_load_messages()


# ---------- Ventana de opciones ----------
func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _choice_overlay(titulo: String, opciones: Array) -> void:
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
	panel.custom_minimum_size = Vector2(280, 0)
	panel.add_theme_stylebox_override("panel", _box(Color("F8FAFC"), C_SOFT, 16, 16, 2))
	centro.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label(titulo, 16, C_TEXT))
	for o in opciones:
		var peligro := bool(o.get("peligro", false))
		var b := _btn(str(o["texto"]), C_RED if peligro else C_PRIMARY, C_RED_DARK if peligro else C_PRIMARY_DARK, 44)
		b.pressed.connect(o["cb"])
		v.add_child(b)
	var cancelar := _btn("Cancelar", Color("94A3B8"), Color("64748B"), 44)
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
