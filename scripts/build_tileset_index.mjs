#!/usr/bin/env node
// Build a tileset index of all subfolders in client/assets/tilesets containing tileset.tsj
// Output: client/assets/tilesets/index.json

import fs from 'fs';
import path from 'path';

const ROOT = 'client/assets/tilesets';

async function main(){
  const out = [];
  const entries = await fs.promises.readdir(ROOT, { withFileTypes: true });
  for(const e of entries){
    if(!e.isDirectory()) continue;
    const dir = path.join(ROOT, e.name);
    const tsj = path.join(dir, 'tileset.tsj');
    try{
      const stat = await fs.promises.stat(tsj);
      if(stat.isFile()){
        out.push({ slug: e.name, tileset: `tilesets/${e.name}/tileset.tsj` });
      }
    }catch{}
  }
  await fs.promises.writeFile(path.join(ROOT, 'index.json'), JSON.stringify({ sets: out }, null, 2));
  console.log('Wrote tilesets index with', out.length, 'entries');
}

main().catch(e=>{ console.error(e); process.exit(1); });


