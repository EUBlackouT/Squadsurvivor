#!/usr/bin/env node
// Softens/removes dark gridlines baked into 48x48 tiles by blending edges toward interior
import fs from 'fs';
import path from 'path';
import sharp from 'sharp';

const root = path.resolve(process.cwd(), 'client/assets/tilesets');
const EDGE = 3; // pixels to blend from each edge

async function softenTile(file){
  const img = sharp(file);
  const { width, height } = await img.metadata();
  if(width!==48 || height!==48){ return; }
  const raw = await img.raw().ensureAlpha().toBuffer();
  // Compute average inner color (exclude border EDGE px)
  let r=0,g=0,b=0,a=0,count=0;
  for(let y=EDGE; y<height-EDGE; y++){
    for(let x=EDGE; x<width-EDGE; x++){
      const i = (y*width + x)*4; r+=raw[i]; g+=raw[i+1]; b+=raw[i+2]; a+=raw[i+3]; count++;
    }
  }
  if(count===0) return;
  r/=count; g/=count; b/=count; a/=count;
  // Blend outer rings toward (r,g,b) using radial mask from edges
  const out = Buffer.from(raw);
  const blend = (x,y)=>{
    const dist = Math.min(x, y, width-1-x, height-1-y);
    const t = Math.max(0, EDGE - dist) / EDGE; // 1 at edge -> 0 inside
    return t;
  };
  for(let y=0; y<height; y++){
    for(let x=0; x<width; x++){
      const t = blend(x,y);
      if(t<=0) continue;
      const i = (y*width + x)*4;
      out[i]   = Math.round(out[i]*(1-t) + r*t);
      out[i+1] = Math.round(out[i+1]*(1-t) + g*t);
      out[i+2] = Math.round(out[i+2]*(1-t) + b*t);
      // keep alpha
    }
  }
  const composed = sharp(out, { raw: { width, height, channels: 4 } });
  await composed.png({ compressionLevel: 9 }).toFile(file);
}

async function main(){
  const entries = fs.readdirSync(root);
  const files = [];
  for(const dir of entries){
    const tiles = path.join(root, dir, 'tiles');
    if(fs.existsSync(tiles)){
      for(const f of fs.readdirSync(tiles)){
        if(/^tile_\d+\.png$/.test(f)) files.push(path.join(tiles, f));
      }
    }
  }
  console.log('Found', files.length, 'tiles');
  let n=0;
  for(const f of files){
    try{ await softenTile(f); n++; if(n%64===0) console.log('Processed', n); }
    catch(e){ console.warn('Skip', f, e.message); }
  }
  console.log('Done. Processed', n, 'tiles.');
}

main().catch(e=>{ console.error(e); process.exit(1); });


