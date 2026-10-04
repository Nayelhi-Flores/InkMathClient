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
