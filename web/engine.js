// Vaciar el Vesubio: motor de la simulación (sin DOM). Mismas reglas y números que la versión de Godot.
// Se carga en el navegador (window.Vesubio) y en Node (module.exports) para los tests.
(function (root) {
  'use strict';

  // ===== Materiales ==========================================================================
  // Para añadir uno: un id, una fila en DEFS y, si hace falta, filas en REACTIONS o DECAYS.
  const EMPTY = 0, STATIC = 1, GRANULAR = 2, LIQUID = 3, GAS = 4;
  const AIR = 0, ROCK = 1, MACHINE = 2, MAGMA = 3, WATER = 4, STEAM = 5, OBSIDIAN = 6;
  const N = 16;
  // [id, nombre, tipo, densidad, fluidez, 4 colores]
  const DEFS = [
    [AIR, 'aire', EMPTY, 0, 0, []],
    [ROCK, 'roca', STATIC, 9, 0, ['#4a3b44', '#53434c', '#433540', '#58474f']],
    [MACHINE, 'máquina', STATIC, 9, 0, []],
    [MAGMA, 'magma', LIQUID, 2.6, 0.35, ['#e2560f', '#ee6512', '#d24a0c', '#f87a1a']],
    [WATER, 'agua', LIQUID, 1.0, 1.0, ['#3d7fbf', '#4789c8', '#3576b4', '#5296d4']],
    [STEAM, 'vapor', GAS, 0.1, 0.45, ['#c9c2cf', '#dad4df', '#b8b0bf', '#e6e1ea']],
    [OBSIDIAN, 'obsidiana', GRANULAR, 2.4, 0, ['#22172a', '#2f2139', '#1a1120', '#43325a']],
  ];
  // [a, b, a pasa a, b pasa a, probabilidad por tick y vecino]
  const REACTIONS = [
    [MAGMA, WATER, OBSIDIAN, STEAM, 0.45],   // el agua templa el magma: obsidiana + vapor
    [OBSIDIAN, MAGMA, MAGMA, MAGMA, 0.0006], // la obsidiana que toca magma acaba fundiéndose
  ];
  // [material, pasa a, probabilidad por tick]
  const DECAYS = [
    [STEAM, WATER, 0.012],  // el vapor se condensa y llueve
    [WATER, AIR, 0.0004],   // el agua se evapora poco a poco
  ];
  const nameOf = (id) => (DEFS.find((d) => d[0] === id) || [0, '?'])[1];

  // Azar de la física: Math.random por defecto; los tests usan uno con semilla para ser repetibles.
  let rnd = Math.random;

  // ===== Mundo ===============================================================================
  const W = 160, H = 90;
  const CENTER_X = 80, RIM_Y = 22, CRATER_HALF_TOP = 24, CONDUIT_TOP = 38, CONDUIT_HALF = 7;
  const CHAMBER_Y = 77, CHAMBER_RX = 36, CHAMBER_RY = 10, MAGMA_START_Y = 40, SOURCE_Y = 86;

  function mulberry32(a) {
    return function () {
      a |= 0; a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // Tablas derivadas (compartidas por todos los mundos)
  const kind = new Uint8Array(N), density = new Float32Array(N), flow = new Float32Array(N);
  const enter = new Uint8Array(N * N);
  const reactA = new Uint8Array(N * N).fill(255), reactB = new Uint8Array(N * N), reactP = new Float32Array(N * N);
  const hasReact = new Uint8Array(N), decayTo = new Uint8Array(N), decayP = new Float32Array(N);
  for (const d of DEFS) { kind[d[0]] = d[2]; density[d[0]] = d[3]; flow[d[0]] = d[4]; }
  for (let a = 0; a < N; a++) {
    for (let b = 0; b < N; b++) {
      let ok = 0;
      if (kind[a] >= GRANULAR) {
        if (b === AIR) ok = 1;
        else if (kind[a] === GAS) ok = kind[b] === LIQUID ? 1 : 0;        // el gas sube a través de líquidos
        else if (kind[b] === LIQUID || kind[b] === GAS) ok = density[a] > density[b] ? 1 : 0;
      }
      enter[a * N + b] = ok;
    }
  }
  function addReaction(a, b, ra, rb, p) { reactA[a * N + b] = ra; reactB[a * N + b] = rb; reactP[a * N + b] = p; hasReact[a] = 1; }
  for (const r of REACTIONS) { addReaction(r[0], r[1], r[2], r[3], r[4]); addReaction(r[1], r[0], r[3], r[2], r[4]); }
  for (const d of DECAYS) { decayTo[d[0]] = d[1]; decayP[d[0]] = d[2]; }

  class World {
    constructor() {
      this.mat = new Uint8Array(W * H);
      this.shade = new Uint8Array(W * H);
      this.interior = new Uint8Array(W * H);
      this.upd = new Uint8Array(W * H);
      this.counts = new Int32Array(N);
      this.stamp = 1;
      this.ticks = 0;
      this.lastBlockCell = -1;
      this.sourceCols = [];
      for (let x = CENTER_X - CONDUIT_HALF + 1; x < CENTER_X + CONDUIT_HALF - 1; x++) this.sourceCols.push(x);
    }

    generate(seed) {
      const rnd = mulberry32(seed || 1);
      const { mat, shade, interior } = this;
      mat.fill(ROCK); interior.fill(0); this.upd.fill(0);
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          const i = y * W + x;
          shade[i] = Math.floor(rnd() * 4);
          const dx = Math.abs(x - CENTER_X);
          const surface = RIM_Y + Math.max(0, dx - CRATER_HALF_TOP) * 0.72;
          if (y < surface) { mat[i] = AIR; continue; }
          let cavity = false;
          if (y >= RIM_Y && y < CONDUIT_TOP) {
            const t = (y - RIM_Y) / (CONDUIT_TOP - RIM_Y);
            cavity = dx <= CRATER_HALF_TOP + (CONDUIT_HALF - CRATER_HALF_TOP) * t;
          } else if (y >= CONDUIT_TOP && y < CHAMBER_Y - CHAMBER_RY + 2) {
            cavity = x >= CENTER_X - CONDUIT_HALF && x < CENTER_X + CONDUIT_HALF;
          }
          if (!cavity && y < H - 2) {
            const ex = (x - CENTER_X) / CHAMBER_RX, ey = (y - CHAMBER_Y) / CHAMBER_RY;
            cavity = ex * ex + ey * ey <= 1;
          }
          if (cavity) { interior[i] = 1; mat[i] = y >= MAGMA_START_Y ? MAGMA : AIR; }
        }
      }
      this.recount();
    }

    recount() { this.counts.fill(0); for (let i = 0; i < this.mat.length; i++) this.counts[this.mat[i]]++; }
    inside(x, y) { return x >= 0 && x < W && y >= 0 && y < H; }
    get(x, y) { return this.inside(x, y) ? this.mat[y * W + x] : ROCK; }
    set(i, m) { const old = this.mat[i]; if (old === m) return; this.counts[old]--; this.counts[m]++; this.mat[i] = m; }

    // Quita una celda del material dentro del rectángulo (la más alta primero).
    takeOne(x0, y0, x1, y1, m) {
      for (let y = Math.max(0, y0); y <= Math.min(H - 1, y1); y++) {
        for (let x = Math.max(0, x0); x <= Math.min(W - 1, x1); x++) {
          const i = y * W + x;
          if (this.mat[i] === m) { this.set(i, AIR); return true; }
        }
      }
      return false;
    }
    put(x, y, m) { if (!this.inside(x, y)) return false; const i = y * W + x; if (this.mat[i] !== AIR) return false; this.set(i, m); return true; }
    // Se puede construir sobre aire, gas o líquido ligero (agua); no sobre roca, magma, obsidiana ni máquinas.
    areaFree(x0, y0, w, h) {
      if (x0 < 0 || y0 < 0 || x0 + w > W || y0 + h > H) return false;
      for (let y = y0; y < y0 + h; y++) {
        for (let x = x0; x < x0 + w; x++) {
          const m = this.mat[y * W + x], k = kind[m];
          if (!(k === EMPTY || k === GAS || (k === LIQUID && density[m] < 2))) return false;
        }
      }
      return true;
    }
    fillArea(x0, y0, w, h, m) { for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) this.set(y * W + x, m); }
    carve(x, y) {
      if (!this.inside(x, y)) return false;
      const i = y * W + x;
      if (this.mat[i] !== ROCK) return false;
      this.interior[i] = 1; this.set(i, AIR); return true;
    }

    // El magma entra por el fondo de la cámara y empuja la columna. false = todo taponado.
    injectMagma() {
      const cols = this.sourceCols, n = cols.length, start = Math.floor(rnd() * n);
      for (let k = 0; k < n; k++) {
        const x = cols[(start + k) % n];
        let y = SOURCE_Y;
        while (y >= 0) {
          const m = this.mat[y * W + x];
          if (m === AIR) break;
          if (kind[m] === STATIC) { this.lastBlockCell = y * W + x; y = -1; break; }
          y--;
        }
        if (y < 0) continue;
        for (let yy = y; yy < SOURCE_Y; yy++) { const a = yy * W + x; this.mat[a] = this.mat[a + W]; }
        this.mat[SOURCE_Y * W + x] = MAGMA;
        this.counts[AIR]--; this.counts[MAGMA]++;
        return true;
      }
      return false;
    }

    step() {
      this.ticks++;
      this.stamp = 1 + (this.ticks & 1);
      const rev = (this.ticks & 1) === 1, mat = this.mat, upd = this.upd, stamp = this.stamp;
      for (let y = H - 1; y >= 0; y--) {
        const row = y * W;
        for (let k = 0; k < W; k++) {
          const x = rev ? W - 1 - k : k, i = row + x, m = mat[i], kd = kind[m];
          if (kd <= STATIC || upd[i] === stamp) continue;
          const dp = decayP[m];
          if (dp > 0 && rnd() < dp) { this.set(i, decayTo[m]); upd[i] = stamp; continue; }
          if (hasReact[m] && this._react(i, x, y, m)) continue;
          if (kd === GAS) this._rise(i, x, y, m); else this._fall(i, x, y, m, kd === LIQUID);
        }
      }
    }
    _swap(i, j) { const t = this.mat[i]; this.mat[i] = this.mat[j]; this.mat[j] = t; this.upd[i] = this.stamp; this.upd[j] = this.stamp; }
    _react(i, x, y, m) {
      const base = m * N;
      for (let n = 0; n < 4; n++) {
        let j;
        if (n === 0) { if (y >= H - 1) continue; j = i + W; }
        else if (n === 1) { if (y === 0) continue; j = i - W; }
        else if (n === 2) { if (x === 0) continue; j = i - 1; }
        else { if (x >= W - 1) continue; j = i + 1; }
        const r = base + this.mat[j];
        if (reactA[r] !== 255 && rnd() < reactP[r]) {
          this.set(i, reactA[r]); this.set(j, reactB[r]); this.upd[i] = this.stamp; this.upd[j] = this.stamp;
          return true;
        }
      }
      return false;
    }
    _fall(i, x, y, m, liquid) {
      const base = m * N, mat = this.mat;
      if (y < H - 1) {
        const j = i + W;
        if (enter[base + mat[j]]) { this._swap(i, j); return; }
        let d = rnd() < 0.5 ? 1 : -1;
        for (let s = 0; s < 2; s++) {
          const nx = x + d;
          if (nx >= 0 && nx < W && enter[base + mat[j + d]]) { this._swap(i, j + d); return; }
          d = -d;
        }
      }
      if (liquid && rnd() < flow[m]) {
        let d = rnd() < 0.5 ? 1 : -1;
        for (let s = 0; s < 2; s++) {
          const nx = x + d;
          if (nx >= 0 && nx < W && enter[base + mat[i + d]]) { this._swap(i, i + d); return; }
          d = -d;
        }
      }
    }
    _rise(i, x, y, m) {
      if (y === 0) { this.set(i, AIR); return; } // se escapa por arriba
      if (rnd() > flow[m]) return;
      const base = m * N, mat = this.mat, j = i - W;
      if (enter[base + mat[j]]) { this._swap(i, j); return; }
      let d = rnd() < 0.5 ? 1 : -1;
      for (let s = 0; s < 2; s++) {
        const nx = x + d;
        if (nx >= 0 && nx < W) {
          if (enter[base + mat[j + d]]) { this._swap(i, j + d); return; }
          if (enter[base + mat[i + d]]) { this._swap(i, i + d); return; }
        }
        d = -d;
      }
    }
  }

  // ===== Máquinas ============================================================================
  // Una máquina ocupa celdas (sólidas para la física) y en cada tick lee y escribe celdas del mundo.
  // No conoce a las demás. Para añadir una: una clase que extienda Machine y una entrada en CATALOG.
  const PX = 2; // píxeles por celda en el lienzo de 320×180
  const COL = { frame: '#2a2230', metal: '#8d868c', metalLit: '#c9c3c8', on: '#8fd694', idle: '#ffc15c', bad: '#ff6b5b' };

  class Machine {
    constructor(id, def, x, y) {
      Object.assign(this, { id, def, x, y, w: def.size[0], h: def.size[1], phase: 0, acc: 0, workT: 0, status: '', retired: false });
    }
    contains(cx, cy) { return cx >= this.x && cx < this.x + this.w && cy >= this.y && cy < this.y + this.h; }
    working() { return this.workT > 0; }
    _did(n, dt) {
      if (n > 0) { this.workT = 0.4; this.status = ''; } else this.workT = Math.max(0, this.workT - dt);
      if (this.workT > 0) this.phase += dt;
    }
    _budget(rate, dt) { this.acc += rate * dt; const n = Math.floor(this.acc); this.acc -= n; return n; }
    tick() {}
    zone() { return null; }
    draw() {}
    _rect(ctx, cx, cy, cw, ch, c) { ctx.fillStyle = c; ctx.fillRect(this.x * PX + cx, this.y * PX + cy, cw, ch); }
    _led(ctx) { this._rect(ctx, this.w * PX - 2, 0, 2, 2, this.working() ? COL.on : (this.status ? COL.bad : COL.idle)); }
  }

  class Aspersor extends Machine {
    tick(g, dt) {
      const n = this._budget(this.def.base.rate * g.rateMult(this.id), dt);
      let made = 0;
      for (let k = 0; k < n; k++) {
        const nx = this.x + 1 + Math.floor(rnd() * (this.w - 2));
        if (g.world.put(nx, this.y + this.h, WATER)) made++; else this.status = 'La salida está tapada';
      }
      this._did(made, dt);
    }
    zone() { return [this.x + 1, this.y + this.h, this.w - 2, 1]; }
    draw(ctx) {
      const pw = this.w * PX, ph = this.h * PX;
      this._rect(ctx, 0, 0, pw, ph - 1, '#3d5f80');
      this._rect(ctx, 1, 1, pw - 2, 1, '#5d86ad');
      for (let k = 1; k < this.w - 1; k++) {
        const drip = this.working() && Math.floor(this.phase * 8 + k) % 3 === 0;
        this._rect(ctx, k * PX, ph - 1, 1, 1, drip ? '#5aa0dc' : COL.frame);
      }
      this._led(ctx);
    }
  }

  class Recolector extends Machine {
    reach(g) { return this.def.base.reach + g.level(this.id); }
    tick(g, dt) {
      const n = this._budget(this.def.base.rate * g.rateMult(this.id), dt);
      let got = 0;
      const r = this.reach(g);
      for (let k = 0; k < n; k++) {
        if (g.world.takeOne(this.x - 1, this.y + this.h, this.x + this.w, this.y + this.h + r - 1, OBSIDIAN)) got++;
        else { this.status = 'No hay obsidiana debajo'; break; }
      }
      if (got > 0) g.gain('obsidiana', got * g.knowledge);
      this._did(got, dt);
    }
    zone(g) { return [this.x - 1, this.y + this.h, this.w + 2, this.reach(g)]; }
    draw(ctx) {
      const pw = this.w * PX, ph = this.h * PX;
      this._rect(ctx, 0, 0, pw, ph - 1, '#b8902c');
      this._rect(ctx, 1, 1, pw - 2, 1, '#e2b84a');
      const open = Math.floor(this.phase * 6) % 2 === 0;
      for (let k = 0; k < pw; k++) if (k % 2 === (open ? 0 : 1)) this._rect(ctx, k, ph - 1, 1, 1, COL.metalLit);
      this._led(ctx);
    }
  }

  class Noria extends Machine {
    reach() { return this.def.base.reach; }
    tick(g, dt) {
      const n = this._budget(this.def.base.rate * g.rateMult(this.id), dt);
      let got = 0;
      for (let k = 0; k < n; k++) {
        if (g.world.takeOne(this.x, this.y + this.h, this.x + this.w - 1, this.y + this.h + this.reach() - 1, MAGMA)) got++;
        else { this.status = 'El magma no llega a los cubos'; break; }
      }
      if (got > 0) g.extract(got);
      this._did(got, dt);
    }
    zone() { return [this.x, this.y + this.h, this.w, this.reach()]; }
    draw(ctx) {
      const pw = this.w * PX, ph = this.h * PX;
      this._rect(ctx, 0, 0, 1, ph, COL.frame);
      this._rect(ctx, pw - 1, 0, 1, ph, COL.frame);
      this._rect(ctx, 0, 0, pw, 2, COL.metal);
      const off = Math.floor(this.phase * 10) % 4;
      for (let k = -1; k < ph / 4 + 1; k++) {
        const yy = k * 4 + off;
        if (yy >= 2 && yy < ph - 1) {
          this._rect(ctx, 1, ph - yy - 2, 2, 2, '#6b5a52');
          this._rect(ctx, pw - 3, yy, 2, 2, this.working() ? '#ff7b1c' : '#6b5a52');
        }
      }
      this._led(ctx);
    }
  }

  class Turbina extends Machine {
    tick(g, dt) {
      const n = this._budget(this.def.base.rate, dt);
      let got = 0;
      for (let k = 0; k < n; k++) {
        if (g.world.takeOne(this.x - 1, this.y - 1, this.x + this.w, this.y + this.h, STEAM)) got++; else break;
      }
      if (got > 0) g.gainEnergy(got * this.def.base.energy * g.rateMult(this.id));
      else this.status = g.res.energia >= g.energyCap - 0.01 ? 'Batería llena' : 'No le llega vapor';
      this._did(got, dt);
    }
    zone() { return [this.x - 1, this.y - 1, this.w + 2, this.h + 2]; }
    draw(ctx) {
      const pw = this.w * PX, ph = this.h * PX;
      this._rect(ctx, 0, 0, pw, ph, '#3a3340');
      const cx = this.x * PX + pw / 2, cy = this.y * PX + ph / 2, r = ph / 2 - 1;
      ctx.fillStyle = '#c9c3c8';
      for (let k = 0; k < 3; k++) {
        const a = this.phase * 9 + (k * Math.PI * 2) / 3;
        for (let s = 0; s <= r; s += 0.5) ctx.fillRect(Math.floor(cx + Math.cos(a) * s), Math.floor(cy + Math.sin(a) * s), 1, 1);
      }
      if (this.working()) this._rect(ctx, 0, ph - 1, pw, 1, '#ffc15c');
      this._led(ctx);
    }
  }

  class Bomba extends Machine {
    reach(g) { return this.def.base.reach + 3 * g.level(this.id); }
    tick(g, dt) {
      const n = this._budget(this.def.base.rate * g.rateMult(this.id), dt);
      let got = 0;
      const cost = this.def.base.energyPerCell;
      for (let k = 0; k < n; k++) {
        if (g.res.energia < cost) { this.status = 'Sin energía'; break; }
        if (g.world.takeOne(this.x, this.y + this.h, this.x + this.w - 1, this.y + this.h + this.reach(g) - 1, MAGMA)) { g.res.energia -= cost; got++; }
        else { this.status = 'El magma no llega al tubo'; break; }
      }
      if (got > 0) g.extract(got);
      this._did(got, dt);
    }
    zone(g) { return [this.x, this.y + this.h, this.w, this.reach(g)]; }
    draw(ctx) {
      const pw = this.w * PX, ph = this.h * PX;
      this._rect(ctx, 0, 0, pw, 5, '#4a6b5a');
      this._rect(ctx, 1, 5, pw - 2, ph - 5, '#7a7078');
      if (this.working()) this._rect(ctx, 1, 5 + (Math.floor(this.phase * 20) % (ph - 6)), pw - 2, 1, '#ff7b1c');
      this._led(ctx);
    }
  }

  class Dinamita extends Machine {
    constructor(...a) { super(...a); this.fuse = 1.2; }
    radius(g) { return this.def.base.radius + g.level(this.id); }
    tick(g, dt) {
      this.fuse -= dt; this.phase += dt;
      if (this.fuse > 0) return;
      const r = this.radius(g), cx = this.x + Math.floor(this.w / 2), cy = this.y + Math.floor(this.h / 2);
      let opened = 0;
      for (let yy = cy - r; yy <= cy + r; yy++)
        for (let xx = cx - r; xx <= cx + r; xx++)
          if ((xx - cx) ** 2 + (yy - cy) ** 2 <= r * r && g.world.carve(xx, yy)) opened++;
      g.events.push(`Dinamita: ${opened} celdas de roca abiertas.`);
      this.retired = true;
    }
    zone(g) { const r = this.radius(g); return [this.x + Math.floor(this.w / 2) - r, this.y + Math.floor(this.h / 2) - r, 2 * r + 1, 2 * r + 1]; }
    draw(ctx) {
      this._rect(ctx, 0, 1, this.w * PX, this.h * PX - 1, '#b8402c');
      this._rect(ctx, this.w * PX - 1, 0, 1, 1, Math.floor(this.phase * 12) % 2 === 0 ? '#ffc15c' : '#f4e9dd');
    }
  }

  // Catálogo (datos). "base" son los números de partida; cada mejora multiplica el ritmo ×1,35.
  const ORDER = ['aspersor', 'recolector', 'noria', 'turbina', 'bomba', 'dinamita'];
  const CATALOG = {
    aspersor: {
      name: 'Aspersor', cls: Aspersor, size: [6, 3], cost: { obsidiana: 15 }, growth: 1.55, base: { rate: 2 },
      desc: 'Echa agua por debajo. Si cae sobre magma, lo templa: sale obsidiana (flota) y vapor (sube).',
      upgrade: { name: 'Más caudal', effect: '+35 % de agua', cost: { obsidiana: 30 }, growth: 2.2 }, unlockScale: 0,
    },
    recolector: {
      name: 'Recolector', cls: Recolector, size: [6, 3], cost: { obsidiana: 20 }, growth: 1.55, base: { rate: 4, reach: 4 },
      desc: 'Recoge la obsidiana que tiene debajo (4 celdas). Si no la recoges, la obsidiana acaba fundiéndose otra vez.',
      upgrade: { name: 'Pala más grande', effect: '+35 % de ritmo y +1 celda de alcance', cost: { obsidiana: 40 }, growth: 2.2 }, unlockScale: 0,
    },
    noria: {
      name: 'Noria de cubos', short: 'Noria', cls: Noria, size: [4, 10], cost: { obsidiana: 25 }, growth: 1.6, base: { rate: 1.2, reach: 5 },
      desc: 'Mete los cangilones hasta 5 celdas por debajo (atraviesan agua y costra), saca magma que fuera se enfría en basalto. No gasta energía.',
      upgrade: { name: 'Cangilones más grandes', effect: '+35 % de ritmo', cost: { obsidiana: 40, basalto: 20 }, growth: 2.2 }, unlockScale: 0,
    },
    turbina: {
      name: 'Turbina de vapor', short: 'Turbina', cls: Turbina, size: [6, 4], cost: { obsidiana: 40, basalto: 25 }, growth: 1.6, base: { rate: 20, energy: 1 },
      desc: 'Atrapa el vapor que la toca y lo convierte en energía para las bombas.',
      upgrade: { name: 'Álabes de obsidiana', effect: '+35 % de energía por vapor', cost: { obsidiana: 60 }, growth: 2.2 }, unlockScale: 0,
    },
    bomba: {
      name: 'Bomba de magma', short: 'Bomba', cls: Bomba, size: [2, 12], cost: { obsidiana: 70, basalto: 60 }, growth: 1.7, base: { rate: 5, reach: 9, energyPerCell: 0.5 },
      desc: 'Tubo que llega hondo (9 celdas) y saca magma deprisa. Gasta 0,5 de energía por celda.',
      upgrade: { name: 'Tubo más largo', effect: '+3 celdas de alcance y +35 % de ritmo', cost: { obsidiana: 100, basalto: 100 }, growth: 2.2 }, unlockScale: 0,
    },
    dinamita: {
      name: 'Dinamita', cls: Dinamita, size: [2, 2], cost: { obsidiana: 30, basalto: 30 }, growth: 1.25, base: { radius: 6 },
      desc: 'Un solo uso: abre un hueco redondo en la roca de alrededor. Sirve para hacer sitio, encauzar el agua… o perforar hasta la cámara.',
      upgrade: { name: 'Más carga', effect: '+1 celda de radio', cost: { obsidiana: 60, basalto: 60 }, growth: 2.0 }, unlockScale: 0,
    },
  };

  // ===== Partida =============================================================================
  const STEP = 1 / 30, MAX_STEPS_PER_FRAME = 8, SAVE_VERSION = 2;
  const SCALES = [
    { name: 'Una grieta', cell: 1e-3 },
    { name: 'La chimenea', cell: 1 },
    { name: 'La cámara magmática', cell: 1e3 },
    { name: 'El Vesubio', cell: 1e6 },
    { name: 'El manto', cell: 1e9 },
  ];
  const RULES = {
    DRAIN_GOAL: 0.9, INFLOW_BASE: 2.5, INFLOW_DRAIN_BOOST: 1.5, PRESSURE_MAX: 40, PRESSURE_DECAY: 0.5,
    UPGRADE_MULT: 1.35, KNOWLEDGE_PER_SCALE: 1.6, OFFLINE_CAP: 8 * 3600, OFFLINE_EFFICIENCY: 0.5, ENERGY_CAP: 60,
  };
  const START_RES = () => ({ obsidiana: 40, basalto: 0, energia: 0 });

  class Game {
    constructor() {
      this.scaleIdx = 0; this.knowledge = 1; this.totalM3 = 0; this.time = 0; this.events = [];
      this.rateIn = 0; this.rateOut = 0; this.gainRates = { obsidiana: 0, basalto: 0, energia: 0 };
      this._simAcc = 0; this._inflowAcc = 0; this._winT = 0; this._winIn = 0; this._winOut = 0;
      this._winGain = { obsidiana: 0, basalto: 0, energia: 0 };
      this.energyCap = RULES.ENERGY_CAP;
      this.newRun();
    }
    newRun() {
      this.world = new World();
      this.world.generate(1 + this.scaleIdx);
      this.machines = []; this.res = START_RES(); this.levels = {}; this.pressure = 0;
      this.magmaStart = Math.max(1, this.world.counts[MAGMA]);
    }

    advance(realDt, speed = 1) {
      this._simAcc += realDt * speed;
      let n = 0;
      while (this._simAcc >= STEP && n < MAX_STEPS_PER_FRAME) { this.step(); this._simAcc -= STEP; n++; }
      if (n === MAX_STEPS_PER_FRAME) this._simAcc = Math.min(this._simAcc, STEP);
    }
    step() {
      this.time += STEP;
      const w = this.world, before = w.counts[MAGMA];
      w.step();
      let injected = 0;
      this._inflowAcc += this.inflowRate() * STEP;
      while (this._inflowAcc >= 1) {
        this._inflowAcc -= 1;
        if (w.injectMagma()) injected++; else this.pressure += 1;
      }
      this.pressure = Math.max(0, this.pressure - RULES.PRESSURE_DECAY * STEP);
      if (this.pressure >= RULES.PRESSURE_MAX) this._erupt();
      for (const m of this.machines) m.tick(this, STEP);
      for (const m of this.machines.filter((x) => x.retired)) this.remove(m, false);
      const out = injected - (w.counts[MAGMA] - before);
      if (out > 0) this.totalM3 += out * this.cellVolume();
      this._winIn += injected; this._winOut += Math.max(0, out); this._winT += STEP;
      if (this._winT >= 1) {
        const a = 0.3, lerp = (x, y) => x + (y - x) * a;
        this.rateIn = lerp(this.rateIn, this._winIn / this._winT);
        this.rateOut = lerp(this.rateOut, this._winOut / this._winT);
        for (const k in this.gainRates) { this.gainRates[k] = lerp(this.gainRates[k], this._winGain[k] / this._winT); this._winGain[k] = 0; }
        this._winT = 0; this._winIn = 0; this._winOut = 0;
      }
    }
    inflowRate() { return RULES.INFLOW_BASE * (1 + RULES.INFLOW_DRAIN_BOOST * this.drained()); }
    drained() { return Math.min(1, Math.max(0, 1 - this.world.counts[MAGMA] / this.magmaStart)); }
    cellVolume() { return SCALES[Math.min(this.scaleIdx, SCALES.length - 1)].cell; }
    scaleName() { return SCALES[Math.min(this.scaleIdx, SCALES.length - 1)].name; }

    // Economía (la usan las máquinas)
    gain(k, amount) { this.res[k] += amount; this._winGain[k] += amount; }
    gainEnergy(amount) { const b = this.res.energia; this.res.energia = Math.min(this.energyCap, b + amount); this._winGain.energia += this.res.energia - b; }
    extract(cells) { this.gain('basalto', cells * this.knowledge); }
    level(id) { return this.levels[id] || 0; }
    rateMult(id) { return Math.pow(RULES.UPGRADE_MULT, this.level(id)) * this.knowledge; }
    _scaled(cost, f) { const o = {}; for (const k in cost) o[k] = cost[k] * f; return o; }
    buildCost(id) { const d = CATALOG[id]; return this._scaled(d.cost, Math.pow(d.growth, this.countOf(id))); }
    upgradeCost(id) { const u = CATALOG[id].upgrade; return this._scaled(u.cost, Math.pow(u.growth, this.level(id))); }
    canAfford(cost) { for (const k in cost) if ((this.res[k] || 0) < cost[k] - 1e-9) return false; return true; }
    _pay(cost) { for (const k in cost) this.res[k] -= cost[k]; }
    countOf(id) { return this.machines.filter((m) => m.id === id).length; }
    unlocked(id) { return this.scaleIdx >= CATALOG[id].unlockScale; }
    placeProblem(id, x, y) {
      const d = CATALOG[id];
      if (!this.unlocked(id)) return 'Aún no disponible';
      if (!this.world.areaFree(x, y, d.size[0], d.size[1])) return 'Necesita espacio libre';
      if (!this.canAfford(this.buildCost(id))) return 'No te llega';
      return '';
    }
    place(id, x, y) {
      if (this.placeProblem(id, x, y)) return null;
      const d = CATALOG[id];
      this._pay(this.buildCost(id));
      const m = new d.cls(id, d, x, y);
      this.machines.push(m);
      this.world.fillArea(x, y, m.w, m.h, MACHINE);
      return m;
    }
    // Quitar devuelve la mitad de lo que costó.
    remove(m, refund = true) {
      const i = this.machines.indexOf(m);
      if (i < 0) return;
      this.machines.splice(i, 1);
      this.world.fillArea(m.x, m.y, m.w, m.h, AIR);
      if (refund) { const c = this.buildCost(m.id); for (const k in c) this.res[k] += c[k] * 0.5; }
    }
    refundOf(m) { const c = this.buildCost(m.id); for (const k in c) c[k] = (c[k] / CATALOG[m.id].growth) * 0.5; return c; }
    machineAt(cx, cy) { return this.machines.find((m) => m.contains(cx, cy)) || null; }
    buyUpgrade(id) { const c = this.upgradeCost(id); if (!this.canAfford(c)) return false; this._pay(c); this.levels[id] = this.level(id) + 1; return true; }

    // Si el magma no puede subir, la presión crece; al máximo revienta lo que tapa la chimenea.
    _erupt() {
      this.pressure = 0;
      const cell = this.world.lastBlockCell;
      if (cell < 0) return;
      const cx = cell % W, cy = Math.floor(cell / W);
      const victim = this.machineAt(cx, cy);
      if (victim) { this.remove(victim, false); this.events.push(`¡La presión ha reventado tu ${CATALOG[victim.id].name.toLowerCase()}!`); }
      for (let k = 0; k < 24; k++) this.world.put(cx + Math.floor(rnd() * 13) - 6, cy - 1 - Math.floor(rnd() * 8), MAGMA);
    }

    canZoomOut() { return this.drained() >= RULES.DRAIN_GOAL; }
    zoomOut() { if (!this.canZoomOut()) return; this.scaleIdx++; this.knowledge *= RULES.KNOWLEDGE_PER_SCALE; this.newRun(); }

    // Fuera, las máquinas siguen a la mitad de su ritmo medio. El mundo no se mueve.
    applyOffline(seconds) {
      const t = Math.min(seconds, RULES.OFFLINE_CAP), got = { seconds: t };
      for (const k of ['obsidiana', 'basalto']) { got[k] = Math.max(0, this.gainRates[k]) * t * RULES.OFFLINE_EFFICIENCY; this.res[k] += got[k]; }
      const b = this.res.energia;
      this.res.energia = Math.min(this.energyCap, b + Math.max(0, this.gainRates.energia) * t * RULES.OFFLINE_EFFICIENCY);
      got.energia = this.res.energia - b;
      return got;
    }

    toDict() {
      return {
        v: SAVE_VERSION, grid: toB64(this.world.mat), interior: toB64(this.world.interior),
        machines: this.machines.map((m) => ({ id: m.id, x: m.x, y: m.y })),
        res: this.res, levels: this.levels, scale: this.scaleIdx, knowledge: this.knowledge, totalM3: this.totalM3,
        magmaStart: this.magmaStart, pressure: this.pressure, time: this.time, gainRates: this.gainRates, lastSeen: Date.now(),
      };
    }
    static fromDict(d) {
      const g = new Game();
      g.scaleIdx = d.scale | 0; g.newRun();
      const grid = fromB64(d.grid || ''), inter = fromB64(d.interior || '');
      if (grid.length === g.world.mat.length) { g.world.mat.set(grid); g.world.recount(); }
      if (inter.length === g.world.interior.length) g.world.interior.set(inter);
      g.knowledge = +d.knowledge || 1; g.totalM3 = +d.totalM3 || 0; g.magmaStart = d.magmaStart || g.magmaStart;
      g.pressure = +d.pressure || 0; g.time = +d.time || 0;
      for (const k in g.res) g.res[k] = +((d.res || {})[k] ?? g.res[k]);
      for (const k in d.levels || {}) g.levels[k] = d.levels[k] | 0;
      for (const k in g.gainRates) g.gainRates[k] = +((d.gainRates || {})[k] || 0);
      for (const md of d.machines || []) {
        const def = CATALOG[md.id];
        if (!def) continue;
        const m = new def.cls(md.id, def, md.x, md.y);
        g.machines.push(m);
        g.world.fillArea(m.x, m.y, m.w, m.h, MACHINE);
      }
      return g;
    }
  }

  function toB64(bytes) {
    if (typeof Buffer !== 'undefined') return Buffer.from(bytes).toString('base64');
    let s = '';
    for (let i = 0; i < bytes.length; i += 4096) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 4096));
    return btoa(s);
  }
  function fromB64(b64) {
    if (!b64) return new Uint8Array(0);
    if (typeof Buffer !== 'undefined') return new Uint8Array(Buffer.from(b64, 'base64'));
    const s = atob(b64), out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  }

  // ===== Formato (español) ===================================================================
  const NF0 = new Intl.NumberFormat('es-ES', { maximumFractionDigits: 0 });
  const sig = (x, d = 3) => new Intl.NumberFormat('es-ES', { maximumSignificantDigits: d }).format(x);
  const SUP = { '-': '⁻', 0: '⁰', 1: '¹', 2: '²', 3: '³', 4: '⁴', 5: '⁵', 6: '⁶', 7: '⁷', 8: '⁸', 9: '⁹' };
  const Fmt = {
    sig,
    num(x) {
      if (!isFinite(x)) return '∞';
      if (Math.abs(x) >= 1e15) { const e = Math.floor(Math.log10(x)); return sig(x / 10 ** e) + ' × 10' + String(e).split('').map((c) => SUP[c]).join(''); }
      return Math.abs(x) >= 1000 ? NF0.format(x) : sig(x);
    },
    vol(m3) {
      if (!(m3 > 0)) return '0 mL';
      if (m3 < 1e-3) return sig(m3 * 1e6) + ' mL';
      if (m3 < 1) return sig(m3 * 1e3) + ' L';
      if (m3 < 1e9) return Fmt.num(m3) + ' m³';
      return Fmt.num(m3 / 1e9) + ' km³';
    },
    pct(p) {
      if (p >= 99.995) return '100 %';
      if (p <= 0) return '0 %';
      if (p >= 0.01) return sig(p, p >= 10 ? 4 : 3) + ' %';
      const d = Math.min(20, Math.ceil(-Math.log10(p)) + 1);
      return new Intl.NumberFormat('es-ES', { minimumFractionDigits: d, maximumFractionDigits: d }).format(p) + ' %';
    },
    dur(s) {
      s = Math.max(0, Math.floor(s));
      const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
      return h ? `${h} h ${m} min` : `${m}:${String(s % 60).padStart(2, '0')}`;
    },
  };
  const VESUVIUS_M3 = (Math.PI / 3) * 7000 * 7000 * 1281; // cono simplificado, ≈ 6,57e10 m³
  const FERMI = [
    [1.5e-5, 'una cucharada', 'cucharadas'], [2.5e-4, 'una taza', 'tazas'], [1e-2, 'un cubo', 'cubos'],
    [1.5e-1, 'una bañera', 'bañeras'], [3e1, 'un camión cisterna', 'camiones cisterna'],
    [2.5e3, 'una piscina olímpica', 'piscinas olímpicas'], [2e5, 'el dirigible Hindenburg', 'Hindenburgs'],
    [2.6e6, 'la Gran Pirámide de Guiza', 'Grandes Pirámides'], [7.4e9, 'el lago Ness', 'lagos Ness'],
    [VESUVIUS_M3, 'el Vesubio entero', 'Vesubios'], [8.9e10, 'el lago Lemán', 'lagos Lemán'],
    [8.93e11, 'el lago Titicaca', 'lagos Titicaca'],
  ];
  Fmt.fermi = function (m3) {
    if (!(m3 > 0)) return 'nada';
    let pick = FERMI[0];
    for (const f of FERMI) if (m3 >= f[0] * 0.95) pick = f;
    const n = m3 / pick[0];
    if (n < 1.5) return (n < 0.95 ? 'casi ' : '') + pick[1];
    return `${n < 10 ? sig(n, 2) : Fmt.num(Math.round(n))} ${pick[2]}`;
  };

  const api = {
    MAT: { AIR, ROCK, MACHINE, MAGMA, WATER, STEAM, OBSIDIAN }, DEFS, REACTIONS, DECAYS, nameOf,
    W, H, PX, World, Machine, CATALOG, ORDER, Game, SCALES, RULES, STEP, SAVE_VERSION, Fmt, VESUVIUS_M3,
    setRandom(f) { rnd = f || Math.random; }, seeded: (s) => mulberry32(s),
  };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.Vesubio = api;
})(typeof window !== 'undefined' ? window : globalThis);
