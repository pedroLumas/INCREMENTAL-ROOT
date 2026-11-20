class_name Machine
extends RefCounted
## Base de todas las máquinas. Una máquina ocupa un rectángulo de celdas (sólidas para la física)
## y en cada tick lee y escribe celdas del mundo. No conoce a las demás máquinas: si dos máquinas
## se combinan, es porque una deja en el mundo algo que la otra recoge.
##
## Para añadir una máquina: un script que extienda este, una entrada en catalog.gd. Nada más.

const M := preload("res://scripts/sim/materials.gd")
const PX := 2  ## píxeles por celda en el SubViewport

const COL_FRAME := Color("#2a2230")
const COL_METAL := Color("#8d868c")
const COL_METAL_LIT := Color("#c9c3c8")
const COL_LED_ON := Color("#8fd694")
const COL_LED_IDLE := Color("#ffc15c")
const COL_LED_BAD := Color("#ff6b5b")

var id := ""
var def: Dictionary = {}
var x := 0
var y := 0
var w := 1
var h := 1
var phase := 0.0       ## animación
var acc := 0.0         ## trabajo fraccional acumulado
var work_t := 0.0      ## > 0 mientras ha trabajado hace poco
var status := ""       ## por qué no trabaja ("" si todo va bien)
var retired := false   ## true = el juego la retira tras este tick (máquinas de un solo uso)


func setup(p_id: String, p_def: Dictionary, px: int, py: int) -> void:
	id = p_id
	def = p_def
	x = px
	y = py
	w = p_def["size"].x
	h = p_def["size"].y


func contains(cx: int, cy: int) -> bool:
	return cx >= x and cx < x + w and cy >= y and cy < y + h


func working() -> bool:
	return work_t > 0.0


## Llamar desde tick(): n = unidades de trabajo hechas en este tick.
func _did(n: int, dt: float) -> void:
	if n > 0:
		work_t = 0.4
		status = ""
	else:
		work_t = maxf(0.0, work_t - dt)
	if work_t > 0.0:
		phase += dt


## Cuánto puede hacer este tick según su ritmo (unidades/s). Devuelve unidades enteras.
func _budget(rate: float, dt: float) -> int:
	acc += rate * dt
	var n := int(acc)
	acc -= n
	return n


func tick(_game, _dt: float) -> void:
	pass


## Zona del mundo sobre la que actúa (para dibujarla al construir o seleccionar). Vacía si no aplica.
func zone(_game) -> Rect2i:
	return Rect2i()


## Dibujo en píxeles del SubViewport (PX px por celda).
func draw(_ci: CanvasItem) -> void:
	pass


func _rect(ci: CanvasItem, cx: float, cy: float, cw: float, ch: float, c: Color) -> void:
	ci.draw_rect(Rect2(x * PX + cx, y * PX + cy, cw, ch), c)


func _led(ci: CanvasItem) -> void:
	var c := COL_LED_ON if working() else (COL_LED_BAD if status != "" else COL_LED_IDLE)
	ci.draw_rect(Rect2(x * PX + w * PX - 2, y * PX, 2, 2), c)
