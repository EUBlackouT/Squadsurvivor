#!/usr/bin/env node
import fs from 'fs';
import path from 'path';

const OUT_DIR = path.join(process.cwd(), 'client', 'assets', 'vfx');
fs.mkdirSync(OUT_DIR, { recursive: true });

let API_BASE = process.env.LEONARDO_API_BASE || 'https://cloud.leonardo.ai/api/rest';
let API_KEY = process.env.LEONARDO_API_KEY || '';
let MODEL_ID = process.env.LEONARDO_MODEL_ID || undefined; // optional

if(!API_KEY){
  try{
    const cfg = JSON.parse(fs.readFileSync(path.join(process.cwd(),'scripts','leonardo.env.json'),'utf8'));
    API_BASE = cfg.base || API_BASE;
    API_KEY = cfg.key || API_KEY;
    MODEL_ID = cfg.model || MODEL_ID;
  }catch{}
}

if(!API_KEY){
  console.error('Missing LEONARDO_API_KEY (env or scripts/leonardo.env.json).');
  process.exit(1);
}

const ITEMS = [
  { name:'mortar_circle', prompt:'top-down VFX, neon teal/orange targeting circle glyph with subtle scanlines, transparent background, pixel-art, 64x64, crisp edges, no perspective' },
  { name:'railgun_beam', prompt:'top-down VFX, straight horizontal energy beam strip with cyan core and white hot center, faint outer glow, transparent background, pixel-art, 8-16 px height' },
  { name:'blink_trail', prompt:'top-down VFX, wispy ghost trail slash, purple/teal, motion blur implied shape, transparent background, pixel-art, 64x32' },
  { name:'hive_body', prompt:'boss prop, biomechanical hive turret, grim metal with neon vents, top-down, transparent background, pixel-art, 96x96' },
  { name:'sentinel_body', prompt:'boss prop, tower sentinel with rail emitter, industrial metal, top-down, transparent background, pixel-art, 96x96' },
  { name:'assassin_body', prompt:'boss prop, techno-wraith core, teal/purple glow, top-down, transparent background, pixel-art, 80x80' }
];

async function createGeneration(prompt){
  const url = `${API_BASE}/v1/generations`;
  const baseBody = {
    prompt,
    num_images: 1,
    width: 512,
    height: 512,
    presetStyle: undefined,
    public: false
  };
  // Try with model if provided; on model lookup error, retry without it
  const body1 = MODEL_ID ? { ...baseBody, modelId: MODEL_ID } : baseBody;
  let res = await fetch(url, { method:'POST', headers:{ 'Authorization': `Bearer ${API_KEY}`, 'Content-Type':'application/json', 'Accept':'application/json' }, body: JSON.stringify(body1) });
  if(!res.ok){
    const txt = await res.text().catch(()=> '');
    if(txt.includes('model lookup error') && MODEL_ID){
      res = await fetch(url, { method:'POST', headers:{ 'Authorization': `Bearer ${API_KEY}`, 'Content-Type':'application/json', 'Accept':'application/json' }, body: JSON.stringify(baseBody) });
    }
    if(!res.ok){ throw new Error(`Leonardo create failed: ${res.status} ${res.statusText} ${txt}`); }
  }
  const j = await res.json();
  const id = j?.sdGenerationJob?.generationId || j?.object?.sdGenerationJob?.generationId;
  if(!id) throw new Error('No generationId returned');
  return id;
}

async function waitForImage(genId){
  const url = `${API_BASE}/v1/generations/${genId}`;
  const started = Date.now();
  while(Date.now()-started < 180000){
    const res = await fetch(url, { headers:{ 'Authorization': `Bearer ${API_KEY}`, 'Accept':'application/json' } });
    if(!res.ok){ throw new Error(`Leonardo poll failed: ${res.status}`); }
    const j = await res.json();
    const status = j?.generations_by_pk?.status || j?.object?.generationsByPk?.status || j?.object?.generationsByPK?.status;
    const arr = j?.generations_by_pk?.generated_images || j?.object?.generationsByPk?.generated_images || j?.object?.generationsByPK?.generated_images;
    if(status === 'COMPLETE' && Array.isArray(arr) && arr.length>0){ return arr[0].url; }
    await new Promise(r=> setTimeout(r, 4000));
  }
  throw new Error('Timeout waiting for Leonardo generation');
}

async function downloadTo(url, filePath){
  const res = await fetch(url);
  if(!res.ok) throw new Error(`Download failed: ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(filePath, buf);
}

async function main(){
  for(const item of ITEMS){
    try{
      const genId = await createGeneration(item.prompt);
      const url = await waitForImage(genId);
      const out = path.join(OUT_DIR, `${item.name}.png`);
      await downloadTo(url, out);
      console.log('Saved', out);
    }catch(err){ console.error(item.name+': '+String(err)); }
  }
}

main().catch(err=>{ console.error(err); process.exit(1); });


