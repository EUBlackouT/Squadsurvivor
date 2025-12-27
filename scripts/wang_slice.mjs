#!/usr/bin/env node
// Slice a 4x4 Wang tileset sheet into 16 tiles and emit a Tiled .tsj
// Usage:
//   node scripts/wang_slice.mjs --input path/to/wang_sheet.png --tile 48 --out client/assets/tilesets/industry

import fs from 'fs';
import path from 'path';
import url from 'url';

let sharp;
try { const mod = await import('sharp'); sharp = mod.default || mod; } catch (e) {
  console.error('sharp is required. Install with: npm i -D sharp');
  process.exit(1);
}

function parseArgs(){
  const args = process.argv.slice(2);
  const out = { input: '', tile: 48, out: '' };
  for(let i=0;i<args.length;i++){
    const a = args[i];
    if(a==='--input') out.input = args[++i]||'';
    else if(a==='--tile') out.tile = Number(args[++i]||'48');
    else if(a==='--out') out.out = args[++i]||'';
  }
  if(!out.input || !out.out){
    console.error('Usage: node scripts/wang_slice.mjs --input wang_sheet.png --tile 48 --out client/assets/tilesets/<name>');
    process.exit(2);
  }
  return out;
}

async function main(){
  const { input, tile, out } = parseArgs();
  const sheetBuf = await fs.promises.readFile(input);
  const baseImg = sharp(sheetBuf);
  const meta = await baseImg.metadata();
  const w = meta.width||0, h = meta.height||0;
  if(w!==tile*4 || h!==tile*4){
    console.error(`Expected a 4x4 grid of ${tile}px tiles. Got ${w}x${h}.`);
    process.exit(3);
  }
  await fs.promises.mkdir(out, { recursive: true });
  // Copy source
  const sheetDst = path.join(out, 'wang_sheet.png');
  await fs.promises.copyFile(input, sheetDst).catch(()=>{});

  // Emit tiles directory
  const tilesDir = path.join(out, 'tiles');
  await fs.promises.mkdir(tilesDir, { recursive: true });

  // Slice 16 tiles (row-major)
  const tiles = [];
  for(let row=0; row<4; row++){
    for(let col=0; col<4; col++){
      const idx = row*4 + col;
      const left = col*tile, top = row*tile;
      const outPath = path.join(tilesDir, `tile_${String(idx).padStart(2,'0')}.png`);
      // Use a fresh extractor per tile to avoid any internal state issues
      await sharp(sheetBuf).extract({ left, top, width: tile, height: tile }).png().toFile(outPath);
      tiles.push({ id: idx, image: path.posix.join('tiles', path.basename(outPath)), width: tile, height: tile, properties: [{ name:'collides', type:'bool', value:false }] });
    }
  }

  // Build Tiled tileset JSON (.tsj)
  const tsj = {
    columns: 4,
    grid: { height: tile, orientation: 'orthogonal', width: tile },
    margin: 0,
    name: path.basename(out),
    spacing: 0,
    tilecount: 16,
    tiledversion: '1.10.2',
    tileheight: tile,
    tilewidth: tile,
    type: 'tileset',
    version: '1.10',
    tiles
  };
  const tsjPath = path.join(out, 'tileset.tsj');
  await fs.promises.writeFile(tsjPath, JSON.stringify(tsj, null, 2));

  // Minimal metadata for our loader
  const metaPath = path.join(out, 'metadata.json');
  const m = { tileSize: tile, wang: true, tileset: path.basename(tsjPath) };
  await fs.promises.writeFile(metaPath, JSON.stringify(m, null, 2));

  console.log(`Sliced 16 tiles to ${tilesDir}`);
  console.log(`Wrote Tiled tileset: ${tsjPath}`);
}

main().catch(e=>{ console.error(e); process.exit(5); });


