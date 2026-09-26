extends Control

@export var option_button_prefab: PackedScene = preload("res://scenes/Prefabs/option_button.tscn")

# Nodos de la interfaz principal
@export var progress_bar_questions_path: NodePath
@export var label_timer_path: NodePath
@export var label_question_title_path: NodePath
@export var options_container_path: NodePath
@export var label_progress_path: NodePath

# Nodos del Modal de Feedback
@export var feedback_panel_path: NodePath
@export var label_status_title_path: NodePath
@export var label_accuracy_path: NodePath
@export var label_coins_path: NodePath

# Botones de Acción
@export var btn_home_path: NodePath
@export var btn_retry_path: NodePath
@export var btn_next_path: NodePath

@onready var _progress_bar_questions: ProgressBar = get_node_or_null(progress_bar_questions_path)
@onready var _label_question_title: Label = get_node_or_null(label_question_title_path)
@onready var _options_container: VBoxContainer = get_node_or_null(options_container_path)
@onready var _label_timer: Label = get_node_or_null(label_timer_path)
@onready var _label_progress: Label = get_node_or_null(label_progress_path)

# Referencia al contenedor principal de la interfaz del test
@onready var _main_vbox: Control = get_node_or_null("MainVBox")

# Modal de Feedback
@onready var _feedback_panel: Control = get_node_or_null(feedback_panel_path)
@onready var _label_status_title: Label = get_node_or_null(label_status_title_path)
@onready var _label_accuracy: Label = get_node_or_null(label_accuracy_path)
@onready var _label_coins: Label = get_node_or_null(label_coins_path)

@onready var _btn_home: Button = get_node_or_null(btn_home_path)
@onready var _btn_retry: Button = get_node_or_null(btn_retry_path)
@onready var _btn_next: Button = get_node_or_null(btn_next_path)

# Estado del Quiz
var _current_test_data: Dictionary = {}
var _preguntas: Array = []
var _current_question_index: int = 0
var _user_responses: Array = []
var _fecha_inicio: String = ""

# Temporizador
var _time_remaining: float = 15.0
const QUESTION_TIME_LIMIT: float = 15.0
var _is_timer_running: bool = false

func _ready() -> void:
	if _feedback_panel:
		_feedback_panel.hide()
		
	if _btn_home and not _btn_home.pressed.is_connected(_on_btn_home_pressed):
		_btn_home.pressed.connect(_on_btn_home_pressed)
	if _btn_retry and not _btn_retry.pressed.is_connected(_on_btn_retry_pressed):
		_btn_retry.pressed.connect(_on_btn_retry_pressed)
	if _btn_next and not _btn_next.pressed.is_connected(_on_btn_next_pressed):
		_btn_next.pressed.connect(_on_btn_next_pressed)
		
	_fecha_inicio = Time.get_datetime_string_from_system(true) + "Z"
	
	var test_id: int = 139
	if GameManager and GameManager.selected_test_id > 0:
		test_id = int(GameManager.selected_test_id)
		
	_cargar_test_desde_api(test_id)

func _process(delta: float) -> void:
	if _is_timer_running:
		_time_remaining -= delta
		
		if _label_timer:
			var total_seconds: int = int(max(0, ceil(_time_remaining)))
			var minutes: int = total_seconds / 60
			var seconds: int = total_seconds % 60
			_label_timer.text = "%02d:%02d" % [minutes, seconds]
			
		if _time_remaining <= 0:
			_is_timer_running = false
			_manejar_tiempo_agotado()

func _cargar_test_desde_api(test_id: int) -> void:
	var respuesta = await ApiService.obtener_preguntas_test_async(test_id)
	var status = respuesta[0]
	var body_text = respuesta[1]
	
	if status == 200:
		var json_data = JSON.parse_string(body_text)
		if json_data is Dictionary:
			_current_test_data = json_data
			if json_data.has("preguntas"):
				_preguntas = json_data["preguntas"]
			elif json_data.has("Preguntas"):
				_preguntas = json_data["Preguntas"]
				
			if _preguntas.size() > 0:
				_current_question_index = 0
				_user_responses.clear()
				_cargar_pregunta_actual()
	else:
		print("[QuizScene] ❌ Error al obtener test. Status: ", status)

func _cargar_pregunta_actual() -> void:
	_is_timer_running = false
	_time_remaining = QUESTION_TIME_LIMIT
	
	if _feedback_panel:
		_feedback_panel.hide()
		
	if _progress_bar_questions and _preguntas.size() > 0:
		_progress_bar_questions.max_value = _preguntas.size()
		_progress_bar_questions.value = _current_question_index + 1
		
	var q = _preguntas[_current_question_index]
	var texto_preg = q.get("pregunta", q.get("textoPregunta", ""))
	
	if _label_question_title: 
		_label_question_title.text = texto_preg
		
	if _label_progress:
		_label_progress.text = "Pregunta " + str(_current_question_index + 1) + " de " + str(_preguntas.size())
		
	if _options_container:
		for child in _options_container.get_children():
			child.queue_free()
			
		var opciones = q.get("opciones", q.get("Opciones", []))
		for opt in opciones:
			var btn_opt: Button
			if option_button_prefab:
				btn_opt = option_button_prefab.instantiate() as Button
			else:
				btn_opt = Button.new()
				btn_opt.custom_minimum_size = Vector2(0, 50)
				
			btn_opt.text = opt.get("textoOpcion", opt.get("texto_opcion", ""))
			btn_opt.pressed.connect(_validar_respuesta.bind(q, opt))
			_options_container.add_child(btn_opt)
			
	_is_timer_running = true

func _validar_respuesta(pregunta: Dictionary, opt_seleccionada: Dictionary) -> void:
	if not _is_timer_running:
		return
		
	_is_timer_running = false
	
	if _options_container:
		for btn in _options_container.get_children():
			if btn is Button:
				btn.disabled = true
				
	var p_id: int = int(pregunta.get("preguntaId", 0))
	var o_id: int = int(opt_seleccionada.get("opcionId", 0))
	var t_txt: String = str(opt_seleccionada.get("textoOpcion", ""))
	
	var resp_dto = {
		"preguntaId": p_id,
		"opcionId": o_id,
		"respuestaTexto": t_txt
	}
	_user_responses.append(resp_dto)
	
	await get_tree().create_timer(0.3).timeout
	_avanzar_siguiente_pregunta()

func _manejar_tiempo_agotado() -> void:
	if _current_question_index >= _preguntas.size():
		return
		
	var pregunta = _preguntas[_current_question_index]
	var p_id: int = int(pregunta.get("preguntaId", 0))
	
	var resp_dto = {
		"preguntaId": p_id,
		"opcionId": null,
		"respuestaTexto": ""
	}
	_user_responses.append(resp_dto)
	_avanzar_siguiente_pregunta()

func _avanzar_siguiente_pregunta() -> void:
	_current_question_index += 1
	if _current_question_index < _preguntas.size():
		_cargar_pregunta_actual()
	else:
		_finalizar_test_async()

func _finalizar_test_async() -> void:
	_is_timer_running = false
	
	# Ocultamos toda la interfaz de preguntas para dejar libre la pantalla
	if _main_vbox: _main_vbox.hide()
	
	var test_id: int = int(_current_test_data.get("testId", 139))
	var estudiante_id: int = ApiService.obtener_estudiante_id_del_navegador()
	if GameManager and GameManager.current_estudiante_id > 0:
		estudiante_id = int(GameManager.current_estudiante_id)
		
	var fecha_fin: String = Time.get_datetime_string_from_system(true) + "Z"
	
	var intento_payload = {
		"testId": test_id,
		"estudianteId": estudiante_id,
		"fechaInicio": _fecha_inicio,
		"fechaFin": fecha_fin,
		"respuestas": _user_responses
	}
	
	print("[QuizScene] 📤 Registrando intento: ", intento_payload)
	var respuesta = await ApiService.registrar_resultado_test_async(intento_payload)
	var status = respuesta[0]
	var body_text = respuesta[1]
	
	if status == 200:
		var res_json = JSON.parse_string(body_text)
		var aciertos: int = int(res_json.get("respuestasCorrectas", 0))
		var total: int = int(res_json.get("totalPreguntas", _preguntas.size()))
		var monedas: float = float(res_json.get("monedasGanadas", 0))
		
		_mostrar_modal_feedback(aciertos, total, monedas)
	else:
		print("[QuizScene] ❌ Backend status: ", status)
		var aciertos_locales: int = 0
		for r in _user_responses:
			if r.get("opcionId", 0) > 0:
				aciertos_locales += 1
		_mostrar_modal_feedback(aciertos_locales, _preguntas.size(), 0)

func _mostrar_modal_feedback(aciertos: int, total: int, monedas: float) -> void:
	if not _feedback_panel:
		return
		
	var porcentaje: float = 0.0
	if total > 0:
		porcentaje = (float(aciertos) / float(total)) * 100.0
		
	var aprobo: bool = porcentaje >= 50.0
	
	if _label_status_title:
		_label_status_title.text = "¡NIVEL COMPLETADO!" if aprobo else "¡INTÉNTALO DE NUEVO!"
	if _label_accuracy:
		_label_accuracy.text = "Aciertos: " + str(aciertos) + " / " + str(total)
	if _label_coins:
		_label_coins.text = "Monedas: +" + str(int(monedas))
		
	if _btn_home: _btn_home.show()
		
	if aprobo:
		if _btn_next: _btn_next.show()
		if _btn_retry: _btn_retry.hide()
	else:
		if _btn_next: _btn_next.hide()
		if _btn_retry: _btn_retry.show()
		
	_feedback_panel.show()

# --- Navegación ---
func _on_btn_home_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/mapa_niveles.tscn")

func _on_btn_retry_pressed() -> void:
	get_tree().reload_current_scene()

func _on_btn_next_pressed() -> void:
	if GameManager:
		GameManager.selected_test_id += 1
	get_tree().reload_current_scene()
