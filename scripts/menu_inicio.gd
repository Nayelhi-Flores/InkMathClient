extends Control
## Menú principal: 4 paneles (modos de juego), monedas acumuladas y salida con logout.

@export var column_ratio := 0.7

const ESCENAS := {
	"Fisica": "res://scenes/fisica.tscn",
	"Fracciones": "res://scenes/fracciones.tscn",
	"Tienda": "res://scenes/tienda.tscn",
	"Quiz": "res://scenes/mapa_niveles.tscn",
}

@onready var _label_monedas: Label = find_child("Monedas", true, false) as Label
@onready var _btn_back: Button = find_child("BtnBack", true, false) as Button

var _navegando := false


func _ready() -> void:
	AudioManager.stop_music()   # el menú no tiene música: se corta la del modo de juego
	# Columna central en pantallas anchas. La barra de navegación va dentro de este contenedor.
	var contenido := _contenido_principal()
	if contenido:
		_limitar_ancho(contenido)
		get_viewport().size_changed.connect(_limitar_ancho.bind(contenido))
	else:
		push_warning("[Menu] No se encontró el contenedor principal (VBoxContainer/Column).")

	for nombre in ESCENAS:
		var panel := find_child(nombre, true, false) as Control
		if panel:
			panel.gui_input.connect(_on_panel_gui_input.bind(nombre))
		else:
			push_warning("[Menu] No se encontró el panel '%s'" % nombre)

	if _btn_back and not _btn_back.pressed.is_connected(_on_btn_back_pressed):
		_btn_back.pressed.connect(_on_btn_back_pressed)

	GameManager.monedas_actualizadas.connect(_mostrar_monedas)
	_mostrar_monedas(GameManager.monedas)
	_cargar_monedas()


# Contenedor raíz del contenido: "Column", "VBoxContainer" o el primer VBoxContainer hijo directo.
func _contenido_principal() -> Control:
	for nombre in ["Column", "VBoxContainer"]:
		var n := get_node_or_null(nombre) as Control
		if n:
			return n
	for c in get_children():
		if c is VBoxContainer:
			return c
	return null


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


# ---------- Monedas ----------
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


# ---------- Paneles ----------
func _on_panel_gui_input(event: InputEvent, nombre: String) -> void:
	var tap := false
	if event is InputEventMouseButton:
		tap = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tap = event.pressed
	if tap:
		_abrir(nombre)


func _abrir(nombre: String) -> void:
	if _navegando or not ESCENAS.has(nombre):
		return
	_navegando = true   # el toque llega como ratón y como pantalla táctil: solo se atiende uno
	get_tree().change_scene_to_file(ESCENAS[nombre])


# ---------- Salir: cierra sesión en la API (borra la cookie) y vuelve al login ----------
func _on_btn_back_pressed() -> void:
	if _navegando:
		return
	_navegando = true
	await ApiService.logout_async()
	GameManager.set_monedas(0)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = '/index.html';")
