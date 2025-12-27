#!/usr/bin/env node
// Fit any PNG to 192x192 (4x4 of 48px) with alpha preserved, then slice via wang_slice.mjs
// Usage:
//   node scripts/wang_fit_and_slice.mjs --input client/assets/tilesets/Grassland-industry.png --out client/assets/tilesets/grass_industry

import fs from 'fs';
import path from 'path';
import child_process from 'child_process';

let sharp;
try { const mod = await import('sharp'); sharp = mod.default || mod; } catch (e) {
  console.error('sharp is required. Install with: npm i -D sharp');
  process.exit(1);
}

const argv = process.argv.slice(2);
function arg(name){ const i = argv.indexOf(`--${name}`); return i>=0 ? (argv[i+1]||'') : ''; }
const INPUT = arg('input');
const OUT = arg('out');
const TILE = Number(arg('tile')||48);
if(!INPUT || !OUT){
  console.error('Usage: node scripts/wang_fit_and_slice.mjs --input <png> --out <dir> [--tile 48]');
  process.exit(2);
}

await fs.promises.mkdir(OUT, { recursive: true });
const target = path.join(OUT, 'wang_sheet.png');
const buf = await fs.promises.readFile(INPUT);
let img = sharp(buf).ensureAlpha();
const meta = await img.metadata();
// Cover-fit to 192x192 (4*tile)
img = sharp(buf).ensureAlpha().resize(TILE*4, TILE*4, { fit:'cover' }).png();
// Optional: soft alpha cleanup on uniform margins
const outBuf = await img.png().toBuffer();
await fs.promises.writeFile(target, outBuf);
// Slice
child_process.execSync(`node scripts/wang_slice.mjs --input "${target}" --tile ${TILE} --out "${OUT}"`, { stdio:'inherit' });
console.log('Done:', OUT);


