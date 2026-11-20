# Vaciar el Vesubio (Godot)

Incremental pixel art 2D en **Godot 4.5** (renderer Compatibility). Probado con Godot 4.5.1.

No es un clicker: el volcán es una **simulación de materiales**. El magma sube desde la cámara,
fluye y reacciona; tú colocas máquinas en el corte del volcán y diseñas cómo sacarlo.

## Abrir y jugar

1. Godot 4.5 o superior → **Importar** → `godot/project.godot`.
2. **F5**.

Controles:
- **1–6:** elegir máquina y colocarla con clic. Se ve en verde, ámbar (no te llega) o rojo (no cabe), con su zona de trabajo.
- **Clic en una máquina:** ver qué le pasa, mejorarla o quitarla (Supr). Clic derecho o Esc para soltar.
- **F1:** modo prueba (×4/×8, +500 recursos, simular 8 h fuera, vaciar el 90 %).

La partida se guarda sola cada 5 s y al cerrar, en `user://partida.json`.

## Cómo funciona

**El mundo.** Una rejilla de 160×90 celdas (el corte del volcán) con materiales que siguen reglas genéricas:
caer, fluir, subir, reaccionar y desaparecer.

| Material | Comportamiento |
|---|---|
| Magma | Líquido espeso. Entra por el fondo de la cámara y empuja la columna hacia arriba. |
| Agua | Líquido. Al tocar magma, ambos se convierten en obsidiana + vapor. Se evapora poco a poco. |
| Vapor | Gas. Sube, atraviesa el agua y se condensa en lluvia. |
| Obsidiana | Grano. Flota sobre el magma y forma costra; si toca magma mucho rato, se funde otra vez. |

**Las máquinas** solo leen y escriben celdas. No se conocen entre ellas: se combinan a través del mundo.

| Máquina | Qué hace |
|---|---|
| Aspersor | Echa agua. Sobre el magma, crea obsidiana y vapor. |
| Recolector | Recoge la obsidiana que tiene debajo (la moneda). |
| Noria | Saca magma hasta 5 celdas por debajo; fuera se enfría en basalto. Sin energía. |
| Turbina | Atrapa el vapor que la toca y da energía. |
| Bomba | Saca magma deprisa y hondo, gastando energía. |
| Dinamita | Un solo uso: abre roca. Para hacer sitio, encauzar agua o perforar hasta la cámara. |

**La carrera.** El magma no para de entrar, y cuanto más vacías, más empuja. Para bajar el nivel tienes que sacar
más del que entra, con máquinas cada vez más hondas en la chimenea. Si algo la tapa del todo, sube la presión
y revienta la máquina que la tapa.

**Prestigio.** Al vaciar el 90 % de la escena, alejas la cámara: empiezas de nuevo y cada celda pasa a ser
1.000 veces más volumen (1 L → 1 m³ → 1.000 m³ → el Vesubio real). Te llevas un bonus ×1,6 a todo.

**Tiempo fuera.** Las máquinas producen a la mitad de su ritmo medio, hasta 8 h. El magma te espera donde lo dejaste.

## Añadir mecánicas

La idea central: **las mecánicas se comunican a través del mundo, no entre ellas.** Por eso añadir la siguiente
no obliga a tocar las anteriores.

**Un material nuevo** (p. ej. pómez, gas, azufre): una fila en `scripts/sim/materials.gd`.
- `DEFS`: tipo, densidad, fluidez y colores.
- `REACTIONS` si reacciona al tocar otro material.
- `DECAYS` si se transforma con el tiempo.

La física (`world.gd`) no cambia.

**Una máquina nueva:**
1. Un script en `scripts/machines/` que extienda `machine.gd` e implemente `tick()` (leer y escribir celdas con `world.take_one`, `world.put`, `world.carve`…), `draw()` y, si actúa sobre una zona, `zone()`.
2. Una entrada en `scripts/machines/catalog.gd` con nombre, tamaño, coste, números base, mejora y escala en la que se desbloquea.

La dinamita se añadió así, después de todo lo demás, con un único gancho genérico nuevo
(`retired`: una máquina puede retirarse sola).

## Archivos

| Archivo | Qué hace |
|---|---|
| `scripts/sim/materials.gd` | Materiales, reacciones y transformaciones (datos). |
| `scripts/sim/world.gd` | Rejilla, mapa del volcán y física genérica. |
| `scripts/machines/machine.gd` | Base de las máquinas. |
| `scripts/machines/*.gd` | Una máquina por archivo. |
| `scripts/machines/catalog.gd` | Catálogo de máquinas (datos). |
| `scripts/game/game.gd` | La partida: tiempo, entrada de magma, presión, economía, mejoras, prestigio, guardado. Sin interfaz. |
| `scripts/scene_view.gd` | Dibujo de la escena: textura del mundo (solo se repinta lo que cambia), brillo del magma, máquinas y vista previa. |
| `scripts/main.gd` | Interfaz y controles. |
| `scripts/fmt.gd` | Números en español y comparaciones de volumen. |
| `fonts/` | Pixelify Sans (OFL), sin ligaduras. |

Rendimiento: un tick de física cuesta ~3,5 ms en GDScript (unos 30 ticks/s, el 10–12 % de un núcleo).

## Tests (desde la raíz del repo)

```bash
godot --headless --path godot --import
```

```bash
godot --headless --path godot -s res://tests/pruebas.gd
```

```bash
godot --headless --path godot -s res://tests/escenario.gd
```

```bash
godot --headless --path godot -s res://tests/bench.gd
```

```bash
xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/capturas.gd -- --salida=/tmp/capturas
```

- `pruebas.gd`: 32 tests de física, reacciones, máquinas, economía, presión, prestigio y guardado.
- `escenario.gd`: monta una base y la deja correr 2 minutos, con ritmos y estado de cada máquina.
- `bench.gd`: coste de un tick.
- `capturas.gd`: recorre una partida y guarda capturas. **Borra la partida guardada.**

## Pendiente

- **Arte y audio:** sprites de pixel art de verdad y sonido.
- **Equilibrio:** ajuste fino de costes y ritmos, jugando.
- **Mecánicas por escala:** cada escala debería traer mecánicas nuevas (gas y presión con válvulas, pómez que flota en el agua, costra de basalto que tapona, explosivos en la cámara…). La arquitectura está pensada para eso.
