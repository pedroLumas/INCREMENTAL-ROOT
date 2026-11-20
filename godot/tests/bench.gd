extends SceneTree
## Mide cuánto tarda un tick de física con el volcán lleno y agua cayendo.
const World := preload("res://scripts/sim/world.gd")
const M := preload("res://scripts/sim/materials.gd")

func _initialize() -> void:
	var w := World.new()
	w.generate(1)
	print("magma inicial: ", w.counts[M.MAGMA], " celdas")
	# agua cayendo sobre el magma desde dos puntos
	var t0 := Time.get_ticks_usec()
	for k in 600:
		for x in [70, 90]:
			w.put(x, 24, M.WATER)
		if k % 10 == 0:
			w.inject_magma()
		w.step()
	var dt := (Time.get_ticks_usec() - t0) / 600.0
	print("tick medio: %.2f ms  (a 30 ticks/s = %.0f %% de CPU)" % [dt / 1000.0, dt / 1000.0 * 30.0 / 10.0])
	print("magma %d · agua %d · vapor %d · obsidiana %d" % [w.counts[M.MAGMA], w.counts[M.WATER], w.counts[M.STEAM], w.counts[M.OBSIDIAN]])
	quit()
