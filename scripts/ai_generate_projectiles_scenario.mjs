import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import fetch from 'node-fetch';

const API_KEY = process.env.SCENARIO_API_KEY;
const API_SECRET = process.env.SCENARIO_SECRET_KEY;
if (!API_KEY || !API_SECRET) { console.log('[AI] Scenario keys missing; skipping projectiles'); process.exit(0); }

const BASE = 'https://api.cloud.scenario.com/v1';
const credentials = Buffer.from(`${API_KEY}:${API_SECRET}`).toString('base64');
const OUT = (...p)=> path.join('client','assets','ai_ready',...p);
fs.mkdirSync(OUT('projectiles'), { recursive: true });

async function txt2img(prompt, width=1024, height=128, modelId=process.env.SCENARIO_MODEL_ID || 'flux.1-dev'){
	const res = await fetch(`${BASE}/generate/txt2img`, {
		method: 'POST', headers: { 'Content-Type':'application/json', Authorization: `Basic ${credentials}` },
		body: JSON.stringify({ prompt, width, height, modelId, numSamples: 1, numInferenceSteps: 28, guidance: 3.0 })
	});
	if(!res.ok) throw new Error(`Scenario txt2img failed: ${res.status} ${await res.text()}`);
	return res.json();
}
async function pollJob(jobId){
	const url = `${BASE}/jobs/${jobId}`;
	for(let i=0;i<30;i++){
		const r = await fetch(url, { headers: { Authorization: `Basic ${credentials}` } });
		const d = await r.json(); if(r.ok){ const st=d?.job?.status; if(st==='success') return d?.job?.metadata?.assetIds||[]; if(st==='failure'||st==='canceled') throw new Error('Scenario job '+st); }
		await new Promise(r=>setTimeout(r,3000));
	}
	return [];
}
async function getAssetUrl(assetId){ const r = await fetch(`${BASE}/assets/${assetId}`, { headers: { Authorization: `Basic ${credentials}` } }); const j = await r.json(); if(!r.ok) throw new Error(`Asset fetch failed: ${r.status} ${JSON.stringify(j)}`); return j?.asset?.url; }
async function dl(url,dest){ const r=await fetch(url); if(!r.ok) throw new Error('Download failed'); fs.writeFileSync(dest, Buffer.from(await r.arrayBuffer())); }

async function gen(name, desc){
    const prompt = `${desc}, pixel art, 8-frame animated spritesheet, single row, frame size 128x128, transparent background, crisp 1px outline, game-ready`;
    const job = await txt2img(prompt, 1024, 128);
	const jobId = job?.job?.jobId || job?.jobId; if(!jobId) throw new Error('No jobId'); console.log('[AI] Scenario proj job:', name, jobId);
	const assets = await pollJob(jobId); if(assets.length>0){ const url = await getAssetUrl(assets[0]); if(url){ const fn = `${name}_sheet.png`; await dl(url, OUT('projectiles', fn)); console.log('[AI] Saved projectile', fn); } }
}

(async()=>{
	try{ await gen('threadneedle', 'sleek cyan energy needle bolt with bright white tip'); }catch(e){ console.warn(e.message); }
	try{ await gen('harpoon', 'metal harpoon spear projectile, steel shaft with triangular head'); }catch(e){ console.warn(e.message); }
	try{ await gen('orb', 'glowing amber orb projectile with inner light bloom'); }catch(e){ console.warn(e.message); }
	try{ await gen('shader', 'violet arcane spark, diamond-shaped flickering edges'); }catch(e){ console.warn(e.message); }
})();
