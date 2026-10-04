class_name Models
extends RefCounted

class NivelDto:
	var nivel_id: int = 0
	var test_id: int = 0
	var titulo: String = ""
	var categoria: String = ""
	var orden: int = 0
	var estado: String = ""
	var puntaje: int = 0
	var intentos: int = 0

	static func from_dictionary(dict: Dictionary) -> NivelDto:
		var dto := NivelDto.new()
		dto.nivel_id = _i(dict.get("nivelId"))
		dto.test_id = _i(dict.get("testId"))   # long? en la API: puede venir null
		dto.titulo = str(dict.get("titulo", ""))
		dto.categoria = str(dict.get("categoria", ""))
		dto.orden = _i(dict.get("orden"))
		dto.estado = str(dict.get("estado", "No Iniciado"))
		dto.puntaje = _i(dict.get("puntaje"))
		dto.intentos = _i(dict.get("intentos"))
		return dto

	static func _i(v: Variant) -> int:
		return int(v) if v != null else 0

class TestEvaluacionDto:
	var test_id: int = 0
	var nombre_test: String = ""
	var total_preguntas: int = 0
	var preguntas: Array[PreguntaDto] = []

class PreguntaDto:
	var pregunta_id: int = 0
	var texto_pregunta: String = ""
	var tipo_pregunta: int = 0
	var opciones: Array[OpcionDto] = []

class OpcionDto:
	var opcion_id: int = 0
	var texto_opcion: String = ""
