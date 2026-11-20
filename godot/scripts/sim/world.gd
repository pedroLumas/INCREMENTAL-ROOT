class_name World
extends RefCounted
## El corte del volcán como rejilla de celdas. La física es genérica: caer, fluir, subir,
## reaccionar y desaparecer según las tablas de Materials. Las máquinas solo leen y escriben celdas.

const M := preload("res://scripts/sim/materials.gd")
const W := 160
const H := 90
const N := M.COUNT

# Geometría del Vesubio en la rejilla
const CENTER_X := 80
const RIM_Y := 22            ## borde del cráter
const CRATER_HALF_TOP := 24  ## semiancho del cráter arriba
const CONDUIT_TOP := 38      ## donde el cráter se convierte en chimenea
const CONDUIT_HALF := 7      ## chimenea: columnas 73..86
const CHAMBER_Y := 77
const CHAMBER_RX := 36
const CHAMBER_RY := 10
const MAGMA_START_Y := 40    ## nivel inicial del magma
const SOURCE_Y := 86         ## fondo de la cámara: por aquí entra el magma

var mat := PackedByteArray()
var shade := PackedByteArray()     ## variación de color fija por celda (0..3)
var interior := PackedByteArray()  ## 1 = cavidad del volcán, 0 = cielo o roca
var upd := PackedByteArray()       ## marca de "ya se movió en este tick"
var counts := PackedInt32Array()
var dirty := PackedInt32Array()    ## celdas cambiadas desde el último dibujo
var stamp := 1
var ticks := 0

# Tablas derivadas de Materials (para que el bucle caliente no toque diccionarios)
var kind := PackedByteArray()
var density := PackedFloat32Array()
var flow := PackedFloat32Array()
var enter := PackedByteArray()     ## enter[a*N+b] = 1 si a puede ocupar el sitio de b
var react_a := PackedByteArray()   ## 255 = sin reacción
var react_b := PackedByteArray()
var react_p := PackedFloat32Array()
var has_react := PackedByteArray()
var decay_to := PackedByteArray()
var decay_p := PackedFloat32Array()

var source_cols: Array[int] = []
var last_block_cell := -1          ## celda que impidió subir al magma (para la presión)


func _init() -> void:
	_build_tables()
	for x in range(CENTER_X - CONDUIT_HALF + 1, CENTER_X + CONDUIT_HALF - 1):
		source_cols.append(x)


func _build_tables() -> void:
	kind.resize(N)
	density.resize(N)
	flow.resize(N)
	has_react.resize(N)
	decay_to.resize(N)
	decay_p.resize(N)
	for d in M.DEFS:
		kind[d[0]] = d[2]
		density[d[0]] = d[3]
		flow[d[0]] = d[4]
	enter.resize(N * N)
	for a in N:
		for b in N:
			var ok := 0
			if kind[a] >= M.GRANULAR:
				if b == M.AIR:
					ok = 1
				elif kind[a] == M.GAS:
					ok = 1 if kind[b] == M.LIQUID else 0  # el gas sube a través de líquidos
				elif kind[b] == M.LIQUID or kind[b] == M.GAS:
					ok = 1 if density[a] > density[b] else 0  # lo pesado se hunde en lo ligero
			enter[a * N + b] = ok
	react_a.resize(N * N)
	react_b.resize(N * N)
	react_p.resize(N * N)
	react_a.fill(255)
	for r in M.REACTIONS:
		_add_reaction(r[0], r[1], r[2], r[3], r[4])
		_add_reaction(r[1], r[0], r[3], r[2], r[4])
	for d in M.DECAYS:
		decay_to[d[0]] = d[1]
		decay_p[d[0]] = d[2]


func _add_reaction(a: int, b: int, ra: int, rb: int, p: float) -> void:
	react_a[a * N + b] = ra
	react_b[a * N + b] = rb
	react_p[a * N + b] = p
	has_react[a] = 1


# --- Mapa ----------------------------------------------------------------------
func generate(seed_value: int = 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	mat.resize(W * H)
	shade.resize(W * H)
	interior.resize(W * H)
	upd.resize(W * H)
	mat.fill(M.ROCK)
	interior.fill(0)
	upd.fill(0)
	for y in H:
		for x in W:
			var i := y * W + x
			shade[i] = rng.randi() % 4
			var dx: int = absi(x - CENTER_X)
			# Ladera exterior: por encima de la línea, cielo
			var surface := RIM_Y + maxf(0.0, dx - CRATER_HALF_TOP) * 0.72
			if y < surface:
				mat[i] = M.AIR
				continue
			var cavity := false
			if y >= RIM_Y and y < CONDUIT_TOP:
				var t := float(y - RIM_Y) / float(CONDUIT_TOP - RIM_Y)
				cavity = dx <= lerpf(CRATER_HALF_TOP, CONDUIT_HALF, t)
			elif y >= CONDUIT_TOP and y < CHAMBER_Y - CHAMBER_RY + 2:
				cavity = x >= CENTER_X - CONDUIT_HALF and x < CENTER_X + CONDUIT_HALF
			if not cavity and y < H - 2:
				var ex := float(x - CENTER_X) / CHAMBER_RX
				var ey := float(y - CHAMBER_Y) / CHAMBER_RY
				cavity = ex * ex + ey * ey <= 1.0
			if cavity:
				interior[i] = 1
				mat[i] = M.MAGMA if y >= MAGMA_START_Y else M.AIR
	recount()
	dirty.clear()


func recount() -> void:
	counts.resize(N)
	counts.fill(0)
	for i in mat.size():
		counts[mat[i]] += 1


# --- API para máquinas y juego -------------------------------------------------------
func idx(x: int, y: int) -> int:
	return y * W + x


func inside(x: int, y: int) -> bool:
	return x >= 0 and x < W and y >= 0 and y < H


func get_mat(x: int, y: int) -> int:
	return mat[y * W + x] if inside(x, y) else M.ROCK


func set_cell(i: int, m: int) -> void:
	var old: int = mat[i]
	if old == m:
		return
	counts[old] -= 1
	counts[m] += 1
	mat[i] = m
	dirty.append(i)


## Quita una celda del material dado dentro del rectángulo (la más alta primero). Devuelve si pudo.
func take_one(x0: int, y0: int, x1: int, y1: int, m: int) -> bool:
	for y in range(maxi(0, y0), mini(H, y1 + 1)):
		for x in range(maxi(0, x0), mini(W, x1 + 1)):
			var i := y * W + x
			if mat[i] == m:
				set_cell(i, M.AIR)
				return true
	return false


## Cuántas celdas del material hay en el rectángulo.
func count_in(x0: int, y0: int, x1: int, y1: int, m: int) -> int:
	var c := 0
	for y in range(maxi(0, y0), mini(H, y1 + 1)):
		for x in range(maxi(0, x0), mini(W, x1 + 1)):
			if mat[y * W + x] == m:
				c += 1
	return c


## Pone una celda si está libre.
func put(x: int, y: int, m: int) -> bool:
	if not inside(x, y):
		return false
	var i := y * W + x
	if mat[i] != M.AIR:
		return false
	set_cell(i, m)
	return true


## ¿Se puede construir en todo el rectángulo? Vale el aire y lo que se aparta (gases y líquidos ligeros
## como el agua); no la roca, el magma, la obsidiana ni otras máquinas.
func area_free(x0: int, y0: int, w: int, h: int) -> bool:
	if x0 < 0 or y0 < 0 or x0 + w > W or y0 + h > H:
		return false
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var m: int = mat[y * W + x]
			var k: int = kind[m]
			if not (k == M.EMPTY or k == M.GAS or (k == M.LIQUID and density[m] < 2.0)):
				return false
	return true


## Convierte roca en hueco (cavidad). Devuelve si había roca.
func carve(x: int, y: int) -> bool:
	if not inside(x, y):
		return false
	var i := y * W + x
	if mat[i] != M.ROCK:
		return false
	interior[i] = 1
	set_cell(i, M.AIR)
	return true


func fill_area(x0: int, y0: int, w: int, h: int, m: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			set_cell(y * W + x, m)


## El magma entra por el fondo de la cámara y empuja la columna hacia arriba.
## Devuelve false si todas las columnas están taponadas (sube la presión).
func inject_magma() -> bool:
	var n := source_cols.size()
	var start := randi() % n
	for k in n:
		var x: int = source_cols[(start + k) % n]
		var y := SOURCE_Y
		while y >= 0:
			var m: int = mat[y * W + x]
			if m == M.AIR:
				break
			if kind[m] == M.STATIC:
				last_block_cell = y * W + x
				y = -1
				break
			y -= 1
		if y < 0:
			continue
		# desplazar la columna una celda hacia arriba
		for yy in range(y, SOURCE_Y):
			var a := yy * W + x
			mat[a] = mat[a + W]
			dirty.append(a)
		var s := SOURCE_Y * W + x
		mat[s] = M.MAGMA
		dirty.append(s)
		counts[M.AIR] -= 1
		counts[M.MAGMA] += 1
		return true
	return false


# --- Física --------------------------------------------------------------------
func step() -> void:
	ticks += 1
	stamp = 1 + (ticks & 1)
	var rev := (ticks & 1) == 1
	for y in range(H - 1, -1, -1):
		var row := y * W
		for k in W:
			var x: int = (W - 1 - k) if rev else k
			var i: int = row + x
			var m: int = mat[i]
			var kd: int = kind[m]
			if kd <= M.STATIC or upd[i] == stamp:
				continue
			var dp: float = decay_p[m]
			if dp > 0.0 and randf() < dp:
				set_cell(i, decay_to[m])
				upd[i] = stamp
				continue
			if has_react[m] == 1 and _react(i, x, y, m):
				continue
			if kd == M.GAS:
				_rise(i, x, y, m)
			else:
				_fall(i, x, y, m, kd == M.LIQUID)


func _swap(i: int, j: int) -> void:
	var t: int = mat[i]
	mat[i] = mat[j]
	mat[j] = t
	upd[i] = stamp
	upd[j] = stamp
	dirty.append(i)
	dirty.append(j)


func _react(i: int, x: int, y: int, m: int) -> bool:
	var base := m * N
	for n in 4:
		var j: int
		if n == 0:
			if y >= H - 1:
				continue
			j = i + W
		elif n == 1:
			if y == 0:
				continue
			j = i - W
		elif n == 2:
			if x == 0:
				continue
			j = i - 1
		else:
			if x >= W - 1:
				continue
			j = i + 1
		var r: int = base + mat[j]
		if react_a[r] != 255 and randf() < react_p[r]:
			set_cell(i, react_a[r])
			set_cell(j, react_b[r])
			upd[i] = stamp
			upd[j] = stamp
			return true
	return false


func _fall(i: int, x: int, y: int, m: int, liquid: bool) -> void:
	var base := m * N
	if y < H - 1:
		var j := i + W
		if enter[base + mat[j]] == 1:
			_swap(i, j)
			return
		var d := 1 if randf() < 0.5 else -1
		for s in 2:
			var nx := x + d
			if nx >= 0 and nx < W and enter[base + mat[j + d]] == 1:
				_swap(i, j + d)
				return
			d = -d
	if liquid and randf() < flow[m]:
		var d2 := 1 if randf() < 0.5 else -1
		for s in 2:
			var nx2 := x + d2
			if nx2 >= 0 and nx2 < W and enter[base + mat[i + d2]] == 1:
				_swap(i, i + d2)
				return
			d2 = -d2


func _rise(i: int, x: int, y: int, m: int) -> void:
	if y == 0:
		set_cell(i, M.AIR)  # se escapa por arriba
		return
	if randf() > flow[m]:
		return
	var base := m * N
	var j := i - W
	if enter[base + mat[j]] == 1:
		_swap(i, j)
		return
	var d := 1 if randf() < 0.5 else -1
	for s in 2:
		var nx := x + d
		if nx >= 0 and nx < W:
			if enter[base + mat[j + d]] == 1:
				_swap(i, j + d)
				return
			if enter[base + mat[i + d]] == 1:
				_swap(i, i + d)
				return
		d = -d
