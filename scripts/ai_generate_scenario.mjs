// Scenario API refs:
// - Overview: https://docs.scenario.com/docs/welcome-to-the-scenario-api
// - Text-to-Image (txt2img): https://docs.scenario.com/docs/text-to-image
// - Image-to-Image (img2img): https://docs.scenario.com/docs/image-to-image-generation-img2img
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import fetch from 'node-fetch';

// Scenario txt2img per docs: https://docs.scenario.com/docs/text-to-image
const API_KEY = process.env.SCENARIO_API_KEY;
const API_SECRET = process.env.SCENARIO_SECRET_KEY;
if (!API_KEY || !API_SECRET) {
    console.log('[AI] Scenario keys missing; skipping');
    process.exit(0);
}

const BASE = 'https://api.cloud.scenario.com/v1';
const OUT = (...p) => path.join('client', 'assets', 'ai_ready', ...p);
fs.mkdirSync(OUT('characters'), { recursive: true });
fs.mkdirSync(OUT('enemies'), { recursive: true });

const credentials = Buffer.from(`${API_KEY}:${API_SECRET}`).toString('base64');

async function txt2img(prompt, width = 512, height = 512, modelId = process.env.SCENARIO_MODEL_ID || 'flux.1-dev') {
    const res = await fetch(`${BASE}/generate/txt2img`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Basic ${credentials}` },
        body: JSON.stringify({ prompt, width, height, modelId, numSamples: 1, numInferenceSteps: 28, guidance: 3.5 })
    });
    if (!res.ok) throw new Error(`Scenario txt2img failed: ${res.status} ${await res.text()}`);
    return res.json(); // returns job
}

async function pollJob(jobId) {
    const url = `${BASE}/jobs/${jobId}`;
    for (let i = 0; i < 30; i++) {
        const r = await fetch(url, { headers: { Authorization: `Basic ${credentials}` } });
        const data = await r.json();
        if (r.ok) {
            const st = data?.job?.status;
            if (st === 'success') return data?.job?.metadata?.assetIds || [];
            if (st === 'failure' || st === 'canceled') throw new Error(`Scenario job ${st}`);
        }
        await new Promise((res) => setTimeout(res, 3000));
    }
    return [];
}

async function getAssetUrl(assetId) {
    const r = await fetch(`${BASE}/assets/${assetId}`, { headers: { Authorization: `Basic ${credentials}` } });
    if (!r.ok) throw new Error(`Asset fetch failed: ${r.status}`);
    const j = await r.json();
    return j?.asset?.url;
}

async function dl(url, dest) {
    const r = await fetch(url);
    if (!r.ok) throw new Error('Download failed');
    fs.writeFileSync(dest, Buffer.from(await r.arrayBuffer()));
}

async function genCharacter(name, silhouette) {
    const p = `${name} from 'PATCHBOUND', pixel art, 32x48 character, top-down readable, 4-frame walk south (single row), consistent frame alignment, distinctive silhouette: ${silhouette}, signature colors: cool gray + neon teal/purple, transparent background, crisp 1px outline, game-ready spritesheet`;
    const job = await txt2img(p);
    const jobId = job?.job?.jobId || job?.jobId;
    if (!jobId) throw new Error('No jobId from Scenario');
    console.log('[AI] Scenario job queued:', jobId);
    const assetIds = await pollJob(jobId);
    if (assetIds.length > 0) {
        const url = await getAssetUrl(assetIds[0]);
        if (url) {
            const fname = `${name.toLowerCase().replace(/\s+/g, '_')}_walk_s.png`;
            await dl(url, OUT('characters', fname));
            console.log('[AI] Scenario saved', fname);
        }
    }
}

async function main() {
    try { await genCharacter('SysOp', 'square shoulders, utility rig, teal node beacons'); } catch (e) { console.warn(e.message); }
    try { await genCharacter('Splice Diver', 'asym cloak with data-thread tassels'); } catch (e) { console.warn(e.message); }
    try { await genCharacter('Load Balancer', 'mirrored shield pauldron, split-color cloak'); } catch (e) { console.warn(e.message); }
    try { await genCharacter('Patchwright', 'shader glyph glove, tall hat, tracer scarf'); } catch (e) { console.warn(e.message); }
}

main();
