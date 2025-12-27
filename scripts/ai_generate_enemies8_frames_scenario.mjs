import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import fetch from 'node-fetch';

const API_KEY = process.env.SCENARIO_API_KEY;
const API_SECRET = process.env.SCENARIO_SECRET_KEY;
if (!API_KEY || !API_SECRET) { console.log('[AI] Scenario keys missing; skipping enemies8-frames'); process.exit(0); }

const BASE = 'https://api.cloud.scenario.com/v1';
const credentials = Buffer.from(`${API_KEY}:${API_SECRET}`).toString('base64');
const PROJECT_ID = process.env.SCENARIO_PROJECT_ID || '';
const OUT = (...p)=> path.join('client','assets','ai_ready','enemies8_frames',...p);
fs.mkdirSync(OUT(), { recursive: true });

async function txt2img(prompt, width=128, height=128, modelId=process.env.SCENARIO_MODEL_ID || 'flux.1-dev', seed){
  const body = { prompt, width, height, modelId, projectId: PROJECT_ID, numSamples: 1, numInferenceSteps: 28, guidance: 3.5, outputFormat: 'png', background: 'transparent', ...(seed!==undefined?{seed}: {}) };
  const res = await fetch(`${BASE}/generate/txt2img`, {
    method: 'POST', headers: { 'Content-Type':'application/json', Authorization: `Basic ${credentials}`, 'X-Scenario-Project-Id': PROJECT_ID },
    body: JSON.stringify(body)
  });
  if(!res.ok) throw new Error(`Scenario txt2img failed: ${res.status} ${await res.text()}`);
  return res.json();
}
async function pollJob(jobId){
  const url = `${BASE}/jobs/${jobId}`;
  for(let i=0;i<30;i++){
    const r = await fetch(url, { headers: { Authorization: `Basic ${credentials}` } });
    const d = await r.json(); if(r.ok){ const st=d?.job?.status; if(st==='success') return d?.job?.metadata?.assetIds||[]; if(st==='failure'||st==='canceled') throw new Error('Scenario job '+st); }
    await new Promise(r=>setTimeout(r,2500));
  }
  return [];
}
async function getAssetUrl(assetId){ const r = await fetch(`${BASE}/assets/${assetId}`, { headers: { Authorization: `Basic ${credentials}` } }); const j = await r.json(); if(!r.ok) throw new Error(`Asset fetch failed: ${r.status} ${JSON.stringify(j)}`); return j?.asset?.url; }
async function dl(url,dest){ const r=await fetch(url); if(!r.ok) throw new Error('Download failed'); fs.writeFileSync(dest, Buffer.from(await r.arrayBuffer())); }

const ENEMIES = [
  ['skeleton_knight','skeleton knight with visor and shield'],
  ['skeleton_archer','skeleton archer with quiver'],
  ['skeleton_mage','skeleton mage with tattered robe']
];
const DIRS = ['east','north-east','north','north-west','west','south-west','south','south-east'];

function dirPrompt(dir){
  return `viewed ${dir.replace('-', ' ')}, walking animation frame, top-down perspective`;
}

async function genFrames(name, desc){
  const baseSeed = Math.floor(Math.random()*1e9);
  for(let d=0; d<DIRS.length; d++){
    const dir = DIRS[d];
    const dirOut = OUT(name, dir); fs.mkdirSync(dirOut, { recursive: true });
    for(let f=0; f<4; f++){
      const framePrompt = `${desc} from 'PATCHBOUND', pixel art enemy sprite, ${dirPrompt(dir)}, frame ${f+1} of 4 of a walk cycle, 128x128, transparent background, object-only (no backdrop), crisp 1px outline, consistent palette`;
      const seed = baseSeed + d*10 + f; // stabilize identity across frames/dirs
      const job = await txt2img(framePrompt, 128, 128, process.env.SCENARIO_MODEL_ID || 'flux.1-dev', seed);
      const jobId = job?.job?.jobId || job?.jobId; if(!jobId) throw new Error('No jobId');
      const assets = await pollJob(jobId); if(assets.length>0){ const url = await getAssetUrl(assets[0]); if(url){ const fn = path.join(dirOut, `frame_${String(f).padStart(3,'0')}.png`); await dl(url, fn); console.log('[AI] Saved frame', name, dir, f); } }
    }
  }
}

(async()=>{
  for(const [name,desc] of ENEMIES){
    try{ await genFrames(name, desc); }catch(e){ console.warn(name, e.message); }
  }
})();


