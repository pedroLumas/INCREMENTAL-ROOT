// Simula un jugador que hace 3 clics/s y compra siempre la mejora más rentable.
// Uso:  node prototype/tools/simular.js '{"SPOON":{"cr":3.7}}'
// El JSON opcional sobreescribe constantes de core.js para probar curvas de coste.
const V = require('../core.js');
const over = JSON.parse(process.argv[2] || '{}');
for (const k of Object.keys(over)) typeof over[k] === 'object' ? Object.assign(V.C[k], over[k]) : (V.C[k] = over[k]);

const CPS = 3;
const rate = (st) => V.autoRate(st) + CPS * V.clickVolume(st);
function bestBuy(st) {
  let best = null;
  for (const k of ['spoon', 'helper', 'speed']) {
    const c = V.cost(st, k), t = { ...st };
    t.magma = Infinity; V.buy(t, k);
    const score = (rate(t) - rate(st)) / c;
    if (!best || score > best.score) best = { k, c, score };
  }
  return best;
}

const st = V.newState(0);
for (let run = 1; run <= 4; run++) {
  let t = 0, next = -4; const marks = []; const dt = 0.5;
  while (t < 8 * 3600) {
    for (let i = 0; i < CPS * dt; i++) V.scoop(st);
    V.tick(st, dt); t += dt;
    for (let g = 0; g < 500; g++) { const b = bestBuy(st); if (st.magma >= b.c) V.buy(st, b.k); else break; }
    while (Math.log10(rate(st)) >= next) { if (next % 2 === 0) marks.push(`10^${next} m³/s @ ${(t / 60).toFixed(0)} min`); next++; }
    if (V.canErupt(st) && st.hole * V.C.ERUPT_MULT >= V.VOLCANO.volume) V.erupt(st);
    if (V.calderaReady(st)) break;
  }
  const lv = `cuchara ${st.spoonLvl} · ayudantes ${st.helpers} · ritmo ${st.speedLvl}`;
  const s = V.caldera(st, 0);
  console.log(`Vuelta ${run}: ${(t / 60).toFixed(1)} min · ${lv} · bonus ×${s.bonus.toFixed(2)}`);
  console.log('  ' + marks.join(' | '));
}
