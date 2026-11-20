// Tests del motor (mismos que godot/tests/pruebas.gd). Uso: node web/tests/motor.test.js
const V = require('../engine.js');
V.setRandom(V.seeded(12345)); // física repetible
const { MAGMA, WATER, STEAM, OBSIDIAN, ROCK, MACHINE } = V.MAT;
let fails = 0;
const check = (name, ok, detail = '') => { console.log(`  ${ok ? 'ok   ' : 'FALLA'} ${name}${ok ? '' : '  ' + detail}`); if (!ok) fails++; };
const steps = (g, n) => { for (let k = 0; k < n; k++) g.step(); };

console.log('Formato');
check('volumen', V.Fmt.vol(1.5e-5) === '15 mL' && V.Fmt.vol(3.01e10) === '30,1 km³', V.Fmt.vol(3.01e10));
check('fermi', V.Fmt.fermi(7.4e9 * 4.1) === '4,1 lagos Ness', V.Fmt.fermi(7.4e9 * 4.1));

console.log('Mundo');
const w = new V.World(); w.generate(1);
const magma0 = w.counts[MAGMA];
check('el volcán empieza con ~1500 celdas de magma', magma0 > 1300 && magma0 < 1700, magma0);
check('el magma entra por abajo', w.injectMagma() && w.counts[MAGMA] === magma0 + 1);
for (let x = 74; x < 86; x++) w.put(x, 30, WATER);
for (let k = 0; k < 90; k++) w.step();
check('agua + magma = obsidiana + vapor', w.counts[OBSIDIAN] > 0, w.counts[OBSIDIAN]);
let deepest = 0, top = V.H;
for (let i = 0; i < w.mat.length; i++) {
  if (w.mat[i] === OBSIDIAN) deepest = Math.max(deepest, Math.floor(i / V.W));
  if (w.mat[i] === MAGMA) top = Math.min(top, Math.floor(i / V.W));
}
check('la obsidiana flota sobre el magma', deepest <= top + 2, `obs y=${deepest}, magma y=${top}`);
const w2 = new V.World(); w2.generate(1);
for (let x = 6; x < 14; x++) w2.put(x, 20, STEAM);
let rose = false;
for (let k = 0; k < 30 && !rose; k++) { w2.step(); for (let i = 0; i < 20 * V.W; i++) if (w2.mat[i] === STEAM) rose = true; }
check('el vapor sube', rose);
const w3 = new V.World(); w3.generate(1); w3.fillArea(73, 39, 14, 1, MACHINE);
check('si algo tapa la chimenea, el magma no puede entrar', !w3.injectMagma());

console.log('Máquinas');
const g = new V.Game(); g.res.obsidiana = 1000; g.res.basalto = 1000;
check('no se construye dentro de la roca', g.placeProblem('noria', 10, 70) !== '');
check('no se construye dentro del magma', g.placeProblem('noria', 78, 45) !== '');
g.world.put(60, 10, WATER);
check('se puede construir encima del agua', g.placeProblem('aspersor', 58, 8) === '');
check('se construye en hueco libre', g.place('aspersor', 74, 24) !== null);
check('cada máquina del mismo tipo cuesta más', g.buildCost('aspersor').obsidiana > 15);
g.place('recolector', 73, 35); g.place('noria', 82, 28); const tur = g.place('turbina', 76, 12);
g.res = { obsidiana: 0, basalto: 0, energia: 0 };
steps(g, 30 * 60);
check('el recolector da obsidiana', g.res.obsidiana > 20, g.res.obsidiana);
check('la noria saca magma y da basalto', g.res.basalto > 10, g.res.basalto);
check('la turbina da energía', g.res.energia > 5, g.res.energia);
g.remove(tur); // sin turbina: la bomba no recibe energía de nadie
g.res.obsidiana = 1000; g.res.basalto = 1000; g.res.energia = 0;
const bom = g.place('bomba', 80, 26);
steps(g, 30);
check('la bomba sin energía no saca', bom && bom.status === 'Sin energía', bom ? bom.status : g.placeProblem('bomba', 80, 26));
g.res.energia = 50; const bas0 = g.res.basalto;
steps(g, 90);
check('la bomba con energía saca magma', g.res.basalto > bas0 && g.res.energia < 50);

console.log('Mecánica añadida después (dinamita)');
const g4 = new V.Game(); g4.res.obsidiana = 500; g4.res.basalto = 500;
const rock0 = g4.world.counts[ROCK];
const din = g4.place('dinamita', 40, 30);
check('la dinamita se puede poner pegada a la roca', din !== null, g4.placeProblem('dinamita', 40, 30));
steps(g4, 60);
check('la dinamita abre la roca', g4.world.counts[ROCK] < rock0 - 20, `${rock0} → ${g4.world.counts[ROCK]}`);
check('y se retira sola', !g4.machines.includes(din) && g4.events.length > 0);

console.log('Economía');
const n0 = g.machines.length, obs0 = g.res.obsidiana;
g.remove(bom);
check('quitar devuelve la mitad', g.machines.length === n0 - 1 && g.res.obsidiana > obs0);
check('al quitarla se libera su hueco', g.world.areaFree(80, 26, 2, 12));
g.res.obsidiana = 1000; g.res.basalto = 1000;
const r0 = g.rateMult('noria');
check('mejorar sube el ritmo un 35 %', g.buyUpgrade('noria') && Math.abs(g.rateMult('noria') / r0 - 1.35) < 1e-6);

console.log('Presión');
const g2 = new V.Game(); g2.res.obsidiana = 1000; g2.res.basalto = 1000;
g2.place('aspersor', 73, 37); g2.place('recolector', 79, 37); g2.place('bomba', 85, 28);
const nm = g2.machines.length;
steps(g2, 30 * 60);
check('tapar la chimenea acaba reventando una máquina', g2.machines.length < nm && g2.events.length > 0, `${nm}→${g2.machines.length}`);

console.log('Prestigio');
const g3 = new V.Game();
check('no se puede alejar sin vaciar', !g3.canZoomOut());
for (let i = 0; i < g3.world.mat.length && g3.world.counts[MAGMA] > g3.magmaStart * 0.05; i++) if (g3.world.mat[i] === MAGMA) g3.world.set(i, 0);
check('vaciando el 90 % se puede alejar', g3.canZoomOut());
g3.zoomOut();
check('alejar sube la escala y el bonus', g3.scaleIdx === 1 && Math.abs(g3.knowledge - 1.6) < 1e-9 && g3.machines.length === 0);
check('en la escala 2 cada celda es 1 m³', g3.cellVolume() === 1);

console.log('Guardado');
const back = V.Game.fromDict(JSON.parse(JSON.stringify(g.toDict())));
check('el guardado conserva máquinas, recursos y mundo', back.machines.length === g.machines.length && Math.abs(back.res.obsidiana - g.res.obsidiana) < 1e-6 && back.world.counts[MAGMA] === g.world.counts[MAGMA] && back.level('noria') === 1);
check('el guardado conserva la roca abierta con dinamita', V.Game.fromDict(JSON.parse(JSON.stringify(g4.toDict()))).world.counts[ROCK] === g4.world.counts[ROCK]);
check('fuera ganas a medio ritmo', back.applyOffline(3600).obsidiana > 0);

const t0 = process.hrtime.bigint();
const gb = new V.Game();
for (let k = 0; k < 600; k++) { gb.world.put(70, 24, WATER); gb.world.put(90, 24, WATER); gb.step(); }
console.log(`tick medio: ${(Number(process.hrtime.bigint() - t0) / 1e6 / 600).toFixed(2)} ms`);
console.log(`FALLOS: ${fails}`);
process.exit(fails ? 1 : 0);
