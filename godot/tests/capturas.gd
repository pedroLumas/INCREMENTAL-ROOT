extends SceneTree
## Recorre una partida y guarda capturas. Necesita pantalla (no --headless).
## Uso: xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/capturas.gd -- --salida=/ruta
## Ojo: borra la partida guardada en user:// antes de empezar.

const Game := preload("res://scripts/game/game.gd")
const M := preload("res://scripts/sim/materials.gd")

var main: Control
var out_dir := "user://capturas"
var t := 0.0
var step := 0
var wait_until := 0.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--salida="):
			out_dir = arg.trim_prefix("--salida=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if FileAccess.file_exists(Game.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	seed(7)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(out_dir.path_join(name))
	var g = main.game
	print("captura %-18s magma %4d · vaciado %2d %% · entra %.1f sale %.1f · obs %.0f bas %.0f ene %.0f · máquinas %d · aviso: %s" % [
		name, g.world.counts[M.MAGMA], int(g.drained() * 100), g.rate_in, g.rate_out,
		g.res["obsidiana"], g.res["basalto"], g.res["energia"], g.machines.size(), main.toast.text])


func _run(g, seconds: float) -> void:
	for k in int(seconds * 30):
		g.step()


func _process(delta: float) -> bool:
	t += delta
	if t < wait_until:
		return false
	var g = main.game
	match step:
		0:
			wait_until = t + 0.5
		1:
			_shot("1-inicio.png")
			main._select_tool("aspersor")
			main.hover = Vector2i(77, 26)
			wait_until = t + 0.3
		2:
			_shot("2-construir.png")
			g.res["obsidiana"] = 400.0
			g.res["basalto"] = 200.0
			for p in [["aspersor", 74, 24], ["recolector", 73, 35], ["noria", 82, 28], ["turbina", 76, 12], ["aspersor", 60, 14]]:
				g.place(p[0], p[1], p[2])
			main.tool = ""
			main.hover = Vector2i(-1, -1)
			_run(g, 60.0)
			main.selected = g.machines[2]
			wait_until = t + 0.5
		3:
			_shot("3-base.png")
			main.selected = null
			g.res["obsidiana"] += 600.0
			g.res["basalto"] += 600.0
			g.res["energia"] = 60.0
			g.place("bomba", 80, 26)
			g.place("turbina", 90, 10)
			g.buy_upgrade("noria")
			g.buy_upgrade("noria")
			_run(g, 40.0)
			g.place("dinamita", 40, 30)
			g.place("dinamita", 118, 30)
			_run(g, 2.0)
			main.selected = g.machines[g.machines.size() - 2]
			wait_until = t + 0.5
		4:
			_shot("4-carrera.png")
			main.selected = null
			# Tapar la chimenea con máquinas hasta que la presión reviente una
			var w = g.world
			for i in w.mat.size():
				if w.mat[i] == M.MAGMA and i / 160 < 46:
					w.set_cell(i, M.AIR)
			g.res["obsidiana"] += 300.0
			g.place("recolector", 73, 40)
			g.place("aspersor", 79, 40)
			for k in int(40.0 * 30):
				g.step()
				if not g.events.is_empty():
					break
			wait_until = t + 0.4
		5:
			_shot("5-erupcion.png")
			main._debug_drain()
			main._update_ui()
			wait_until = t + 0.3
		6:
			main._ask_zoom()
			wait_until = t + 0.3
		7:
			_shot("6-alejar.png")
			main._close_modal(true)
			wait_until = t + 0.6
		8:
			_shot("7-escala-2.png")
			return true
	step += 1
	return false
