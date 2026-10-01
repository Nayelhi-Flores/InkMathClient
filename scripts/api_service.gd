extends Node

# Variables para almacenar el JWT activo y la URL base de la API
var auth_token: String = ""
var base_url: String = "https://localhost:7222/api/"

func _ready() -> void:
	if OS.has_feature("web"):
		var origen = JavaScriptBridge.eval("window.location.origin")
		if origen != null and str(origen).begins_with("http"):
			base_url = str(origen) + "/api/"
		print("[ApiService] 🌐 Ejecutando en entorno Web. Base URL configurada a: ", base_url)
	else:
		print("[ApiService] 💻 Ejecutando en Desktop/Editor. Base URL configurada a: ", base_url)

	obtener_token_del_navegador()

# Obtiene el JWT almacenado bajo la clave 'token' en el localStorage del navegador
func obtener_token_del_navegador() -> void:
	if OS.has_feature("web"):
		var token_js = JavaScriptBridge.eval("localStorage.getItem('token');")
		
		if token_js != null and str(token_js) != "null" and str(token_js).strip_edges() != "":
			auth_token = str(token_js)
			print("[ApiService] 🔑 Token recuperado con éxito desde la clave 'token' en localStorage.")
		else:
			auth_token = ""
			print("[ApiService] ⚠️ La clave 'token' no existe en localStorage o está vacía.")
	else:
		print("[ApiService] ℹ️ No se ejecuta en navegador Web; localStorage no está disponible.")

# Extrae el ID del estudiante desde 'usuario_id' en localStorage o decodificando el JWT
func obtener_estudiante_id_del_navegador() -> int:
	if OS.has_feature("web"):
		# 1. Intentar lectura directa de 'usuario_id' en localStorage
		var id_js = JavaScriptBridge.eval("localStorage.getItem('usuario_id');")
		if id_js != null and str(id_js) != "null" and str(id_js).strip_edges() != "":
			var id_parsed = int(str(id_js))
			if id_parsed > 0:
				print("[ApiService] 👤 ID de usuario obtenido directamente de 'usuario_id' en localStorage: ", id_parsed)
				return id_parsed
		
		print("[ApiService] ⚠️ No se encontró 'usuario_id' directo. Intentando decodificar desde el payload del JWT...")
		
		# 2. Respaldo: Decodificar el ID directamente desde la estructura del JWT
		if not auth_token.is_empty():
			var id_jwt = _extraer_id_desde_jwt(auth_token)
			if id_jwt > 0:
				print("[ApiService] 🔑 ID de usuario decodificado con éxito desde el JWT: ", id_jwt)
				return id_jwt
			else:
				print("[ApiService] ❌ No se pudo extraer un ID válido del payload del JWT.")
		else:
			print("[ApiService] ❌ Imposible decodificar JWT: auth_token está vacío.")

	print("[ApiService] 🚨 Imposible recuperar ID de usuario (Entorno no-Web o credenciales no encontradas).")
	return 0 # Devuelve 0 para evidenciar el error real en lugar de falsear con un ID por defecto

# Función auxiliar para parsear y decodificar el payload Base64URL del JWT
func _extraer_id_desde_jwt(jwt: String) -> int:
	var partes = jwt.split(".")
	if partes.size() < 2:
		print("[ApiService] ❌ Estructura de JWT inválida (se esperaban secciones divididas por puntos).")
		return 0
		
	var payload_b64 = partes[1]
	while payload_b64.length() % 4 != 0:
		payload_b64 += "="
	payload_b64 = payload_b64.replace("-", "+").replace("_", "/")
	
	var json_bytes = Marshalls.base64_to_raw(payload_b64)
	var json_text = json_bytes.get_string_from_utf8()
	
	var json = JSON.new()
	if json.parse(json_text) == OK:
		var data: Dictionary = json.data
		# Claims de identidad habituales emitidos por backend .NET
		if data.has("nameid"):
			return int(data["nameid"])
		elif data.has("sub"):
			return int(data["sub"])
		elif data.has("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"):
			return int(data["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"])
			
	print("[ApiService] ❌ Ningún claim de ID estándar encontrado en la carga útil del JWT.")
	return 0

# Petición GET asíncrona no bloqueante
func get_async(endpoint: String) -> Array:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var headers = [
		"Content-Type: application/json",
		"Accept: application/json"
	]
	
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer " + auth_token)
		print("[ApiService] 🔒 Petición adjuntando encabezado 'Authorization: Bearer'.")
	else:
		print("[ApiService] ⚠️ Petición enviada sin encabezado de autorización (Token ausente).")
		
	var full_url = base_url + endpoint
	print("[ApiService] 🚀 Enviando petición GET a: ", full_url)
	
	var err = http_request.request(full_url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		print("[ApiService] ❌ Error al iniciar la solicitud HTTPRequest: ", err)
		http_request.queue_free()
		return [500, "{}"]
		
	var result = await http_request.request_completed
	var response_code = result[1]
	var body = result[3].get_string_from_utf8()
	
	http_request.queue_free()
	print("[ApiService] 📩 Respuesta GET recibida con estado HTTP: [", response_code, "]")
	return [response_code, body]

# Petición POST asíncrona no bloqueante
func post_json_async(endpoint: String, payload: Dictionary) -> Array:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var headers = [
		"Content-Type: application/json",
		"Accept: application/json"
	]
	
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer " + auth_token)
		
	var full_url = base_url + endpoint
	var json_body = JSON.stringify(payload)
	print("[ApiService] 🚀 Enviando petición POST a: ", full_url)
	
	var err = http_request.request(full_url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		print("[ApiService] ❌ Error al iniciar la solicitud HTTPRequest POST: ", err)
		http_request.queue_free()
		return [500, "{}"]
		
	var result = await http_request.request_completed
	var response_code = result[1]
	var body = result[3].get_string_from_utf8()
	
	http_request.queue_free()
	print("[ApiService] 📩 Respuesta POST recibida con estado HTTP: [", response_code, "]")
	return [response_code, body]

# --- LLAMADAS A ENDPOINTS DE LA API ---

func obtener_mapa_niveles_async(estudiante_id: int) -> Array:
	return await get_async("Niveles/estudiante/" + str(estudiante_id))

func obtener_preguntas_test_async(test_id: int, limite_preguntas: int = 15) -> Array:
	return await get_async("Evaluaciones/test/" + str(test_id) + "?limitePreguntas=" + str(limite_preguntas))

func registrar_resultado_test_async(intento_dto: Dictionary) -> Array:
	return await post_json_async("Evaluaciones/resultados", intento_dto)
