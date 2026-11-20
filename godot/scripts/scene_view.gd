extends Node2D
## Dibuja la escena en un SubViewport de 320×180 (2 px por celda), que se muestra ×3 sin suavizado:
## el mundo como textura (solo se repintan las celdas que cambian), las máquinas encima,
## la vista previa al construir y la zona de trabajo de lo seleccionado.

const M := preload("res://scripts/sim/materials.gd")
const World := preload("res://scripts/sim/world.gd")
const Catalog := preload("res://scripts/machines/catalog.gd")
const PX := 2

const SHIMMER := """
shader_type canvas_item;
// Hace brillar el magma (píxeles naranjas) con una onda lenta.
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float hot = step(0.75, c.r) * step(c.g, 0.6) * step(c.b, 0.2);
	float wave = sin(TIME * 2.2 + UV.x * 70.0 + UV.y * 45.0) * 0.5 + 0.5;
	c.rgb += hot * wave * vec3(0.12, 0.07, 0.0);
	COLOR = c;
}
"""

var game        ## Game
var ui          ## main.gd: tool, hover, selected
var _img: Image
var _tex: ImageTexture
var _sprite: Sprite2D
var _pixels := PackedByteArray()
var _pal := PackedByteArray()   ## (material*4 + variación)*3 → RGB
var _bg := PackedByteArray()    ## color del aire en cada celda (cielo o cavidad)
var _world_ref = null


func _ready() -> void:
	_pal.resize(M.COUNT * 4 * 3)
	for d in M.DEFS:
		var cols: Array = d[5]
		for s in 4:
			var c := Color(cols[s]) if cols.size() == 4 else Color.BLACK
			var p: int = (d[0] * 4 + s) * 3
			_pal[p] = c.r8
			_pal[p + 1] = c.g8
			_pal[p + 2] = c.b8
	_img = Image.create_empty(World.W, World.H, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.scale = Vector2(PX, PX)
	_sprite.texture = _tex
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.show_behind_parent = true
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHIMMER
	_sprite.material = mat
	add_child(_sprite)


func _rebuild_all(w) -> void:
	_pixels.resize(World.W * World.H * 4)
	_bg.resize(World.W * World.H * 4)
	var sky_top := Color("#2b1d36")
	var sky_bottom := Color("#5a3044")
	for y in World.H:
		var sky := sky_top.lerp(sky_bottom, clampf(y / 62.0, 0.0, 1.0))
		for x in World.W:
			var i: int = y * World.W + x
			if w.interior[i] == 1:
				_set_bg_cave(w, i)
				continue
			_bg[i * 4] = sky.r8
			_bg[i * 4 + 1] = sky.g8
			_bg[i * 4 + 2] = sky.b8
			_bg[i * 4 + 3] = 255
	for i in World.W * World.H:
		_paint(w, i)
	w.dirty.clear()


func _paint(w, i: int) -> void:
	var o := i * 4
	var m: int = w.mat[i]
	if m == M.AIR or m == M.MACHINE:
		if w.interior[i] == 1 and _bg[o + 3] != 254:
			_set_bg_cave(w, i)
		_pixels[o] = _bg[o]
		_pixels[o + 1] = _bg[o + 1]
		_pixels[o + 2] = _bg[o + 2]
	else:
		var p: int = (m * 4 + w.shade[i]) * 3
		_pixels[o] = _pal[p]
		_pixels[o + 1] = _pal[p + 1]
		_pixels[o + 2] = _pal[p + 2]
	_pixels[o + 3] = 255


const CAVE := [Color("#1a1219"), Color("#1d141c"), Color("#171016"), Color("#20161f")]


## Fondo de cueva para una celda (alfa 254 marca "ya es cueva").
func _set_bg_cave(w, i: int) -> void:
	var c: Color = CAVE[w.shade[i]]
	_bg[i * 4] = c.r8
	_bg[i * 4 + 1] = c.g8
	_bg[i * 4 + 2] = c.b8
	_bg[i * 4 + 3] = 254


## Llamar una vez por frame.
func refresh() -> void:
	if game == null:
		return
	var w = game.world
	if w != _world_ref:
		_world_ref = w
		_rebuild_all(w)
	else:
		var d: PackedInt32Array = w.dirty
		for k in d.size():
			_paint(w, d[k])
		d.clear()
		w.dirty = d
	_img.set_data(World.W, World.H, false, Image.FORMAT_RGBA8, _pixels)
	_tex.update(_img)
	queue_redraw()


func _zone_rect(r: Rect2i, c: Color) -> void:
	if r.size.x <= 0:
		return
	draw_rect(Rect2(r.position.x * PX, r.position.y * PX, r.size.x * PX, r.size.y * PX), c)


func _draw() -> void:
	if game == null:
		return
	for m in game.machines:
		m.draw(self)
	# Seleccionada: contorno y zona de trabajo
	if ui and ui.selected and game.machines.has(ui.selected):
		var s = ui.selected
		_zone_rect(s.zone(game), Color(1.0, 0.76, 0.36, 0.28))
		draw_rect(Rect2(s.x * PX - 1, s.y * PX - 1, s.w * PX + 2, s.h * PX + 2), Color("#f4e9dd"), false, 1.0)
	# Vista previa al construir
	if ui and ui.tool != "" and ui.hover.x >= 0:
		var d: Dictionary = Catalog.DEFS[ui.tool]
		var origin: Vector2i = ui.placement_origin()
		var ghost = d["script"].new()
		ghost.setup(ui.tool, d, origin.x, origin.y)
		var why: String = game.place_problem(ui.tool, origin.x, origin.y)
		var col := Color("#8fd694") if why == "" else (Color("#ffc15c") if why == "No te llega" else Color("#ff6b5b"))
		_zone_rect(ghost.zone(game), Color(col, 0.25))
		draw_rect(Rect2(origin.x * PX, origin.y * PX, ghost.w * PX, ghost.h * PX), Color(col, 0.35))
		draw_rect(Rect2(origin.x * PX, origin.y * PX, ghost.w * PX, ghost.h * PX), col, false, 1.0)
