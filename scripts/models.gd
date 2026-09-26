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
		var dto = NivelDto.new()
		dto.nivel_id = int(dict.get("nivelId", 0))
		dto.test_id = int(dict.get("testId", 0))
		dto.titulo = str(dict.get("titulo", ""))
		dto.categoria = str(dict.get("categoria", ""))
		dto.orden = int(dict.get("orden", 0))
		dto.estado = str(dict.get("estado", ""))
		dto.puntaje = int(dict.get("puntaje", 0))
		dto.intentos = int(dict.get("intentos", 0))
		return dto

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
