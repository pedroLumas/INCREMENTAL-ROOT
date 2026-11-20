class_name VolcanCore
extends RefCounted
## Reglas puras de "Vaciar el Vesubio" (sin nodos ni dibujo). Las usan el juego, los tests y el simulador.

const State := preload("res://scripts/state.gd")
const FmtLib := preload("res://scripts/fmt.gd")

# --- Mundo -------------------------------------------------------------------
# Vesubio como cono simplificado: 14 km de base y 1.281 m de altura.
# No hay una cifra publicada fiable del volumen del edificio; esto es una estimación geométrica.
const VOLCANO_NAME := "Vesubio"
const RADIUS := 7000.0  # m
const HEIGHT := 1281.0  # m
const VOLUME := PI / 3.0 * RADIUS * RADIUS * HEIGHT  # ≈ 6,57e10 m³

# --- Reglas ------------------------------------------------------------------
const S0 := 1.5e-5            ## cuchara sopera: 15 mL
const REFILL_TIME := 30.0     ## s: entra = agujero / REFILL_TIME
const ERUPT_MULT := 10.0      ## una erupción multiplica el agujero ×10
const ERUPT_CHARGE := 90.0    ## s para cargar la presión
const HELPER_RATE := 0.5      ## cucharadas por segundo de cada ayudante
const SPOON_MULT := 2.0
const SPEED_MULT := 2.0
const SAVE_PATH := "user://partida.json"

# Costes: c0 * cr^nivel (en m³ de magma enfriado). Son static var para que el simulador
# pueda probar otras curvas. Con estos valores un jugador óptimo tarda ~37 min la 1ª vuelta.
static var spoon_c0 := 1e-4
static var spoon_cr := 3.6
static var helper_c0 := 2e-4
static var helper_cr := 1.14
static var speed_c0 := 5e-3
static var speed_cr := 24.0

const KINDS := ["spoon", "helper", "speed"]


static func spoon(st: State) -> float:
	return S0 * pow(SPOON_MULT, st.spoon_lvl)


static func scoops_per_sec(st: State) -> float:
	return st.helpers * HELPER_RATE * pow(SPEED_MULT, st.speed_lvl)


## Extracción automática en m³/s (sin contar clics).
static func auto_rate(st: State) -> float:
	return spoon(st) * scoops_per_sec(st) * st.legacy


static func click_volume(st: State) -> float:
	return spoon(st) * st.legacy


static func inflow(st: State) -> float:
	return st.hole / REFILL_TIME


static func cost(st: State, kind: String) -> float:
	match kind:
		"spoon":
			return spoon_c0 * pow(spoon_cr, st.spoon_lvl)
		"helper":
			return helper_c0 * pow(helper_cr, st.helpers)
		"speed":
			return speed_c0 * pow(speed_cr, st.speed_lvl)
	push_error("Mejora desconocida: %s" % kind)
	return INF


static func buy(st: State, kind: String) -> bool:
	var c := cost(st, kind)
	if st.magma < c:
		return false
	st.magma -= c
	match kind:
		"spoon":
			st.spoon_lvl += 1
		"helper":
			st.helpers += 1
		"speed":
			st.speed_lvl += 1
	return true


## Si el agujero llega al volumen del volcán, la caldera queda marcada.
static func _mark_caldera(st: State) -> void:
	if st.hole >= VOLUME * 0.999999:
		st.hole = VOLUME
		st.caldera_due = true


static func scoop(st: State) -> float:
	var v := click_volume(st)
	st.magma += v
	st.run_total += v
	st.hole = minf(VOLUME, st.hole + v)
	st.clicks += 1
	_mark_caldera(st)
	return v


static func can_erupt(st: State) -> bool:
	return st.pressure >= 1.0 and st.hole > 0.0


## Devuelve lo expulsado (no va a la montaña).
static func erupt(st: State) -> float:
	if not can_erupt(st):
		return 0.0
	var before := st.hole
	st.hole = minf(VOLUME, st.hole * ERUPT_MULT)
	st.pressure = 0.0
	_mark_caldera(st)
	return st.hole - before


static func caldera_ready(st: State) -> bool:
	return st.caldera_due


static func caldera_bonus(st: State) -> float:
	return 1.0 + sqrt(st.run_total / VOLUME)


## Hunde el volcán: reinicia la vuelta y conserva calderas, bonus y récord.
static func caldera(st: State, now: float) -> Dictionary:
	var bonus := caldera_bonus(st)
	var summary := {"bonus": bonus, "run_seconds": st.run_seconds, "run_total": st.run_total}
	var fresh := State.new(now)
	fresh.calderas = st.calderas + 1
	fresh.legacy = st.legacy * bonus
	fresh.best_run_seconds = st.run_seconds if st.best_run_seconds < 0.0 else minf(st.best_run_seconds, st.run_seconds)
	for f in State.FIELDS:
		st.set(f, fresh.get(f))
	summary["legacy"] = st.legacy
	return summary


## El agujero sigue dH/dt = A - H/REFILL_TIME, con solución exacta para cualquier dt.
static func tick(st: State, dt: float) -> void:
	if dt <= 0.0 or st.caldera_due:
		return
	var a := auto_rate(st)
	var eq := a * REFILL_TIME
	st.hole = clampf(eq + (st.hole - eq) * exp(-dt / REFILL_TIME), 0.0, VOLUME)
	var gained := a * dt
	st.magma += gained
	st.run_total += gained
	st.pressure = minf(1.0, st.pressure + dt / ERUPT_CHARGE)
	st.run_seconds += dt
	_mark_caldera(st)


## Tiempo fuera: ganas lo de tus ayudantes y el agujero nunca queda peor que como lo dejaste.
static func offline(st: State, dt: float) -> Dictionary:
	if dt <= 0.0:
		return {"seconds": 0.0, "gained": 0.0}
	var hole_before := st.hole
	var magma_before := st.magma
	tick(st, dt)
	if st.hole < hole_before:
		st.hole = hole_before
	return {"seconds": dt, "gained": st.magma - magma_before}


# --- Escala de Fermi (volúmenes aproximados) ---------------------------------
const FERMI := [
	[1.5e-5, "una cucharada", "cucharadas"],
	[2.5e-4, "una taza", "tazas"],
	[1e-2, "un cubo", "cubos"],
	[1.5e-1, "una bañera", "bañeras"],
	[3e1, "un camión cisterna", "camiones cisterna"],
	[2.5e3, "una piscina olímpica", "piscinas olímpicas"],
	[2e5, "el dirigible Hindenburg", "Hindenburgs"],
	[2.6e6, "la Gran Pirámide de Guiza", "Grandes Pirámides"],
	[7.4e9, "el lago Ness", "lagos Ness"],
	[VOLUME, "el Vesubio entero", "Vesubios"],
	[8.9e10, "el lago Lemán", "lagos Lemán"],
	[8.93e11, "el lago Titicaca", "lagos Titicaca"],
]


static func fermi(vol: float) -> String:
	if not (vol > 0.0):
		return "nada"
	var pick: Array = FERMI[0]
	for f in FERMI:
		if vol >= f[0] * 0.95:
			pick = f
	var n: float = vol / pick[0]
	if n < 1.5:
		return ("casi " if n < 0.95 else "") + pick[1]
	var shown := FmtLib.sig(n, 2) if n < 10.0 else FmtLib.num(roundf(n))
	return "%s %s" % [shown, pick[2]]
