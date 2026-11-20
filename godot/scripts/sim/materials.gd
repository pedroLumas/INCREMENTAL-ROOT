class_name Materials
extends RefCounted
## Materiales del mundo. Para añadir uno: un id, una fila en DEFS y, si hace falta,
## filas en REACTIONS o DECAYS. La física no necesita saber nada más.

# Tipos de comportamiento
const EMPTY := 0
const STATIC := 1
const GRANULAR := 2
const LIQUID := 3
const GAS := 4

const AIR := 0
const ROCK := 1
const MACHINE := 2   ## celdas ocupadas por máquinas: sólidas para la física
const MAGMA := 3
const WATER := 4
const STEAM := 5
const OBSIDIAN := 6
const COUNT := 16    ## tamaño de las tablas (deja hueco para materiales nuevos)

## [id, nombre, tipo, densidad, fluidez (0..1: probabilidad de moverse de lado / de subir), 4 colores]
const DEFS := [
	[AIR, "aire", EMPTY, 0.0, 0.0, []],
	[ROCK, "roca", STATIC, 9.0, 0.0, ["#4a3b44", "#53434c", "#433540", "#58474f"]],
	[MACHINE, "máquina", STATIC, 9.0, 0.0, []],
	[MAGMA, "magma", LIQUID, 2.6, 0.35, ["#e2560f", "#ee6512", "#d24a0c", "#f87a1a"]],
	[WATER, "agua", LIQUID, 1.0, 1.0, ["#3d7fbf", "#4789c8", "#3576b4", "#5296d4"]],
	[STEAM, "vapor", GAS, 0.1, 0.45, ["#c9c2cf", "#dad4df", "#b8b0bf", "#e6e1ea"]],
	[OBSIDIAN, "obsidiana", GRANULAR, 2.4, 0.0, ["#22172a", "#2f2139", "#1a1120", "#43325a"]],
]

## [a, b, a pasa a, b pasa a, probabilidad por tick y vecino]
const REACTIONS := [
	[MAGMA, WATER, OBSIDIAN, STEAM, 0.45],   # el agua templa el magma: obsidiana + vapor
	[OBSIDIAN, MAGMA, MAGMA, MAGMA, 0.0006], # la obsidiana que toca magma acaba fundiéndose
]

## [material, pasa a, probabilidad por tick]
const DECAYS := [
	[STEAM, WATER, 0.012],   # el vapor se condensa y llueve
	[WATER, AIR, 0.0004],    # el agua se evapora poco a poco
]


static func name_of(id: int) -> String:
	for d in DEFS:
		if d[0] == id:
			return d[1]
	return "?"
