class_name Catalog
extends RefCounted
## Catálogo de máquinas (datos). Para añadir una máquina: su script y una entrada aquí.
## "base" son sus números de partida; las mejoras multiplican el ritmo un 35 % por nivel.

const ORDER := ["aspersor", "recolector", "noria", "turbina", "bomba", "dinamita"]

const DEFS := {
	"aspersor": {
		"name": "Aspersor",
		"desc": "Echa agua por debajo. Si cae sobre magma, lo templa: sale obsidiana (flota) y vapor (sube).",
		"script": preload("res://scripts/machines/aspersor.gd"),
		"size": Vector2i(6, 3),
		"cost": {"obsidiana": 15.0},
		"growth": 1.55,
		"base": {"rate": 2.0},
		"upgrade": {"name": "Más caudal", "effect": "+35 % de agua", "cost": {"obsidiana": 30.0}, "growth": 2.2},
		"unlock_scale": 0,
	},
	"recolector": {
		"name": "Recolector",
		"desc": "Recoge la obsidiana que tiene debajo (4 celdas). Si no la recoges, la obsidiana acaba fundiéndose otra vez.",
		"script": preload("res://scripts/machines/recolector.gd"),
		"size": Vector2i(6, 3),
		"cost": {"obsidiana": 20.0},
		"growth": 1.55,
		"base": {"rate": 4.0, "reach": 4},
		"upgrade": {"name": "Pala más grande", "effect": "+35 % de ritmo y +1 celda de alcance", "cost": {"obsidiana": 40.0}, "growth": 2.2},
		"unlock_scale": 0,
	},
	"noria": {
		"name": "Noria de cubos",
		"short": "Noria",
		"desc": "Mete los cangilones hasta 5 celdas por debajo (atraviesan agua y costra), saca magma que fuera se enfría en basalto. No gasta energía.",
		"script": preload("res://scripts/machines/noria.gd"),
		"size": Vector2i(4, 10),
		"cost": {"obsidiana": 25.0},
		"growth": 1.6,
		"base": {"rate": 1.2, "reach": 5},
		"upgrade": {"name": "Cangilones más grandes", "effect": "+35 % de ritmo", "cost": {"obsidiana": 40.0, "basalto": 20.0}, "growth": 2.2},
		"unlock_scale": 0,
	},
	"turbina": {
		"name": "Turbina de vapor",
		"short": "Turbina",
		"desc": "Atrapa el vapor que la toca y lo convierte en energía para las bombas.",
		"script": preload("res://scripts/machines/turbina.gd"),
		"size": Vector2i(6, 4),
		"cost": {"obsidiana": 40.0, "basalto": 25.0},
		"growth": 1.6,
		"base": {"rate": 20.0, "energy": 1.0},
		"upgrade": {"name": "Álabes de obsidiana", "effect": "+35 % de energía por vapor", "cost": {"obsidiana": 60.0}, "growth": 2.2},
		"unlock_scale": 0,
	},
	"dinamita": {
		"name": "Dinamita",
		"desc": "Un solo uso: abre un hueco redondo en la roca de alrededor. Sirve para hacer sitio, encauzar el agua… o perforar hasta la cámara.",
		"script": preload("res://scripts/machines/dinamita.gd"),
		"size": Vector2i(2, 2),
		"cost": {"obsidiana": 30.0, "basalto": 30.0},
		"growth": 1.25,
		"base": {"radius": 6},
		"upgrade": {"name": "Más carga", "effect": "+1 celda de radio", "cost": {"obsidiana": 60.0, "basalto": 60.0}, "growth": 2.0},
		"unlock_scale": 0,
	},
	"bomba": {
		"name": "Bomba de magma",
		"short": "Bomba",
		"desc": "Tubo que llega hondo (9 celdas) y saca magma deprisa. Gasta 0,5 de energía por celda.",
		"script": preload("res://scripts/machines/bomba.gd"),
		"size": Vector2i(2, 12),
		"cost": {"obsidiana": 70.0, "basalto": 60.0},
		"growth": 1.7,
		"base": {"rate": 5.0, "reach": 9, "energy_per_cell": 0.5},
		"upgrade": {"name": "Tubo más largo", "effect": "+3 celdas de alcance y +35 % de ritmo", "cost": {"obsidiana": 100.0, "basalto": 100.0}, "growth": 2.2},
		"unlock_scale": 0,
	},
}
