extends Control

@export var niveles_container_path: NodePath
@export var level_button_prefab: PackedScene
@export var quiz_scene: PackedScene

@onready var _niveles_container: VBoxContainer = get_node_or_null(niveles_container_path)

# Parámetros para la distribución visual en S-Curve
const MAP_WIDTH: float = 360.0
const BUBBLE_SIZE: float = 80.0
const WAVE_AMPLITUDE: float = 110.0
const WAVE_FREQUENCY: float = 0.5

func _ready() -> void:
	print("[MapaNiveles] 🎬 Escena lista. Iniciando flujo de carga de niveles...")
	_cargar_niveles()

func _cargar_niveles() -> void:
	# 1. Recuperar el ID del estudiante de forma dinámica desde ApiService
	var estudiante_id = ApiService.obtener_estudiante_id_del_navegador()
	
	if estudiante_id <= 0:
		print("[MapaNiveles] 🛑 CANCELADO: ID de estudiante inválido (", estudiante_id, "). Verifique el inicio de sesión.")
		return

	print("[MapaNiveles] 🔄 Solicitando mapa de niveles a la API para el estudiante ID: ", estudiante_id)
	
	# 2. Petición HTTP asíncrona a la API
	var res_niveles = await ApiService.obtener_mapa_niveles_async(estudiante_id)
	
	if res_niveles[0] == 200:
		var json_niveles = JSON.new()
		if json_niveles.parse(res_niveles[1]) == OK:
			var lista_niveles_raw: Array = json_niveles.data
			var niveles_dto: Array[Models.NivelDto] = []
			
			print("[MapaNiveles] 📦 Se recibieron ", lista_niveles_raw.size(), " niveles en total desde la API.")
			
			for item in lista_niveles_raw:
				var dto = Models.NivelDto.new()
				dto.nivel_id = int(item.get("nivelId", 0))
				dto.titulo = str(item.get("titulo", ""))
				dto.test_id = int(item.get("testId", 0))
				dto.estado = str(item.get("estado", "Bloqueado"))
				niveles_dto.append(dto)
				
			# 3. FILTRADO OFICIAL: Únicamente los 27 niveles curriculares a partir de nivel_id >= 132
			var niveles_filtrados: Array[Models.NivelDto] = []
			for n in niveles_dto:
				if n.nivel_id >= 132:
					niveles_filtrados.append(n)
					if niveles_filtrados.size() == 27:
						break
						
			print("[MapaNiveles] 🗺️ Se filtraron ", niveles_filtrados.size(), " niveles oficiales para la interfaz (IDs >= 132).")
			
			if niveles_filtrados.is_empty():
				print("[MapaNiveles] ⚠️ La API devolvió datos, pero ningún nivel cumple con el criterio de ID >= 132.")
			else:
				_renderizar_niveles(niveles_filtrados)
		else:
			print("[MapaNiveles] ❌ Error al procesar la respuesta JSON de niveles.")
	else:
		print("[MapaNiveles] ❌ Error de comunicación con la API. Estado HTTP: ", res_niveles[0], " - Detalle: ", res_niveles[1])

func _renderizar_niveles(niveles: Array[Models.NivelDto]) -> void:
	if not _niveles_container:
		push_error("[MapaNiveles] ❌ No se encontró el nodo contenedor '_niveles_container'.")
		return
		
	# Limpieza de botones previo a la renderización
	for child in _niveles_container.get_children():
		child.queue_free()
		
	var index: int = 0
	
	for nivel in niveles:
		index += 1
		
		var margin_wrapper = MarginContainer.new()
		margin_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Offset sinusoidal para la curva del mapa
		var center_offset: float = (MAP_WIDTH - BUBBLE_SIZE) / 2.0
		var x_shift: float = sin(index * WAVE_FREQUENCY) * WAVE_AMPLITUDE
		var left_margin: float = max(10.0, center_offset + x_shift)
		
		margin_wrapper.add_theme_constant_override("margin_left", int(left_margin))
		
		var btn: Button
		if level_button_prefab:
			btn = level_button_prefab.instantiate() as Button
		else:
			btn = Button.new()
			
		btn.custom_minimum_size = Vector2(BUBBLE_SIZE, BUBBLE_SIZE)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		
		# Etiqueta secuencial (1 al 27)
		btn.text = str(index)
		btn.disabled = (nivel.estado == "Bloqueado")
		
		if nivel.estado == "Bloqueado":
			btn.modulate = Color(0.6, 0.6, 0.6, 0.8)
		elif nivel.estado == "Completado":
			btn.modulate = Color(1.0, 0.9, 0.3, 1.0) # Tono dorado para niveles superados
		else:
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0) # Tono blanco/normal para el nivel activo
			
		btn.pressed.connect(_on_level_selected.bind(nivel.test_id, nivel.titulo))
		
		margin_wrapper.add_child(btn)
		_niveles_container.add_child(margin_wrapper)

func _on_level_selected(test_id: int, titulo: String) -> void:
	print("[MapaNiveles] 🎯 Nivel seleccionado por el usuario: ", titulo, " (TestID: ", test_id, ")")
	if GameManager:
		GameManager.selected_test_id = test_id
		GameManager.selected_test_title = titulo
		
	if quiz_scene:
		get_tree().change_scene_to_packed(quiz_scene)
	else:
		var ruta_escena = "res://scenes/quiz_scene.tscn"
		if FileAccess.file_exists(ruta_escena):
			get_tree().change_scene_to_file(ruta_escena)
		else:
			push_error("[MapaNiveles] ❌ No se encontró la escena en la ruta especificada: " + ruta_escena)
			


func _on_btn_back_pressed() -> void:
	if OS.has_feature("web"):
		# Redirige el navegador a index.html en la raíz
		JavaScriptBridge.eval("window.location.href = '/index.html';")
	else:
		print("[Navegacion] Volviendo a pantalla principal (Desktop)")

func _on_btn_simulacion_pressed() -> void:
	pass # get_tree().change_scene_to_file("res://scenes/tienda_simulacion.tscn")
