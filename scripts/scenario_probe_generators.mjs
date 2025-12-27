#!/usr/bin/env node
import fetch from 'node-fetch';

// Allow passing credentials via CLI flags to avoid shell env issues
// Usage: node scripts/scenario_probe_generators.mjs --apiKey X --secret Y [--project Z]
const argv = process.argv.slice(2);
function arg(name){ const i = argv.indexOf(`--${name}`); return i>=0 ? (argv[i+1]||'') : ''; }
const API_KEY = arg('apiKey') || process.env.SCENARIO_API_KEY || '';
const SECRET = arg('secret') || process.env.SCENARIO_SECRET_KEY || '';
const PROJECT = arg('project') || process.env.SCENARIO_PROJECT_ID || '';

if(!API_KEY || !SECRET){
  console.error('Missing SCENARIO_API_KEY or SCENARIO_SECRET_KEY env vars');
  process.exit(2);
}

const auth = 'Basic ' + Buffer.from(`${API_KEY}:${SECRET}`).toString('base64');
const base = 'https://api.scenario.com/v1';

async function tryGet(url){
  try{
    const res = await fetch(url, { headers:{ Authorization: auth }});
    if(!res.ok){ return { ok:false, status:res.status, url }; }
    const json = await res.json();
    return { ok:true, json, url };
  }catch(e){ return { ok:false, error:String(e), url }; }
}

function rank(g){
  const name = (g.name||'').toLowerCase();
  const desc = (g.description||'').toLowerCase();
  const s = name + ' ' + desc;
  let score = 0;
  if(/tile|tileset|tilesheet|wang|autotile/.test(s)) score += 5;
  if(/pixel/.test(s)) score += 3;
  if(/top[- ]?down|rpg/.test(s)) score += 1;
  return score;
}

async function main(){
  const tries = [];
  tries.push(await tryGet(`${base}/generators`));
  if(PROJECT) tries.push(await tryGet(`${base}/projects/${PROJECT}/generators`));
  tries.push(await tryGet(`${base}/models`));
  const found = [];
  for(const t of tries){
    if(t.ok){
      const arr = Array.isArray(t.json) ? t.json : (Array.isArray(t.json?.items)? t.json.items : []);
      for(const it of arr){
        const score = rank(it);
        found.push({ source:t.url, score, id: it.id || it.modelId || it.generatorId, name: it.name, description: it.description||'', type: it.type||'' });
      }
    }
  }
  found.sort((a,b)=> b.score - a.score);
  console.log(JSON.stringify({ best: found.slice(0,8) }, null, 2));
}

main().catch(e=>{ console.error(e); process.exit(1); });


