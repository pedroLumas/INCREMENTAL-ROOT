extends SceneTree
## Monta una base razonable y la deja correr para ver si el sistema se encadena.
## Uso: godot --headless --path godot -s res://tests/escenario.gd
const Game := preload("res://scripts/game/game.gd")
const M := preload("res://scripts/sim/materials.gd")

func _initialize() -> void:
	var g := Game.new()
	g.res["obsidiana"] = 1000.0
	g.res["basalto"] = 1000.0
	var plan := [["aspersor", 74, 24], ["recolector", 73, 35], ["noria", 82, 28], ["turbina", 76, 12]]
	for p in plan:
		var why := g.place_problem(p[0], p[1], p[2])
		print("%-10s en (%d,%d): %s" % [p[0], p[1], p[2], "ok" if why == "" else why])
		g.place(p[0], p[1], p[2])
	g.res = {"obsidiana": 0.0, "basalto": 0.0, "energia": 0.0}
	var t0 := Time.get_ticks_usec()
	for s in range(1, 121):
		for k in 30:
			g.step()
		if s % 20 == 0:
			var st := []
			for m in g.machines:
				st.append("%s:%s" % [m.id, "ok" if m.working() else (m.status if m.status != "" else "parada")])
			print("t=%3ds magma %4d (vaciado %2d %%) · entra %.1f/s sale %.1f/s · obs %.0f bas %.0f ene %.0f · agua %d vapor %d obsidiana %d · %s" % [
				s, g.world.counts[M.MAGMA], int(g.drained() * 100), g.rate_in, g.rate_out,
				g.res["obsidiana"], g.res["basalto"], g.res["energia"],
				g.world.counts[M.WATER], g.world.counts[M.STEAM], g.world.counts[M.OBSIDIAN], " ".join(st)])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / (120 * 30)
	print("tick medio con máquinas: %.2f ms" % ms)
	quit()
