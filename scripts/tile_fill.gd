class_name TileFill
extends TileMapLayer
## Extiende lo que pintaste para cubrir TODA la pantalla, sin importar su tamaño:
##  - repite una franja de columnas hacia la izquierda y la derecha
##  - repite la última fila hacia abajo
## Colócalo como hijo directo de la raíz de la escena (no dentro de "Column").

@export var repeat_x := true
@export var extend_down := true
@export var margin_cells := 2
## Escribe en la consola del navegador lo que hace el script (desactívalo cuando todo funcione)
@export var debug_log := true

@export_group("Franja que se repite (opcional)")
## Columna (en celdas) donde empieza la franja base. Con ancho 0 se repite todo lo pintado.
@export var pattern_x := 0
@export var pattern_width := 0

@export_group("Alineación con la arena (opcional)")
## Nodo "Arena" de la escena. Si se asigna, la capa se desplaza para que el suelo coincida con el de la arena.
@export var arena_path: NodePath
## Fila de celdas donde empieza la superficie del suelo (se ve en el editor de TileMap).
@export var ground_row := 0
## Igual a GROUND_PX en fisica.gd
@export var ground_margin_px := 14.0

var _pattern: Dictionary = {}   # Vector2i -> [source, atlas, alternativa]
var _rect := Rect2i()
var _px := 0
var _pw := 0
var _arena: Control


var _ready_ok := false
var _warned := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel art nítido
	_arena = get_node_or_null(arena_path) as Control
	get_viewport().size_changed.connect(_refresh)
	if _arena:
		_arena.resized.connect(_refresh)
	_refresh.call_deferred()


# Lee lo pintado la primera vez que hace falta (por si la capa aún no estaba lista en _ready)
func _setup() -> bool:
	if _ready_ok:
		return true
	_rect = get_used_rect()
	if _rect.size.x <= 0 or tile_set == null:
		return false

	for y in range(_rect.position.y, _rect.end.y):
		for x in range(_rect.position.x, _rect.end.x):
			var c := Vector2i(x, y)
			var sid := get_cell_source_id(c)
			if sid != -1:
				_pattern[c] = [sid, get_cell_atlas_coords(c), get_cell_alternative_tile(c)]

	if pattern_width > 0:
		_px = pattern_x
		_pw = pattern_width
	else:
		_px = _rect.position.x
		_pw = _rect.size.x
	_ready_ok = true
	return true


func _src_x(x: int) -> int:
	if x >= _rect.position.x and x < _rect.end.x:
		return x
	return _px + posmod(x - _px, _pw)


func _copy(src: Vector2i, dst: Vector2i) -> void:
	if _pattern.has(src):
		var d: Array = _pattern[src]
		set_cell(dst, d[0], d[1], d[2])


func _align_to_arena() -> void:
	if _arena == null or tile_set == null:
		return
	var ground_y := _arena.global_position.y + _arena.size.y - ground_margin_px
	var layer_ground := float(ground_row * tile_set.tile_size.y) * global_scale.y
	global_position.y = ground_y - layer_ground


func _refresh() -> void:
	if not _setup():
		if not _warned:
			_warned = true
			push_warning("[TileFill] La capa '%s' no tiene celdas pintadas o no tiene TileSet (¿el script está en la capa equivocada?)." % name)
		return
	_align_to_arena()

	var ts := Vector2(tile_set.tile_size)
	var vr := get_viewport_rect()
	var tl := to_local(vr.position)     # esquina superior izquierda de la pantalla, en coordenadas de esta capa
	var br := to_local(vr.end)          # esquina inferior derecha
	var x_min := floori(tl.x / ts.x) - margin_cells
	var x_max := ceili(br.x / ts.x) + margin_cells
	var y_max := ceili(br.y / ts.y) + margin_cells

	if debug_log:
		print("[TileFill] %s | pintado=%s | patrón=%d..%d | pantalla=%s | columnas %d a %d | filas hasta %d"
				% [name, _rect, _px, _px + _pw - 1, vr.size, x_min, x_max, y_max])

	if repeat_x:
		for x in range(x_min, x_max + 1):
			if x >= _rect.position.x and x < _rect.end.x:
				continue
			var sx := _src_x(x)
			for y in range(_rect.position.y, _rect.end.y):
				_copy(Vector2i(sx, y), Vector2i(x, y))

	if extend_down:
		var last := _rect.end.y - 1
		var xa := x_min if repeat_x else _rect.position.x
		var xb := x_max if repeat_x else _rect.end.x - 1
		for x in range(xa, xb + 1):
			var sx2 := _src_x(x)
			for y in range(_rect.end.y, y_max + 1):
				_copy(Vector2i(sx2, last), Vector2i(x, y))
