extends Control

@export var niveles_container_path: NodePath
@export var level_button_prefab: PackedScene
@export var quiz_scene: PackedScene

@onready var _niveles_container: VBoxContainer = get_node_or_null(niveles_container_path)
@onready var _label_monedas: Label = get_node_or_null("MainLayoutVBox/TopHeaderMargin/TopHeaderHBox/Monedas")

const BUBBLE_SIZE: float = 80.0
const MAX_AMPLITUDE: float = 110.0
const WAVE_FREQUENCY: float = 0.5
# La API no expone categoría; hasta filtrar en servidor, los niveles curriculares empiezan aquí.
const MIN_NIVEL_ID: int = 132
const MAX_NIVELES: int = 27

var _niveles: Array[Models.NivelDto] = []


func _ready() -> void:
	if _label_monedas == null:
		_label_monedas = find_child("Monedas", true, false) as Label
	GameManager.monedas_actualizadas.connect(_mostrar_monedas)
	_mostrar_monedas(GameManager.monedas)   # caché mientras llega el valor real

	get_viewport().size_changed.connect(_renderizar_niveles)
	_cargar_monedas()
	_cargar_niveles()


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


# ---------- Niveles ----------
func _cargar_niveles() -> void:
	var res := await ApiService.obtener_mapa_niveles_async()
	if not is_inside_tree() or res[0] != 200:
		push_warning("[MapaNiveles] HTTP %s" % res[0])
		return

	var json := JSON.new()
	if json.parse(res[1]) != OK or not (json.data is Array):
		push_warning("[MapaNiveles] Respuesta inválida: %s" % json.get_error_message())
		return

	_niveles.clear()
	for item in json.data:
		if item is Dictionary:
			var dto := Models.NivelDto.from_dictionary(item)
			if dto.nivel_id >= MIN_NIVEL_ID:
				_niveles.append(dto)
	_niveles.sort_custom(func(a, b): return a.orden < b.orden)
	if _niveles.size() > MAX_NIVELES:
		_niveles.resize(MAX_NIVELES)

	GameManager.ordered_test_ids.clear()
	for n in _niveles:
		GameManager.ordered_test_ids.append(n.test_id)

	_renderizar_niveles()


func _renderizar_niveles() -> void:
	if _niveles_container == null or _niveles.is_empty():
		return

	for child in _niveles_container.get_children():
		_niveles_container.remove_child(child)
		child.queue_free()

	var ancho: float = _niveles_container.size.x
	if ancho <= 0.0:
		ancho = get_viewport_rect().size.x
	var centro: float = (ancho - BUBBLE_SIZE) / 2.0
	var amplitud: float = clampf(centro - 10.0, 0.0, MAX_AMPLITUDE)

	var anterior_completado := true
	var index := 0
	for nivel in _niveles:
		index += 1
		var bloqueado: bool = nivel.estado == "Bloqueado" or (not anterior_completado and nivel.estado != "Completado")
		anterior_completado = nivel.estado == "Completado"

		var wrapper := MarginContainer.new()
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var left: float = maxf(10.0, centro + sin(index * WAVE_FREQUENCY) * amplitud)
		wrapper.add_theme_constant_override("margin_left", int(left))

		var btn: Button = level_button_prefab.instantiate() as Button if level_button_prefab else Button.new()
		btn.custom_minimum_size = Vector2(BUBBLE_SIZE, BUBBLE_SIZE)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		btn.text = str(index)
		btn.disabled = bloqueado or nivel.test_id <= 0

		if btn.disabled:
			btn.modulate = Color(0.6, 0.6, 0.6, 0.8)
		elif nivel.estado == "Completado":
			btn.modulate = Color(1.0, 0.9, 0.3)
		else:
			btn.modulate = Color.WHITE

		btn.pressed.connect(_on_level_selected.bind(nivel.test_id, nivel.titulo))
		wrapper.add_child(btn)
		_niveles_container.add_child(wrapper)


func _on_level_selected(test_id: int, titulo: String) -> void:
	if test_id <= 0:
		return
	GameManager.selected_test_id = test_id
	GameManager.selected_test_title = titulo
	if quiz_scene:
		get_tree().change_scene_to_packed(quiz_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/quiz_scene.tscn")


func _on_btn_back_pressed() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = '/index.html';")


func _on_btn_simulacion_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/tienda.tscn")
