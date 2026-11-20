extends "res://scripts/machines/machine.gd"
## Carga de un solo uso: al encenderse abre un hueco redondo en la roca y se retira.

var fuse := 1.2  ## segundos de mecha


func radius(game) -> int:
	return int(def["base"]["radius"]) + game.level(id)


func tick(game, dt: float) -> void:
	fuse -= dt
	phase += dt
	if fuse > 0.0:
		return
	var r := radius(game)
	var cx := x + w / 2
	var cy := y + h / 2
	var opened := 0
	for yy in range(cy - r, cy + r + 1):
		for xx in range(cx - r, cx + r + 1):
			if (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= r * r and game.world.carve(xx, yy):
				opened += 1
	game.events.append("Dinamita: %d celdas de roca abiertas." % opened)
	retired = true


func zone(game) -> Rect2i:
	var r := radius(game)
	return Rect2i(x + w / 2 - r, y + h / 2 - r, 2 * r + 1, 2 * r + 1)


func draw(ci: CanvasItem) -> void:
	_rect(ci, 0, 1, w * PX, h * PX - 1, Color("#b8402c"))
	var spark := Color("#ffc15c") if int(phase * 12.0) % 2 == 0 else Color("#f4e9dd")
	_rect(ci, w * PX - 1, 0, 1, 1, spark)
