class_name Fmt
extends RefCounted
## Formato de números en español: punto para miles, coma decimal, unidades de volumen.

const SUP := {"-": "⁻", "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"}


## Entero con puntos de miles (como es-ES: 4 cifras sin separador).
static func group_int(n: int) -> String:
	var s := str(absi(n))
	var neg := "-" if n < 0 else ""
	if s.length() <= 4:
		return neg + s
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return neg + out


## Número con `digits` cifras significativas, sin ceros sobrantes.
static func sig(x: float, digits: int = 3) -> String:
	if x == 0.0:
		return "0"
	var e := floori(log(absf(x)) / log(10.0))
	var dec := maxi(0, digits - 1 - e)
	var s := ("%." + str(dec) + "f") % x
	if dec > 0:
		s = s.rstrip("0").rstrip(".")
	return s.replace(".", ",")


static func sup(n: int) -> String:
	var out := ""
	for c in str(n):
		out += SUP[c]
	return out


static func sci(x: float) -> String:
	var e := floori(log(absf(x)) / log(10.0))
	return "%s × 10%s" % [sig(x / pow(10.0, e)), sup(e)]


static func num(x: float) -> String:
	if is_inf(x) or is_nan(x):
		return "∞"
	if absf(x) >= 1e15:
		return sci(x)
	if absf(x) >= 1000.0:
		return group_int(int(roundf(x)))
	return sig(x)


## Entero completo (para el contador de cucharadas) mientras quepa en 64 bits.
static func big_int(x: float) -> String:
	if x < 9e18:
		return group_int(int(ceilf(x)))
	return sci(x)


static func vol(m3: float) -> String:
	if not (m3 > 0.0):
		return "0 mL"
	if m3 < 1e-3:
		return sig(m3 * 1e6) + " mL"
	if m3 < 1.0:
		return sig(m3 * 1e3) + " L"
	if m3 < 1e9:
		return num(m3) + " m³"
	return num(m3 / 1e9) + " km³"


static func length(m: float) -> String:
	if m < 0.01:
		return sig(m * 1000.0) + " mm"
	if m < 1.0:
		return sig(m * 100.0) + " cm"
	if m < 1000.0:
		return sig(m) + " m"
	return sig(m / 1000.0) + " km"


static func pct(p: float) -> String:
	if p >= 99.995:
		return "100 %"
	if p <= 0.0:
		return "0 %"
	if p >= 0.01:
		return sig(p, 4 if p >= 10.0 else 3) + " %"
	var d := mini(20, ceili(-log(p) / log(10.0)) + 1)
	return (("%." + str(d) + "f") % p).replace(".", ",") + " %"


@warning_ignore("integer_division")
static func dur(seconds: float) -> String:
	var s := maxi(0, floori(seconds))
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%d h %d min" % [h, m]
	return "%d:%02d" % [m, s % 60]


# --- Escala de Fermi (volúmenes aproximados) ---------------------------------
const VESUVIUS_M3 := PI / 3.0 * 7000.0 * 7000.0 * 1281.0  ## cono simplificado, ≈ 6,57e10 m³
const FERMI := [
	[1.5e-5, "una cucharada", "cucharadas"],
	[2.5e-4, "una taza", "tazas"],
	[1e-2, "un cubo", "cubos"],
	[1.5e-1, "una bañera", "bañeras"],
	[3e1, "un camión cisterna", "camiones cisterna"],
	[2.5e3, "una piscina olímpica", "piscinas olímpicas"],
	[2e5, "el dirigible Hindenburg", "Hindenburgs"],
	[2.6e6, "la Gran Pirámide de Guiza", "Grandes Pirámides"],
	[7.4e9, "el lago Ness", "lagos Ness"],
	[VESUVIUS_M3, "el Vesubio entero", "Vesubios"],
	[8.9e10, "el lago Lemán", "lagos Lemán"],
	[8.93e11, "el lago Titicaca", "lagos Titicaca"],
]


## "≈ 4,1 lagos Ness", "una bañera", "nada"…
static func fermi(m3: float) -> String:
	if not (m3 > 0.0):
		return "nada"
	var pick: Array = FERMI[0]
	for f in FERMI:
		if m3 >= f[0] * 0.95:
			pick = f
	var n: float = m3 / pick[0]
	if n < 1.5:
		return ("casi " if n < 0.95 else "") + pick[1]
	var shown := sig(n, 2) if n < 10.0 else num(roundf(n))
	return "%s %s" % [shown, pick[2]]
