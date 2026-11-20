# Vaciar el Vesubio (Godot)

Prototipo jugable en **Godot 4.5** (renderer Compatibility): vaciar un volcán con una cuchara, como incremental con final.
Probado con Godot 4.5.1.

## Abrir y jugar

1. Abre Godot 4.5 o superior → **Importar** → elige `godot/project.godot`.
2. Pulsa **F5** (o el botón ▶).

Controles:
- **Sacar una cucharada:** con el botón, haciendo clic en la escena o con la barra espaciadora.
- **Modo prueba:** F1 (o arrancar con `-- --prueba`) para acelerar el tiempo ×10/×100 o simular 8 h fuera.

La partida se guarda sola cada 5 s y al cerrar, en `user://partida.json`.
En Linux está en `~/.local/share/godot/app_userdata/Vaciar el Vesubio/`.

## Cómo está hecho

| Archivo | Qué hace |
|---|---|
| `scripts/core.gd` | Reglas puras: mejoras, relleno, erupción, caldera y offline. Sin nodos. |
| `scripts/state.gd` | Estado de la partida y guardado a JSON. |
| `scripts/fmt.gd` | Números en español: `4.382.102.872.737.283`, `30,1 km³`, `0,00000000000069 %`. |
| `scripts/scene_view.gd` | Escena pixel art: un SubViewport de 320×180 que se muestra ×2 sin suavizado, con el Vesubio entero (altura ×3) y una lupa a la escala de la cuchara. |
| `scripts/main.gd` | Interfaz (construida en código), bucle, guardado, modales. |
| `scenes/main.tscn` | Escena principal (solo el nodo raíz con `main.gd`). |
| `fonts/` | Pixelify Sans (licencia OFL, ver `fonts/OFL.txt`), sin ligaduras para que "fi" no se lea "Á". |

Reglas y números: los mismos que la versión web (ver `../prototype/README.md`).
Con un jugador óptimo, la 1ª vuelta dura unos 37 min, la 2ª 17, la 3ª 8 y la 4ª 5.

## Tests (desde la raíz del repo)

```bash
godot --headless --path godot --import
```

```bash
godot --headless --path godot -s res://tests/pruebas.gd
```

```bash
godot --headless --path godot -s res://tests/simular.gd -- spoon_cr=3.7
```

```bash
xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/capturas.gd -- --salida=/tmp/capturas
```

- `pruebas.gd`: 26 tests de reglas y formato.
- `simular.gd`: duración de las vueltas con otra curva de costes.
- `capturas.gd`: recorre una partida y guarda capturas. **Borra la partida guardada.**

## Lo que falta a propósito

- **Arte y sonido:** sprites de pixel art y sonido (la escena son polígonos planos).
- **Escalera de volcanes:** Stromboli → Vesubio → Krakatoa → Yellowstone → manto → la Tierra.
- **El final:** tu montaña de obsidiana resulta ser el nuevo volcán.
