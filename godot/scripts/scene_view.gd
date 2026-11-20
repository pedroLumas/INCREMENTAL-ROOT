extends Node2D
## Dibuja la escena en un SubViewport de 320×180 que se muestra ×2 con píxeles duros:
## el Vesubio entero (altura ×3), tu montaña y una lupa a la escala real de la cuchara.

const Core := preload("res://scripts/core.gd")
const W := 320.0
const H := 180.0
const VE := 3.0  # exageración vertical del dibujo: el Vesubio real es muy plano
const R := Core.RADIUS
const HV := Core.HEIGHT
const PAD := 24.0

const COL_SKY_TOP := Color("#2b1d36")
const COL_SKY_BOTTOM := Color("#4e2c3c")
const COL_ROCK := Color("#5a4a52")
const COL_ROCK_EDGE := Color("#8a747f")
const COL_CAVITY := Color("#120d16")
const COL_MAGMA := Color("#e2560f")
const COL_GLOW := Color("#ffb347")
const COL_PILE := Color("#0b080e")
const COL_PILE_LIT := Color("#2a2030")
const COL_GROUND := Color("#2a1d24")
const COL_LAKE := Color("#3d6b8a")
const COL_STEEL := Color("#d6d0d4")
const COL_STEEL_IN := Color("#8d868c")
const COL_BONE := Color("#f4e9dd")
const COL_ORANGE := Color("#ff7b1c")

var game: Node          ## main.gd: lee st, collapse, dip y particles
var font: Font
var lupa_zoom := 0.0    ## para el texto bajo la escena
var lupa_bar := 0.0


## Vista: el punto del mundo (cx, cy) se dibuja en (ox, oy); scale = metros por píxel.
class View:
	var cx: float
	var cy: float
	var scale: float
	var ox: float
	var oy: float
	var ve: float
	var clip: Array  # polígono convexo en píxeles, como [[x, y], ...]

	func _init(p_cx: float, p_cy: float, p_scale: float, p_ox: float, p_oy: float, p_ve: float, p_clip: Array) -> void:
		cx = p_cx
		cy = p_cy
		scale = p_scale
		ox = p_ox
		oy = p_oy
		ve = p_ve
		clip = p_clip

	func px(x: float, y: float) -> Array:
		return [ox + (x - cx) / scale, oy - (y - cy) * ve / scale]


# --- Recorte (Sutherland–Hodgman contra un polígono convexo, en doble precisión) ---
static func _side(a: Array, b: Array, p: Array) -> float:
	return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])


static func _area(pts: Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a: Array = pts[i]
		var b: Array = pts[(i + 1) % pts.size()]
		s += a[0] * b[1] - b[0] * a[1]
	return s * 0.5


static func clip_convex(subject: Array, clipper: Array) -> Array:
	var out := subject
	var orient := signf(_area(clipper))
	for i in clipper.size():
		var a: Array = clipper[i]
		var b: Array = clipper[(i + 1) % clipper.size()]
		var inp := out
		out = []
		if inp.is_empty():
			break
		for j in inp.size():
			var cur: Array = inp[j]
			var prev: Array = inp[(j + inp.size() - 1) % inp.size()]
			var sc := _side(a, b, cur) * orient
			var sp := _side(a, b, prev) * orient
			if sc >= 0.0:
				if sp < 0.0:
					var t := sp / (sp - sc)
					out.append([prev[0] + t * (cur[0] - prev[0]), prev[1] + t * (cur[1] - prev[1])])
				out.append(cur)
			elif sp >= 0.0:
				var t2 := sp / (sp - sc)
				out.append([prev[0] + t2 * (cur[0] - prev[0]), prev[1] + t2 * (cur[1] - prev[1])])
	return out


static func rect_poly(x0: float, y0: float, x1: float, y1: float) -> Array:
	return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]


static func circle_poly(cx: float, cy: float, r: float, n: int = 48) -> Array:
	var pts := []
	for i in n:
		var a := TAU * i / n
		pts.append([cx + cos(a) * r, cy + sin(a) * r])
	return pts


## Pasa un polígono del mundo a píxeles, lo recorta y lo devuelve listo para dibujar.
func _project(v: View, world: Array) -> PackedVector2Array:
	var p := []
	for w in world:
		p.append(v.px(w[0], w[1]))
	p = clip_convex(p, v.clip)
	var out := PackedVector2Array()
	for q in p:
		var pt := Vector2(q[0], q[1])
		if out.is_empty() or out[out.size() - 1].distance_squared_to(pt) > 1e-6:
			out.append(pt)
	if out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) <= 1e-6:
		out.remove_at(out.size() - 1)
	if out.size() < 3:
		return PackedVector2Array()
	var area := 0.0
	for i in out.size():
		area += out[i].cross(out[(i + 1) % out.size()])
	return out if absf(area) > 0.4 else PackedVector2Array()


func _fill(v: View, world: Array, color: Color) -> PackedVector2Array:
	var pts := _project(v, world)
	if pts.size() >= 3:
		draw_colored_polygon(pts, color)
	return pts


static func _pile(m: float) -> Vector2:
	if m <= 0.0:
		return Vector2.ZERO
	var tan_a := tan(deg_to_rad(33.0))  # ángulo de reposo
	var r := pow(3.0 * m / (PI * tan_a), 1.0 / 3.0)
	return Vector2(r, r * tan_a)


static func hole_depth(h: float) -> float:
	return minf(HV, pow(3.0 * h * HV * HV / (PI * R * R), 1.0 / 3.0))


func _sky(pts: Array) -> void:
	var poly := PackedVector2Array()
	var cols := PackedColorArray()
	for p in pts:
		poly.append(Vector2(p[0], p[1]))
		cols.append(COL_SKY_TOP.lerp(COL_SKY_BOTTOM, clampf(p[1] / H, 0.0, 1.0)))
	draw_polygon(poly, cols)


## Dibuja el mundo en una vista. Devuelve la altura de la superficie del magma (m).
func _draw_world(v: View, outline: bool) -> float:
	var st = game.st
	_sky(v.clip)
	var d := hole_depth(st.hole)
	var r := R * d / HV
	var ys := HV - d
	var e: float = 1.0 - pow(1.0 - game.collapse, 3.0) if game.collapse > 0.0 else 0.0
	if e > 0.0:
		# Caldera: la cima se hunde y queda un lago.
		var top := HV * (1.0 - 0.4 * e)
		var rc := R * 0.3 * e
		var dep := HV * 0.22 * e
		var rock := _fill(v, [[-R, 0.0], [-rc, top], [-rc * 0.55, top - dep], [rc * 0.55, top - dep], [rc, top], [R, 0.0]], COL_ROCK)
		if outline and rock.size() >= 3:
			rock.append(rock[0])
			draw_polyline(rock, COL_ROCK_EDGE, 4.0)
		_fill(v, [[-rc * 0.55, top - dep], [rc * 0.55, top - dep], [rc * 0.78, top - dep * 0.4], [-rc * 0.78, top - dep * 0.4]], COL_LAKE)
	else:
		var rock := _fill(v, [[-R, 0.0], [0.0, HV], [R, 0.0]], COL_ROCK)
		if outline and rock.size() >= 3:
			rock.append(rock[0])
			draw_polyline(rock, COL_ROCK_EDGE, 4.0)
		if d > 0.0:
			_fill(v, [[-r, ys], [0.0, HV], [r, ys]], COL_CAVITY)
		_fill(v, [[-R, 0.0], [-r, ys], [r, ys], [R, 0.0]], COL_MAGMA)
		var s2 := 2.0 * v.scale / v.ve  # capa brillante de 2 px
		var r2 := R * minf(HV, d + s2) / HV
		_fill(v, [[-r2, ys - s2], [-r, ys], [r, ys], [r2, ys - s2]], COL_GLOW)
	# Montaña de magma enfriado
	var pile := _pile(st.run_total)
	if pile.x > 0.0:
		var px := R * 0.85 + pile.x
		_fill(v, [[px - pile.x, 0.0], [px, pile.y], [px + pile.x, 0.0]], COL_PILE)
		_fill(v, [[px - pile.x, 0.0], [px, pile.y], [px - pile.x * 0.2, 0.0]], COL_PILE_LIT)
	# Suelo: un rectángulo enorme bajo y = 0, recortado a la vista
	_fill(v, [[-1e9, 0.0], [1e9, 0.0], [1e9, -1e9], [-1e9, -1e9]], COL_GROUND)
	return ys


func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)


## Cuchara sobre la superficie (x, ys en el mundo), elevada `lift` píxeles.
func _draw_spoon(v: View, ys: float, l: float, lift: float) -> Vector2:
	var p := v.px(0.0, ys)
	var b := Vector2(p[0], p[1] - lift)
	var rx := maxf(1.5, l * 0.55 / v.scale)
	var ry := maxf(1.0, l * 0.32 / v.scale)
	draw_line(b + Vector2(rx * 0.8, -ry * 0.4), b + Vector2(rx * 2.6, -ry * 3.2), COL_STEEL, maxf(1.0, l * 0.18 / v.scale))
	_ellipse(b, rx, ry, COL_STEEL)
	_ellipse(b + Vector2(0, -ry * 0.15), rx * 0.7, ry * 0.55, COL_ORANGE if game.dip > 0.25 else COL_STEEL_IN)
	return b


func _particles(anchor: Vector2, lupa: bool) -> void:
	for p in game.particles:
		if p["lupa"] == lupa:
			draw_rect(Rect2(roundf(anchor.x + p["x"]), roundf(anchor.y + p["y"]), 2, 2), p["c"])


static func _nice_len(target: float) -> float:
	var p := pow(10.0, floorf(log(target) / log(10.0)))
	for m in [5.0, 2.0, 1.0]:
		if m * p <= target:
			return m * p
	return p


func _draw() -> void:
	if game == null or game.st == null:
		return
	var st = game.st
	# Vista principal: el Vesubio entero y tu montaña.
	var pile := _pile(st.run_total)
	var x1 := maxf(R, R * 0.85 + 2.0 * pile.x)
	var ground_y := H * 0.86
	var scale_main := maxf((x1 + R) * 1.06 / W, maxf(HV, pile.y) * VE * 1.2 / (ground_y - 6.0))
	var vm := View.new((x1 - R) / 2.0, 0.0, scale_main, W / 2.0, ground_y, VE, rect_poly(-PAD, -PAD, W + PAD, H + PAD))
	var ys := _draw_world(vm, true)
	var top_arr := vm.px(0.0, ys)
	var top := Vector2(top_arr[0], top_arr[1])
	_particles(top, false)

	var l := pow(Core.spoon(st), 1.0 / 3.0)  # tamaño lineal de la cuchara
	var scale_l := l / 9.0                   # en la lupa la cuchara mide ~9 px
	var zoom := scale_main / scale_l
	lupa_zoom = 0.0
	lupa_bar = 0.0
	if game.collapse > 0.0:
		return
	if zoom <= 2.0:
		var b := _draw_spoon(vm, ys, l, (l / scale_main) * (1.2 - game.dip * 1.1))
		_particles(b, true)
		return

	# Marcador "tú" y línea hacia la lupa
	var lr := 48.0
	var lc := Vector2(lr + 6.0, lr + 6.0)
	draw_line(top, lc + Vector2(lr, lr) * 0.71, Color(COL_BONE, 0.6), 1.0)
	draw_rect(Rect2(roundf(top.x) - 1, roundf(top.y) - 1, 3, 3), COL_BONE)
	if font:
		draw_string(font, Vector2(roundf(top.x) + 4, roundf(top.y) - 2), "tú", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_BONE)

	# Lupa: el mundo a la escala de la cuchara, recortado a un círculo
	var vl := View.new(0.0, ys, scale_l, lc.x, lc.y + 12.0, VE, circle_poly(lc.x, lc.y, lr))
	_draw_world(vl, false)
	var bowl := _draw_spoon(vl, ys, l, 8.0 - game.dip * 9.0)
	_particles(bowl, true)
	var bar := _nice_len(28.0 * scale_l)
	var bpx := bar / scale_l
	draw_rect(Rect2(roundf(lc.x - bpx / 2.0), roundf(lc.y + lr - 11.0), roundf(bpx), 2), COL_BONE)
	draw_arc(lc, lr, 0.0, TAU, 64, COL_BONE, 3.0)
	lupa_zoom = zoom
	lupa_bar = bar
