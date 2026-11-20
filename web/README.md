# Vaciar el Vesubio (web)

La misma simulación que [`../godot/`](../godot/), en HTML/JavaScript, para probarla en cualquier navegador (también en el móvil).
Mismas reglas y números que la versión de Godot.

## Jugar

Abre `index.html` en el navegador (no hace falta servidor). La partida se guarda en ese navegador.
Añade `#prueba` a la dirección para el modo prueba: tiempo ×4/×8, +500 recursos, simular 8 h fuera y vaciar el 90 %.

Controles:
- **Ratón:** elige una máquina (o teclas 1–6), pasa por la escena para ver la vista previa (verde, ámbar o roja) y haz clic para construir. Clic en una máquina para verla, mejorarla o quitarla. Clic derecho o Esc para soltar.
- **Móvil:** elige una máquina, toca la escena para ver dónde va y toca otra vez en el mismo sitio para construir. «Soltar» para dejar de construir.

## Archivos

| Archivo | Qué hace |
|---|---|
| `engine.js` | Motor sin interfaz: materiales, mundo, máquinas, catálogo, partida, guardado y formato. Funciona en el navegador y en Node. |
| `index.html` | Interfaz: escena en un canvas de 320×180 con píxeles duros, barra de máquinas, panel y avisos. |
| `tests/motor.test.js` | 32 tests del motor, con física repetible (azar con semilla). |

```bash
node web/tests/motor.test.js
```

Para añadir mecánicas, el modelo es el mismo que en Godot (ver `../godot/README.md`):
- **Un material:** una fila en `DEFS`, `REACTIONS` o `DECAYS`.
- **Una máquina:** una clase que extienda `Machine` y una entrada en `CATALOG`.

Si se cambian las reglas, conviene cambiarlas en las dos versiones.
