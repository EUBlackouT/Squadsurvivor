#!/usr/bin/env node
// Simple Scenario/Leonardo-compatible VFX fetcher.
// Reads prompts and model IDs from below, calls a text-to-image endpoint, and
// writes images into client/assets/vfx/<name>.png. Designed to be tolerant of
// either JSON(base64) or direct-binary responses.

import fs from 'fs';
import path from 'path';

const OUT_DIR = path.join(process.cwd(), 'client', 'assets', 'vfx');
fs.mkdirSync(OUT_DIR, { recursive: true });

// Configure via env vars to avoid committing secrets.
// SCENARIO_API_BASE: e.g., https://api.scenario.com or your proxy base
// SCENARIO_API_KEY: Bearer token
// SCENARIO_MODEL_ID: default model id for VFX (override per item below if needed)
let API_BASE = process.env.SCENARIO_API_BASE || 'https://api.scenario.com';
let API_KEY = process.env.SCENARIO_API_KEY || '';
let DEFAULT_MODEL = process.env.SCENARIO_MODEL_ID || '';
let API_SECRET = process.env.SCENARIO_API_SECRET || '';
let TEAM_ID = process.env.SCENARIO_TEAM_ID || '';
let PROJECT_ID = process.env.SCENARIO_PROJECT_ID || '';

if(!API_KEY){
  // Try reading local config file scripts/scenario.env.json
  try{
    const cfgPath = path.join(process.cwd(), 'scripts', 'scenario.env.json');
    const txt = fs.readFileSync(cfgPath, 'utf8');
    const cfg = JSON.parse(txt);
    API_BASE = cfg.base || API_BASE;
    API_KEY = cfg.key || API_KEY;
    DEFAULT_MODEL = cfg.model || DEFAULT_MODEL;
    API_SECRET = cfg.secret || API_SECRET;
    TEAM_ID = cfg.teamId || TEAM_ID;
    PROJECT_ID = cfg.projectId || PROJECT_ID;
  }catch{}
}

if(!API_KEY){
  console.error('Missing SCENARIO_API_KEY (env or scripts/scenario.env.json).');
  process.exit(1);
}

// Describe each asset. Override modelId if you need a different model per asset.
const ITEMS = [
  {
    name: 'mortar_circle',
    prompt: 'top-down VFX, neon teal/orange targeting circle glyph with subtle scanlines, transparent background, pixel-art, 48-96 px, sharp edges, no perspective',
    modelId: DEFAULT_MODEL
  },
  {
    name: 'railgun_beam',
    prompt: 'top-down VFX, straight horizontal energy beam strip with cyan core and white hot center, faint outer glow, transparent background, pixel-art, 8-16 px height',
    modelId: DEFAULT_MODEL
  },
  {
    name: 'blink_trail',
    prompt: 'top-down VFX, wispy ghost trail slash, purple/teal, motion blur implied shape, transparent background, pixel-art, 64x32 preferred',
    modelId: DEFAULT_MODEL
  },
  {
    name: 'hive_body',
    prompt: 'boss prop, biomechanical hive turret body, grimy metal with neon vents, top-down view, single sprite, transparent background, pixel-art, 96x96',
    modelId: DEFAULT_MODEL
  },
  {
    name: 'sentinel_body',
    prompt: 'boss prop, tower sentinel base with rail emitter, industrial metal, top-down, single sprite, transparent background, pixel-art, 96x96',
    modelId: DEFAULT_MODEL
  },
  {
    name: 'assassin_body',
    prompt: 'boss prop, techno-wraith core silhouette, teal/purple glow, top-down, single sprite, transparent background, pixel-art, 80x80',
    modelId: DEFAULT_MODEL
  }
];

// Scenario custom endpoint with job polling
async function generateImage({ name, prompt, modelId }){
  const base = API_BASE.replace(/\/$/, '');
  const candidateUrls = [
    `${base}/v1/generate/custom/${encodeURIComponent(modelId || DEFAULT_MODEL || '')}`,
    `${base}/v1/images/generate`,
    `${base}/v1/generate`,
    `${base}/v1/generations`
  ];
  const payload = { prompt, width: 96, height: 96, outputFormat: 'png', transparentBackground: true };
  const headers = {
    'Authorization': `Bearer ${API_KEY}`,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    // Some deployments also accept x-api-key; include to be safe
    'x-api-key': API_KEY,
    // Include secret/team/project if provided
    ...(API_SECRET ? { 'x-api-secret': API_SECRET } : {}),
    ...(TEAM_ID ? { 'x-team-id': TEAM_ID } : {}),
    ...(PROJECT_ID ? { 'x-project-id': PROJECT_ID } : {})
  };
  let job; let lastErr;
  for(const url of candidateUrls){
    let res = await fetch(url, { method:'POST', headers, body: JSON.stringify(payload) });
    if(!res.ok && res.status===403 && API_SECRET){
      const basic = Buffer.from(`${API_KEY}:${API_SECRET}`).toString('base64');
      const headersBasic = { ...headers, Authorization: `Basic ${basic}` };
      res = await fetch(url, { method:'POST', headers: headersBasic, body: JSON.stringify(payload) });
    }
    if(res.ok){ try{ job = await res.json(); break; }catch(e){ lastErr = e; }
    } else { lastErr = new Error(`${res.status} ${await res.text().catch(()=> res.statusText)}`); }
  }
  if(!job) throw new Error(`Scenario create failed for ${name}: ${lastErr}`);
  const jobId = job.jobId || job.id || job.data?.jobId;
  if(!jobId) throw new Error(`No jobId returned for ${name}`);
  // Poll job status
  const pollUrl = `${base}/v1/jobs/${encodeURIComponent(jobId)}`;
  const started = Date.now(); let result;
  while(Date.now()-started < 180000){
    const r = await fetch(pollUrl, { headers });
    if(!r.ok){ throw new Error(`Scenario poll failed for ${name}: ${r.status}`); }
    const j = await r.json();
    const status = j.status || j.data?.status;
    if(status==='success' || status==='completed' || status==='complete'){
      result = j; break;
    }
    if(status==='failed' || status==='error'){ throw new Error(`Scenario job failed for ${name}`); }
    await new Promise(rz=> setTimeout(rz, 3000));
  }
  if(!result) throw new Error(`Scenario job timeout for ${name}`);
  // Extract asset
  const urlOut = result.assetUrl || result.data?.assetUrl || result.assets?.[0]?.url || result.data?.assets?.[0]?.url;
  if(urlOut){
    const bin = await fetch(urlOut); if(!bin.ok) throw new Error(`Download failed for ${name}: ${bin.status}`);
    const buf = Buffer.from(await bin.arrayBuffer());
    const outPath = path.join(OUT_DIR, `${name}.png`);
    fs.writeFileSync(outPath, buf); console.log('Saved', outPath); return;
  }
  // Fallback to base64 fields
  const b64 = result.image_base64 || result.output?.[0]?.base64;
  if(!b64) throw new Error(`No asset URL or base64 in job for ${name}`);
  const outPath = path.join(OUT_DIR, `${name}.png`);
  fs.writeFileSync(outPath, Buffer.from(b64, 'base64')); console.log('Saved', outPath);
}

async function main(){
  for(const item of ITEMS){
    try{ await generateImage(item); }
    catch(err){ console.error(String(err)); }
  }
}

main().catch(err=>{ console.error(err); process.exit(1); });


