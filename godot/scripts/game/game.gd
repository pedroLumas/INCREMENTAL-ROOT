class_name Game
extends RefCounted
## Una partida: el mundo, las máquinas, los recursos y las reglas que las unen.
## No dibuja nada: la interfaz lo lee. Así se puede probar y simular sin pantalla.

const World := preload("res://scripts/sim/world.gd")
const M := preload("res://scripts/sim/materials.gd")
const Catalog := preload("res://scripts/machines/catalog.gd")

const STEP := 1.0 / 30.0          ## un tick de física
const MAX_STEPS_PER_FRAME := 8
const SAVE_VERSION := 2
const SAVE_PATH := "user://partida.json"

## Cada vez que vacías la escena, la cámara se aleja: cada celda pasa a representar más volumen.
const SCALES := [
	{"name": "Una grieta", "cell": 1e-3},
	{"name": "La chimenea", "cell": 1.0},
	{"name": "La cámara magmática", "cell": 1e3},
	{"name": "El Vesubio", "cell": 1e6},
	{"name": "El manto", "cell": 1e9},
]
const DRAIN_GOAL := 0.9           ## hay que vaciar el 90 % del magma inicial
const INFLOW_BASE := 2.5          ## celdas/s que entran al empezar
const INFLOW_DRAIN_BOOST := 1.5   ## cuanto más vacías, más empuja el manto
const PRESSURE_MAX := 40.0
const PRESSURE_DECAY := 0.5       ## por segundo (menos de lo que entra: un tapón acaba reventando)
const START_RES := {"obsidiana": 40.0, "basalto": 0.0, "energia": 0.0}
const UPGRADE_MULT := 1.35
const KNOWLEDGE_PER_SCALE := 1.6
const OFFLINE_CAP := 8.0 * 3600.0
const OFFLINE_EFFICIENCY := 0.5

var world: World
var machines: Array = []
var res := {}
var energy_cap := 60.0
var levels := {}
var scale_idx := 0
var knowledge := 1.0            ## bonus permanente por escalas superadas
var total_m3 := 0.0             ## magma sacado de verdad (m³), sumando todas las escalas
var magma_start := 1
var pressure := 0.0
var time := 0.0
var events: Array[String] = []  ## avisos para la interfaz

# Medias de ritmo (por segundo de juego)
var rate_in := 0.0
var rate_out := 0.0
var gain_rates := {"obsidiana": 0.0, "basalto": 0.0, "energia": 0.0}
var _sim_acc := 0.0
var _inflow_acc := 0.0
var _win_t := 0.0
var _win_in := 0
var _win_out := 0
var _win_gain := {"obsidiana": 0.0, "basalto": 0.0, "energia": 0.0}


func _init() -> void:
	new_run()


func new_run() -> void:
	world = World.new()
	world.generate(1 + scale_idx)
	machines.clear()
	res = START_RES.duplicate()
	levels = {}
	pressure = 0.0
	magma_start = maxi(1, world.counts[M.MAGMA])


# --- Tiempo -------------------------------------------------------------------------
## Avanza el juego. `speed` > 1 solo para pruebas; se limita a MAX_STEPS_PER_FRAME ticks.
func advance(real_dt: float, speed: float = 1.0) -> void:
	_sim_acc += real_dt * speed
	var n := 0
	while _sim_acc >= STEP and n < MAX_STEPS_PER_FRAME:
		step()
		_sim_acc -= STEP
		n += 1
	if n == MAX_STEPS_PER_FRAME:
		_sim_acc = minf(_sim_acc, STEP)


func step() -> void:
	time += STEP
	var before: int = world.counts[M.MAGMA]
	world.step()
	var injected := 0
	_inflow_acc += inflow_rate() * STEP
	while _inflow_acc >= 1.0:
		_inflow_acc -= 1.0
		if world.inject_magma():
			injected += 1
		else:
			pressure += 1.0
	pressure = maxf(0.0, pressure - PRESSURE_DECAY * STEP)
	if pressure >= PRESSURE_MAX:
		_erupt()
	for m in machines:
		m.tick(self, STEP)
	for m in machines.filter(func(x) -> bool: return x.retired):
		remove(m, false)
	var out := injected - (world.counts[M.MAGMA] - before)
	if out > 0:
		total_m3 += out * cell_volume()
	_win_in += injected
	_win_out += maxi(0, out)
	_win_t += STEP
	if _win_t >= 1.0:
		var a := 0.3
		rate_in = lerpf(rate_in, _win_in / _win_t, a)
		rate_out = lerpf(rate_out, _win_out / _win_t, a)
		for k in gain_rates:
			gain_rates[k] = lerpf(gain_rates[k], _win_gain[k] / _win_t, a)
			_win_gain[k] = 0.0
		_win_t = 0.0
		_win_in = 0
		_win_out = 0


func inflow_rate() -> float:
	return INFLOW_BASE * (1.0 + INFLOW_DRAIN_BOOST * drained())


## Fracción del magma inicial que ya no está.
func drained() -> float:
	return clampf(1.0 - float(world.counts[M.MAGMA]) / magma_start, 0.0, 1.0)


func cell_volume() -> float:
	return SCALES[mini(scale_idx, SCALES.size() - 1)]["cell"]


func scale_name() -> String:
	return SCALES[mini(scale_idx, SCALES.size() - 1)]["name"]


# --- Economía (la usan las máquinas) -------------------------------------------------
func gain(kind: String, amount: float) -> void:
	res[kind] += amount
	_win_gain[kind] += amount


func gain_energy(amount: float) -> void:
	var before: float = res["energia"]
	res["energia"] = minf(energy_cap, before + amount)
	_win_gain["energia"] += res["energia"] - before


## Magma sacado por una máquina: fuera se enfría en basalto.
func extract(cells: int) -> void:
	gain("basalto", cells * knowledge)


func level(id: String) -> int:
	return levels.get(id, 0)


func rate_mult(id: String) -> float:
	return pow(UPGRADE_MULT, level(id)) * knowledge


func _scaled(cost: Dictionary, f: float) -> Dictionary:
	var out := {}
	for k in cost:
		out[k] = cost[k] * f
	return out


func build_cost(id: String) -> Dictionary:
	var d: Dictionary = Catalog.DEFS[id]
	return _scaled(d["cost"], pow(d["growth"], count_of(id)))


func upgrade_cost(id: String) -> Dictionary:
	var u: Dictionary = Catalog.DEFS[id]["upgrade"]
	return _scaled(u["cost"], pow(u["growth"], level(id)))


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if res.get(k, 0.0) < cost[k] - 1e-9:
			return false
	return true


func _pay(cost: Dictionary) -> void:
	for k in cost:
		res[k] -= cost[k]


func count_of(id: String) -> int:
	var c := 0
	for m in machines:
		if m.id == id:
			c += 1
	return c


func unlocked(id: String) -> bool:
	return scale_idx >= Catalog.DEFS[id]["unlock_scale"]


## "" si se puede construir ahí; si no, el motivo.
func place_problem(id: String, x: int, y: int) -> String:
	var d: Dictionary = Catalog.DEFS[id]
	if not unlocked(id):
		return "Aún no disponible"
	if not world.area_free(x, y, d["size"].x, d["size"].y):
		return "Necesita espacio libre"
	if not can_afford(build_cost(id)):
		return "No te llega"
	return ""


func place(id: String, x: int, y: int) -> Object:
	if place_problem(id, x, y) != "":
		return null
	var d: Dictionary = Catalog.DEFS[id]
	_pay(build_cost(id))
	var m = d["script"].new()
	m.setup(id, d, x, y)
	machines.append(m)
	world.fill_area(x, y, m.w, m.h, M.MACHINE)
	return m


## Quitar devuelve la mitad de lo que costó.
func remove(m: Object, refund: bool = true) -> void:
	if not machines.has(m):
		return
	machines.erase(m)
	world.fill_area(m.x, m.y, m.w, m.h, M.AIR)
	if refund:
		var c := build_cost(m.id)
		for k in c:
			res[k] += c[k] * 0.5


func machine_at(cx: int, cy: int) -> Object:
	for m in machines:
		if m.contains(cx, cy):
			return m
	return null


func buy_upgrade(id: String) -> bool:
	var c := upgrade_cost(id)
	if not can_afford(c):
		return false
	_pay(c)
	levels[id] = level(id) + 1
	return true


# --- Presión y erupciones ------------------------------------------------------------
## Si el magma no puede subir, la presión crece; al llegar al máximo revienta lo que tapa la chimenea.
func _erupt() -> void:
	pressure = 0.0
	var cell := world.last_block_cell
	if cell < 0:
		return
	var cx := cell % World.W
	var cy := cell / World.W
	var victim = machine_at(cx, cy)
	if victim:
		remove(victim, false)
		events.append("¡La presión ha reventado tu %s!" % Catalog.DEFS[victim.id]["name"].to_lower())
	# bombas de lava que salen despedidas
	for k in 24:
		world.put(cx + randi_range(-6, 6), cy - randi_range(1, 8), M.MAGMA)


# --- Prestigio: alejar la cámara ----------------------------------------------------
func can_zoom_out() -> bool:
	return drained() >= DRAIN_GOAL


func zoom_out() -> void:
	if not can_zoom_out():
		return
	scale_idx += 1
	knowledge *= KNOWLEDGE_PER_SCALE
	new_run()


# --- Tiempo fuera -------------------------------------------------------------------
## Mientras no juegas, las máquinas siguen al ritmo medio de antes (a la mitad).
## El mundo no se mueve: el magma te espera donde lo dejaste.
func apply_offline(seconds: float) -> Dictionary:
	var t := minf(seconds, OFFLINE_CAP)
	var got := {}
	for k in ["obsidiana", "basalto"]:
		got[k] = maxf(0.0, gain_rates[k]) * t * OFFLINE_EFFICIENCY
		res[k] += got[k]
	var before: float = res["energia"]
	res["energia"] = minf(energy_cap, before + maxf(0.0, gain_rates["energia"]) * t * OFFLINE_EFFICIENCY)
	got["energia"] = res["energia"] - before
	got["seconds"] = t
	return got


# --- Guardado -------------------------------------------------------------------------
func to_dict() -> Dictionary:
	var ms := []
	for m in machines:
		ms.append({"id": m.id, "x": m.x, "y": m.y})
	return {
		"v": SAVE_VERSION,
		"grid": Marshalls.raw_to_base64(world.mat),
		"machines": ms,
		"res": res,
		"levels": levels,
		"scale": scale_idx,
		"knowledge": knowledge,
		"total_m3": total_m3,
		"magma_start": magma_start,
		"pressure": pressure,
		"time": time,
		"gain_rates": gain_rates,
		"last_seen": Time.get_unix_time_from_system(),
	}


static func from_dict(d: Dictionary) -> Game:
	var g := Game.new()
	g.scale_idx = int(d.get("scale", 0))
	g.new_run()
	var grid := Marshalls.base64_to_raw(String(d.get("grid", "")))
	if grid.size() == g.world.mat.size():
		g.world.mat = grid
		g.world.recount()
	g.knowledge = float(d.get("knowledge", 1.0))
	g.total_m3 = float(d.get("total_m3", 0.0))
	g.magma_start = int(d.get("magma_start", g.magma_start))
	g.pressure = float(d.get("pressure", 0.0))
	g.time = float(d.get("time", 0.0))
	for k in g.res:
		g.res[k] = float(d.get("res", {}).get(k, g.res[k]))
	for k in d.get("levels", {}):
		g.levels[k] = int(d["levels"][k])
	for k in g.gain_rates:
		g.gain_rates[k] = float(d.get("gain_rates", {}).get(k, 0.0))
	for md in d.get("machines", []):
		var id: String = md["id"]
		if not Catalog.DEFS.has(id):
			continue
		var def: Dictionary = Catalog.DEFS[id]
		var m = def["script"].new()
		m.setup(id, def, int(md["x"]), int(md["y"]))
		g.machines.append(m)
		g.world.fill_area(m.x, m.y, m.w, m.h, M.MACHINE)
	g.world.dirty.clear()
	return g


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "", false, true))


## Devuelve [partida, segundos fuera] o [null, 0] si no hay partida guardada compatible.
static func load_saved() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		return [null, 0.0]
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY or int(d.get("v", 0)) != SAVE_VERSION:
		return [null, 0.0]
	var away := Time.get_unix_time_from_system() - float(d.get("last_seen", 0.0))
	return [from_dict(d), away]
