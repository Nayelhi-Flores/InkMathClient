class_name ItemVisual
extends RefCounted
## Texturas de los ítems (los mismos de la tienda) por nombre corto.
## IMPORTANTE: ajusta FILES a los nombres reales de tu carpeta res://assets/items/.
## Si un archivo no existe, se dibuja un círculo de color en su lugar (el juego no falla).

const DIR := "res://assets/items/"
const FILES := {
	"estrella": "items1.png",
	"ancla": "items2.png",
	"botella": "items3.png",
	"concha_luna": "items4.png",
	"concha_cono": "items5.png",
	"vieira": "items6.png",
	"concha_almeja": "items7.png",
	"almeja": "items8.png",
	"algas": "items9.png",
}

static var _cache: Dictionary = {}


static func texture(slug: String) -> Texture2D:
	if _cache.has(slug):
		return _cache[slug]
	var tex: Texture2D = null
	var f = FILES.get(slug)
	if f != null and ResourceLoader.exists(DIR + str(f)):
		tex = load(DIR + str(f)) as Texture2D
	_cache[slug] = tex
	return tex


static func fallback_color(slug: String) -> Color:
	return Color.from_hsv(float(absi(hash(slug)) % 360) / 360.0, 0.55, 0.92)
