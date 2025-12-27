import fs from 'fs'; import path from 'path';

const out=p=>path.join('client','assets',p); fs.mkdirSync(out('sprites'),{recursive:true}); fs.mkdirSync(out('tilemaps'),{recursive:true});

// 1x1 transparent PNG
const PNG_1x1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/VMr9SIAAAAASUVORK5YII=';

function writeBase64Png(relPath, b64){
  fs.writeFileSync(out(relPath), Buffer.from(b64, 'base64'));
}

// Use 1x1 placeholders to avoid native deps; game will still run
writeBase64Png('sprites/player_placeholder.png', PNG_1x1);
writeBase64Png('sprites/bullet_placeholder.png', PNG_1x1);

// Tilesheet 1x1, and adjust tileset to use 1x1 tiles
writeBase64Png('tilemaps/tilesheet.png', PNG_1x1);

const room = {
  height: 28,
  width: 50,
  tileheight: 1,
  tilewidth: 1,
  type: 'map',
  orientation: 'orthogonal',
  tilesets: [{ firstgid: 1, source: 'tilesheet.tsj', name: 'tilesheet' }],
  layers: [
    { name: 'ground', type: 'tilelayer', width: 50, height: 28, data: Array(50*28).fill(1) }
  ]
};
fs.writeFileSync(out('tilemaps/room1.tmj'), JSON.stringify(room, null, 2));

const tileset = {
  name: 'tilesheet', tilewidth: 1, tileheight: 1, image: 'tilesheet.png',
  imagewidth: 1, imageheight: 1, tilecount: 1, columns: 1
};
fs.writeFileSync(out('tilemaps/tilesheet.tsj'), JSON.stringify(tileset, null, 2));

console.log('Client placeholders generated');

