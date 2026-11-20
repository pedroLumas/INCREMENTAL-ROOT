extends SceneTree
## Tests de la lógica y del formato. Uso: godot --headless --path godot -s res://tests/pruebas.gd

const Core := preload("res://scripts/core.gd")
const State := preload("res://scripts/state.gd")
const Fmt := preload("res://scripts/fmt.gd")

var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   ", name)
	else:
		fails += 1
		print("  FALLA ", name, "  ", detail)


func eq(name: String, got, want) -> void:
	check(name, got == want, "obtenido=%s esperado=%s" % [str(got), str(want)])


func _initialize() -> void:
	print("Formato")
	eq("miles", Fmt.group_int(4382102872737283), "4.382.102.872.737.283")
	eq("4 cifras sin punto", Fmt.group_int(1234), "1234")
	eq("mL", Fmt.vol(1.5e-5), "15 mL")
	eq("L", Fmt.vol(0.465), "465 L")
	eq("m³", Fmt.vol(68669.4), "68.669 m³")
	eq("km³", Fmt.vol(3.01e10), "30,1 km³")
	eq("porcentaje pequeño", Fmt.pct(6.9e-13), "0,00000000000069 %")
	eq("porcentaje normal", Fmt.pct(10.444), "10,44 %")
	eq("científica", Fmt.sci(4.38e15), "4,38 × 10¹⁵")
	eq("duración", Fmt.dur(2200), "36:40")
	eq("duración horas", Fmt.dur(8 * 3600 + 120), "8 h 2 min")
	eq("fermi cucharada", Core.fermi(1.5e-5), "una cucharada")
	eq("fermi plural", Core.fermi(2.5e3 * 57), "57 piscinas olímpicas")
	eq("fermi decimal", Core.fermi(7.4e9 * 4.1), "4,1 lagos Ness")

	print("Reglas")
	var st := State.new(0.0)
	eq("volumen del Vesubio ≈ 6,57e10", snappedf(Core.VOLUME / 1e10, 0.01), 6.57)
	for i in 30:
		Core.scoop(st)
	check("30 clics dan 450 mL", absf(st.magma - 30 * 1.5e-5) < 1e-12)
	check("no se puede comprar sin magma", not Core.buy(State.new(0.0), "speed"))
	check("comprar cuchara", Core.buy(st, "spoon") and st.spoon_lvl == 1)

	# Agujero en equilibrio = lo que sacas × REFILL_TIME
	var s2 := State.new(0.0)
	s2.helpers = 10
	Core.tick(s2, 10000.0)
	check("equilibrio del agujero", absf(s2.hole - Core.auto_rate(s2) * Core.REFILL_TIME) < 1e-9)

	# Erupción final: la caldera queda marcada aunque el relleno baje el agujero después
	var s3 := State.new(0.0)
	s3.hole = Core.VOLUME * 0.2
	s3.pressure = 1.0
	Core.erupt(s3)
	Core.tick(s3, 0.016)
	check("la erupción final hunde el volcán", Core.caldera_ready(s3))

	# Offline: el agujero nunca queda peor que como lo dejaste
	var s4 := State.new(0.0)
	s4.hole = 1000.0
	s4.helpers = 1
	var r := Core.offline(s4, 8 * 3600.0)
	check("offline no rellena el agujero", s4.hole >= 1000.0)
	check("offline da magma de los ayudantes", r.gained > 0.0)

	# Caldera: conserva calderas y bonus, reinicia la vuelta
	var s5 := State.new(0.0)
	s5.run_total = Core.VOLUME
	s5.run_seconds = 100.0
	s5.helpers = 50
	var sum := Core.caldera(s5, 0.0)
	check("bonus = 1 + √(sacado / volumen)", absf(sum.bonus - 2.0) < 1e-9)
	check("caldera reinicia la vuelta", s5.helpers == 0 and s5.calderas == 1 and absf(s5.legacy - 2.0) < 1e-9)
	eq("récord de vuelta", s5.best_run_seconds, 100.0)

	# Guardado: ida y vuelta por JSON
	var s6 := State.new(123.0)
	s6.spoon_lvl = 7
	s6.hole = 1.25e-4
	s6.caldera_due = true
	var back := State.from_dict(JSON.parse_string(JSON.stringify(s6.to_dict(), "", false, true)))
	check("JSON conserva tipos y valores", back.spoon_lvl == 7 and back.hole == 1.25e-4 and back.caldera_due and back.last_seen == 123.0)

	print("FALLOS: %d" % fails)
	quit(1 if fails > 0 else 0)
