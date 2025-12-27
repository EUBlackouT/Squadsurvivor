// If AI outputs exist, move them into live asset paths and overwrite placeholders.
import fs from 'fs';
import path from 'path';
import sharp from 'sharp';

const MAP = [
	{ src: ['client', 'assets', 'ai_ready', 'tiles', 'tilesheet.png'], dst: ['client', 'assets', 'tilemaps', 'tilesheet.png'] },
	{ src: ['client', 'assets', 'ai_ready', 'ui', 'icons.png'], dst: ['client', 'assets', 'sprites', 'ui_icons.png'] },
	{ src: ['client', 'assets', 'ai_ready', 'characters', 'sysop_walk_s.png'], dst: ['client', 'assets', 'sprites', 'player_sysop_walk_s.png'] },
	{ src: ['client', 'assets', 'ai_ready', 'projectiles', 'threadneedle_sheet.png'], dst: ['client', 'assets', 'sprites', 'projectiles', 'threadneedle_sheet.png'] },
	{ src: ['client', 'assets', 'ai_ready', 'projectiles', 'harpoon_sheet.png'], dst: ['client', 'assets', 'sprites', 'projectiles', 'harpoon_sheet.png'] },
	{ src: ['client', 'assets', 'ai_ready', 'projectiles', 'orb_sheet.png'], dst: ['client', 'assets', 'sprites', 'projectiles', 'orb_sheet.png'] },
	{ src: ['client', 'assets', 'ai_ready', 'projectiles', 'shader_sheet.png'], dst: ['client', 'assets', 'sprites', 'projectiles', 'shader_sheet.png'] }
];

for (const m of MAP) {
	const s = path.join(...m.src);
	const d = path.join(...m.dst);
	if (fs.existsSync(s)) {
		fs.mkdirSync(path.dirname(d), { recursive: true });
		fs.copyFileSync(s, d);
		console.log('[AI] Updated asset:', d);
	}
}

// Copy generated enemy sheets and write a manifest for loaders
try{
  const srcDir = path.join('client','assets','ai_ready','enemies');
  const dstDir = path.join('client','assets','sprites','enemies','generated');
  if(fs.existsSync(srcDir)){
    fs.mkdirSync(dstDir, { recursive: true });
    const files = fs.readdirSync(srcDir).filter(f=>f.endsWith('_walk.png'));
    const names = [];
    for(const f of files){
      const name = f.replace('_walk.png','');
      names.push(name);
      fs.copyFileSync(path.join(srcDir,f), path.join(dstDir,f));
      console.log('[AI] Copied enemy sheet:', name);
    }
    fs.writeFileSync(path.join(dstDir,'manifest.json'), JSON.stringify({ names }, null, 2));
  }
}catch(e){ console.warn('[AI] Enemy postprocess failed', e.message); }

// Copy generated 8-direction enemy sheets and write manifest
try{
  // Copy per-frame enemy sheets (Scenario frames) into PixelLab-like structure
  const srcDirF = path.join('client','assets','ai_ready','enemies8_frames');
  const dstDirF = path.join('client','assets','sprites','enemies','generated8_frames');
  if(fs.existsSync(srcDirF)){
    fs.mkdirSync(dstDirF, { recursive: true });
    const species = fs.readdirSync(srcDirF, { withFileTypes: true }).filter(d=>d.isDirectory()).map(d=>d.name);
    const names = [];
    for(const sp of species){
      names.push(sp);
      const dirSrc = path.join(srcDirF, sp);
      const dirDst = path.join(dstDirF, sp, 'animations', 'walking-4-frames');
      const dirs = ['east','north-east','north','north-west','west','south-west','south','south-east'];
      for(const dir of dirs){
        const from = path.join(dirSrc, dir);
        const to = path.join(dirDst, dir);
        if(!fs.existsSync(from)) continue;
        fs.mkdirSync(to, { recursive: true });
        const frames = fs.readdirSync(from).filter(f=>/\.(png|jpg|jpeg|webp|avif)$/i.test(f));
        for(const f of frames){
          const src = path.join(from,f);
          const dst = path.join(to, f.replace(/\.(jpg|jpeg|webp|avif)$/i, '.png'));
          try{
            const buf = fs.readFileSync(src);
            const png = await sharp(buf, { failOn: 'none' }).ensureAlpha().toColourspace('rgba').png({ quality: 100, compressionLevel: 9, adaptiveFiltering: false }).toBuffer();
            // alpha punchout via corner sampling
            const meta = await sharp(png).metadata(); const w = meta.width||0, h = meta.height||0;
            const raw = await sharp(png).raw().toBuffer();
            const idx = (x,y)=> (y*w+x)*4;
            const get = (x,y)=> ({ r: raw[idx(x,y)+0], g: raw[idx(x,y)+1], b: raw[idx(x,y)+2] });
            const c1=get(0,0), c2=get(w-1,0), c3=get(0,h-1), c4=get(w-1,h-1);
            const bg = { r: Math.round((c1.r+c2.r+c3.r+c4.r)/4), g: Math.round((c1.g+c2.g+c3.g+c4.g)/4), b: Math.round((c1.b+c2.b+c3.b+c4.b)/4) };
            const tol = 22;
            for(let y=0;y<h;y++) for(let x=0;x<w;x++){ const i=idx(x,y); const r=raw[i],g=raw[i+1],b=raw[i+2]; if(Math.abs(r-bg.r)<tol && Math.abs(g-bg.g)<tol && Math.abs(b-bg.b)<tol){ raw[i+3]=0; } }
            const outPng = await sharp(raw, { raw: { width:w, height:h, channels:4 } }).png().toBuffer();
            fs.writeFileSync(dst, outPng);
          }catch(e){ fs.copyFileSync(src, dst); console.warn('[AI] Frame convert failed (copied as-is):', sp, dir, f, e.message); }
        }
      }
      console.log('[AI] Copied enemy8 frames:', sp);
    }
    fs.writeFileSync(path.join(dstDirF,'manifest.json'), JSON.stringify({ names }, null, 2));
  }
}catch(e){ console.warn('[AI] Enemy8 frames postprocess failed', e.message); }

try{
  const srcDir8 = path.join('client','assets','ai_ready','enemies8');
  const dstDir8 = path.join('client','assets','sprites','enemies','generated8');
  if(fs.existsSync(srcDir8)){
    fs.mkdirSync(dstDir8, { recursive: true });
    // Remove any stale JPGs to prevent accidental jpg loading
    try{ for(const f of fs.readdirSync(dstDir8)){ if(f.endsWith('_walk_8dir.jpg')){ fs.unlinkSync(path.join(dstDir8,f)); } } }catch{}
    const filesAll = fs.readdirSync(srcDir8).filter(f=> f.endsWith('_walk_8dir.png') || f.endsWith('_walk_8dir.jpg'));
    const names = [];
    for(const f of filesAll){
      const isJpg = f.endsWith('.jpg');
      const base = f.replace('_walk_8dir.png','').replace('_walk_8dir.jpg','');
      names.push(base);
      const src = path.join(srcDir8, f);
      const dstPng = path.join(dstDir8, `${base}_walk_8dir.png`);
      // If JPG, convert to PNG and punch out flat background to alpha
      if(isJpg){
        try{
          const buf = fs.readFileSync(src);
          const png = await sharp(buf, { failOn: 'none' }).ensureAlpha().png().toBuffer();
          fs.writeFileSync(dstPng, png);
          console.log('[AI] Converted JPG→PNG with alpha:', base);
        }catch(e){ fs.copyFileSync(src, dstPng); console.warn('[AI] JPG→PNG convert failed, copied as-is:', base, e.message); }
      } else {
        fs.copyFileSync(src, dstPng);
        console.log('[AI] Copied enemy8 sheet (PNG):', base);
      }
    }
    fs.writeFileSync(path.join(dstDir8,'manifest.json'), JSON.stringify({ names }, null, 2));
  }
}catch(e){ console.warn('[AI] Enemy8 postprocess failed', e.message); }
