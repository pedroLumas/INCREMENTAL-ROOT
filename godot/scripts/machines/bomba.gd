extends "res://scripts/machines/machine.gd"
## Tubo con motor: llega hondo y saca magma deprisa, pero gasta energía.

const COL_PIPE := Color("#7a7078")
const COL_MOTOR := Color("#4a6b5a")


func reach(game) -> int:
	return int(def["base"]["reach"]) + 3 * game.level(id)


func tick(game, dt: float) -> void:
	var n := _budget(def["base"]["rate"] * game.rate_mult(id), dt)
	var got := 0
	var cost: float = def["base"]["energy_per_cell"]
	for k in n:
		if game.res["energia"] < cost:
			status = "Sin energía"
			break
		if game.world.take_one(x, y + h, x + w - 1, y + h + reach(game) - 1, M.MAGMA):
			game.res["energia"] -= cost
			got += 1
		else:
			status = "El magma no llega al tubo"
			break
	if got > 0:
		game.extract(got)
	_did(got, dt)


func draw(ci: CanvasItem) -> void:
	var pw := w * PX
	var ph := h * PX
	_rect(ci, 0, 0, pw, 5, COL_MOTOR)
	_rect(ci, 1, 5, pw - 2, ph - 5, COL_PIPE)
	if working():
		var yy := 5 + (int(phase * 20.0) % (ph - 6))
		_rect(ci, 1, yy, pw - 2, 1, Color("#ff7b1c"))
	_led(ci)


func zone(game) -> Rect2i:
	return Rect2i(x, y + h, w, reach(game))
