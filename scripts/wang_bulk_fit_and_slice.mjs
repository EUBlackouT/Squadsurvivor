#!/usr/bin/env node
// Bulk process all PNG sheets in a directory:
// - Fit to 192x192 (4x4 of 48px)
// - Slice into 16 tiles
// - Emit Tiled tileset (.tsj) and metadata.json
// Usage: node scripts/wang_bulk_fit_and_slice.mjs --dir client/assets/tilesets

import fs from 'fs';
import path from 'path';

let sharp;
try { const mod = await import('sharp'); sharp = mod.default || mod; } catch (e) {
  console.error('sharp is required. Install with: npm i -D sharp');
  process.exit(1);
}

const argv = process.argv.slice(2);
function arg(name, def=''){ const i = argv.indexOf(`--${name}`); return i>=0 ? (argv[i+1]||def) : def; }
const DIR = arg('dir', 'client/assets/tilesets');
const TILE = Number(arg('tile','48'));

function slugify(name){
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 64);
}

async function sliceTo(outDir, sheetBuf){
  await fs.promises.mkdir(outDir, { recursive: true });
  const sheetDst = path.join(outDir, 'wang_sheet.png');
  // Fit/cover to 4*tile
  const fitted = await sharp(sheetBuf).ensureAlpha().resize(TILE*4, TILE*4, { fit:'cover' }).png().toBuffer();
  await fs.promises.writeFile(sheetDst, fitted);
  const tilesDir = path.join(outDir, 'tiles');
  await fs.promises.mkdir(tilesDir, { recursive: true });
  const tiles = [];
  for(let row=0; row<4; row++){
    for(let col=0; col<4; col++){
      const idx = row*4 + col;
      const left = col*TILE, top = row*TILE;
      const tilePath = path.join(tilesDir, `tile_${String(idx).padStart(2,'0')}.png`);
      await sharp(fitted).extract({ left, top, width: TILE, height: TILE }).png().toFile(tilePath);
      tiles.push({ id: idx, image: path.posix.join('tiles', path.basename(tilePath)), width: TILE, height: TILE, properties: [{ name:'collides', type:'bool', value:false }] });
    }
  }
  const tsj = {
    columns: 4,
    grid: { height: TILE, orientation: 'orthogonal', width: TILE },
    margin: 0,
    name: path.basename(outDir),
    spacing: 0,
    tilecount: 16,
    tiledversion: '1.10.2',
    tileheight: TILE,
    tilewidth: TILE,
    type: 'tileset',
    version: '1.10',
    tiles
  };
  await fs.promises.writeFile(path.join(outDir, 'tileset.tsj'), JSON.stringify(tsj, null, 2));
  await fs.promises.writeFile(path.join(outDir, 'metadata.json'), JSON.stringify({ tileSize:TILE, wang:true, tileset:'tileset.tsj' }, null, 2));
}

async function main(){
  const items = await fs.promises.readdir(DIR, { withFileTypes:true });
  const pngs = items.filter(d=> d.isFile() && d.name.toLowerCase().endsWith('.png'));
  for(const f of pngs){
    const src = path.join(DIR, f.name);
    const buf = await fs.promises.readFile(src);
    const base = path.parse(f.name).name;
    const outSlug = slugify(base);
    const outDir = path.join(DIR, outSlug);
    await sliceTo(outDir, buf);
    console.log('Processed:', f.name, '->', outSlug);
  }
}

main().catch(e=>{ console.error(e); process.exit(1); });


