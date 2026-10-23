extends Node

const MUSIC_LEVEL := preload("res://assets/audio/Nivel-1-Bucle.mp3")
const SFX_POINTS := preload("res://assets/audio/puntos.wav")
const SFX_GAMEOVER := preload("res://assets/audio/GameOver.mp3")

const MUSIC_DB := -10.0
const SILENT_DB := -40.0

var _music: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)

	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")


func play_music(volume_db: float = MUSIC_DB) -> void:
	if _music.playing and _music.stream == MUSIC_LEVEL:
		_fade_music(volume_db, 0.4)   # ya suena: solo ajusta volumen, no reinicia
		return
	_music.stream = MUSIC_LEVEL
	_music.volume_db = SILENT_DB
	_music.play()
	_fade_music(volume_db, 0.8)


func stop_music(fade: float = 0.4) -> void:
	if not _music.playing:
		return
	_fade_music(SILENT_DB, fade)
	await get_tree().create_timer(fade).timeout
	if _music.volume_db <= SILENT_DB + 0.5:
		_music.stop()


func play_result(positive: bool) -> void:
	stop_music(0.2)
	_sfx.stream = SFX_POINTS if positive else SFX_GAMEOVER
	_sfx.play()


func _fade_music(target_db: float, time: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_music, "volume_db", target_db, time)
