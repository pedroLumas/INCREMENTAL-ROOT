extends "res://scripts/machines/machine.gd"
## Recoge la obsidiana que tiene debajo (y un poco a los lados).

const COL_BODY := Color("#b8902c")
const COL_BODY_LIT := Color("#e2b84a")


func reach(game) -> int:
	return int(def["base"]["reach"]) + game.level(id)


func tick(game, dt: float) -> void:
	var n := _budget(def["base"]["rate"] * game.rate_mult(id), dt)
	var got := 0
	var r := reach(game)
	for k in n:
		if game.world.take_one(x - 1, y + h, x + w, y + h + r - 1, M.OBSIDIAN):
			got += 1
		else:
			status = "No hay obsidiana debajo"
			break
	if got > 0:
		game.gain("obsidiana", got * game.knowledge)
	_did(got, dt)


func draw(ci: CanvasItem) -> void:
	_rect(ci, 0, 0, w * PX, h * PX - 1, COL_BODY)
	_rect(ci, 1, 1, w * PX - 2, 1, COL_BODY_LIT)
	var open := int(phase * 6.0) % 2 == 0
	for k in w * PX:
		if k % 2 == (0 if open else 1):
			_rect(ci, k, h * PX - 1, 1, 1, COL_METAL_LIT)
	_led(ci)


func zone(game) -> Rect2i:
	return Rect2i(x - 1, y + h, w + 2, reach(game))
