import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import { canPhase, chaseStep, hasPhaseClearance } from './logic.js';

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

const PORT = 3001;

type PID = string; type Branch = 'A'|'B';
interface Player { id:PID; branch:Branch; x:number; y:number; lastPhaseAt:number }
const players = new Map<PID, Player>();

// Entangled enemies (Task 5 minimal)
type EID = string;
interface Enemy { id: string; entangledId?: EID; branch: Branch; x: number; y: number; hp: number; }
const enemies = new Map<string, Enemy>();
const entangledHp = new Map<EID, { hp: number; max: number }>();
let roomIndex = 1; let extractReady = false; let anomaly: 'none'|'loopback'|'crossfade'|'flip' = 'none'; let topologyLockRooms = 0; let roomSpawned = false;

function spawnEntangledPair(centerX:number, centerY:number, entId:EID){
  // Shared HP pool for twins
  entangledHp.set(entId, { hp: 20, max: 20 });
  const eA: Enemy = { id: entId+'-A', entangledId: entId, branch:'A', x: centerX-80, y: centerY, hp: 1 };
  const eB: Enemy = { id: entId+'-B', entangledId: entId, branch:'B', x: centerX+80, y: centerY, hp: 1 };
  enemies.set(eA.id, eA); enemies.set(eB.id, eB);
  roomSpawned = true;
}

function clearEnemies(){ enemies.clear(); entangledHp.clear(); }

function spawnBoss(){
  extractReady = false;
  const boss: Enemy = { id:'boss', branch: 'A', x: 400, y: 180, hp: 120 };
  enemies.set(boss.id, boss);
  roomSpawned = true;
  bossPhase = 1; redBuildUntil = 0;
}

// Merge Window timer (Task 6 minimal)
let mergeActive = false; let mergeEndsAt = 0; let lastMerge = 0;
const MERGE_DURATION_MS = 12000; const MERGE_COOLDOWN_MS = 18000;
let fusionActive = false; let fusionEndsAt = 0; const FUSION_DURATION_MS = 10000; const FUSION_WINDOW_MS = 2000;
const fusionRequests: Map<PID, number> = new Map();
let bossPhase: 0|1|2|3 = 0; let redBuildUntil = 0; let turretTarget: Branch = 'A'; let lastTurretSwitch = 0;

io.on('connection', (socket)=>{
  socket.on('join', (data?:{ testBoss?: boolean })=>{
    const aCount = [...players.values()].filter(p=>p.branch==='A').length;
    const bCount = [...players.values()].filter(p=>p.branch==='B').length;
    const branch:Branch = aCount <= bCount ? 'A' : 'B';
    players.set(socket.id, { id: socket.id, branch, x: 400, y: 225, lastPhaseAt: 0 });
    socket.emit('welcome', { branch, id: socket.id });
    // Ensure a wave exists on first join
    if(data?.testBoss){ clearEnemies(); roomIndex = 6; spawnBoss(); }
    else if(enemies.size===0){ spawnEntangledPair(400, 200, 'pair'+roomIndex); }
  });
  socket.on('input', (inp:{moveX:number;moveY:number})=>{
    const p = players.get(socket.id); if(!p) return;
    const speed = 4; p.x += (inp.moveX||0)*speed; p.y += (inp.moveY||0)*speed;
  });
  // Test helper: force a merge window
  socket.on('merge:force', ()=>{
    const now = Date.now();
    mergeActive = true; mergeEndsAt = now + 2500; lastMerge = now;
    io.emit('merge:forced', { endsAt: mergeEndsAt });
  });
  // Phase gate: toggle with cooldown
  socket.on('phase:request', ()=>{
    const p = players.get(socket.id); if(!p) return;
    const now = Date.now();
    if(!canPhase(now, p.lastPhaseAt, 1500)) return; // 1.5s cooldown
    const targetBranch:Branch = p.branch === 'A' ? 'B' : 'A';
    const nearBlocked = !hasPhaseClearance(p, [...enemies.values()].map(e=>({ x:e.x, y:e.y, branch:e.branch })), targetBranch, 28);
    if(nearBlocked){ socket.emit('phase:denied', { reason: 'blocked' }); return; }
    p.lastPhaseAt = now; p.branch = targetBranch;
  });
  // Fusion requests: start when two distinct players request within window
  socket.on('fusion:request', ()=>{
    const now = Date.now(); fusionRequests.set(socket.id, now);
    const reqs = [...fusionRequests.entries()].filter(([id,t])=> now - t <= FUSION_WINDOW_MS);
    if(reqs.length >= 2 && !fusionActive){ fusionActive = true; fusionEndsAt = now + FUSION_DURATION_MS; fusionRequests.clear(); }
  });
  // Projectile hit against enemy id
  socket.on('projectile:hit', (data:{ enemyId:string, shooterBranch?:Branch, mode?:string, bossBonus?: boolean, bias?: boolean })=>{
    const e = enemies.get(data.enemyId); if(!e) return;
    let dmg = (e.branch && data.shooterBranch && e.branch!==data.shooterBranch) ? 15 : 10;
    if(e.id==='boss' && data.bossBonus){ dmg = Math.floor(dmg * 1.2); }
    if(data.bias){ dmg += 5; }
    if(data.mode==='harpoon'){
      const shooter = players.get(socket.id); if(shooter){
        const dx = shooter.x - e.x; const dy = shooter.y - e.y; const len = Math.hypot(dx,dy)||1; const pull = 24;
        e.x += (dx/len)*pull; e.y += (dy/len)*pull;
      }
    }
    if(e.entangledId){
      const pool = entangledHp.get(e.entangledId); if(!pool) return;
      pool.hp = Math.max(0, pool.hp - dmg);
      if(pool.hp <= 0){
        enemies.delete(e.entangledId+'-A');
        enemies.delete(e.entangledId+'-B');
        entangledHp.delete(e.entangledId);
      }
    } else {
      e.hp = (e.hp||10) - dmg; if(e.hp<=0) enemies.delete(e.id);
    }
    if(enemies.size===0){ extractReady = true; }
  });

  // Advance room
  socket.on('room:next', ()=>{
    clearEnemies();
    roomIndex = roomIndex + 1;
    roomSpawned = false;
    // roll anomaly unless locked
    if(topologyLockRooms>0){ topologyLockRooms--; anomaly='none'; } else {
      const r = Math.random(); anomaly = r<0.2 ? 'loopback' : (r<0.35 ? 'crossfade' : (r<0.45 ? 'flip' : 'none'));
    }
    if(roomIndex < 6){ spawnEntangledPair(400, 200, 'starter'+roomIndex); }
    else { spawnBoss(); }
    const snapPlayers = [...players.values()].map(p=>({ id:p.id, branch:p.branch, x:p.x, y:p.y }));
    const snapEnemies = [...enemies.values()].map(e=>({ id:e.id, entangledId:e.entangledId, branch:e.branch, x:e.x, y:e.y }));
    const snap = { players: snapPlayers, enemies: snapEnemies, mergeState: { active: mergeActive, endsAt: mergeActive? mergeEndsAt : undefined }, fusion: { active: fusionActive, endsAt: fusionActive? fusionEndsAt : undefined }, room: { index: roomIndex, extractReady, anomaly }, boss: { phase: bossPhase, redBuildUntil, turretTarget } };
    io.emit('snapshot', snap as any);
  });
  // Spawn a wave without advancing (debug/help)
  socket.on('room:spawn', ()=>{
    if(enemies.size===0){ spawnEntangledPair(400, 200, 'pair'+roomIndex); }
    const snapPlayers = [...players.values()].map(p=>({ id:p.id, branch:p.branch, x:p.x, y:p.y }));
    const snapEnemies = [...enemies.values()].map(e=>({ id:e.id, entangledId:e.entangledId, branch:e.branch, x:e.x, y:e.y }));
    const snap = { players: snapPlayers, enemies: snapEnemies, mergeState: { active: mergeActive, endsAt: mergeActive? mergeEndsAt : undefined }, fusion: { active: fusionActive, endsAt: fusionActive? fusionEndsAt : undefined }, room: { index: roomIndex, extractReady, anomaly }, boss: { phase: bossPhase, redBuildUntil, turretTarget } };
    io.emit('snapshot', snap as any);
  });
  // Test helpers: force and weaken boss
  socket.on('boss:force', ()=>{ clearEnemies(); roomIndex = 6; spawnBoss(); const snapPlayers = [...players.values()].map(p=>({ id:p.id, branch:p.branch, x:p.x, y:p.y })); const snapEnemies = [...enemies.values()].map(e=>({ id:e.id, entangledId:e.entangledId, branch:e.branch, x:e.x, y:e.y })); const snap = { players: snapPlayers, enemies: snapEnemies, mergeState: { active: mergeActive, endsAt: mergeActive? mergeEndsAt : undefined }, fusion: { active: fusionActive, endsAt: fusionActive? fusionEndsAt : undefined }, room: { index: roomIndex, extractReady, anomaly }, boss: { phase: bossPhase, redBuildUntil, turretTarget } }; io.emit('snapshot', snap as any); });
  socket.on('boss:weaken', ()=>{ const boss = enemies.get('boss'); if(boss){ boss.hp = Math.min(boss.hp, 10); } });
  socket.on('test:setRoom', (idx:number)=>{
    if(typeof idx !== 'number') return;
    clearEnemies(); roomIndex = Math.max(1, Math.floor(idx)); roomSpawned = false; extractReady = false;
    if(roomIndex < 6){ spawnEntangledPair(400, 200, 'starter'+roomIndex); }
    else { spawnBoss(); }
    const snapPlayers2 = [...players.values()].map(p=>({ id:p.id, branch:p.branch, x:p.x, y:p.y })); const snapEnemies2 = [...enemies.values()].map(e=>({ id:e.id, entangledId:e.entangledId, branch:e.branch, x:e.x, y:e.y })); const snap2 = { players: snapPlayers2, enemies: snapEnemies2, mergeState: { active: mergeActive, endsAt: mergeActive? mergeEndsAt : undefined }, fusion: { active: fusionActive, endsAt: fusionActive? fusionEndsAt : undefined }, room: { index: roomIndex, extractReady, anomaly }, boss: { phase: bossPhase, redBuildUntil, turretTarget } }; io.emit('snapshot', snap2 as any);
  });
  // Red Build cleanse
  socket.on('redbuild:cleanse', ()=>{ if(redBuildUntil>0) redBuildUntil = Date.now(); });
  // Topology lock (prevents anomaly for N rooms)
  socket.on('topology:lock', (rooms?:number)=>{ topologyLockRooms = Math.max(1, Math.min(5, Math.floor(rooms||2))); });
  socket.on('disconnect', ()=>{ players.delete(socket.id); });
});

const g:any = globalThis as any;
if(g.__pbTickInterval){ clearInterval(g.__pbTickInterval); }
g.__pbTickInterval = setInterval(()=>{
  // Lazy spawn only once per room
  if(!roomSpawned){
    if(roomIndex < 6){ spawnEntangledPair(400, 200, 'starter'+roomIndex); extractReady = false; }
    else { spawnBoss(); extractReady = false; }
  }

  // Update Merge Window state
  const now = Date.now();
  if(bossPhase===2){ mergeActive = true; mergeEndsAt = now + 800; }
  else if(!mergeActive){ if(now - lastMerge > MERGE_COOLDOWN_MS){ mergeActive = true; mergeEndsAt = now + MERGE_DURATION_MS; } }
  else if(now >= mergeEndsAt){ mergeActive = false; lastMerge = now; }
  if(fusionActive && now >= fusionEndsAt){ fusionActive = false; }
  const snapPlayers = [...players.values()].map(p=>({ id:p.id, branch:p.branch, x:p.x, y:p.y }));
  // Simple boss chase the closest player
  const boss = enemies.get('boss');
  if(boss){
    const ps = [...players.values()];
    if(ps.length>0){
      const closest = ps.reduce((a,b)=> (Math.hypot((a.x-boss!.x),(a.y-boss!.y)) < Math.hypot((b.x-boss!.x),(b.y-boss!.y)) ? a : b));
      const next = chaseStep({x: boss.x, y: boss.y}, {x: closest.x, y: closest.y}, 1.6);
      boss.x = next.x; boss.y = next.y;
    }
    // Boss phases
    if(bossPhase===1 && boss.hp <= 80){ bossPhase = 2; const now2 = Date.now(); mergeActive = true; mergeEndsAt = now2 + 8000; }
    if(bossPhase===2 && boss.hp <= 40){ bossPhase = 3; redBuildUntil = Date.now() + 15000; for(const p of players.values()){ p.branch = p.branch==='A'?'B':'A'; } }
    if(now - lastTurretSwitch > 2500){ lastTurretSwitch = now; turretTarget = turretTarget==='A' ? 'B' : 'A'; }
    if(boss.hp <= 0){ enemies.delete('boss'); extractReady = true; bossPhase = 0; redBuildUntil = 0; }
  }
  const snapEnemies = [...enemies.values()].map(e=>({ id:e.id, entangledId:e.entangledId, branch:e.branch, x:e.x, y:e.y }));
  const snap = { players: snapPlayers, enemies: snapEnemies, mergeState: { active: mergeActive, endsAt: mergeActive? mergeEndsAt : undefined }, fusion: { active: fusionActive, endsAt: fusionActive? fusionEndsAt : undefined }, room: { index: roomIndex, extractReady, anomaly }, boss: { phase: bossPhase, redBuildUntil, turretTarget } };
  io.emit('snapshot', snap as any);
}, 100);

if(!g.__pbServerStarted){
  server.listen(PORT, ()=> console.log('Server on', PORT));
  g.__pbServerStarted = true;
}

