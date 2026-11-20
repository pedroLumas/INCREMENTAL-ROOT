# Prototipo: Vaciar el Vesubio

Prototipo jugable del concepto que eligió el consejo: **vaciar un volcán con una cuchara**, como incremental con final.
Sin arte final: la escena se dibuja con formas simples en un canvas de 320×200 escalado con píxeles duros, para adelantar el pixel art.

## Cómo jugar

Abre `index.html` en el navegador (no hace falta servidor). La partida se guarda en ese navegador.

- **Sacar una cucharada:** con el botón, tocando la escena o con la barra espaciadora.
- **Mejoras:** una cuchara más grande (×2), ayudantes (media cucharada por segundo cada uno, también offline) y ayudantes más rápidos (×2).
- **Erupción:** se carga en 90 s y multiplica el agujero ×10. Lo que sale no va a tu montaña.
- **Caldera:** cuando vacías el volcán entero, se hunde y empiezas otro con un bonus permanente de ×(1 + √(magma sacado / volumen del Vesubio)). Si esperas antes de la erupción final, el bonus es mayor.
- **Modo prueba:** añade `#prueba` a la URL para acelerar el tiempo (×10, ×100) o simular 8 h fuera.

## Qué prueba (protocolo del consejo)

1. Juega **2 horas** de verdad, no 15 minutos.
2. Ciérralo **8 horas** y vuelve.
3. Si al volver no te apetece comprar "una mejora más", se descarta el volcán y se prueba *42 Dobleces* reutilizando el código.

Preguntas que debe responder:
- ¿Engancha ver bajar el contador de cucharadas aunque el dibujo sea plano?
- ¿Se entiende la carrera "Sacas / Entra" sin explicación?
- ¿La erupción final se vive como premio? ¿Dudas entre hundir ya o esperar más bonus?
- ¿La lupa transmite la escala absurda (cuchara diminuta frente a volcán enorme)?

## Reglas y números

| Pieza | Valor |
|---|---|
| Volumen del Vesubio | ≈ 66 km³: cono simplificado de 14 km de base y 1.281 m de alto. No hay una cifra oficial del volumen del edificio. |
| Cuchara inicial | 15 mL (cucharada sopera) |
| Relleno | Entra = agujero / 30 s. El agujero tiende a (lo que sacas × 30 s). Nunca hay erupción en tu contra. |
| Offline | Ganas lo de tus ayudantes; el agujero nunca queda peor que como lo dejaste. |
| Costes | cuchara ×3,6 por nivel · ayudante ×1,14 por unidad · ritmo ×24 por nivel |
| Dibujo | Altura ×3, como en los cortes geológicos, porque el Vesubio real es muy plano. |

Duración con un jugador óptimo (`node prototype/tools/simular.js`): **1ª vuelta ≈ 37 min, 2ª ≈ 17, 3ª ≈ 8, 4ª ≈ 5**.
Un jugador real tardará más. Para probar otra curva: `node prototype/tools/simular.js '{"SPOON":{"cr":3.7}}'`.

## Lo que falta a propósito

- Pixel art final y sonido.
- La escalera de volcanes (Stromboli → Vesubio → Krakatoa → Yellowstone → manto → la Tierra): de momento cada caldera repite el Vesubio.
- El final: tu montaña de obsidiana resulta ser el nuevo volcán.

## Archivos

- `core.js`: reglas puras, sin DOM. Funciona en navegador (`window.Volcan`) y en Node.
- `index.html`: escena, interfaz, guardado y progreso offline.
- `tools/simular.js`: simulador de economía.
