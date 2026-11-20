extends "res://scripts/machines/machine.gd"
## Atrapa el vapor que la toca y lo convierte en energía.

const COL_HOUSING := Color("#3a3340")
const COL_BLADE := Color("#c9c3c8")
const COL_GLOW := Color("#ffc15c")


func tick(game, dt: float) -> void:
	var n := _budget(def["base"]["rate"], dt)
	var got := 0
	for k in n:
		if game.world.take_one(x - 1, y - 1, x + w, y + h, M.STEAM):
			got += 1
		else:
			break
	if got > 0:
		game.gain_energy(got * def["base"]["energy"] * game.rate_mult(id))
	elif game.res["energia"] >= game.energy_cap - 0.01:
		status = "Batería llena"
	else:
		status = "No le llega vapor"
	_did(got, dt)


func draw(ci: CanvasItem) -> void:
	var pw := w * PX
	var ph := h * PX
	_rect(ci, 0, 0, pw, ph, COL_HOUSING)
	var c := Vector2(x * PX + pw / 2.0, y * PX + ph / 2.0)
	for k in 3:
		var a := phase * 9.0 + k * TAU / 3.0
		ci.draw_line(c, c + Vector2(cos(a), sin(a)) * (ph / 2.0 - 1.0), COL_BLADE, 1.0)
	if working():
		_rect(ci, 0, ph - 1, pw, 1, COL_GLOW)
	_led(ci)


func zone(_game) -> Rect2i:
	return Rect2i(x - 1, y - 1, w + 2, h + 2)
