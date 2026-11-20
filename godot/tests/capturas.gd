extends SceneTree
## Recorre una partida y guarda capturas. Necesita pantalla (no --headless).
## Uso: godot --path godot -s res://tests/capturas.gd -- --salida=/ruta/a/carpeta
## Ojo: borra la partida guardada en user:// antes de empezar.

const Core := preload("res://scripts/core.gd")
const State := preload("res://scripts/state.gd")

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
	if FileAccess.file_exists(Core.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Core.SAVE_PATH))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("captura ", name, "  modal=", main.modal.visible, "  faltan=", main.lbl_remaining.text, "  lupa=", main.lbl_lupa.text)


func _set_state(patch: Dictionary) -> void:
	var s := State.new(Time.get_unix_time_from_system())
	for k in patch:
		s.set(k, patch[k])
	s.hole = Core.auto_rate(s) * Core.REFILL_TIME
	main.st = s
	main._update_ui()


func _process(delta: float) -> bool:
	t += delta
	if t < wait_until:
		return false
	match step:
		0:
			for i in 30:
				main._do_scoop()
			Core.buy(main.st, "spoon")
			Core.buy(main.st, "helper")
			wait_until = t + 0.15
		1:
			_shot("1-temprano.png")
			_set_state({"spoon_lvl": 20, "helpers": 150, "speed_lvl": 8, "magma": 1e6, "run_total": 5e8, "pressure": 1.0, "run_seconds": 700.0})
			wait_until = t + 0.4
		2:
			_shot("2-mitad.png")
			main._do_erupt()
			wait_until = t + 0.35
		3:
			_shot("3-erupcion.png")
			_set_state({"spoon_lvl": 27, "helpers": 222, "speed_lvl": 10, "magma": 1e9, "run_total": 3e10, "pressure": 1.0, "run_seconds": 2200.0})
			wait_until = t + 0.4
		4:
			_shot("4-final.png")
			main._do_erupt()
			wait_until = t + 1.3
		5:
			_shot("5-hundimiento.png")
			wait_until = t + 1.5
		6:
			_shot("6-caldera.png")
			main._close_modal()
			wait_until = t + 0.3
		7:
			_shot("7-nuevo-vesubio.png")
			main.st.helpers = 40
			main.st.spoon_lvl = 10
			main.st.speed_lvl = 3
			main._apply_away(8 * 3600.0)
			wait_until = t + 0.3
		8:
			_shot("8-offline.png")
			return true
	step += 1
	return false
