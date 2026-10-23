extends Control
## Modo "Cañón de Burbujas" (RF-12): ángulo y velocidad -> trayectoria parabólica.
## La trayectoria se dibuja con las mismas fórmulas que calculan el alcance:
##   x = x0 + v·cos(θ)·t     y = v·sen(θ)·t − ½·g·t²

@export var menu_scene: String = "res://scenes/mapa_niveles.tscn"
@export_range(0.4, 1.0) var column_ratio := 0.7
@export var banner_good: Texture2D
@export var banner_bad: Texture2D

const G := 9.8
const WORLD_W := 42.0        # metros visibles a lo ancho
const WORLD_H_MIN := 22.0    # metros mínimos visibles a lo alto
const ORIGIN_X := 2.0        # posición del cañón (m)
const TARGET_HALF := 1.5     # semiancho del cofre (m): tolerancia de acierto
const MAX_ATTEMPTS := 3
const TIME_SCALE := 1.5      # la simulación va 1.5x para que sea ágil
const SAMPLES := 48
const GROUND_PX := 14.0
const MODES := ["VELOCIDAD", "VELOCIDAD", "ANGULO", "ANGULO", "LIBRE"]
const ROUNDS := 5

var _round := 0
var _mode := ""
var _attempts := 0
var _fixed_angle := 45
var _fixed_speed := 12
var _sol_v := 0.0
var _sol_a := 45.0
var _target_x := 20.0
var _dist := 18.0

var _shots: Array = []       # intentos previos {v, a}
var _cur_v := 0.0
var _cur_a := 0.0
var _t := 0.0
var _flying := false
var _round_done := false
var _round_stars := 0
var _stars_total := 0
var _solved := 0
var _help_open := false
var _info_text := ""

var _paused := false
var _pause: PauseOverlay

@onready var column: Control = _fn("Column")
@onready var round_label: Label = _fn("RoundLabel")
@onready var attempts_label: Label = _fn("AttemptsLabel")
@onready var back_btn: Button = _fn("BackBtn")
@onready var pause_btn: Button = _fn("PauseBtn")
@onready var info_label: Label = _fn("InfoLabel")
@onready var arena: Control = _fn("Arena")
@onready var angle_slider: HSlider = _fn("AngleSlider")
@onready var angle_value: Label = _fn("AngleValue")
@onready var speed_slider: HSlider = _fn("SpeedSlider")
@onready var speed_value: Label = _fn("SpeedValue")
@onready var feedback_label: Label = _fn("FeedbackLabel")
@onready var help_btn: Button = _fn("HelpBtn")
@onready var launch_btn: Button = _fn("LaunchBtn")
@onready var final_modal: Control = _fn("FeedbackPanel")
@onready var modal_title: Label = _fn("LabelStatusTitle")
@onready var modal_accuracy: Label = _fn("LabelAccuracy2")
@onready var modal_coins: Label = _fn("LabelCoins")
@onready var modal_banner: TextureRect = _fn("BannerIllustration")
@onready var btn_home: Button = _fn("BtnHome")
@onready var btn_retry: Button = _fn("BtnRetry")
@onready var btn_next: Button = _fn("BtnNext")


func _fn(path: String) -> Node:
	var n := get_node_or_null(path)
	if n == null:
		n = find_child(path.get_file(), true, false)
	if n == null:
		push_error("No se encontró el nodo '%s' (revisa nombre/ruta)." % path)
	return n


func _ready() -> void:
	randomize()

	_pause = PauseOverlay.new()
	add_child(_pause)
	_pause.resumed.connect(func(): _paused = false)
	_pause.exit_requested.connect(_go_menu)
	pause_btn.pressed.connect(_abrir_pausa)

	angle_slider.min_value = 5
	angle_slider.max_value = 85
	angle_slider.step = 1
	speed_slider.min_value = 5
	speed_slider.max_value = 20
	speed_slider.step = 1
	angle_slider.value_changed.connect(_on_slider_changed)
	speed_slider.value_changed.connect(_on_slider_changed)

	launch_btn.pressed.connect(_on_launch_pressed)
	help_btn.pressed.connect(_on_help_pressed)
	back_btn.pressed.connect(_go_menu)
	btn_home.pressed.connect(_go_menu)
	btn_retry.pressed.connect(func(): get_tree().reload_current_scene())
	btn_next.hide()
	final_modal.hide()

	arena.clip_contents = true
	arena.draw.connect(_draw_arena)
	arena.resized.connect(arena.queue_redraw)
	get_viewport().size_changed.connect(_apply_column)
	_apply_column()

	AudioManager.play_music(-14.0)
	_new_round()


func _apply_column() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		return
	var w := minf(vp.x, vp.y * column_ratio)
	var m := (vp.x - w) / 2.0 / vp.x
	column.anchor_left = m
	column.anchor_right = 1.0 - m
	column.offset_left = 0
	column.offset_right = 0


# ---------- FÍSICA ----------
func _pos(t: float, v: float, a: float) -> Vector2:
	return Vector2(ORIGIN_X + v * cos(a) * t, v * sin(a) * t - 0.5 * G * t * t)


func _flight_time(v: float, a: float) -> float:
	return 2.0 * v * sin(a) / G


func _range(v: float, a: float) -> float:
	return v * v * sin(2.0 * a) / G


# ---------- RONDAS ----------
func _new_round() -> void:
	_mode = MODES[_round]
	_attempts = 0
	_shots.clear()
	_round_done = false
	_round_stars = 0
	_help_open = false
	_flying = false
	_generate_target()

	angle_slider.editable = _mode != "VELOCIDAD"
	speed_slider.editable = _mode != "ANGULO"
	angle_slider.value = _fixed_angle if _mode == "VELOCIDAD" else 45
	speed_slider.value = _fixed_speed if _mode == "ANGULO" else 12

	match _mode:
		"VELOCIDAD":
			_info_text = "El cañón está fijo a %d°. Elige la velocidad para llegar al cofre, a %.1f m." % [_fixed_angle, _dist]
		"ANGULO":
			_info_text = "La velocidad es %d m/s. Elige el ángulo para llegar al cofre, a %.1f m." % [_fixed_speed, _dist]
		_:
			_info_text = "¡Tú decides! Combina ángulo y velocidad para llegar al cofre, a %.1f m." % _dist

	info_label.text = _info_text
	help_btn.text = "Fórmula"
	feedback_label.text = ""
	round_label.text = "Cofre %d/%d" % [_round + 1, ROUNDS]
	launch_btn.text = "¡Lanzar!"
	launch_btn.disabled = false
	_update_attempts()
	_on_slider_changed(0.0)
	arena.queue_redraw()


# Genera el cofre a partir de una solución entera: siempre existe una respuesta exacta.
func _generate_target() -> void:
	for i in 60:
		match _mode:
			"VELOCIDAD":
				_fixed_angle = [30, 45, 60][randi() % 3]
				_sol_a = float(_fixed_angle)
				_sol_v = float(randi_range(8, 20))
			"ANGULO":
				_fixed_speed = randi_range(10, 20)
				_sol_v = float(_fixed_speed)
				_sol_a = float(randi_range(15, 75))
			_:
				_sol_a = 45.0
				_sol_v = 0.0
		if _mode == "LIBRE":
			_dist = snappedf(randf_range(10.0, 36.0), 0.1)
			_sol_v = sqrt(_dist * G)
			break
		_dist = snappedf(_range(_sol_v, deg_to_rad(_sol_a)), 0.1)
		if _dist >= 6.0 and _dist <= 38.0:
			break
	_target_x = ORIGIN_X + _dist


func _solution_text() -> String:
	match _mode:
		"VELOCIDAD":
			return "Una solución: %.1f m/s a %d°." % [snappedf(_sol_v, 0.1), _fixed_angle]
		"ANGULO":
			return "Una solución: %d° (también %d°) a %d m/s." % [int(_sol_a), 90 - int(_sol_a), _fixed_speed]
	return "Por ejemplo: 45° con %.1f m/s." % snappedf(_sol_v, 0.1)


func _update_attempts() -> void:
	attempts_label.text = "Intentos: %d/%d" % [_attempts, MAX_ATTEMPTS]


func _on_slider_changed(_v: float) -> void:
	angle_value.text = "%d°" % int(angle_slider.value)
	speed_value.text = "%d m/s" % int(speed_slider.value)
	arena.queue_redraw()


func _on_help_pressed() -> void:
	_help_open = not _help_open
	if _help_open:
		info_label.text = "Alcance = v² · sen(2θ) ÷ g, con g = 9,8 m/s². A 45° el alcance es el máximo; θ y 90° − θ llegan igual de lejos."
		help_btn.text = "Ocultar"
	else:
		info_label.text = _info_text
		help_btn.text = "Fórmula"


# ---------- LANZAMIENTO ----------
func _on_launch_pressed() -> void:
	if _paused or _flying:
		return
	if _round_done:
		_next_round()
		return
	_cur_v = speed_slider.value
	_cur_a = deg_to_rad(angle_slider.value)
	_attempts += 1
	_t = 0.0
	_flying = true
	launch_btn.disabled = true
	angle_slider.editable = false
	speed_slider.editable = false
	feedback_label.text = ""
	_update_attempts()


func _process(delta: float) -> void:
	if not _flying or _paused:
		return
	_t += delta * TIME_SCALE
	var total := _flight_time(_cur_v, _cur_a)
	if _t >= total:
		_t = total
		_flying = false
		_land()
	arena.queue_redraw()


func _land() -> void:
	var rng := _range(_cur_v, _cur_a)
	var diff := (ORIGIN_X + rng) - _target_x
	var apex := pow(_cur_v * sin(_cur_a), 2.0) / (2.0 * G)
	var datos := "Alcance %.1f m · Altura máx. %.1f m · Tiempo %.1f s" % [rng, apex, _flight_time(_cur_v, _cur_a)]
	_shots.append({"v": _cur_v, "a": _cur_a})

	if absf(diff) <= TARGET_HALF:
		_round_stars = MAX_ATTEMPTS + 1 - _attempts
		_stars_total += _round_stars
		_solved += 1
		_round_done = true
		feedback_label.text = "¡Dio en el cofre! %s" % datos
	elif _attempts >= MAX_ATTEMPTS:
		_round_done = true
		feedback_label.text = "Sin intentos. %s\n%s" % [datos, _solution_text()]
	else:
		var pista := "Se quedó corto por %.1f m." % absf(diff) if diff < 0.0 else "Se pasó por %.1f m." % diff
		feedback_label.text = "%s %s" % [pista, datos]

	launch_btn.disabled = false
	if _round_done:
		launch_btn.text = "Siguiente" if _round < ROUNDS - 1 else "Ver resultado"
	else:
		angle_slider.editable = _mode != "VELOCIDAD"
		speed_slider.editable = _mode != "ANGULO"


func _next_round() -> void:
	_round += 1
	if _round >= ROUNDS:
		_finish()
	else:
		_new_round()


func _finish() -> void:
	var pct := float(_solved) / ROUNDS
	var positive := pct >= 0.5
	pause_btn.hide()
	modal_title.text = "¡Buen trabajo!" if positive else "¡Sigue practicando!"
	modal_accuracy.text = "Cofres: %d/%d" % [_solved, ROUNDS]
	modal_coins.text = "Estrellas: %d/%d · Modo práctica" % [_stars_total, ROUNDS * MAX_ATTEMPTS]
	var tex := banner_good if positive else banner_bad
	if tex != null and modal_banner != null:
		modal_banner.texture = tex
	AudioManager.play_result(positive)
	final_modal.show()


# ---------- DIBUJO DE LA ARENA (coordenadas del mundo en metros -> píxeles) ----------
func _scale() -> float:
	return minf(arena.size.x / WORLD_W, arena.size.y / WORLD_H_MIN)


func _to_px(p: Vector2) -> Vector2:
	var s := _scale()
	var x_off := (arena.size.x - WORLD_W * s) / 2.0
	return Vector2(x_off + p.x * s, arena.size.y - GROUND_PX - p.y * s)


func _draw_path(v: float, a: float, until: float, color: Color, width: float) -> void:
	if until <= 0.0:
		return
	var pts := PackedVector2Array()
	for i in range(SAMPLES + 1):
		pts.append(_to_px(_pos(until * float(i) / SAMPLES, v, a)))
	arena.draw_polyline(pts, color, width, true)


func _draw_arena() -> void:
	var s := _scale()
	var sz := arena.size
	var font := arena.get_theme_default_font()

	arena.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.04, 0.22, 0.42, 0.35))
	arena.draw_rect(Rect2(0, sz.y - GROUND_PX, sz.x, GROUND_PX), Color("e8c27a"))

	# Regla: distancia al cañón cada 5 m (etiqueta cada 10 m)
	var k := 0
	while ORIGIN_X + k * 5.0 <= WORLD_W:
		var p := _to_px(Vector2(ORIGIN_X + k * 5.0, 0.0))
		arena.draw_line(p, p + Vector2(0, 5), Color("8a5a1a"), 1.0)
		if k % 2 == 0:
			arena.draw_string(font, p + Vector2(-6, GROUND_PX - 1), str(k * 5), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("5b3a0a"))
		k += 1

	# Cofre (objetivo) y zona de acierto
	var tp := _to_px(Vector2(_target_x, 0.0))
	var w := TARGET_HALF * 2.0 * s
	var h := maxf(10.0, w * 0.55)
	arena.draw_line(tp + Vector2(-w / 2.0, 0), tp + Vector2(w / 2.0, 0), Color("4ade80"), 4.0)
	arena.draw_rect(Rect2(tp.x - w / 2.0, tp.y - h, w, h), Color("8a4b14"))
	arena.draw_rect(Rect2(tp.x - w / 2.0, tp.y - h, w, h * 0.35), Color("fbbf24"))
	arena.draw_string(font, tp + Vector2(-18, -h - 4), "%.1f m" % _dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	# Intentos previos, solución (si se agotaron) y vuelo actual
	for shot in _shots:
		_draw_path(shot.v, shot.a, _flight_time(shot.v, shot.a), Color(1, 1, 1, 0.4), 2.0)
	if _round_done and _round_stars == 0:
		var sv := _sol_v
		_draw_path(sv, deg_to_rad(_sol_a if _mode != "VELOCIDAD" else float(_fixed_angle)),
				_flight_time(sv, deg_to_rad(_sol_a if _mode != "VELOCIDAD" else float(_fixed_angle))),
				Color(0.3, 1.0, 0.45, 0.7), 2.0)
	if _flying:
		_draw_path(_cur_v, _cur_a, _t, Color("fde047"), 3.0)
		arena.draw_circle(_to_px(_pos(_t, _cur_v, _cur_a)), maxf(4.0, 0.45 * s), Color("e0f2fe"))

	# Cañón: el tubo sigue el ángulo elegido
	var o := _to_px(Vector2(ORIGIN_X, 0.0))
	var ang := _cur_a if _flying else deg_to_rad(angle_slider.value)
	var tip := o + Vector2(cos(ang), -sin(ang)) * (2.4 * s)
	arena.draw_line(o, tip, Color("334155"), maxf(6.0, 0.8 * s), true)
	arena.draw_circle(o, maxf(8.0, 1.0 * s), Color("1e293b"))


# ---------- PAUSA / NAVEGACIÓN ----------
func _abrir_pausa() -> void:
	if _paused or final_modal.visible:
		return
	_paused = true
	_pause.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_abrir_pausa()


func _go_menu() -> void:
	get_tree().change_scene_to_file(menu_scene)
