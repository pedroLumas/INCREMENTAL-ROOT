extends SceneTree
## Simula un jugador que hace 3 clics/s y compra siempre la mejora más rentable.
## Uso: godot --headless --path godot -s res://tests/simular.gd [-- spoon_cr=3.7 helper_cr=1.15 ...]

const Core := preload("res://scripts/core.gd")
const State := preload("res://scripts/state.gd")
const CPS := 3


func _rate(st: State) -> float:
	return Core.auto_rate(st) + CPS * Core.click_volume(st)


func _best(st: State) -> Dictionary:
	var best := {}
	for k in Core.KINDS:
		var c := Core.cost(st, k)
		var t := st.copy()
		t.magma = INF
		Core.buy(t, k)
		var score := (_rate(t) - _rate(st)) / c
		if best.is_empty() or score > best.score:
			best = {"k": k, "c": c, "score": score}
	return best


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() != 2:
			continue
		var v := float(kv[1])
		match kv[0]:
			"spoon_c0": Core.spoon_c0 = v
			"spoon_cr": Core.spoon_cr = v
			"helper_c0": Core.helper_c0 = v
			"helper_cr": Core.helper_cr = v
			"speed_c0": Core.speed_c0 = v
			"speed_cr": Core.speed_cr = v
			_: push_error("Parámetro desconocido: " + kv[0])
	var st := State.new(0.0)
	for run in range(1, 5):
		var t := 0.0
		var dt := 0.5
		var next := -4
		var marks := []
		while t < 8 * 3600:
			for i in int(CPS * dt):
				Core.scoop(st)
			Core.tick(st, dt)
			t += dt
			for g in 500:
				var b := _best(st)
				if st.magma >= b.c:
					Core.buy(st, b.k)
				else:
					break
			while log(_rate(st)) / log(10.0) >= next:
				if next % 2 == 0:
					marks.append("10^%d m³/s @ %d min" % [next, int(t / 60.0)])
				next += 1
			if Core.can_erupt(st) and st.hole * Core.ERUPT_MULT >= Core.VOLUME:
				Core.erupt(st)
			if Core.caldera_ready(st):
				break
		var lv := "cuchara %d · ayudantes %d · ritmo %d" % [st.spoon_lvl, st.helpers, st.speed_lvl]
		var s := Core.caldera(st, 0.0)
		print("Vuelta %d: %.1f min · %s · bonus ×%.2f" % [run, t / 60.0, lv, s.bonus])
		print("  " + " | ".join(marks))
	quit()
