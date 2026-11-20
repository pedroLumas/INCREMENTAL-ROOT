// Vaciar el Vesubio: lógica pura del prototipo (sin DOM).
// Se carga en el navegador (window.Volcan) y en Node (module.exports) para simular la economía.
(function (root) {
  'use strict';

  // --- Mundo -----------------------------------------------------------------
  // Vesubio como cono simplificado: 14 km de base, 1.281 m de altura.
  // No hay una cifra publicada fiable del volumen del edificio; esto es una estimación geométrica.
  const VOLCANO = {
    name: 'Vesubio',
    radius: 7000, // m
    height: 1281, // m
  };
  VOLCANO.volume = (Math.PI / 3) * VOLCANO.radius * VOLCANO.radius * VOLCANO.height; // ≈ 6,57e10 m³

  // --- Reglas ----------------------------------------------------------------
  const C = {
    S0: 1.5e-5,          // cuchara sopera: 15 mL
    TAU: 30,             // s: el agujero se rellena con constante de tiempo TAU (entra = agujero / TAU)
    ERUPT_MULT: 10,      // una erupción multiplica el agujero ×10
    ERUPT_CHARGE: 90,    // s para cargar la presión
    // Mejoras: coste = c0 * cr^nivel (en m³ de magma enfriado)
    // Ajustado con simulación: un jugador óptimo tarda ~37 min la 1ª vuelta, ~17 la 2ª, ~8 la 3ª.
    SPOON: { mult: 2, c0: 1e-4, cr: 3.6 },
    HELPER: { rate: 0.5, c0: 2e-4, cr: 1.14 },
    SPEED: { mult: 2, c0: 5e-3, cr: 24 },
    // Bonus de caldera: ×(1 + sqrt(magma extraído en la vuelta / volumen del volcán))
    SAVE_KEY: 'vaciar-volcan-v1',
  };

  function newState(now) {
    return {
      v: 1,
      hole: 0,            // m³ vaciados ahora mismo
      magma: 0,           // m³ de magma enfriado disponible (la moneda)
      runTotal: 0,        // m³ extraídos en esta vuelta (la montaña)
      spoonLvl: 0,
      helpers: 0,
      speedLvl: 0,
      pressure: 0,        // 0..1
      calderaDue: false,  // se ha vaciado entero: la caldera ya no se puede deshacer
      calderas: 0,
      legacy: 1,          // multiplicador permanente por calderas
      clicks: 0,
      runStart: now,
      runSeconds: 0,
      bestRunSeconds: null,
      lastSeen: now,
    };
  }

  // --- Derivados -------------------------------------------------------------
  const spoon = (st) => C.S0 * Math.pow(C.SPOON.mult, st.spoonLvl);
  const scoopsPerSec = (st) => st.helpers * C.HELPER.rate * Math.pow(C.SPEED.mult, st.speedLvl);
  // Extracción automática en m³/s (sin contar clics)
  const autoRate = (st) => spoon(st) * scoopsPerSec(st) * st.legacy;
  const clickVolume = (st) => spoon(st) * st.legacy;
  const inflow = (st) => st.hole / C.TAU;

  function cost(st, kind) {
    if (kind === 'spoon') return C.SPOON.c0 * Math.pow(C.SPOON.cr, st.spoonLvl);
    if (kind === 'helper') return C.HELPER.c0 * Math.pow(C.HELPER.cr, st.helpers);
    if (kind === 'speed') return C.SPEED.c0 * Math.pow(C.SPEED.cr, st.speedLvl);
    throw new Error('mejora desconocida: ' + kind);
  }

  function buy(st, kind) {
    const c = cost(st, kind);
    if (st.magma < c) return false;
    st.magma -= c;
    if (kind === 'spoon') st.spoonLvl++;
    else if (kind === 'helper') st.helpers++;
    else if (kind === 'speed') st.speedLvl++;
    return true;
  }

  // Si el agujero llega al volumen del volcán, la caldera queda marcada.
  function markCaldera(st) {
    if (st.hole >= VOLCANO.volume * 0.999999) {
      st.hole = VOLCANO.volume;
      st.calderaDue = true;
    }
  }

  // --- Acciones --------------------------------------------------------------
  function scoop(st) {
    const v = clickVolume(st);
    st.magma += v;
    st.runTotal += v;
    st.hole = Math.min(VOLCANO.volume, st.hole + v);
    st.clicks++;
    markCaldera(st);
    return v;
  }

  const canErupt = (st) => st.pressure >= 1 && st.hole > 0;

  function erupt(st) {
    if (!canErupt(st)) return 0;
    const before = st.hole;
    st.hole = Math.min(VOLCANO.volume, st.hole * C.ERUPT_MULT);
    st.pressure = 0;
    markCaldera(st);
    return st.hole - before; // lo expulsado: no va a la montaña
  }

  const calderaReady = (st) => !!st.calderaDue;
  const calderaBonus = (st) => 1 + Math.sqrt(st.runTotal / VOLCANO.volume);

  function caldera(st, now) {
    const bonus = calderaBonus(st);
    const summary = {
      bonus,
      runSeconds: st.runSeconds,
      runTotal: st.runTotal,
      legacyBefore: st.legacy,
    };
    const keep = {
      calderas: st.calderas + 1,
      legacy: st.legacy * bonus,
      bestRunSeconds: st.bestRunSeconds == null ? st.runSeconds : Math.min(st.bestRunSeconds, st.runSeconds),
    };
    Object.assign(st, newState(now), keep);
    summary.legacyAfter = st.legacy;
    return summary;
  }

  // --- Tiempo ----------------------------------------------------------------
  // Agujero: dH/dt = A - H/TAU, con solución exacta para cualquier dt.
  function tick(st, dt) {
    if (dt <= 0 || st.calderaDue) return;
    const A = autoRate(st);
    const eq = A * C.TAU;
    st.hole = eq + (st.hole - eq) * Math.exp(-dt / C.TAU);
    if (st.hole > VOLCANO.volume) st.hole = VOLCANO.volume;
    if (st.hole < 0) st.hole = 0;
    const gained = A * dt;
    st.magma += gained;
    st.runTotal += gained;
    st.pressure = Math.min(1, st.pressure + dt / C.ERUPT_CHARGE);
    st.runSeconds += dt;
    markCaldera(st);
  }

  // Tiempo fuera: ganas lo de tus ayudantes y el agujero nunca queda peor que como lo dejaste.
  function offline(st, dt) {
    if (dt <= 0) return null;
    const holeBefore = st.hole;
    const magmaBefore = st.magma;
    tick(st, dt);
    if (st.hole < holeBefore) st.hole = holeBefore;
    return { seconds: dt, gained: st.magma - magmaBefore };
  }

  // --- Escala de Fermi -------------------------------------------------------
  // Volúmenes aproximados, para comparar.
  const FERMI = [
    [1.5e-5, 'una cucharada', 'cucharadas'],
    [2.5e-4, 'una taza', 'tazas'],
    [1e-2, 'un cubo', 'cubos'],
    [1.5e-1, 'una bañera', 'bañeras'],
    [3e1, 'un camión cisterna', 'camiones cisterna'],
    [2.5e3, 'una piscina olímpica', 'piscinas olímpicas'],
    [2e5, 'el dirigible Hindenburg', 'Hindenburgs'],
    [2.6e6, 'la Gran Pirámide de Guiza', 'Grandes Pirámides'],
    [7.4e9, 'el lago Ness', 'lagos Ness'],
    [VOLCANO.volume, 'el Vesubio entero', 'Vesubios'],
    [8.9e10, 'el lago Lemán', 'lagos Lemán'],
    [8.93e11, 'el lago Titicaca', 'lagos Titicaca'],
  ];

  function fermi(vol) {
    if (!(vol > 0)) return 'nada';
    let pick = FERMI[0];
    for (const f of FERMI) if (vol >= f[0] * 0.95) pick = f;
    const n = vol / pick[0];
    if (n < 1.5) return (n < 0.95 ? 'casi ' : '') + pick[1];
    const nf = n < 10 ? Math.round(n * 10) / 10 : Math.round(n);
    return nf.toLocaleString('es-ES') + ' ' + pick[2];
  }

  const api = {
    VOLCANO, C, FERMI,
    newState, spoon, scoopsPerSec, autoRate, clickVolume, inflow, cost, buy,
    scoop, canErupt, erupt, calderaReady, calderaBonus, caldera, tick, offline, fermi,
  };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.Volcan = api;
})(typeof window !== 'undefined' ? window : globalThis);
