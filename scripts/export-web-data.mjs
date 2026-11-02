#!/usr/bin/env node
// Exports the website game's data and golden test fixtures into this repo. The website is the
// source of truth: this runs its real engine, so the Swift port is tested against actual output.
//
//   node scripts/export-web-data.mjs [path/to/Shrenil.com/word-bubbles]
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const web = process.argv[2] || path.resolve(repo, '../Shrenil.com/word-bubbles');
const res = path.join(repo, 'WordBubblesCore/Sources/WordBubblesCore/Resources');
const fix = path.join(repo, 'WordBubblesCore/Tests/WordBubblesCoreTests/Fixtures');
fs.mkdirSync(res, { recursive: true });
fs.mkdirSync(fix, { recursive: true });

const html = fs.readFileSync(path.join(web, 'index.html'), 'utf8');
const ctx = {};
vm.createContext(ctx);
const engine = html.match(/<script id="engine">([\s\S]*?)<\/script>/)[1];
vm.runInContext(engine + ';globalThis.WB = WB;', ctx);
vm.runInContext(fs.readFileSync(path.join(web, 'bonus.js'), 'utf8') + ';globalThis.WB_BONUS = WB_BONUS;', ctx);
vm.runInContext(fs.readFileSync(path.join(web, 'secrets.js'), 'utf8') + ';globalThis.WB_SECRETS = WB_SECRETS;', ctx);
const { WB, WB_BONUS, WB_SECRETS } = ctx;
const tzCountry = JSON.parse(html.match(/const WB_TZ_COUNTRY = (\{.*?\});/)[1]);
const tzLocal = JSON.parse(html.match(/const WB_TZ_LOCAL = (\{.*?\});/)[1]);

const write = (dir, name, value) => fs.writeFileSync(path.join(dir, name), JSON.stringify(value));

write(res, 'puzzles.json', WB.PUZZLES);
write(res, 'bonus.json', WB_BONUS);
write(res, 'secrets.json', WB_SECRETS);
write(res, 'timezones.json', { country: tzCountry, local: tzLocal });

// ---- golden fixtures ----
const compact = pz => ({
  level: pz.level, theme: pz.theme, words: pz.words, chunksByWord: pz.chunksByWord,
  bubbles: pz.bubbles.map(b => [b.id, b.text, b.wi, b.ci, b.nudge]),
  unique: pz.unique, strict: pz.strict, attempts: pz.attempts
});
const days = [];
for (let d = 1; d <= 210; d++) days.push(d);
days.push(365, 366, 1000, 4097, 12345, 99999);
const boards = [];
for (const day of days) {
  for (const level of WB.LEVELS) {
    boards.push({ day, ...compact(WB.buildPuzzle(level, day, WB.PUZZLES[WB.puzzleIndex(day)][level])) });
  }
}
write(fix, 'boards.json', boards);
write(fix, 'tutorial.json', compact(WB.buildTutorial()));

// todayNumber is computed from a local calendar date
const dates = [[2026, 8, 1], [2026, 8, 2], [2026, 7, 31], [2026, 10, 2], [2027, 0, 1], [2027, 2, 14], [2028, 1, 29]];
write(fix, 'days.json', dates.map(([y, m, d]) => ({ year: y, month: m + 1, day: d, number: WB.todayNumber(new Date(y, m, d, 12)) })));

// layoutBoard/fitBoardHeight from the page, with the DOM swapped for arguments
function fitHeight(W, n) {
  let best = null;
  for (let cols = 1; cols <= 8; cols++) {
    const rows = Math.ceil(n / cols);
    const cell = Math.min(W / (cols + (rows > 1 ? 0.5 : 0)), 100);
    const needH = (rows > 1 ? (rows - 1) * 0.9 * cell : 0) + cell;
    if (!best || cell > best.cell + 0.5 || (Math.abs(cell - best.cell) <= 0.5 && needH < best.needH)) best = { cell, needH };
  }
  return Math.ceil(best.needH + 12);
}
function layout(W, H, n) {
  let best = null;
  for (let cols = 1; cols <= 8; cols++) {
    const rows = Math.ceil(n / cols);
    const cell = Math.min(W / (cols + (rows > 1 ? 0.5 : 0)), H / (rows > 1 ? 1 + (rows - 1) * 0.9 : 1));
    if (!best || cell > best.cell + 0.5) best = { cols, rows, cell };
  }
  const cell = Math.min(best.cell, 100);
  const d = Math.round(cell * 0.86);
  const rows = best.rows;
  const counts = [];
  for (let r = 0; r < rows; r++) counts.push(Math.floor(n / rows));
  const rowRank = [];
  for (let r = 0; r < rows; r++) rowRank.push(r);
  rowRank.sort((a, b) => Math.abs(a - (rows - 1) / 2) - Math.abs(b - (rows - 1) / 2));
  for (let i = 0; i < n % rows; i++) counts[rowRank[i]]++;
  const pitchY = rows > 1 ? cell * 0.9 : cell;
  const y0 = (H - ((rows - 1) * pitchY + cell)) / 2;
  const points = [];
  for (let r = 0; r < rows; r++) {
    const c = counts[r];
    const shift = rows > 1 ? (r % 2 === 1 ? cell / 4 : -cell / 4) : 0;
    const x0 = (W - c * cell) / 2 + shift;
    for (let i = 0; i < c; i++) points.push([x0 + i * cell + cell / 2, y0 + r * pitchY + cell / 2]);
  }
  return { diameter: d, fontSize: Math.min(24, Math.round(d * 0.32)), points };
}
const layouts = [];
for (const W of [288, 343, 358, 398, 488]) {
  for (const n of [1, 3, 7, 10, 13, 16, 19, 22, 25, 28, 31, 36]) {
    const H = Math.min(fitHeight(W, n), 460);
    layouts.push({ width: W, height: H, count: n, fitHeight: fitHeight(W, n), ...layout(W, H, n) });
  }
}
write(fix, 'layouts.json', layouts);

console.log(`puzzles ${WB.PUZZLES.length}, bonus days ${Object.keys(WB_BONUS).length}, boards ${boards.length}, layouts ${layouts.length}`);
