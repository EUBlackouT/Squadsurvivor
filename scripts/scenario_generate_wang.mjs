#!/usr/bin/env node
// Generate a 4x4 Wang tileset sheet (192x192 PNG) via Scenario txt2img and save to <out>/wang_sheet.png
// Usage:
//   node scripts/scenario_generate_wang.mjs --apiKey KEY --secret SEC --modelId MODEL --prompt "..." --out client/assets/tilesets/grass_industry

import fs from 'fs';
import path from 'path';
import fetch from 'node-fetch';
import child_process from 'child_process';

let sharp;
try { const mod = await import('sharp'); sharp = mod.default || mod; } catch (e) {
  console.error('sharp is required. Install with: npm i -D sharp');
  process.exit(1);
}

const argv = process.argv.slice(2);
function arg(name, def=''){ const i = argv.indexOf(`--${name}`); return i>=0 ? (argv[i+1]||def) : def; }
const API_KEY = arg('apiKey');
const SECRET = arg('secret');
const MODEL_ID = arg('modelId');
const OUT_DIR = arg('out');
const API_BASE = arg('base', process.env.SCENARIO_API_BASE || 'https://api.cloud.scenario.com/v1');
const TILE = Number(arg('tile','48'));

const BASE_PROMPT = arg('prompt', 'top-down pixel art Wang tileset, 4x4 grid, 48px tiles, transparent background, object-only, strict grid, no gutters, no margins, each tile is a unique corner combination, high micro-detail, baked edge AO, limited palette, crisp outline, no text');
const NEGATIVE = arg('negative', 'no perspective, no shadows across tiles, no drop shadows, no borders around sheet, no spacing, no background behind tiles');

if(!API_KEY || !SECRET || !MODEL_ID || !OUT_DIR){
  console.error('Usage: node scripts/scenario_generate_wang.mjs --apiKey KEY --secret SEC --modelId MODEL --out PATH [--prompt "..."]');
  process.exit(2);
}

const auth = 'Basic ' + Buffer.from(`${API_KEY}:${SECRET}`).toString('base64');
const base = API_BASE;

async function postJson(url, body){
  const res = await fetch(url, { method:'POST', headers:{ 'Authorization': auth, 'Content-Type':'application/json' }, body: JSON.stringify(body) });
  if(!res.ok){ const txt = await res.text(); throw new Error(`HTTP ${res.status} ${res.statusText}: ${txt}`); }
  const ct = res.headers.get('content-type')||'';
  if(ct.includes('application/json')) return await res.json();
  const buf = await res.buffer(); return buf;
}

async function sleep(ms){ return new Promise(r=>setTimeout(r, ms)); }

async function generateSheet(){
  const payload = {
    prompt: BASE_PROMPT,
    negative_prompt: NEGATIVE,
    width: TILE*4,
    height: TILE*4,
    output_format: 'png',
    transparent: true
  };
  // Try txt2img job create + poll
  try{
    const job = await postJson(`${base}/models/${MODEL_ID}/txt2img`, payload);
    const jobId = job?.id || job?.jobId || job?.data?.id;
    if(jobId){
      for(let i=0;i<60;i++){
        await sleep(2500);
        const st = await fetch(`${base}/jobs/${jobId}`, { headers:{ Authorization: auth }});
        const js = await st.json().catch(()=>({}));
        const status = js?.status || js?.data?.status;
        if(status==='completed' && js?.images?.[0]?.image){ return Buffer.from(js.images[0].image, 'base64'); }
        if(status==='failed'){ throw new Error('Scenario job failed'); }
      }
      throw new Error('Timed out waiting for Scenario job');
    }
  }catch(e){ /* fall back */ }
  // Try synchronous endpoint as fallback
  try{
    const res = await postJson(`${base}/models/${MODEL_ID}/generate`, payload);
    if(Buffer.isBuffer(res)) return res;
    if(res?.images?.[0]?.image) return Buffer.from(res.images[0].image, 'base64');
    throw new Error('No image in response');
  }catch(e){
    throw e;
  }
}

async function ensurePng192(buf){
  let img = sharp(buf).png();
  const meta = await sharp(buf).metadata();
  let out = img;
  if((meta.width!==TILE*4) || (meta.height!==TILE*4)){
    out = sharp(buf).resize(TILE*4, TILE*4, { fit:'cover' }).png();
  }
  const b = await out.toBuffer();
  // Heuristic background alpha cleanup if solid bg detected
  const raw = await sharp(b).ensureAlpha().raw().toBuffer({ resolveWithObject:true });
  const { data, info } = raw;
  const w = info.width, h = info.height;
  const idx = (x,y)=> (y*w + x)*4;
  const c1 = data.slice(idx(0,0), idx(0,0)+3);
  const c2 = data.slice(idx(w-1,0), idx(w-1,0)+3);
  const c3 = data.slice(idx(0,h-1), idx(0,h-1)+3);
  const c4 = data.slice(idx(w-1,h-1), idx(w-1,h-1)+3);
  const same = (a,b)=> Math.abs(a[0]-b[0])<6 && Math.abs(a[1]-b[1])<6 && Math.abs(a[2]-b[2])<6;
  const solid = same(c1,c2)&&same(c1,c3)&&same(c1,c4);
  if(solid){
    for(let y=0;y<h;y++){
      for(let x=0;x<w;x++){
        const i = (y*w + x)*4; if(Math.abs(data[i]-c1[0])<8 && Math.abs(data[i+1]-c1[1])<8 && Math.abs(data[i+2]-c1[2])<8){ data[i+3]=0; }
      }
    }
    return sharp(data, { raw:{ width:w, height:h, channels:4 } }).png().toBuffer();
  }
  return b;
}

async function main(){
  await fs.promises.mkdir(OUT_DIR, { recursive: true });
  const png = await generateSheet();
  const cleaned = await ensurePng192(png);
  const dst = path.join(OUT_DIR, 'wang_sheet.png');
  await fs.promises.writeFile(dst, cleaned);
  console.log('Saved', dst);
  // Slice
  child_process.execSync(`node scripts/wang_slice.mjs --input "${dst}" --tile ${TILE} --out "${OUT_DIR}"`, { stdio:'inherit' });
}

main().catch(e=>{ console.error('Generation failed:', e.message||e); process.exit(1); });


