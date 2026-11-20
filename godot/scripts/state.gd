class_name VolcanState
extends RefCounted
## Estado de una partida. Se guarda como JSON en user://partida.json.

const VERSION := 1

var hole := 0.0            ## m³ vaciados ahora mismo
var magma := 0.0           ## m³ de magma enfriado disponible (la moneda)
var run_total := 0.0       ## m³ sacados en esta vuelta (la montaña)
var spoon_lvl := 0
var helpers := 0
var speed_lvl := 0
var pressure := 0.0        ## 0..1, carga de la erupción
var caldera_due := false   ## se ha vaciado entero: la caldera ya no se puede deshacer
var calderas := 0
var legacy := 1.0          ## multiplicador permanente por calderas
var clicks := 0
var run_seconds := 0.0
var best_run_seconds := -1.0
var last_seen := 0.0       ## hora Unix del último guardado

const FIELDS := [
	"hole", "magma", "run_total", "spoon_lvl", "helpers", "speed_lvl", "pressure", "caldera_due",
	"calderas", "legacy", "clicks", "run_seconds", "best_run_seconds", "last_seen",
]


func _init(now: float = 0.0) -> void:
	last_seen = now


func to_dict() -> Dictionary:
	var d := {"v": VERSION}
	for f in FIELDS:
		d[f] = get(f)
	return d


static func from_dict(d: Dictionary) -> VolcanState:
	var s := VolcanState.new()
	for f in FIELDS:
		if not d.has(f):
			continue
		match typeof(s.get(f)):
			TYPE_INT:
				s.set(f, int(d[f]))
			TYPE_BOOL:
				s.set(f, bool(d[f]))
			_:
				s.set(f, float(d[f]))
	return s


func copy() -> VolcanState:
	return VolcanState.from_dict(to_dict())
