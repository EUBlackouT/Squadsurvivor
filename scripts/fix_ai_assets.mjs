import fs from 'fs';
import path from 'path';
import fg from 'fast-glob';
import sharp from 'sharp';

// Directories
const ROOT = process.cwd();
const AI_READY = path.join(ROOT, 'client', 'assets', 'ai_ready');
const OUT_SPRITES = path.join(ROOT, 'client', 'assets', 'sprites');

fs.mkdirSync(OUT_SPRITES, { recursive: true });

async function toPngBuffer(buf){
  // Always re-encode into clean PNG with straight alpha
  return await sharp(buf, { failOn: 'none' }).png({ quality: 100, compressionLevel: 9, adaptiveFiltering: false }).toBuffer();
}

async function stitchRowFromBuffers(frameBuffers, frameW, frameH){
  const count = frameBuffers.length;
  const rowW = frameW * count;
  const rowH = frameH;
  const blank = await sharp({ create: { width: rowW, height: rowH, channels: 4, background: { r:0,g:0,b:0,alpha:0 } } }).png().toBuffer();
  const composite = [];
  for(let i=0;i<count;i++) composite.push({ input: frameBuffers[i], left: i*frameW, top: 0 });
  return await sharp(blank).composite(composite).png().toBuffer();
}

async function processEnemies8Frames(){
  const baseDir = path.join(AI_READY, 'enemies8_frames');
  if(!fs.existsSync(baseDir)) return;
  const species = fs.readdirSync(baseDir, { withFileTypes: true }).filter(d=>d.isDirectory()).map(d=>d.name);
  const dirs = ['east','north-east','north','north-west','west','south-west','south','south-east'];
  const outDir = path.join(OUT_SPRITES, 'enemies', 'generated8_stitched');
  fs.mkdirSync(outDir, { recursive: true });
  for(const sp of species){
    for(const dir of dirs){
      const dirPath = path.join(baseDir, sp, dir);
      if(!fs.existsSync(dirPath)) continue;
      const framePaths = (await fg(['frame_*.{png,jpg,jpeg,webp,avif}'], { cwd: dirPath, absolute: true })).sort();
      if(framePaths.length === 0) continue;
      const buffers = [];
      let w = 128, h = 128;
      for(const fp of framePaths){
        const buf = fs.readFileSync(fp);
        const png = await toPngBuffer(buf);
        const meta = await sharp(png).metadata();
        w = meta.width || w; h = meta.height || h;
        buffers.push(png);
      }
      // Optional resize to 128x128 for consistency
      const resized = [];
      for(const b of buffers){ resized.push(await sharp(b).resize({ width: 128, height: 128, fit: 'fill' }).png().toBuffer()); }
      const sheet = await stitchRowFromBuffers(resized, 128, 128);
      const outName = `${sp}_walk_${dir}.png`;
      fs.writeFileSync(path.join(outDir, outName), sheet);
      console.log('[assets:fix] stitched', sp, dir, '->', path.join('client','assets','sprites','enemies','generated8_stitched', outName));
    }
  }
}

async function main(){
  await processEnemies8Frames();
}

main().catch(e=>{ console.error(e); process.exit(1); });


