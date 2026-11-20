extends SceneTree
## Tests de física, máquinas, economía y guardado.
## Uso: godot --headless --path godot -s res://tests/pruebas.gd

const Game := preload("res://scripts/game/game.gd")
const World := preload("res://scripts/sim/world.gd")
const M := preload("res://scripts/sim/materials.gd")
const Fmt := preload("res://scripts/fmt.gd")

var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok    ", name)
	else:
		fails += 1
		print("  FALLA ", name, "  ", detail)


func _steps(g, n: int) -> void:
	for k in n:
		g.step()


func _initialize() -> void:
	seed(12345)
	print("Formato")
	check("miles", Fmt.group_int(4382102872737283) == "4.382.102.872.737.283")
	check("volumen", Fmt.vol(1.5e-5) == "15 mL" and Fmt.vol(3.01e10) == "30,1 km³", Fmt.vol(3.01e10))
	check("fermi", Fmt.fermi(7.4e9 * 4.1) == "4,1 lagos Ness", Fmt.fermi(7.4e9 * 4.1))

	print("Mundo")
	var w := World.new()
	w.generate(1)
	var magma0: int = w.counts[M.MAGMA]
	check("el volcán empieza con ~1500 celdas de magma", magma0 > 1300 and magma0 < 1700, str(magma0))
	check("el magma entra por abajo", w.inject_magma() and w.counts[M.MAGMA] == magma0 + 1)
	# agua sobre magma → obsidiana + vapor
	for x in range(74, 86):
		w.put(x, 30, M.WATER)
	for k in 90:
		w.step()
	check("agua + magma = obsidiana + vapor", w.counts[M.OBSIDIAN] > 0, "obsidiana=%d" % w.counts[M.OBSIDIAN])
	var deepest_obs := 0
	var top_magma := World.H
	for i in w.mat.size():
		if w.mat[i] == M.OBSIDIAN:
			deepest_obs = maxi(deepest_obs, i / World.W)
		if w.mat[i] == M.MAGMA:
			top_magma = mini(top_magma, i / World.W)
	check("la obsidiana flota sobre el magma", deepest_obs <= top_magma + 2, "obsidiana más honda y=%d, magma desde y=%d" % [deepest_obs, top_magma])
	var w2 := World.new()
	w2.generate(1)
	w2.put(10, 20, M.STEAM)
	var rose := false
	for k in 30:
		w2.step()
	for i in w2.mat.size():
		if w2.mat[i] == M.STEAM and i / World.W < 20:
			rose = true
	check("el vapor sube", rose)
	var w3 := World.new()
	w3.generate(1)
	w3.fill_area(73, 39, 14, 1, M.MACHINE)
	check("si algo tapa la chimenea, el magma no puede entrar", not w3.inject_magma())

	print("Máquinas")
	var g := Game.new()
	g.res["obsidiana"] = 1000.0
	g.res["basalto"] = 1000.0
	check("no se construye dentro de la roca", g.place_problem("noria", 10, 70) != "")
	check("no se construye dentro del magma", g.place_problem("noria", 78, 45) != "")
	g.world.put(60, 10, M.WATER)
	check("se puede construir encima del agua (la aparta)", g.place_problem("aspersor", 58, 8) == "")
	var asp = g.place("aspersor", 74, 24)
	check("se construye en hueco libre", asp != null)
	check("cada máquina del mismo tipo cuesta más", g.build_cost("aspersor")["obsidiana"] > 15.0)
	var rec = g.place("recolector", 73, 35)
	var nor = g.place("noria", 82, 28)
	var tur = g.place("turbina", 76, 12)
	g.res = {"obsidiana": 0.0, "basalto": 0.0, "energia": 0.0}
	_steps(g, 30 * 60)
	check("el recolector da obsidiana", g.res["obsidiana"] > 20.0, str(g.res["obsidiana"]))
	check("la noria saca magma y da basalto", g.res["basalto"] > 10.0, str(g.res["basalto"]))
	check("la turbina da energía", g.res["energia"] > 5.0, str(g.res["energia"]))
	var bom = null
	g.res["obsidiana"] = 1000.0
	g.res["basalto"] = 1000.0
	g.res["energia"] = 0.0
	print("    (bomba en (80,26): %s)" % g.place_problem("bomba", 80, 26))
	bom = g.place("bomba", 80, 26)
	_steps(g, 30)
	check("la bomba sin energía no saca", bom != null and bom.status == "Sin energía", bom.status if bom else "no se pudo construir")
	g.res["energia"] = 50.0
	var bas0: float = g.res["basalto"]
	_steps(g, 30 * 3)
	check("la bomba con energía saca magma", g.res["basalto"] > bas0 and g.res["energia"] < 50.0)

	print("Mecánica añadida después (dinamita)")
	var g4 := Game.new()
	g4.res["obsidiana"] = 500.0
	g4.res["basalto"] = 500.0
	var rock0: int = g4.world.counts[M.ROCK]
	var din = g4.place("dinamita", 40, 30)
	check("la dinamita se puede poner pegada a la roca", din != null, g4.place_problem("dinamita", 40, 30))
	_steps(g4, 60)
	check("la dinamita abre la roca", g4.world.counts[M.ROCK] < rock0 - 20, "%d → %d" % [rock0, g4.world.counts[M.ROCK]])
	check("y se retira sola", not g4.machines.has(din) and not g4.events.is_empty())

	print("Economía")
	var before := g.res.duplicate()
	var n_before := g.machines.size()
	g.remove(tur)
	check("quitar una máquina devuelve la mitad", g.machines.size() == n_before - 1 and g.res["obsidiana"] > before["obsidiana"])
	check("al quitarla se libera su hueco", g.world.area_free(76, 12, 6, 4))
	g.res["obsidiana"] = 1000.0
	g.res["basalto"] = 1000.0
	var r0: float = g.rate_mult("noria")
	check("mejorar sube el ritmo un 35 %", g.buy_upgrade("noria") and absf(g.rate_mult("noria") / r0 - 1.35) < 1e-6)

	print("Presión")
	var g2 := Game.new()
	g2.res["obsidiana"] = 1000.0
	g2.res["basalto"] = 1000.0
	g2.place("aspersor", 73, 37)
	g2.place("recolector", 79, 37)
	g2.place("bomba", 85, 28)
	var n2 := g2.machines.size()
	_steps(g2, 30 * 60)
	check("tapar la chimenea acaba reventando una máquina", g2.machines.size() < n2 and not g2.events.is_empty(), "máquinas %d→%d" % [n2, g2.machines.size()])

	print("Prestigio")
	var g3 := Game.new()
	check("no se puede alejar sin vaciar", not g3.can_zoom_out())
	for i in g3.world.mat.size():
		if g3.world.counts[M.MAGMA] <= int(g3.magma_start * 0.05):
			break
		if g3.world.mat[i] == M.MAGMA:
			g3.world.set_cell(i, M.AIR)
	check("vaciando el 90 % se puede alejar", g3.can_zoom_out())
	g3.zoom_out()
	check("alejar sube la escala y el bonus", g3.scale_idx == 1 and absf(g3.knowledge - 1.6) < 1e-6 and g3.machines.is_empty())
	check("en la escala 2 cada celda es 1 m³", g3.cell_volume() == 1.0)

	print("Guardado")
	var d := g.to_dict()
	var back := Game.from_dict(JSON.parse_string(JSON.stringify(d, "", false, true)))
	check("el guardado conserva máquinas, recursos y mundo",
		back.machines.size() == g.machines.size()
		and absf(back.res["obsidiana"] - g.res["obsidiana"]) < 1e-6
		and back.world.counts[M.MAGMA] == g.world.counts[M.MAGMA]
		and back.level("noria") == 1)
	var back4 := Game.from_dict(JSON.parse_string(JSON.stringify(g4.to_dict(), "", false, true)))
	check("el guardado conserva la roca abierta con dinamita", back4.world.counts[M.ROCK] == g4.world.counts[M.ROCK] and back4.world.interior == g4.world.interior)
	var off := back.apply_offline(3600.0)
	check("fuera ganas a medio ritmo", off["obsidiana"] > 0.0, str(off))

	print("FALLOS: %d" % fails)
	quit(1 if fails > 0 else 0)
