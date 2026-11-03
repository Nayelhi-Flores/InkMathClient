extends Control
## Modo "Pizzería Marina" (RF-13): reparto equitativo con fracciones.
## Verificación: el cliente recibió lo pedido si  porciones_recibidas / total_porciones == num / den
## (se comparan por producto cruzado, así 2/4 y 1/2 cuentan como iguales).

@export var menu_scene: String = "res://scenes/menu_inicio.tscn"
@export_range(0.4, 1.0) var column_ratio := 0.7
@export var banner_good: Texture2D
@export var banner_bad: Texture2D

const CUT_OPTIONS := [2, 3, 4, 6, 8]
const COLORS := [Color("38bdf8"), Color("f472b6"), Color("4ade80"), Color("fbbf24")]
# cada cliente: [nombre, numerador, denominador]
const LEVELS := [
	{"clientes": [["Delfín", 1, 2], ["Ballena", 1, 2]]},
	{"clientes": [["Delfín", 1, 4], ["Ballena", 1, 4], ["Tortuga", 1, 4], ["Pulpo", 1, 4]]},
	{"clientes": [["Delfín", 1, 3], ["Ballena", 1, 3], ["Tortuga", 1, 3]]},
	{"clientes": [["Delfín", 1, 2], ["Ballena", 1, 4], ["Tortuga", 1, 4]]},
	{"clientes": [["Delfín", 1, 2], ["Ballena", 1, 3], ["Tortuga", 1, 6]]},
]
const STARS_PASS := 0.6

var _level := 0
var _customers: Array = []
var _n := 0                      # porciones en que se cortó (0 = entera)
var _owner: Array[int] = []      # cliente dueño de cada porción (-1 = sin asignar)
var _active := -1                # cliente seleccionado
var _errors := 0
var _level_done := false
var _stars_total := 0
var _first_try := 0
var _cards: Array[Button] = []
var _ticket := ""
var _all_attempts: Array = []   # por nivel: [{partes, duenos}, ...]
var _level_log: Array = []

var _paused := false
var _pause: PauseOverlay

@onready var column: Control = _fn("Column")
@onready var level_label: Label = _fn("LevelLabel")
@onready var back_btn: Button = _fn("BackBtn")
@onready var pause_btn: Button = _fn("PauseBtn")
@onready var order_label: Label = _fn("OrderLabel")
@onready var pizza_view: Control = _fn("PizzaView")
@onready var cuts_box: HBoxContainer = _fn("CutsBox")
@onready var customers_box: HFlowContainer = _fn("CustomersBox")
@onready var feedback_label: Label = _fn("FeedbackLabel")
@onready var serve_btn: Button = _fn("ServeBtn")
@onready var final_modal: Control = _fn("FeedbackPanel")
@onready var modal_title: Label = _fn("LabelStatusTitle")
@onready var modal_accuracy: Label = _fn("LabelAccuracy2")
@onready var modal_coins: Label = _fn("LabelCoins")
@onready var modal_banner: TextureRect = _fn("BannerIllustration")
@onready var btn_home: Button = _fn("BtnHome")
@onready var btn_retry: Button = _fn("BtnRetry")
@onready var btn_next: Button = _fn("BtnNext")


func _fn(path: String) -> Node:
	var n := get_node_or_null(path)
	if n == null:
		n = find_child(path.get_file(), true, false)
	if n == null:
		push_error("No se encontró el nodo '%s' (revisa nombre/ruta)." % path)
	return n


func _ready() -> void:
	_pause = PauseOverlay.new()
	add_child(_pause)
	_pause.resumed.connect(func(): _paused = false)
	_pause.exit_requested.connect(_go_menu)
	pause_btn.pressed.connect(_abrir_pausa)

	serve_btn.pressed.connect(_on_serve_pressed)
	back_btn.pressed.connect(_go_menu)
	btn_home.pressed.connect(_go_menu)
	btn_retry.pressed.connect(func(): get_tree().reload_current_scene())
	btn_next.hide()
	final_modal.hide()

	pizza_view.draw.connect(_draw_pizza)
	pizza_view.resized.connect(pizza_view.queue_redraw)
	pizza_view.gui_input.connect(_on_pizza_input)
	get_viewport().size_changed.connect(_apply_column)
	_apply_column()

	AudioManager.play_music(-14.0)
	_iniciar_sesion()


func _apply_column() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		return
	var w := minf(vp.x, vp.y * column_ratio)
	var m := (vp.x - w) / 2.0 / vp.x
	column.anchor_left = m
	column.anchor_right = 1.0 - m
	column.offset_left = 0
	column.offset_right = 0


# ---------- SESIÓN ----------
func _iniciar_sesion() -> void:
	serve_btn.disabled = true
	_set_feedback("Preparando la pizzería...")
	var res := await ApiService.iniciar_juego_async("fracciones")
	if not is_inside_tree():
		return
	var data = JSON.parse_string(res[1]) if res[0] == 200 else null
	if data is Dictionary and not str(data.get("intentoToken", "")).is_empty():
		_ticket = str(data["intentoToken"])
		_all_attempts.clear()
		_level = 0
		_stars_total = 0
		_first_try = 0
		_start_level()
	else:
		_set_feedback("No se pudo iniciar el juego. Revisa tu conexión.", -1)
		serve_btn.text = "Reintentar"
		serve_btn.disabled = false


# ---------- NIVELES ----------
func _start_level() -> void:
	_level_log = []
	_customers = LEVELS[_level]["clientes"]
	_n = 0
	_owner = []
	_active = -1
	_errors = 0
	_level_done = false

	level_label.text = "Pizza %d/%d" % [_level + 1, LEVELS.size()]
	var pedidos: Array[String] = []
	for c in _customers:
		pedidos.append("%s quiere %d/%d" % [c[0], c[1], c[2]])
	order_label.text = "Reparte la pizza en partes iguales.\n" + ", ".join(pedidos) + "."

	_clear(cuts_box)
	var group := ButtonGroup.new()
	for n in CUT_OPTIONS:
		var b := Button.new()
		b.text = "%d" % n
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(44, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_cut_selected.bind(n))
		cuts_box.add_child(b)

	_clear(customers_box)
	_cards.clear()
	var card_group := ButtonGroup.new()
	for i in _customers.size():
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = card_group
		card.custom_minimum_size = Vector2(96, 60)
		card.self_modulate = COLORS[i]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(_on_card_pressed.bind(i))
		customers_box.add_child(card)
		_cards.append(card)
	_refresh_cards()

	serve_btn.text = "Servir"
	serve_btn.disabled = true
	_set_feedback("Primero corta la pizza en partes iguales.")
	pizza_view.queue_redraw()


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _on_cut_selected(n: int) -> void:
	if _level_done or _paused:
		return
	_n = n
	_owner = []
	_owner.resize(n)
	_owner.fill(-1)
	serve_btn.disabled = false
	_set_feedback("Elige un cliente y toca las porciones que le das.")
	_refresh_cards()
	pizza_view.queue_redraw()


func _on_card_pressed(i: int) -> void:
	_active = i


func _count(i: int) -> int:
	var k := 0
	for o in _owner:
		if o == i:
			k += 1
	return k


func _refresh_cards() -> void:
	for i in _cards.size():
		var c = _customers[i]
		var got := _count(i)
		var tiene := "0" if _n == 0 or got == 0 else "%d/%d" % [got, _n]
		_cards[i].text = "%s\nQuiere %d/%d\nTiene %s" % [c[0], c[1], c[2], tiene]
		_cards[i].modulate = Color.WHITE


# ---------- TOQUE SOBRE LA PIZZA ----------
func _radius() -> float:
	return maxf(20.0, minf(pizza_view.size.x, pizza_view.size.y) / 2.0 - 6.0)


func _on_pizza_input(ev: InputEvent) -> void:
	if _paused or _level_done or _n == 0:
		return
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _active == -1:
		_set_feedback("Elige primero a qué cliente le das la porción.")
		return
	var d := mb.position - pizza_view.size / 2.0
	if d.length() > _radius():
		return
	var a := fposmod(atan2(d.y, d.x) + PI / 2.0, TAU)    # 0 = arriba, sentido horario
	var idx := int(a / (TAU / _n)) % _n
	_owner[idx] = -1 if _owner[idx] == _active else _active
	_refresh_cards()
	pizza_view.queue_redraw()


# ---------- VERIFICACIÓN ----------
func _on_serve_pressed() -> void:
	if _paused:
		return
	if _ticket.is_empty():
		_iniciar_sesion()
		return
	if _level_done:
		_next_level()
		return
	if _n == 0:
		return
	_level_log.append({"partes": _n, "duenos": _owner.duplicate()})

	var wrong: Array[String] = []
	var asignadas := 0
	for i in _customers.size():
		var c = _customers[i]
		var num: int = c[1]
		var den: int = c[2]
		var got := _count(i)
		asignadas += got
		var ok := got * den == num * _n
		_cards[i].modulate = Color(0.75, 1.0, 0.75) if ok else Color(1.0, 0.65, 0.65)
		if not ok:
			wrong.append("%s pidió %d/%d y recibió %s" % [c[0], num, den, _frac_text(got, _n)])

	if wrong.is_empty():
		_level_done = true
		_all_attempts.append(_level_log)
		var stars := 3 - mini(_errors, 2)
		_stars_total += stars
		if _errors == 0:
			_first_try += 1
		_set_feedback("¡Reparto justo! " + _equivalence_note(), 1)
		serve_btn.text = "Siguiente" if _level < LEVELS.size() - 1 else "Ver resultado"
	else:
		_errors += 1
		var extra := ""
		if asignadas < _n:
			extra = "\nQuedan %d porciones sin repartir." % (_n - asignadas)
		_set_feedback("Revisa:\n" + "\n".join(wrong) + extra, -1)


@warning_ignore("integer_division")
func _frac_text(got: int, n: int) -> String:
	if got == 0:
		return "0"
	var g := _gcd(got, n)
	if g > 1:
		return "%d/%d (= %d/%d)" % [got, n, got / g, n / g]
	return "%d/%d" % [got, n]


func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a


@warning_ignore("integer_division")
func _equivalence_note() -> String:
	for i in _customers.size():
		var c = _customers[i]
		var den: int = c[2]
		if _n != den and _n % den == 0:
			var factor: int = _n / den
			return "Recuerda: %d/%d = %d/%d." % [c[1], den, int(c[1]) * factor, _n]
	return ""


func _next_level() -> void:
	_level += 1
	if _level >= LEVELS.size():
		_finish()
	else:
		_start_level()


func _finish() -> void:
	pause_btn.hide()
	serve_btn.disabled = true
	var res := await ApiService.finalizar_juego_async("fracciones", _ticket, _all_attempts)
	if not is_inside_tree():
		return

	var ok := false
	var aciertos := 0
	var total := LEVELS.size()
	var estrellas := _stars_total
	var monedas := 0
	if res[0] == 200:
		var r = JSON.parse_string(res[1])
		if r is Dictionary:
			ok = true
			aciertos = int(r.get("aciertos", 0))
			total = int(r.get("total", total))
			estrellas = int(r.get("estrellas", 0))
			monedas = int(r.get("monedasGanadas", 0))
			GameManager.set_monedas(int(r.get("nuevoSaldoMonedas", GameManager.monedas)))

	var positive := ok and estrellas >= int(ceil(total * 3 * STARS_PASS))
	if ok:
		modal_title.text = "¡Buen reparto!" if positive else "¡Sigue practicando!"
		modal_accuracy.text = "Pizzas: %d/%d · Estrellas: %d/%d" % [aciertos, total, estrellas, total * 3]
		modal_coins.text = "Monedas: +%d" % monedas
	else:
		modal_title.text = "No se pudo guardar tu resultado"
		modal_accuracy.text = "Revisa tu conexión"
		modal_coins.text = "Inténtalo de nuevo"
	var tex := banner_good if positive else banner_bad
	if tex != null and modal_banner != null:
		modal_banner.texture = tex
	if ok:
		AudioManager.play_result(positive)
	final_modal.show()


func _set_feedback(msg: String, state: int = 0) -> void:
	feedback_label.text = msg
	var col := Color("2B3A4A")
	if state == 1:
		col = Color("047857")
	elif state == -1:
		col = Color("b91c1c")
	feedback_label.add_theme_color_override("font_color", col)


# ---------- DIBUJO DE LA PIZZA ----------
func _draw_pizza() -> void:
	var c := pizza_view.size / 2.0
	var r := _radius()
	var crust := Color("c98a3b")
	var dough := Color("f6c85f")
	var font := pizza_view.get_theme_default_font()

	pizza_view.draw_circle(c, r, crust)
	if _n == 0:
		pizza_view.draw_circle(c, r - 8.0, dough)
		return

	var step := TAU / _n
	var seg := 14
	for i in _n:
		var a0 := -PI / 2.0 + i * step
		var a1 := a0 + step
		var col: Color = dough if _owner[i] == -1 else COLORS[_owner[i]]
		var pts := PackedVector2Array([c])
		for k in range(seg + 1):
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(k) / seg)) * (r - 8.0))
		pizza_view.draw_colored_polygon(pts, col)
		pizza_view.draw_line(c, c + Vector2.from_angle(a0) * (r - 8.0), Color("8a4b14"), 2.0, true)
		if _owner[i] != -1:
			var mid := (a0 + a1) / 2.0
			var p := c + Vector2.from_angle(mid) * (r * 0.55)
			var ini := str(_customers[_owner[i]][0]).left(1)
			pizza_view.draw_string(font, p + Vector2(-6, 6), ini, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("0f172a"))


# ---------- PAUSA / NAVEGACIÓN ----------
func _abrir_pausa() -> void:
	if _paused or final_modal.visible:
		return
	_paused = true
	_pause.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_abrir_pausa()


func _go_menu() -> void:
	get_tree().change_scene_to_file(menu_scene)
