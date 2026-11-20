extends "res://scripts/machines/machine.gd"
## Echa agua por debajo. Si el agua cae sobre magma, el mundo la convierte en obsidiana y vapor.

const COL_TANK := Color("#3d5f80")
const COL_TANK_LIT := Color("#5d86ad")


func tick(game, dt: float) -> void:
	var n := _budget(def["base"]["rate"] * game.rate_mult(id), dt)
	var made := 0
	for k in n:
		var nx := x + 1 + randi() % (w - 2)
		if game.world.put(nx, y + h, M.WATER):
			made += 1
		else:
			status = "La salida está tapada"
	_did(made, dt)


func draw(ci: CanvasItem) -> void:
	_rect(ci, 0, 0, w * PX, h * PX - 1, COL_TANK)
	_rect(ci, 1, 1, w * PX - 2, 1, COL_TANK_LIT)
	for k in range(1, w - 1):
		var drip := working() and int(phase * 8.0 + k) % 3 == 0
		_rect(ci, k * PX, h * PX - 1, 1, 1, Color("#5aa0dc") if drip else COL_FRAME)
	_led(ci)


func zone(_game) -> Rect2i:
	return Rect2i(x + 1, y + h, w - 2, 1)
