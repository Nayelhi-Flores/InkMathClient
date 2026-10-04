extends Control

@export var option_button_prefab: PackedScene = preload("res://scenes/Prefabs/option_button.tscn")

@export var progress_bar_questions_path: NodePath
@export var label_timer_path: NodePath
@export var label_question_title_path: NodePath
@export var options_container_path: NodePath
@export var label_progress_path: NodePath

@export var feedback_panel_path: NodePath
@export var label_status_title_path: NodePath
@export var label_accuracy_path: NodePath
@export var label_coins_path: NodePath

@export var btn_home_path: NodePath
@export var btn_retry_path: NodePath
@export var btn_next_path: NodePath

@onready var _progress_bar_questions: ProgressBar = get_node_or_null(progress_bar_questions_path)
@onready var _label_question_title: Label = get_node_or_null(label_question_title_path)
@onready var _options_container: VBoxContainer = get_node_or_null(options_container_path)
@onready var _label_timer: Label = get_node_or_null(label_timer_path)
@onready var _label_progress: Label = get_node_or_null(label_progress_path)
@onready var _main_vbox: Control = get_node_or_null("MainVBox")

@onready var _feedback_panel: Control = get_node_or_null(feedback_panel_path)
@onready var _label_status_title: Label = get_node_or_null(label_status_title_path)
@onready var _label_accuracy: Label = get_node_or_null(label_accuracy_path)
@onready var _label_coins: Label = get_node_or_null(label_coins_path)
@onready var _btn_home: Button = get_node_or_null(btn_home_path)
@onready var _btn_retry: Button = get_node_or_null(btn_retry_path)
@onready var _btn_next: Button = get_node_or_null(btn_next_path)

const MAP_SCENE := "res://scenes/mapa_niveles.tscn"
const QUESTION_TIME_LIMIT: float = 15.0

var _preguntas: Array = []
var _test_id: int = 0
var _current_question_index: int = 0
var _user_responses: Array = []
var _intento_token: String = ""   # ticket firmado por el servidor
var _time_remaining: float = QUESTION_TIME_LIMIT
var _is_timer_running: bool = false


func _ready() -> void:
	if _feedback_panel:
		_feedback_panel.hide()
	if _btn_home: _btn_home.pressed.connect(_on_btn_home_pressed)
	if _btn_retry: _btn_retry.pressed.connect(_on_btn_retry_pressed)
	if _btn_next: _btn_next.pressed.connect(_on_btn_next_pressed)

	_test_id = GameManager.selected_test_id
	if _test_id <= 0:
		_volver_al_mapa()
		return
	_cargar_test_desde_api(_test_id)


func _process(delta: float) -> void:
	if not _is_timer_running:
		return
	_time_remaining -= delta
	if _label_timer:
		var total_seconds: int = int(maxf(0.0, ceilf(_time_remaining)))
		@warning_ignore("integer_division")
		var minutos: int = total_seconds / 60
		_label_timer.text = "%02d:%02d" % [minutos, total_seconds % 60]
	if _time_remaining <= 0.0:
		_is_timer_running = false
		_manejar_tiempo_agotado()


func _cargar_test_desde_api(test_id: int) -> void:
	var respuesta := await ApiService.obtener_preguntas_test_async(test_id)
	if not is_inside_tree():
		return
	if respuesta[0] == 200:
		var data = JSON.parse_string(respuesta[1])
		if data is Dictionary:
			_preguntas = data.get("preguntas", data.get("Preguntas", []))
			_intento_token = str(data.get("intentoToken", ""))
	if _preguntas.is_empty() or _intento_token.is_empty():
		_preguntas.clear()
		if _label_question_title:
			_label_question_title.text = "No se pudo cargar el test. Intenta de nuevo."
		return
	_current_question_index = 0
	_user_responses.clear()
	_cargar_pregunta_actual()


func _cargar_pregunta_actual() -> void:
	_is_timer_running = false
	_time_remaining = QUESTION_TIME_LIMIT
	if _feedback_panel:
		_feedback_panel.hide()
	if _progress_bar_questions:
		_progress_bar_questions.max_value = _preguntas.size()
		_progress_bar_questions.value = _current_question_index + 1

	var q: Dictionary = _preguntas[_current_question_index]
	if _label_question_title:
		_label_question_title.text = str(q.get("pregunta", q.get("textoPregunta", "")))
	if _label_progress:
		_label_progress.text = "Pregunta %d de %d" % [_current_question_index + 1, _preguntas.size()]

	if _options_container:
		for child in _options_container.get_children():
			child.queue_free()
		for opt in q.get("opciones", q.get("Opciones", [])):
			var btn: Button = option_button_prefab.instantiate() as Button if option_button_prefab else Button.new()
			btn.custom_minimum_size.y = maxf(btn.custom_minimum_size.y, 50.0)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.text = str(opt.get("textoOpcion", ""))
			btn.pressed.connect(_validar_respuesta.bind(q, opt))
			_options_container.add_child(btn)

	_is_timer_running = true


func _validar_respuesta(pregunta: Dictionary, opt: Dictionary) -> void:
	if not _is_timer_running:
		return
	_is_timer_running = false
	if _options_container:
		for b in _options_container.get_children():
			if b is Button:
				b.disabled = true

	_user_responses.append({
		"preguntaId": int(pregunta.get("preguntaId", 0)),
		"opcionId": int(opt.get("opcionId", 0)),
		"respuestaTexto": str(opt.get("textoOpcion", ""))
	})
	await get_tree().create_timer(0.3).timeout
	if not is_inside_tree():
		return
	_avanzar_siguiente_pregunta()


func _manejar_tiempo_agotado() -> void:
	if _current_question_index >= _preguntas.size():
		return
	_user_responses.append({
		"preguntaId": int(_preguntas[_current_question_index].get("preguntaId", 0)),
		"opcionId": null,
		"respuestaTexto": ""
	})
	_avanzar_siguiente_pregunta()


func _avanzar_siguiente_pregunta() -> void:
	_current_question_index += 1
	if _current_question_index < _preguntas.size():
		_cargar_pregunta_actual()
	else:
		_finalizar_test_async()


func _finalizar_test_async() -> void:
	_is_timer_running = false
	if _main_vbox:
		_main_vbox.hide()

	# El servidor toma el estudiante del token y fija las fechas; solo se envía el ticket.
	var payload := {
		"testId": _test_id,
		"intentoToken": _intento_token,
		"respuestas": _user_responses
	}
	var respuesta := await ApiService.registrar_resultado_test_async(payload)
	if not is_inside_tree():
		return

	if respuesta[0] == 200:
		var r = JSON.parse_string(respuesta[1])
		if r is Dictionary:
			GameManager.set_monedas(int(r.get("nuevoSaldoMonedas", GameManager.monedas)))
			_mostrar_modal_feedback(int(r.get("respuestasCorrectas", 0)),
					int(r.get("totalPreguntas", _preguntas.size())),
					int(r.get("monedasGanadas", 0)), true)
			return
	# Sin respuesta válida del servidor no se inventan aciertos.
	_mostrar_modal_feedback(0, _preguntas.size(), 0, false)


func _mostrar_modal_feedback(aciertos: int, total: int, monedas: int, ok: bool) -> void:
	if not _feedback_panel:
		return
	# El servidor marca el nivel como completado solo con 100% de aciertos.
	var completado := ok and total > 0 and aciertos == total

	if _label_status_title:
		if not ok:
			_label_status_title.text = "No se pudo guardar tu resultado"
		else:
			_label_status_title.text = "¡NIVEL COMPLETADO!" if completado else "¡INTÉNTALO DE NUEVO!"
	if _label_accuracy:
		_label_accuracy.text = "Aciertos: %d / %d" % [aciertos, total] if ok else "Revisa tu conexión"
	if _label_coins:
		_label_coins.text = "Monedas: +%d" % monedas

	if _btn_home: _btn_home.show()
	if _btn_next: _btn_next.visible = completado and GameManager.next_test_id() > 0
	if _btn_retry: _btn_retry.visible = not completado
	_feedback_panel.show()


func _volver_al_mapa() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


func _on_btn_home_pressed() -> void:
	_volver_al_mapa()


func _on_btn_retry_pressed() -> void:
	get_tree().reload_current_scene()


func _on_btn_next_pressed() -> void:
	var nxt := GameManager.next_test_id()
	if nxt <= 0:
		_volver_al_mapa()
		return
	GameManager.selected_test_id = nxt
	get_tree().reload_current_scene()
