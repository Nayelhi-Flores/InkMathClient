class_name VisualRenderer
extends Control
## Dibuja el contenido visual de una pregunta (JSON de preguntas_test.contenido_visual).
## Tipos: conteo, grupos, comparar, posicion, tamano, patron, figuras, linea, reloj.
## Es responsivo: todo se calcula a partir del tamaño actual del control.

const INK := Color("2B3A4A")
const COLORS := {
	"rojo": Color("EF4444"), "azul": Color("3B82F6"),
	"verde": Color("22C55E"), "amarillo": Color("FACC15"),
}

var _data: Dictionary = {}
var _bg: StyleBoxFlat
var _panel: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(0, 190)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bg = StyleBoxFlat.new()
	_bg.bg_color = Color("EBF8FF")
	_bg.set_corner_radius_all(16)
	_panel = StyleBoxFlat.new()
	_panel.bg_color = Color.WHITE
	_panel.set_corner_radius_all(12)


func _ready() -> void:
	resized.connect(queue_redraw)


func set_data(d: Dictionary) -> void:
	_data = d
	queue_redraw()


func _draw() -> void:
	draw_style_box(_bg, Rect2(Vector2.ZERO, size))
	match str(_data.get("tipo", "")):
		"conteo": _draw_conteo()
		"grupos": _draw_grupos()
		"comparar": _draw_comparar()
		"posicion": _draw_posicion()
		"tamano": _draw_tamano()
		"patron": _draw_patron()
		"figuras": _draw_figuras()
		"linea": _draw_linea()
		"reloj": _draw_reloj()


# ---------- Utilidades ----------
func _item(slug: String, center: Vector2, box: Vector2) -> void:
	var tex := ItemVisual.texture(slug)
	if tex == null:
		draw_circle(center, minf(box.x, box.y) * 0.4, ItemVisual.fallback_color(slug))
		return
	var ts := tex.get_size()
	var sc := minf(box.x / ts.x, box.y / ts.y)
	var s := ts * sc
	draw_texture_rect(tex, Rect2(center - s / 2.0, s), false)


func _item_stretched(slug: String, rect: Rect2) -> void:
	var tex := ItemVisual.texture(slug)
	if tex == null:
		draw_rect(rect, ItemVisual.fallback_color(slug))
		return
	draw_texture_rect(tex, rect, false)


func _text(txt: String, rect: Rect2, rel: float, col: Color = Color(INK, 0.5)) -> void:
	var font := get_theme_default_font()
	var fs := maxi(10, int(rect.size.y * rel))
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + fs * 0.35),
			txt, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fs, col)


# Reparte n ítems en una cuadrícula dentro de rect
func _grid(slug: String, n: int, rect: Rect2) -> void:
	if n <= 0:
		draw_rect(rect.grow(-6), Color(INK, 0.25), false, 2.0)
		_text("0", rect, 0.4)
		return
	var cols := clampi(int(ceil(sqrt(n * rect.size.x / maxf(rect.size.y, 1.0)))), 1, n)
	var rows := int(ceil(float(n) / cols))
	var cell := minf(rect.size.x / cols, rect.size.y / rows)
	var total := Vector2(cell * cols, cell * rows)
	var origin := rect.position + (rect.size - total) / 2.0
	for i in n:
		var r := floori(float(i) / cols)
		var c := i % cols
		_item(slug, origin + Vector2((c + 0.5) * cell, (r + 0.5) * cell), Vector2(cell, cell) * 0.85)


func _panels(groups: Array) -> void:
	var n := groups.size()
	if n == 0:
		return
	var gap := 10.0
	var w := (size.x - gap * (n + 1)) / n
	for i in n:
		var g: Dictionary = groups[i]
		var rect := Rect2(gap + i * (w + gap), gap, w, size.y - gap * 2.0)
		draw_style_box(_panel, rect)
		_grid(str(g.get("item", "")), int(g.get("cantidad", 0)), rect.grow(-8))


# ---------- Tipos ----------
func _draw_conteo() -> void:
	_grid(str(_data.get("item", "")), int(_data.get("cantidad", 0)), Rect2(Vector2.ZERO, size).grow(-12))


func _draw_grupos() -> void:
	_panels(_data.get("grupos", []))


func _draw_comparar() -> void:
	var a: Dictionary = _data.get("a", {})
	var b: Dictionary = _data.get("b", {})
	if not _data.get("parear", false):
		_panels([a, b])
		return
	var na := int(a.get("cantidad", 0))
	var nb := int(b.get("cantidad", 0))
	var rows := maxi(maxi(na, nb), 1)
	var row_h := minf((size.y - 24.0) / rows, size.x * 0.16)
	var top := (size.y - row_h * rows) / 2.0
	var xa := size.x * 0.3
	var xb := size.x * 0.7
	var sz := Vector2(row_h, row_h) * 0.85
	for i in rows:
		var y := top + (i + 0.5) * row_h
		if i < na:
			_item(str(a.get("item", "")), Vector2(xa, y), sz)
		if i < nb:
			_item(str(b.get("item", "")), Vector2(xb, y), sz)
		if i < na and i < nb:
			draw_line(Vector2(xa + sz.x / 2.0, y), Vector2(xb - sz.x / 2.0, y), Color(INK, 0.35), 2.0, true)


func _offset(lugar: String, ref_size: Vector2, u: float) -> Vector2:
	var half := ref_size / 2.0
	match lugar:
		"arriba": return Vector2(0, -(half.y + u * 1.05))
		"abajo": return Vector2(0, half.y + u * 1.05)
		"encima": return Vector2(0, -(half.y + u * 0.5))
		"debajo": return Vector2(0, half.y + u * 0.5)
		"adentro": return Vector2.ZERO
		"afuera": return Vector2(-(half.x + u * 1.3), 0)
		"borde": return Vector2(half.x, 0)
		"cerca": return Vector2(half.x + u * 0.6, 0)
		"lejos": return Vector2(-(half.x + u * 1.7), 0)
		"izquierda": return Vector2(-(half.x + u * 0.85), 0)
		"derecha": return Vector2(half.x + u * 0.85, 0)
		"delante": return Vector2(half.x * 0.55, half.y * 0.7)
		"detras": return Vector2(-half.x * 0.55, -half.y * 0.7)
	return Vector2.ZERO


func _draw_posicion() -> void:
	var ref := str(_data.get("ref", "caja"))
	var items: Array = _data.get("items", [])
	var u := minf(size.x / 6.0, size.y / 4.4)
	var c := size / 2.0
	var ref_size := Vector2(u * 1.5, u * 1.2) if ref == "caja" else Vector2(u, u)
	var item_box := Vector2(u, u)

	for it in items:      # lo que está DETRÁS se dibuja antes
		if str(it.get("lugar", "")) == "detras":
			_item(str(it.get("item", "")), c + _offset("detras", ref_size, u), item_box)

	if ref == "caja":
		var r := Rect2(c - ref_size / 2.0, ref_size)
		draw_rect(r, Color("CBD5E1", 0.5))
		draw_rect(r, Color("64748B"), false, 4.0)
	else:
		_item(ref, c, ref_size)

	for it in items:
		var l := str(it.get("lugar", ""))
		if l != "detras":
			_item(str(it.get("item", "")), c + _offset(l, ref_size, u), item_box)


func _draw_tamano() -> void:
	var items: Array = _data.get("items", [])
	var n := items.size()
	if n == 0:
		return
	var eje := str(_data.get("eje", "ambos"))
	var u := minf(size.x / (n + 0.5), size.y * 0.55) * 0.65
	var base_y := size.y * 0.85
	draw_line(Vector2(8, base_y), Vector2(size.x - 8, base_y), Color(INK, 0.25), 3.0)
	for i in n:
		var it: Dictionary = items[i]
		var e := float(it.get("escala", 1.0))
		var cx := size.x * (i + 0.5) / n
		var w := u
		var h := u
		match eje:
			"alto": h = u * e
			"ancho": w = u * e
			_:
				w = u * e
				h = u * e
		if eje == "ambos":
			_item(str(it.get("item", "")), Vector2(cx, base_y - h / 2.0), Vector2(w, h))
		else:
			_item_stretched(str(it.get("item", "")), Rect2(cx - w / 2.0, base_y - h, w, h))


func _draw_patron() -> void:
	var seq: Array = _data.get("secuencia", [])
	var n := seq.size()
	if n == 0:
		return
	var slot := minf(size.x * 0.94 / n, size.y * 0.7)
	var x0 := (size.x - slot * n) / 2.0
	var y0 := (size.y - slot) / 2.0
	for i in n:
		var r := Rect2(x0 + i * slot, y0, slot, slot).grow(-3)
		var s := str(seq[i])
		if s == "?":
			draw_rect(r, Color("FEF3C7"))
			draw_rect(r, Color("F59E0B"), false, 3.0)
			_text("?", r, 0.7, Color("D97706"))
		else:
			draw_style_box(_panel, r)
			_item(s, r.get_center(), r.size * 0.8)


func _draw_figuras() -> void:
	var figs: Array = _data.get("figuras", [])
	var n := figs.size()
	if n == 0:
		return
	var cell := minf(size.x * 0.9 / n, size.y * 0.75)
	for i in n:
		var f: Dictionary = figs[i]
		var col: Color = COLORS.get(str(f.get("color", "azul")), Color("3B82F6"))
		var s := cell * 0.62 * float(f.get("escala", 1.0))
		var ctr := Vector2(size.x * (i + 0.5) / n, size.y / 2.0)
		var edge := col.darkened(0.3)
		match str(f.get("forma", "circulo")):
			"circulo":
				draw_circle(ctr, s / 2.0, col)
				draw_arc(ctr, s / 2.0, 0.0, TAU, 40, edge, 3.0, true)
			"cuadrado":
				var r := Rect2(ctr - Vector2(s, s) / 2.0, Vector2(s, s))
				draw_rect(r, col)
				draw_rect(r, edge, false, 3.0)
			"rectangulo":
				var sz := Vector2(s * 1.3, s * 0.75)
				var r2 := Rect2(ctr - sz / 2.0, sz)
				draw_rect(r2, col)
				draw_rect(r2, edge, false, 3.0)
			"triangulo":
				var pts := PackedVector2Array([
					ctr + Vector2(0, -s / 2.0), ctr + Vector2(s / 2.0, s / 2.0), ctr + Vector2(-s / 2.0, s / 2.0)])
				draw_colored_polygon(pts, col)
				pts.append(pts[0])
				draw_polyline(pts, edge, 3.0, true)


func _draw_linea() -> void:
	var col := Color("0984C6")
	var m := size * 0.14
	match str(_data.get("clase", "horizontal")):
		"horizontal":
			draw_line(Vector2(m.x, size.y / 2.0), Vector2(size.x - m.x, size.y / 2.0), col, 8.0, true)
		"vertical":
			draw_line(Vector2(size.x / 2.0, m.y), Vector2(size.x / 2.0, size.y - m.y), col, 8.0, true)
		"curva":
			var pts := PackedVector2Array()
			for i in 41:
				var t := float(i) / 40.0
				pts.append(Vector2(lerpf(m.x, size.x - m.x, t), size.y / 2.0 + sin(t * TAU) * size.y * 0.28))
			draw_polyline(pts, col, 8.0, true)


func _draw_reloj() -> void:
	var hora := int(_data.get("hora", 12))
	var minuto := int(_data.get("min", 0))
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.44
	var font := get_theme_default_font()
	draw_circle(c, r + 6.0, Color("F59E0B"))
	draw_circle(c, r, Color.WHITE)
	var fs := maxi(10, int(r * 0.22))
	for h in range(1, 13):
		var a := float(h) / 12.0 * TAU - PI / 2.0
		var p := c + Vector2.from_angle(a) * r * 0.78
		draw_string(font, p + Vector2(-fs * 0.5, fs * 0.35), str(h), HORIZONTAL_ALIGNMENT_CENTER, fs, fs, INK)
	var ah := (float(hora % 12) + float(minuto) / 60.0) / 12.0 * TAU - PI / 2.0
	var am := float(minuto) / 60.0 * TAU - PI / 2.0
	draw_line(c, c + Vector2.from_angle(ah) * r * 0.5, Color("1D4ED8"), 6.0, true)
	draw_line(c, c + Vector2.from_angle(am) * r * 0.75, Color("EF4444"), 4.0, true)
	draw_circle(c, 5.0, INK)
