import 'dotenv/config';
import fetch from 'node-fetch';

const API_KEY = process.env.SCENARIO_API_KEY;
const API_SECRET = process.env.SCENARIO_SECRET_KEY;
const PROJECT_ID = process.env.SCENARIO_PROJECT_ID || 'proj_eZwJyAETLAMiH2qJkZekx8By';
const BASE = 'https://api.cloud.scenario.com/v1';
const basic = Buffer.from(`${API_KEY}:${API_SECRET}`).toString('base64');

if (!API_KEY || !API_SECRET) { console.error('Missing SCENARIO keys'); process.exit(1); }

async function get(path){
    const res = await fetch(BASE+path, { headers: { Authorization: `Basic ${basic}` } });
    if(!res.ok){ console.log(`[${res.status}] GET ${path}`); throw new Error(await res.text()); }
    return res.json();
}

(async ()=>{
    try{
        const models = await get('/models');
        console.log('Models:', JSON.stringify(models).slice(0,800));
    }catch(e){ console.log('models err', e.message); }
    try{
        const proj = await get(`/projects/${PROJECT_ID}/models`);
        console.log('Project Models:', JSON.stringify(proj).slice(0,800));
    }catch(e){ console.log('project models err', e.message); }
    try{
        const gens = await get('/generators');
        console.log('Generators:', JSON.stringify(gens).slice(0,800));
    }catch(e){ console.log('generators err', e.message); }
})();
