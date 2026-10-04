extends Control

const TOTAL_CLIENTES := 5
@export var CLIENT_TIME_LIMIT := 20.0

@export var menu_scene: String = "res://scenes/mapa_niveles.tscn"
@export var next_scene: String = ""
@export var coins_per_correct := 10
@export var banner_good: Texture2D
@export var banner_bad: Texture2D
@export var item_textures: Array[Texture2D]
## Orden: BALLENA, DELFIN, TORTUGA, TRALALERO
@export var customer_sheets: Array[Texture2D]
@export var final_customer_index := 3
@export var sheet_hframes := 4
@export var sheet_vframes := 1
## Ancho máximo de la columna de juego = alto de pantalla * este valor
@export_range(0.4, 1.0) var column_ratio := 0.7

var catalog := [
	{"name": "Estrella", "price": 5},
	{"name": "Ancla", "price": 8},
	{"name": "Botella", "price": 6},
	{"name": "Concha Lunar", "price": 7},
	{"name": "Concha Cono", "price": 9},
	{"name": "Vieira", "price": 4},
	{"name": "Concha de Almeja", "price": 10},
	{"name": "Almeja", "price": 11},
	{"name": "Algas", "price": 3},
]
var unlock_order := [1, 2, 3, 0, 5, 8, 4, 6, 7]

var current := 0
var correct := 0
var solved := false
var paid := 0
var order: Dictionary = {}
var _bag: Array = []
var _last_idx := -1
var _shelf_nodes: Array = []
var _cust_home := Vector2.ZERO
var _moving := false
var _locked := false

var _time_remaining: float = CLIENT_TIME_LIMIT
var _is_timer_running: bool = false
var _tail_node: Node2D = null

@onready var keypad: GridContainer = _fn("Keypad")
@onready var column: Control = _fn("Column")
@onready var customer: Sprite2D = _fn("Customer")
@onready var customer_slot: Control = _fn("CustomerSlot")
@onready var shelf: HBoxContainer = _fn("Shelf")
@onready var order_list: HBoxContainer = _fn("OrderList")
@onready var order_bubble: Control = _fn("OrderBubble")
@onready var paid_label: Label = _fn("PaidLabel")
@onready var change_input: LineEdit = _fn("ChangeInput")
@onready var check_btn: Button = _fn("CheckBtn")
@onready var feedback: Label = _fn("Feedback")
@onready var score_label: Label = _fn("ScoreLabel")
@onready var timer_label: Label = _fn("LabelTimer")
@onready var calc_panel: Control = _fn("CalcPanel")
@onready var anim_timer: Timer = _fn("AnimTimer")
@onready var back_btn: Button = _fn("BackBtn")
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
	randomize()
	anim_timer.wait_time = 0.16
	if item_textures.size() < catalog.size() or customer_sheets.is_empty():
		push_error("Asigna items1..items9 y los clientes en el Inspector del nodo raíz.")
		return
	final_customer_index = mini(final_customer_index, customer_sheets.size() - 1)

	_build_shelf()
	_create_speech_tail()
	_build_keypad()
	var mobile := _is_mobile()
	keypad.visible = mobile
	change_input.virtual_keyboard_enabled = not mobile  # en móvil se usa el keypad propio
	
	check_btn.pressed.connect(_on_check_pressed)
	change_input.text_submitted.connect(func(_t): _on_check_pressed())
	change_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file(menu_scene))
	btn_home.pressed.connect(func(): get_tree().change_scene_to_file(menu_scene))
	btn_retry.pressed.connect(func(): get_tree().reload_current_scene())
	if next_scene.is_empty():
		btn_next.hide()
	else:
		btn_next.pressed.connect(func(): get_tree().change_scene_to_file(next_scene))
	anim_timer.timeout.connect(func(): customer.frame = (customer.frame + 1) % sheet_hframes)

	get_viewport().size_changed.connect(_apply_column)
	customer_slot.resized.connect(_layout)
	order_bubble.resized.connect(func(): if _tail_node: _tail_node.queue_redraw())
	final_modal.hide()

	_apply_column()
	await get_tree().process_frame   # deja que los contenedores calculen tamaños
	_layout()
	_load_customer()


func _process(delta: float) -> void:
	if not _is_timer_running:
		return
	_time_remaining -= delta
	if timer_label != null:
		var total_seconds: int = int(maxf(0.0, ceilf(_time_remaining)))
		timer_label.text = "%02d:%02d" % [total_seconds / 60.0, total_seconds % 60]
	if _time_remaining <= 0.0:
		_is_timer_running = false
		_on_time_out()


# ---------- LAYOUT ----------
# Columna central: ancho = min(pantalla, alto * column_ratio). Solo se tocan anclas (sin warnings).
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


func _layout() -> void:
	if customer == null or customer.texture == null or customer_slot.size.x <= 0.0:
		return
	var fw := customer.texture.get_width() / float(sheet_hframes)
	var fh := customer.texture.get_height() / float(sheet_vframes)
	var sc := minf(customer_slot.size.x / fw, customer_slot.size.y / fh)
	customer.scale = Vector2.ONE * sc
	_cust_home = Vector2(
		customer_slot.global_position.x + customer_slot.size.x / 2.0,
		customer_slot.global_position.y + customer_slot.size.y - fh * sc / 2.0)
	if not _moving:
		customer.global_position = _cust_home


# ---------- PUNTERO DE LA BURBUJA ----------
func _create_speech_tail() -> void:
	if order_bubble == null:
		return
	_tail_node = Node2D.new()
	_tail_node.name = "BubbleTail"
	order_bubble.add_child(_tail_node)
	_tail_node.draw.connect(_draw_tail)


func _draw_tail() -> void:
	var c := Color("03182b")
	var w := order_bubble.size.x
	var h := order_bubble.size.y
	_tail_node.draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.55, h), Vector2(w * 0.65, h), Vector2(w * 0.58, h + 14)]), c)


# ---------- ESTANTE ----------
func _build_shelf() -> void:
	for t in item_textures:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 11)
		v.add_child(r)
		v.add_child(l)
		shelf.add_child(v)
		_shelf_nodes.append({"sprite": r, "label": l})


func _refresh_shelf() -> void:
	var unlocked := unlock_order.slice(0, 2 + current)
	for i in _shelf_nodes.size():
		var open: bool = i in unlocked
		var node = _shelf_nodes[i]
		node.sprite.modulate = Color.WHITE if open else Color(0, 0, 0, 0.35)
		node.label.text = ("Q%d" % catalog[i].price) if open else "?"


# ---------- CLIENTE Y PEDIDO ----------
func _next_sheet(is_last: bool) -> Texture2D:
	if is_last:
		return customer_sheets[final_customer_index]
	if _bag.is_empty():
		for i in customer_sheets.size():
			if i != final_customer_index:
				_bag.append(i)
		_bag.shuffle()
		if _bag.size() > 1 and _bag.back() == _last_idx:
			_bag.reverse()
	_last_idx = _bag.pop_back()
	return customer_sheets[_last_idx]


func _make_order(level: int) -> Dictionary:
	var pool := unlock_order.slice(0, 2 + level)
	pool.shuffle()
	var kinds := mini(randi_range(2, 3), pool.size())
	var lines: Array = []
	for i in kinds:
		lines.append({"id": pool[i], "qty": randi_range(1, 3)})
	return {"lines": lines}


func _total(o: Dictionary) -> int:
	var t := 0
	for l in o.lines:
		t += l.qty * catalog[l.id].price
	return t


func _load_customer() -> void:
	_is_timer_running = false
	_locked = false
	_time_remaining = CLIENT_TIME_LIMIT

	order = _make_order(current)
	paid = _total(order) + randi_range(1, 8)
	solved = false

	customer.texture = _next_sheet(current == TOTAL_CLIENTES - 1)
	customer.hframes = sheet_hframes
	customer.vframes = sheet_vframes
	customer.frame = 0

	paid_label.text = "Pago recibido: %d" % paid
	change_input.text = ""
	change_input.editable = true
	check_btn.text = "Validar"
	_set_feedback("Piensa el vuelto y escribe solo esa cantidad.", 0)
	_update_score()
	_refresh_shelf()
	_moving = true
	_layout()
	_show_order()
	_customer_enter()


func _show_order() -> void:
	for c in order_list.get_children():
		c.queue_free()
	for l in order.lines:
		var icon := TextureRect.new()
		icon.texture = item_textures[l.id]
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var qty := Label.new()
		qty.text = "x%d" % l.qty
		qty.add_theme_font_size_override("font_size", 16)
		order_list.add_child(icon)
		order_list.add_child(qty)


func _customer_enter() -> void:
	order_bubble.modulate.a = 0.0
	customer.global_position = Vector2(-customer_slot.size.x, _cust_home.y)
	var tw := create_tween()
	tw.tween_property(customer, "global_position:x", _cust_home.x, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(order_bubble, "modulate:a", 1.0, 0.25)
	tw.finished.connect(func():
		_moving = false
		_is_timer_running = true)
	anim_timer.start()


func _customer_leave() -> Tween:
	_is_timer_running = false
	_moving = true
	var tw := create_tween()
	tw.tween_property(order_bubble, "modulate:a", 0.0, 0.15)
	tw.tween_property(customer, "global_position:x",
		get_viewport_rect().size.x + customer_slot.size.x, 0.5).set_ease(Tween.EASE_IN)
	return tw


# ---------- VALIDACIÓN Y TIEMPO ----------
func _on_check_pressed() -> void:
	if _locked or _moving:
		return
	if solved:
		_next_step()
	else:
		_validate()


func _validate() -> void:
	var txt := change_input.text.strip_edges()
	if not txt.is_valid_int():
		_set_feedback("Escribe el vuelto que debe devolver la caja.", -1)
		return
	if int(txt) == paid - _total(order):
		_is_timer_running = false
		correct += 1
		solved = true
		change_input.editable = false
		check_btn.text = "Siguiente"
		_set_feedback("¡Correcto! El vuelto está bien.", 1)
		_update_score()
		var y := customer.global_position.y
		var tw := create_tween()
		tw.tween_property(customer, "global_position:y", y - 12, 0.1)
		tw.tween_property(customer, "global_position:y", y, 0.1)
	else:
		_set_feedback("No es correcto. Revisa la resta.", -1)
		_shake(calc_panel)


func _on_time_out() -> void:
	_locked = true
	change_input.editable = false
	_set_feedback("¡Se agotó el tiempo!", -1)
	_shake(calc_panel)
	await get_tree().create_timer(1.2).timeout
	_next_step()


func _next_step() -> void:
	_locked = true
	await _customer_leave().finished
	current += 1
	if current < TOTAL_CLIENTES:
		_load_customer()
	else:
		_open_final()


# ---------- UI ----------
func _set_feedback(msg: String, state: int) -> void:
	feedback.text = msg
	match state:
		1: feedback.modulate = Color("047857")
		-1: feedback.modulate = Color("b91c1c")
		_: feedback.modulate = Color("56738c")


func _update_score() -> void:
	score_label.text = "Clientes %d/%d" % [correct, TOTAL_CLIENTES]


func _shake(node: Control) -> void:
	var x := node.position.x
	var tw := create_tween()
	for d in [-8, 8, -5, 5, 0]:
		tw.tween_property(node, "position:x", x + d, 0.04)


func _open_final() -> void:
	_is_timer_running = false
	anim_timer.stop()
	var pct := roundi(float(correct) / TOTAL_CLIENTES * 100.0)
	modal_title.text = "¡Nivel completado!" if pct >= 50 else "¡Sigue intentando!"
	modal_accuracy.text = "Aciertos: %d/%d (%d%%)" % [correct, TOTAL_CLIENTES, pct]
	modal_coins.text = "Modo práctica"   # la tienda aún no acredita monedas en el servidor
	var tex := banner_good if pct >= 50 else banner_bad
	if tex != null:
		modal_banner.texture = tex
	final_modal.show()

func _is_mobile() -> bool:
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches || navigator.maxTouchPoints > 0")
		return bool(r)
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

func _build_keypad() -> void:
	keypad.columns = 3
	keypad.add_theme_constant_override("h_separation", 4)
	keypad.add_theme_constant_override("v_separation", 4)
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "DEL", "0", "C"]:
		var b := Button.new()
		b.text = k
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_key.bind(k))
		keypad.add_child(b)


func _on_key(k: String) -> void:
	if _locked or _moving or solved:
		return
	match k:
		"DEL":
			change_input.text = change_input.text.left(-1)
		"C":
			change_input.text = ""
		_:
			if change_input.text.length() < 4:
				change_input.text += k
