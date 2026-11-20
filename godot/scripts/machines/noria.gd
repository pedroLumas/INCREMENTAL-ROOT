extends "res://scripts/machines/machine.gd"
## Noria de cubos: baja los cangilones al magma que tiene justo debajo y lo saca.
## Lo que saca se enfría fuera en basalto. No necesita energía.

const COL_BUCKET := Color("#6b5a52")
const COL_FULL := Color("#ff7b1c")


func reach(_game) -> int:
	return int(def["base"]["reach"])


func tick(game, dt: float) -> void:
	var n := _budget(def["base"]["rate"] * game.rate_mult(id), dt)
	var got := 0
	for k in n:
		if game.world.take_one(x, y + h, x + w - 1, y + h + reach(game) - 1, M.MAGMA):
			got += 1
		else:
			status = "El magma no llega a los cubos"
			break
	if got > 0:
		game.extract(got)
	_did(got, dt)


func draw(ci: CanvasItem) -> void:
	var pw := w * PX
	var ph := h * PX
	_rect(ci, 0, 0, 1, ph, COL_FRAME)
	_rect(ci, pw - 1, 0, 1, ph, COL_FRAME)
	_rect(ci, 0, 0, pw, 2, COL_METAL)
	# cangilones: bajan vacíos por la izquierda y suben llenos por la derecha
	var off := int(phase * 10.0) % 4
	for k in range(-1, ph / 4 + 1):
		var yy := k * 4 + off
		if yy >= 2 and yy < ph - 1:
			_rect(ci, 1, ph - yy - 2, 2, 2, COL_BUCKET)
			_rect(ci, pw - 3, yy, 2, 2, COL_FULL if working() else COL_BUCKET)
	_led(ci)


func zone(game) -> Rect2i:
	return Rect2i(x, y + h, w, reach(game))
