extends Node

const PROD_URL := "https://inkmath.online/api/"
const REQUEST_TIMEOUT := 15.0

var base_url: String = PROD_URL


func _ready() -> void:
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin")
		if origin != null and str(origin).begins_with("http"):
			base_url = str(origin) + "/api/"


func _manejar_no_autorizado() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href='/index.html';")


# Devuelve [status_http, body]. status 0 = fallo de red/timeout.
func _send(method: int, endpoint: String, payload: Variant = null) -> Array:
	var http := HTTPRequest.new()
	http.accept_gzip = false
	http.timeout = REQUEST_TIMEOUT
	add_child(http)

	var headers := ["Content-Type: application/json", "Accept: application/json"]
	var body := "" if payload == null else JSON.stringify(payload)

	if http.request(base_url + endpoint, headers, method, body) != OK:
		http.queue_free()
		return [0, "{}"]

	var result: Array = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return [0, "{}"]

	var code: int = result[1]
	if code == 401:
		_manejar_no_autorizado()
	return [code, (result[3] as PackedByteArray).get_string_from_utf8()]


func get_async(endpoint: String) -> Array:
	return await _send(HTTPClient.METHOD_GET, endpoint)


func post_json_async(endpoint: String, payload: Dictionary) -> Array:
	return await _send(HTTPClient.METHOD_POST, endpoint, payload)


# --- Endpoints (el ID del estudiante lo toma el servidor desde la cookie/token) ---
func obtener_mapa_niveles_async() -> Array:
	return await get_async("Niveles/mi-mapa")


func obtener_saldo_async() -> Array:
	return await get_async("Monedas/mi-saldo")


func obtener_preguntas_test_async(test_id: int, limite_preguntas: int = 15) -> Array:
	return await get_async("Evaluaciones/test/%d?limitePreguntas=%d" % [test_id, limite_preguntas])


func registrar_resultado_test_async(intento_dto: Dictionary) -> Array:
	return await post_json_async("Evaluaciones/resultados", intento_dto)

func iniciar_juego_async(modo: String) -> Array:
	return await post_json_async("Juegos/%s/iniciar" % modo, {})


func finalizar_juego_async(modo: String, intento_token: String, respuestas: Variant) -> Array:
	return await _send(HTTPClient.METHOD_POST, "Juegos/%s/resultado" % modo,
			{"intentoToken": intento_token, "respuestas": respuestas})

func logout_async() -> Array:
	return await post_json_async("Auth/logout", {})

func arrecife_perfil_async() -> Array:
	return await get_async("Chat/arrecife/perfil")

func arrecife_mensajes_async(aula_id: int) -> Array:
	return await get_async("Chat/arrecife/aula/%d" % aula_id)

func arrecife_enviar_async(aula_id: int, contenido: String, es_emoji: bool, padre_id: int = 0) -> Array:
	return await post_json_async("Chat/arrecife/enviar", {
		"aulaId": aula_id, "contenido": contenido, "esEmoji": es_emoji,
		"mensajePadreId": null if padre_id <= 0 else padre_id})

func arrecife_votar_async(mensaje_id: int) -> Array:
	return await post_json_async("Chat/arrecife/%d/votar-util" % mensaje_id, {})

func arrecife_reportar_async(mensaje_id: int, motivo: String) -> Array:
	return await post_json_async("Chat/arrecife/%d/reportar" % mensaje_id, {"motivo": motivo})

func arrecife_eliminar_async(mensaje_id: int) -> Array:
	return await _send(HTTPClient.METHOD_DELETE, "Chat/arrecife/%d" % mensaje_id)

func mis_aulas_async() -> Array:
	return await get_async("Aulas/mis-aulas")

func aula_tests_async(aula_id: int) -> Array:
	return await get_async("Aulas/%d/tests" % aula_id)

func aula_recursos_async(aula_id: int) -> Array:
	return await get_async("Aulas/%d/recursos" % aula_id)

func aula_ranking_async(aula_id: int) -> Array:
	return await get_async("Aulas/%d/ranking-companeros" % aula_id)

func aula_vincular_async(codigo: String) -> Array:
	return await post_json_async("Aulas/vincular", {"codigoAcceso": codigo})

func aula_salir_async(aula_id: int) -> Array:
	return await _send(HTTPClient.METHOD_DELETE, "Aulas/%d/salir" % aula_id)
