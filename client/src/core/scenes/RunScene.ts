import Phaser from 'phaser';
import { io, Socket } from 'socket.io-client';
import { GAME_WIDTH, GAME_HEIGHT } from '../game';
import { PatchesManager } from '../../systems/PatchesManager';
import { loadOptions } from '../../ui/Options';
import { loadUnlocks, saveUnlocks, computeUnlockedWeapons, notifyRoomCleared, notifyKill, notifyBossDefeated, grantBlueprint, notifyCouncilCompleted, type UnlocksState } from '../../systems/Unlocks';
import { loadOptions } from '../../ui/Options';
import { BlueprintsMenu } from '../../ui/BlueprintsMenu';
import seedrandom from 'seedrandom';

type Branch = 'A'|'B';
interface NetPlayer { id: string; branch: Branch; x: number; y: number; }
interface NetEnemy { id: string; entangledId?: string; branch: Branch; x: number; y: number; }

export class RunScene extends Phaser.Scene {
  player!: Phaser.Types.Physics.Arcade.ImageWithDynamicBody | Phaser.Physics.Arcade.Sprite;
  cursors!: Phaser.Types.Input.Keyboard.CursorKeys;
  socket!: Socket; branch: Branch = 'A';
  lastInputSend = 0; selfId: string | null = null;
  remotes: Map<string, Phaser.GameObjects.Image> = new Map();
  // Council (Task 4 stub)
  councilActive = false; councilProgress = 0; councilText?: Phaser.GameObjects.Text;
  padA?: Phaser.Types.Physics.Arcade.ImageWithStaticBody; padB?: Phaser.Types.Physics.Arcade.ImageWithStaticBody;
  // Weapons & Fusion (Task 7 minimal local)
  weaponIndex = 0; weapons: string[] = ['Threadneedle','Refactor Harpoon','Garbage Collector','Shader Scepter'];
  weaponText?: Phaser.GameObjects.Text; firing = false; altFiring = false; fireTimer?: Phaser.Time.TimerEvent; altTimer?: Phaser.Time.TimerEvent;
  bullets?: Phaser.Physics.Arcade.Group; fusionActive = false; fusionUntil = 0;
  enemyBullets?: Phaser.Physics.Arcade.Group;
  patches = new PatchesManager();
  opts = loadOptions();
  enemyGroup!: Phaser.Physics.Arcade.Group;
  structureGroup!: Phaser.Physics.Arcade.Group; // legacy, no longer used for visuals
  private structVisuals: Phaser.GameObjects.Sprite[] = [];
  private devHitboxOverlay = false;
  private structDebugGraphics?: Phaser.GameObjects.Graphics;
  private structInteractHint?: Phaser.GameObjects.Text;
  phaseCooldownUntil = 0;
  private lastSelfHits: Map<string, number> = new Map();
  private unlocks!: UnlocksState; private prevRoomIndex = 1;
  private lastEntangledKill: Map<string, number> = new Map();
  private bpMenu?: BlueprintsMenu;
  private map?: Phaser.Tilemaps.Tilemap;
  // --- Supermap (Wang streaming) ---
  private tilesetIndex?: { sets: Array<{ slug:string; tileset:string }> };
  private primaryTilesetSlug?: string;
  private activeSlugs: string[] = [];
  private tilesetLoaded: Set<string> = new Set();
  private chunkContainers: Map<string, Phaser.GameObjects.Container> = new Map();
  private worldSeed = 1337;
  private tileSize = 48; // px
  private tilesPerChunk = 24; // 24*48 = 1152px
  private worldTiles = 240; // 240*48 = 11520px wide/high
  // --- Local spawn director ---
  private directorStartMs = 0;
  private lastSpawnCheck = 0;
  private localIdSeq = 0;
  private localEnemyIds: Set<string> = new Set();
  // --- Spawn Director (waves/boss schedule) ---
  private lastWaveAt = 0;
  private waveIndex = 0;
  private bossScheduleIdx = 0;
  // --- VFX/Decals cache ---
  private vfxLoaded: Set<string> = new Set();
  // --- On-demand PixelLab enemy asset loader attempts ---
  private triedPixLoad: Set<string> = new Set();

  constructor(){ super('Run'); }
  create(){
    // Ensure projectile textures are present even if BootScene missed them
    this.ensureProjectileTextures();
    try{ this.map = this.make.tilemap({ key:'room1' }); const tiles = this.map.addTilesetImage('tilesheet','tiles'); const lyr = this.map.createLayer('ground', tiles!, 0, 0); lyr?.setDepth(-100); }catch{}
    // Use a sprite to allow animations; fall back to image if frames unavailable
    try{
      this.player = this.physics.add.sprite(GAME_WIDTH/2, GAME_HEIGHT/2, 'player-walk-south-0');
      (this.player as Phaser.Physics.Arcade.Sprite).play({ key: 'player-walk-south', startFrame: 0 }, true);
    }catch{
      this.player = this.physics.add.image(GAME_WIDTH/2,GAME_HEIGHT/2,'player');
    }
    this.player.setScale(0.85);
    (this.player as any).setDepth?.(6);
    // Camera & world bounds: follow player within a large world (prep for supermap streaming)
    const cam = this.cameras.main;
    const worldW = this.worldTiles * this.tileSize;
    const worldH = this.worldTiles * this.tileSize;
    this.physics.world.setBounds(0, 0, worldW, worldH);
    cam.setBounds(0, 0, worldW, worldH);
    cam.startFollow(this.player as any, true, 0.12, 0.12);
    this.player.setCollideWorldBounds(true);

    // Kick off tileset discovery and initial chunks
    this.loadTilesetRegistry().then(()=>{
      // Delay initial build a tick to allow textures to register
      this.time.delayedCall(100, ()=> this.ensureChunksAroundCamera());
    }).catch(()=>{});
    // Load optional VFX/decals (Scenario/Leonardo outputs) lazily
    this.ensureVfxAssets(['mortar_circle','railgun_beam','blink_trail','hive_body','sentinel_body','assassin_body']).catch(()=>{});
    // Ensure structure art is present; if BootScene missed, slice here as a fallback
    this.ensureStructureAssets?.().catch(()=>{});
    this.cursors = this.input.keyboard!.createCursorKeys();
    this.socket = io('http://localhost:3001');
    ;(window as any).__socket = this.socket;
    // init debug vars for e2e
    ;(window as any).__pbLastEnemyCount = 0;
    ;(window as any).__pbRoom = 1;
    ;(window as any).__pbPhaseCooldown = (ms:number)=>{ this.phaseCooldownUntil = (this.time.now||0) + ms; };
    ;(window as any).__pbForceMerge = (ms:number=2500)=>{ this.renderMergeOverlay(true, (Date.now()) + ms); };
    ;(window as any).__pbJoinBoss = ()=>{ try{ this.socket.emit('join', { testBoss: true }); }catch{} };
    ;(window as any).__pbEnsureBoss = ()=>{ try{ if((this.socket as any).connected){ this.socket.emit('boss:force'); } else { (window as any).__pbEnsureBossPending = true; } }catch{} };
    ;(window as any).__pbEnsureBossWeaken = ()=>{ try{ if((this.socket as any).connected){ this.socket.emit('boss:weaken'); } else { (window as any).__pbEnsureBossWeakenPending = true; } }catch{} };
    // Local boss preview helpers (spawn immediately near player)
    ;(window as any).__pbSpawnMortarHive = ()=>{ try{ this.spawnBossMortarHive(this.time.now||0); }catch{} };
    ;(window as any).__pbSpawnBlinkAssassin = ()=>{ try{ this.spawnBossBlinkAssassin(this.time.now||0); }catch{} };
    ;(window as any).__pbSpawnRailgunSentinel = ()=>{ try{ this.spawnBossRailgunSentinel(this.time.now||0); }catch{} };
    // Short aliases without underscores
    ;(window as any).pbSpawnMortarHive = (window as any).__pbSpawnMortarHive;
    ;(window as any).pbSpawnBlinkAssassin = (window as any).__pbSpawnBlinkAssassin;
    ;(window as any).pbSpawnRailgunSentinel = (window as any).__pbSpawnRailgunSentinel;
    // Enemy spawn helpers for testing
    ;(window as any).pbSpawnOrcBrute = ()=>{ try{ this.spawnLocalEnemyNearPlayer(this.time.now||0, 'orc_brute', false, this.getSpawnStage(((this.time.now||0) - this.directorStartMs)/1000), 0); }catch{} };
    ;(window as any).pbSpawnKnight = ()=>{ try{ this.spawnLocalEnemyNearPlayer(this.time.now||0, 'skeleton_knight', false, this.getSpawnStage(((this.time.now||0) - this.directorStartMs)/1000), 0); }catch{} };
    ;(window as any).pbSpawnPaladin = ()=>{ try{ this.spawnLocalEnemyNearPlayer(this.time.now||0, 'empire_paladin_tower', false, this.getSpawnStage(((this.time.now||0) - this.directorStartMs)/1000), 0); }catch{} };
    ;(window as any).pbSpawnJuggernaut = ()=>{ try{ this.spawnLocalEnemyNearPlayer(this.time.now||0, 'clockwork_juggernaut', false, this.getSpawnStage(((this.time.now||0) - this.directorStartMs)/1000), 0); }catch{} };
    ;(window as any).pbSpawnShrine = ()=>{ try{ this.spawnWarpShrineNearPlayer(); }catch{} };
    // defer join until listeners are registered below
    this.socket.on('welcome', (data:{ branch:Branch, id:string })=>{ this.branch = data.branch; this.selfId = data.id; (window as any).__pbReady = true; this.applyBranchTint(); this.socket.emit('room:spawn'); if((window as any).__pbEnsureBossPending){ this.socket.emit('boss:force'); (window as any).__pbEnsureBossPending = false; } if((window as any).__pbEnsureBossWeakenPending){ this.socket.emit('boss:weaken'); (window as any).__pbEnsureBossWeakenPending = false; } const gr = (window as any).__pbGotoRoomPending; if(typeof gr==='number'){ this.socket.emit('test:setRoom', gr); (window as any).__pbGotoRoomPending = undefined; } const pending = (window as any).__pbPendingEmits||[]; while(pending.length>0){ const [ev,p] = pending.shift(); this.socket.emit(ev, p); } });
    this.socket.on('snapshot', (snap:{ players: NetPlayer[]; enemies?: NetEnemy[]; mergeState?: { active:boolean; endsAt?: number }, fusion?: { active:boolean; endsAt?: number }, room?: { index:number; extractReady:boolean; anomaly?: string }, boss?: { phase:number; redBuildUntil:number; turretTarget?: 'A'|'B' } })=>{
      this.renderSnapshot(snap.players); this.renderEnemies(snap.enemies||[]);
      this.renderMergeOverlay(!!snap.mergeState?.active, snap.mergeState?.endsAt);
      if(snap.fusion?.active){ this.beginFusionLocal((snap.fusion.endsAt||this.time.now) - (this.time.now||0)); }
      this.renderRoomUi(snap.room?.index||1, !!snap.room?.extractReady);
      this.renderAnomaly((snap.room?.anomaly||'none') as any);
      this.renderBossInfo(snap.boss?.phase||0, snap.boss?.redBuildUntil||0, snap.boss?.turretTarget);
      (window as any).__pbLastEnemyCount = (snap.enemies||[]).length;
      (window as any).__pbRoom = snap.room?.index||1;
      const currentRoom = snap.room?.index||1;
      if(currentRoom > this.prevRoomIndex){
        const newly = notifyRoomCleared(this.unlocks);
        if(newly.length>0){ newly.forEach(n=> this.showUnlockToast('Unlocked: '+n)); this.onUnlocksChanged(); }
        this.prevRoomIndex = currentRoom;
      }
    });
    this.socket.on('merge:forced', (m:{endsAt:number})=>{ this.renderMergeOverlay(true, m.endsAt); const mergeDom=document.getElementById('hud-merge'); if(mergeDom) mergeDom.textContent = (((m.endsAt - Date.now())/1000).toFixed(1)+'s'); });
    this.socket.on('phase:denied', ()=>{
      const r = this.add.rectangle(this.player.x, this.player.y, 40, 40, 0xff4444, 0.2).setDepth(60);
      this.tweens.add({ targets: r, alpha: 0, scale: 2, duration: 280, onComplete: ()=> r.destroy() });
      (window as any).__pbPhaseDeniedAt = Date.now();
    });
    // now safe to join
    this.socket.emit('join', { name: 'player' + Math.floor(Math.random()*999) });
    // e2e: query param boss=1 to jump to boss room deterministically
    try{
      const qs = new URLSearchParams(window.location.search);
      if(qs.get('boss')==='1'){
        this.socket.emit('test:setRoom', 6);
        this.socket.emit('boss:force');
        this.socket.emit('boss:weaken');
      }
    }catch{}
    // Bind Phase Gate: F key (client cooldown gate)
    this.input.keyboard!.on('keydown-F', ()=>{ const now=this.time.now||0; const base=1500; const cd=this.patches.getPhaseCooldown(base); if(now<this.phaseCooldownUntil) return; this.phaseCooldownUntil=now+cd; this.socket.emit('phase:request'); });

    // Trigger a Council after a brief delay to simulate room clear (stub)
    this.time.delayedCall(2500, ()=> this.spawnCouncilStub());

    // Load unlocks and filter weapons
    this.unlocks = loadUnlocks();
    this.weapons = computeUnlockedWeapons(this.weapons);
    // Weapons HUD and bindings
    this.weaponText = this.add.text(10, 28, 'Weapon: '+this.weapons[this.weaponIndex], { fontFamily:'monospace', fontSize:'14px', color:'#ddd' });
    this.ensureHudDom();
    this.updateBlueprintHud();
    this.input.keyboard!.on('keydown-Q', ()=> this.swapWeapon(-1));
    this.input.keyboard!.on('keydown-E', ()=> this.swapWeapon(1));

    // Fusion (server request) on R
    this.input.keyboard!.on('keydown-R', ()=> this.socket.emit('fusion:request'));

    // Bullets and enemies physics groups
    this.bullets = this.physics.add.group({ classType: Phaser.Physics.Arcade.Image, maxSize: 128, runChildUpdate: false });
    this.enemyBullets = this.physics.add.group({ classType: Phaser.Physics.Arcade.Image, maxSize: 128, runChildUpdate: false });
    this.enemyGroup = this.physics.add.group({ immovable: true });
    // Structures are now non-physics static sprites (pure visuals)
    this.physics.add.overlap(this.bullets, this.enemyGroup, (b, sprite)=>{
      const bullet = b as Phaser.Types.Physics.Arcade.ImageWithDynamicBody;
      // Use a hitbox to ensure overlap refers to this sprite instance
      const mode = (bullet as any).getData?.('mode') || 'normal';
      // If merge window is inactive, only allow hits against same-branch enemies
      // Allow hits regardless of enemy branch for now; rule gating can be re-enabled later
      for(const [id, spr] of this.enemiesMap){ if(spr===sprite){
        // Local enemies: apply client-side HP and death
        const isLocal = (spr as any).getData?.('local') === true;
        if(isLocal){
          const hp = Math.max(0, ((spr as any).getData?.('hp')||1) - 1);
          (spr as any).setData?.('hp', hp);
          if(hp<=0){ this.killLocalEnemy(id, spr as any); }
        } else {
          const bossBonus = (this.patches as any).hasPatch?.('monolith_debug') && id==='boss'; this.socket.emit('projectile:hit', { enemyId: id, shooterBranch: this.branch, mode, bossBonus });
        }
        const shards = this.patches.getShardCount(); if(shards>0){ for(let i=0;i<shards;i++){ const ang = Math.random()*Math.PI*2; const sh = this.bullets!.get(this.player.x, this.player.y, 'bullet') as any; if(!sh) continue; sh.setActive(true).setVisible(true).setDepth(4).setScale(0.7).setTint(0xffaaff); this.physics.velocityFromRotation(ang, 260, sh.body.velocity); this.time.delayedCall(700,()=> sh.destroy()); } }
        break; } }
      this.doHitStop(40); this.doShake();
      const hits = ((bullet as any).getData?.('hits') ?? 0) + 1;
      (bullet as any).setData?.('hits', hits);
      const mActive = !!this.mergeOverlay?.visible;
      const mergeBonus = (mActive && (this.patches as any).hasPatch?.('branch_overload')) ? 1 : 0;
      const maxHits = (mActive ? 4 : 1) + this.patches.getBulletPierceBonus() + mergeBonus;
      if(hits >= maxHits){ (bullet as any).destroy(); }
      // Temporal Refund: if enemy dies, refund phase cooldown
      // Record last hit time per enemy
      const now = this.time.now||0; const last = this.lastSelfHits.get((sprite as any).name||'')||0; this.lastSelfHits.set((sprite as any).name||'', now);
    });
    this.input.on('pointerdown', (p:Phaser.Input.Pointer)=>{ if(p.rightButtonDown()){ this.startAltFire(); } else { this.startFire(); } });
    this.input.on('pointerup', (p:Phaser.Input.Pointer)=>{ if(!p.rightButtonDown()){ this.stopFire(); } if(!p.leftButtonDown()){ this.stopAltFire(); } });
    // Enemy projectile hits player
    this.physics.add.overlap(this.enemyBullets, this.player as any, (b:any)=>{ try{ b.destroy?.(); }catch{} this.doHitStop(70); this.doShake(); });
    this.input.keyboard!.on('keydown-H', ()=> this.toggleControlsHint());
    this.input.keyboard!.on('keydown-B', ()=> this.toggleBlueprintsMenu());

    // Removed structure overlaps; structures are visuals only

    // Remove interact hint for structures (no interaction in visual-only mode)
    this.structInteractHint = undefined as any;

    // Spawn simple static structure visuals (delay to allow slicing)
    this.time.delayedCall(600, ()=> this.spawnRandomStructuresForRun());

    // Council selection overlay on resolve
    this.events.on('council:resolve', ()=> this.showCouncilChoices());
    this.events.on('council:cleanup', async ()=>{ try{ const newly = notifyCouncilCompleted(this.unlocks); if(newly.length>0){ newly.forEach((n:string)=> this.showUnlockToast('Unlocked: '+n)); this.onUnlocksChanged(); } saveUnlocks(this.unlocks); await this.tryAwardBlueprint(false); }catch{} });
  }

  private async loadTilesetRegistry(){
    try{
      const res = await fetch('/tilesets/index.json');
      this.tilesetIndex = await res.json();
      // Activate a broad set of tilesets for biome variety (avoid only empty placeholders)
      const all = (this.tilesetIndex?.sets||[]);
      const usable = all.filter(s=> !!s.slug);
      // Shuffle deterministically from worldSeed for even coverage, pick up to 6
      const arr = [...usable];
      const r = seedrandom(String(this.worldSeed));
      for(let i=arr.length-1;i>0;i--){ const j = Math.floor(r()* (i+1)); const t = arr[i]; arr[i]=arr[j]; arr[j]=t; }
      const picks = arr.slice(0, Math.min(6, arr.length));
      this.activeSlugs = picks.map(p=> p.slug);
      this.primaryTilesetSlug = this.activeSlugs[0];
      for(const s of this.activeSlugs){ await this.ensureTilesetLoaded(s); }
    }catch{}
  }

  private async ensureTilesetLoaded(slug:string){
    if(this.tilesetLoaded.has(slug)) return;
    try{
      // Load 16 tile images into Phaser textures
      for(let i=0;i<16;i++){
        const idx = String(i).padStart(2,'0');
        const key = `wang_${slug}_${idx}`;
        if(this.textures.exists(key)) continue;
        const img = new Image();
        img.crossOrigin = 'anonymous';
        img.src = `/tilesets/${slug}/tiles/tile_${idx}.png?v=${Date.now()}`;
        const dec: Promise<void> = (img as any).decode ? (img as any).decode() : new Promise((resolve,reject)=>{ img.onload=()=>resolve(); img.onerror=()=>resolve(); });
        await dec;
        try{ this.textures.addImage(key, img as any); }catch{}
      }
      this.tilesetLoaded.add(slug);
    }catch{}
  }

  private ensureChunksAroundCamera(){
    const cam = this.cameras.main;
    const midX = cam.worldView.centerX || (cam.scrollX + cam.width/2);
    const midY = cam.worldView.centerY || (cam.scrollY + cam.height/2);
    const cx = Math.floor((midX) / (this.tileSize*this.tilesPerChunk));
    const cy = Math.floor((midY) / (this.tileSize*this.tilesPerChunk));
    for(let dy=-1; dy<=1; dy++){
      for(let dx=-1; dx<=1; dx++){
        const k = `${cx+dx},${cy+dy}`;
        if(!this.chunkContainers.has(k)) this.buildChunk(cx+dx, cy+dy);
      }
    }
    // Cull far chunks
    for(const [k, c] of this.chunkContainers){
      const [sx, sy] = k.split(',').map(n=> parseInt(n,10));
      if(Math.abs(sx-cx)>2 || Math.abs(sy-cy)>2){ c.destroy(); this.chunkContainers.delete(k); }
    }
  }

  // Optional VFX textures loader: tries /vfx/<name>.png and /vfx/<name>.webp
  private async ensureVfxAssets(names:string[]){
    const tryLoad = async (key:string, url:string)=>{
      if(this.textures.exists(key)) return true;
      try{
        const img = new Image(); (img as any).crossOrigin = 'anonymous'; img.src = url;
        const dec: Promise<void> = (img as any).decode ? (img as any).decode() : new Promise((res)=>{ img.onload=()=>res(); img.onerror=()=>res(); });
        await dec; this.textures.addImage(key, img as any); return true;
      }catch{ return false; }
    };
    for(const n of names){
      if(this.vfxLoaded.has(n)) continue;
      const ok = await tryLoad(`vfx_${n}`, `/vfx/${n}.png?v=${Date.now()}`) || await tryLoad(`vfx_${n}`, `/vfx/${n}.webp?v=${Date.now()}`);
      if(ok){ this.vfxLoaded.add(n); try{ this.sliceVfxIfSpritesheet(n); }catch{} }
    }
  }

  // If a VFX image is a spritesheet (strip or grid), slice it into frames and register an animation under key `vfx_<name>`
  private sliceVfxIfSpritesheet(name:string){
    const baseKey = `vfx_${name}`; if(!this.textures.exists(baseKey)) return;
    const tex:any = this.textures.get(baseKey); const img:any = tex.getSourceImage ? tex.getSourceImage() : undefined; if(!img) return;
    const w = img.naturalWidth||img.width; const h = img.naturalHeight||img.height;
    let cols = 1, rows = 1;
    if(w>h && w % h === 0){ cols = Math.min(16, w/h); rows = 1; }
    else if(h>w && h % w === 0){ rows = Math.min(16, h/w); cols = 1; }
    else {
      // try a small grid 2..8
      for(let g=2; g<=8; g++){ if(w%g===0 && h%g===0){ cols=g; rows=g; break; } }
    }
    const frames:number[] = [];
    if(cols*rows>1){
      const cw = Math.floor(w/cols), ch = Math.floor(h/rows);
      for(let r=0;r<rows;r++){
        for(let c=0;c<cols;c++){
          const key = `vfx_${name}-${frames.length}`;
          if(this.textures.exists(key)) continue;
          const canvas:any = this.textures.createCanvas(key, cw, ch);
          const ctx = canvas.getContext(); ctx.clearRect(0,0,cw,ch);
          ctx.drawImage(img, c*cw, r*ch, cw, ch, 0, 0, cw, ch);
          canvas.refresh(); frames.push(frames.length);
        }
      }
      const animKey = `vfx_${name}`;
      if(this.anims.exists(animKey)) this.anims.remove(animKey);
      this.anims.create({ key: animKey, frames: frames.map(i=>({ key: `vfx_${name}-${i}` })), frameRate: 12, repeat: -1 });
    }
  }

  private makeVfxAt(name:string, x:number, y:number, depth:number=40): Phaser.GameObjects.GameObject{
    const animKey = `vfx_${name}`;
    if(this.anims.exists(animKey)){
      const spr = this.add.sprite(x, y, `${animKey}-0`).setDepth(depth);
      try{ (spr as any).play?.(animKey, true); }catch{}
      return spr;
    }
    return this.add.image(x,y,`vfx_${name}`).setDepth(depth);
  }

  private async ensureStructureAssets(){
    const defs = [
      { name:'arcane_cube', sheet:'/sprites/structures/sheets/arcane_cube_sheet.png' },
      { name:'obelisk', sheet:'/sprites/structures/sheets/obelisk_sheet.png' },
      { name:'green_fountain', sheet:'/sprites/structures/sheets/green_fountain_sheet.png' },
    ];
    const slice = (n:string, img:HTMLImageElement)=>{
      const W = img.naturalWidth||img.width; const H = img.naturalHeight||img.height; if(!W||!H) return;
      // Force known layout for provided sheets to avoid mis-detection jitter
      const forced: Record<string,[number,number]> = {
        'arcane_cube': [2,4],
        'obelisk': [2,4],
        'green_fountain': [2,4],
      };
      const [cols, rows] = forced[n] || [2,4];
      if(W % cols !== 0 || H % rows !== 0){ const fk = `struct_${n}-0`; if(!this.textures.exists(fk)){ const cvs:any = this.textures.createCanvas(fk, W, H); const ctx = cvs.getContext(); ctx.clearRect(0,0,W,H); ctx.drawImage(img,0,0); cvs.refresh(); } return; }
      const cw = Math.floor(W/cols), ch = Math.floor(H/rows);
      // Strict equal-grid slicing: draw each cell directly, no trimming or shifts
      let idx=0; for(let ry=0; ry<rows; ry++){
        for(let cx=0; cx<cols; cx++){
          if(idx>=8) break;
          const sx = cx*cw, sy = ry*ch;
          const fk=`struct_${n}-${idx}`; if(this.textures.exists(fk)) { idx++; continue; }
          const cvs:any = this.textures.createCanvas(fk, cw, ch);
          const ctx = cvs.getContext(); ctx.clearRect(0,0,cw,ch);
          ctx.drawImage(img, sx, sy, cw, ch, 0, 0, cw, ch);
          cvs.refresh(); idx++;
        }
      }
      const animKey = `struct_${n}-idle`; if(this.anims.exists(animKey)) this.anims.remove(animKey);
      const frames = Array.from({length:8},(_,i)=> ({ key:`struct_${n}-${i}` })).filter(f=> this.textures.exists(f.key));
      if(frames.length>0) this.anims.create({ key: animKey, frames, frameRate: 14, repeat: -1 });
    };
    for(const d of defs){ if(this.textures.exists(`struct_${d.name}-0`)) continue; try{ const img = new Image(); (img as any).crossOrigin='anonymous'; img.src = `${d.sheet}?v=${Date.now()}`; const dec: Promise<void> = (img as any).decode ? (img as any).decode() : new Promise(res=>{ img.onload=()=>res(); img.onerror=()=>res(); }); await dec; slice(d.name, img); }catch{} }
  }

  // Compute trimmed bounds of opaque pixels for a structure frame texture key
  private computeAlphaBoundsForKey(texKey:string, threshold=16): { x:number;y:number;width:number;height:number }|null{
    try{
      const tex:any = this.textures.get(texKey); if(!tex || !tex.getSourceImage) return null;
      const img:any = tex.getSourceImage(); const W = img.naturalWidth||img.width; const H = img.naturalHeight||img.height; if(!W||!H) return null;
      const cvs = document.createElement('canvas'); cvs.width=W; cvs.height=H; const ctx = cvs.getContext('2d')!; ctx.clearRect(0,0,W,H); ctx.drawImage(img,0,0);
      const id = ctx.getImageData(0,0,W,H); const data = id.data;
      let x0=Infinity, y0=Infinity, x1=-1, y1=-1;
      for(let y=0;y<H;y++){
        const base=y*W; for(let x=0;x<W;x++){ const a=data[(base+x)*4+3]; if(a>threshold){ if(x<x0) x0=x; if(y<y0) y0=y; if(x>x1) x1=x; if(y>y1) y1=y; } }
      }
      if(x1<0) return { x:0, y:0, width:W, height:H };
      return { x:x0, y:y0, width:x1-x0+1, height:y1-y0+1 };
    }catch{ return null; }
  }

  // Create a containerized structure with base sprite and static physics hitbox
  private createStructureAt(keyPrefix:string, x:number, y:number, targetH:number, meta?:{ offsetY?:number; collisionOffset?:{x:number;y:number}; collisionScale?:{x:number;y:number} }): Phaser.GameObjects.Container{
    // New approach: manual frame player on a fixed-size RenderTexture to guarantee no drift/cropping
    const cont = this.add.container(x, y).setDepth(4);
    const frames:string[] = [];
    for(let i=0;i<8;i++){ const k = `${keyPrefix}-${i}`; if(this.textures.exists(k)) frames.push(k); }
    const alphaBounds = (k:string)=> this.computeAlphaBoundsForKey(k) || { x:0,y:0,width:(this.textures.get(k) as any)?.getSourceImage()?.width||1, height:(this.textures.get(k) as any)?.getSourceImage()?.height||1 };
    let maxW = 1, maxH = 1;
    const bbs = frames.map(k=>{ const b=alphaBounds(k); maxW = Math.max(maxW, b.width); maxH = Math.max(maxH, b.height); return b; });
    // Canvas large enough for all frames' opaque content
    const rt:any = this.add.renderTexture(0, 0, maxW, maxH).setOrigin(0.5, 1);
    // Scale to target height based on canvas
    const sc = Phaser.Math.Clamp(targetH / maxH, 0.3, 2); rt.setScale(sc);
    cont.add(rt);
    const offY = meta?.offsetY ?? -6; cont.y += offY;
    // Precompute draw offsets so bottom-center aligns
    const offsets = bbs.map(b=>{ const pivotLocalWithinBB = b.width/2; const dx = Math.floor(maxW/2 - pivotLocalWithinBB); const dy = maxH - b.height; return { dx, dy }; });
    let fi = 0;
    const drawFrame = ()=>{ if(frames.length===0) return; const fk = frames[fi%frames.length]; const {dx,dy} = offsets[fi%offsets.length]; rt.clear(); rt.draw(fk, dx, dy); fi=(fi+1)%frames.length; };
    // start at frame 0
    drawFrame();
    // tick at ~10 FPS
    const ev = this.time.addEvent({ delay: 100, loop: true, callback: drawFrame });
    cont.setData('animEvent', ev);
    // Hitbox (optional): simple rectangle matching canvas bottom area
    try{
      const hb = this.physics.add.staticImage(x, y, frames[0]).setVisible(false).setDepth(3).setOrigin(0.5,1);
      (hb.body as Phaser.Physics.Arcade.Body).setSize(Math.max(8, Math.round(maxW*sc*0.8)), Math.max(8, Math.round(maxH*sc*0.3)));
      cont.setData('hitbox', hb);
    }catch{}
    return cont;
  }

  private applyStructureAnimAndScale(s: Phaser.Physics.Arcade.Sprite, stype: 'warp_shrine'|'hazard_obelisk'|'mystery_cube', animKey: string, baseKey: string){
    if(this.anims.exists(animKey)){
      try{ s.play(animKey, true); }catch{}
    }
    // Scale heuristics based on first frame size
    try{
      const tex:any = this.textures.get(baseKey); const img:any = tex && tex.getSourceImage ? tex.getSourceImage() : undefined;
      const h = img ? (img.naturalHeight||img.height) : 0;
      let targetH = 128;
      if(stype==='mystery_cube') targetH = 96;
      if(stype==='hazard_obelisk') targetH = 160;
      if(h && h>0){ const scale = Math.min(2, Math.max(0.25, targetH / h)); s.setScale(scale); }
    }catch{}
  }

  private buildChunk(cx:number, cy:number){
    if(this.activeSlugs.length===0) return; for(const s of this.activeSlugs){ if(!this.tilesetLoaded.has(s)) return; }
    const cont = this.add.container(cx*this.tilesPerChunk*this.tileSize, cy*this.tilesPerChunk*this.tileSize).setDepth(-100);
    const rng = seedrandom(`${this.worldSeed}:${cx},${cy}`);
    const threshold = 0.55;
    // --- Coherent noise helpers ---
    const rot = (x:number,y:number,a:number)=>{ const ca=Math.cos(a), sa=Math.sin(a); return [x*ca - y*sa, x*sa + y*ca]; };
    const hash2 = (x:number,y:number)=>{ const n = Math.sin(x*127.1 + y*311.7 + this.worldSeed*0.013)*43758.5453; return n - Math.floor(n); };
    const valueNoise = (x:number,y:number)=>{
      const x0 = Math.floor(x), y0 = Math.floor(y);
      const xf = x - x0, yf = y - y0;
      const s = (t:number)=> t*t*(3-2*t);
      const n00 = hash2(x0, y0), n10 = hash2(x0+1, y0), n01 = hash2(x0, y0+1), n11 = hash2(x0+1, y0+1);
      const nx0 = n00 + (n10 - n00)*s(xf);
      const nx1 = n01 + (n11 - n01)*s(xf);
      return nx0 + (nx1 - nx0)*s(yf);
    };
    const fbm = (x:number,y:number,oct=4)=>{ let amp=0.5, freq=1, sum=0; for(let i=0;i<oct;i++){ sum += amp*valueNoise(x*freq, y*freq); freq*=2; amp*=0.5; } return sum; };
    const warpedField = (x:number,y:number)=>{
      // domain warp to avoid grid-aligned artifacts
      const [rx, ry] = rot(x*0.035, y*0.035, 0.6);
      const w1 = fbm(rx*0.45, ry*0.45, 3);
      const w2 = fbm(rx*0.9 + w1*2.4, ry*0.8 - w1*2.4, 4);
      return Phaser.Math.Clamp(w2, 0, 1);
    };
    const smoothField = (x:number,y:number)=>{
      // low-cost majority smoothing around a vertex
      const c = warpedField(x,y);
      const a = warpedField(x+0.6,y);
      const b = warpedField(x-0.6,y);
      const d = warpedField(x,y+0.6);
      const e = warpedField(x,y-0.6);
      return (c*0.5) + ((a+b+d+e)/4)*0.5;
    };
    // Macro features per chunk: plates (discs) and 0-1 local road, plus global hub roads
    const discs: Array<{x:number;y:number;r:number}> = [];
    const discCount = 1 + Math.floor(rng()*3);
    for(let i=0;i<discCount;i++){ discs.push({ x: rng()*this.tilesPerChunk, y: rng()*this.tilesPerChunk, r: 3 + rng()*6 }); }
    const hasRoad = rng() < 0.55;
    const road = hasRoad ? { x1: rng()<0.5 ? -4 : this.tilesPerChunk+4, y1: rng()*this.tilesPerChunk, x2: rng()*this.tilesPerChunk, y2: rng()<0.5 ? -4 : this.tilesPerChunk+4, w: 1.2 + rng()*1.6 } : null;
    const distToSeg = (px:number,py:number, x1:number,y1:number,x2:number,y2:number)=>{
      const vx = x2-x1, vy = y2-y1; const wx = px-x1, wy = py-y1; const c1 = vx*wx + vy*wy; const c2 = vx*vx + vy*vy; const t = Phaser.Math.Clamp(c1/(c2||1), 0, 1); const dx = x1 + t*vx - px; const dy = y1 + t*vy - py; return Math.hypot(dx,dy);
    };
    // Global hub roads every M chunks
    const macro = 4; // chunks per hub cell
    const hubPx = (ix:number,iy:number)=>({ x: (ix+0.5)*macro*this.tilesPerChunk, y: (iy+0.5)*macro*this.tilesPerChunk });
    const thisHub = hubPx(Math.floor(cx/macro), Math.floor(cy/macro));
    const eastHub = hubPx(Math.floor(cx/macro)+1, Math.floor(cy/macro));
    const southHub = hubPx(Math.floor(cx/macro), Math.floor(cy/macro)+1);
    const globalRoadW = 2.4;
    // Chunk-level biome identity with soft blending across chunk borders
    const chunkToSlugIdx = (ix:number, iy:number)=>{
      const s = 0.18; // low frequency for large regions
      const v = fbm(ix*s + this.worldSeed*0.001, iy*s - this.worldSeed*0.002, 3);
      const idx = Math.max(0, Math.min(this.activeSlugs.length-1, Math.floor(v * this.activeSlugs.length)));
      return idx;
    };
    const baseIdx = chunkToSlugIdx(cx, cy);
    const northIdx = chunkToSlugIdx(cx, cy-1);
    const southIdx = chunkToSlugIdx(cx, cy+1);
    const westIdx  = chunkToSlugIdx(cx-1, cy);
    const eastIdx  = chunkToSlugIdx(cx+1, cy);
    const neighborIdxAt = (side:'N'|'S'|'W'|'E')=> side==='N'?northIdx: side==='S'?southIdx: side==='W'?westIdx:eastIdx;
    for(let ty=0; ty<this.tilesPerChunk; ty++){
      for(let tx=0; tx<this.tilesPerChunk; tx++){
        // Choose tileset region by low-frequency noise
        const gx = cx*this.tilesPerChunk + tx;
        const gy = cy*this.tilesPerChunk + ty;
        // Base biome for this chunk
        let pickIdx = baseIdx;
        // Soft blend near chunk edges
        const edgeBandTiles = 3; // tiles inside the border to blend
        const dLeft = tx;
        const dRight = this.tilesPerChunk - 1 - tx;
        const dTop = ty;
        const dBottom = this.tilesPerChunk - 1 - ty;
        const minDist = Math.min(dLeft, dRight, dTop, dBottom);
        if(minDist < edgeBandTiles){
          const side = (minDist===dTop)?'N' : (minDist===dBottom)?'S' : (minDist===dLeft)?'W':'E';
          const neighbor = neighborIdxAt(side as any);
          const t = (edgeBandTiles - minDist) / edgeBandTiles; // 0..1 approaching edge
          const rnd = hash2(gx*0.37, gy*0.41);
          if(rnd < t*0.75){ pickIdx = neighbor; }
        }
        const slug = this.activeSlugs[pickIdx] || this.primaryTilesetSlug!;

        // Vertex samples at cell corners using warped noise + macro features
        const upperAt = (vx:number,vy:number)=>{
          let h = smoothField(vx*0.9, vy*0.9);
          // discs add metal/upper patches
          for(const d of discs){ const dx=vx - (cx*this.tilesPerChunk + d.x), dy=vy - (cy*this.tilesPerChunk + d.y); const dist=Math.hypot(dx,dy); if(dist < d.r){ h = Math.max(h, 0.85 - (dist/d.r)*0.4); }
          }
          // road overlay
          if(road){ const d = distToSeg(vx - cx*this.tilesPerChunk, vy - cy*this.tilesPerChunk, road.x1, road.y1, road.x2, road.y2); if(d < road.w){ h = 0.95; }
          }
          // global roads: connect hubs
          const wx = vx; const wy = vy; // world tile units
          const dE = distToSeg(wx, wy, thisHub.x, thisHub.y, eastHub.x, eastHub.y);
          const dS = distToSeg(wx, wy, thisHub.x, thisHub.y, southHub.x, southHub.y);
          if(Math.min(dE,dS) < globalRoadW){ h = 0.97; }
          // local threshold jitter for edge breakup
          const thrJitter = (hash2(Math.floor(vx/6), Math.floor(vy/6)) - 0.5) * 0.22;
          const tLoc = threshold + thrJitter;
          return h > tLoc ? 1 : 0;
        };
        const nw = upperAt(gx, gy);
        const ne = upperAt(gx+1, gy);
        const se = upperAt(gx+1, gy+1);
        const sw = upperAt(gx, gy+1);
        const idx = (nw<<3)|(ne<<2)|(se<<1)|sw;
        const key = `wang_${slug}_${String(idx).padStart(2,'0')}`;
        const img = this.add.image(tx*this.tileSize + this.tileSize/2, ty*this.tileSize + this.tileSize/2, key).setOrigin(0.5);
        cont.add(img);
      }
    }
    this.chunkContainers.set(`${cx},${cy}`, cont);
  }
  private ensureProjectileTextures(){
    const proj = ['threadneedle','harpoon','orb','shader'];
    const dirs = ['east','north-east','north','north-west','west','south-west','south','south-east'];
    const cb = String(Date.now());
    const addFromUrl = (key:string, url:string)=>{
      if(this.textures.exists(key)) return;
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.src = url;
      const register = ()=>{ try{ this.textures.addImage(key, img as any); }catch{} };
      if((img as any).decode){ (img as any).decode().then(register).catch(register); }
      else { img.onload = register; img.onerror = register; }
    };
    for(const n of proj){
      for(const d of dirs){
        for(let i=0;i<8;i++){
          const key = `proj_${n}-${d}-${i}`;
          const idx = String(i).padStart(3,'0');
          const url = `/sprites/projectiles/${n}/animations/walking-8-frames/${d}/frame_${idx}.png?v=${cb}`;
          addFromUrl(key, url);
        }
        const rotKey = `proj_${n}-rot-${d}`;
        addFromUrl(rotKey, `/sprites/projectiles/${n}/rotations/${d}.png?v=${cb}`);
      }
    }
  }

  private applyBranchTint(pulse:boolean=false){
    const tint = this.branch==='A' ? 0x29d3c6 : 0x9b59ff; // teal vs purple
    this.player.setTint(tint);
    if(pulse){
      const r = this.add.rectangle(this.player.x, this.player.y, 40, 40, tint, 0.2).setDepth(50);
      this.tweens.add({ targets: r, alpha: 0, scale: 2, duration: 300, onComplete: ()=> r.destroy() });
    }
  }

  private mergeOverlay?: Phaser.GameObjects.Rectangle; private mergeEndsAt?: number; private mergeTimerText?: Phaser.GameObjects.Text;
  private renderMergeOverlay(active:boolean, endsAt?: number){
    if(active){
      this.mergeEndsAt = endsAt;
      if(!this.mergeOverlay){ this.mergeOverlay = this.add.rectangle(GAME_WIDTH/2, GAME_HEIGHT/2, GAME_WIDTH, GAME_HEIGHT, 0x9b59ff, 0.07).setDepth(100); }
      this.mergeOverlay.setVisible(true);
      if(!this.mergeTimerText){ this.mergeTimerText = this.add.text(GAME_WIDTH/2, 8, '', { fontFamily:'monospace', fontSize:'14px', color:'#c9f' }).setOrigin(0.5,0).setDepth(200); }
      this.mergeTimerText.setVisible(true);
      (window as any).__pbMergeActive = true;
    } else if(this.mergeOverlay){ this.mergeOverlay.setVisible(false); }
    if(!active && this.mergeTimerText){ this.mergeTimerText.setVisible(false); (window as any).__pbMergeActive = false; }
  }

  private roomText?: Phaser.GameObjects.Text; private extractText?: Phaser.GameObjects.Text;
  private enterArmed = false;
  private renderRoomUi(index:number, extractReady:boolean){
    if(!this.roomText){ this.roomText = this.add.text(10, 44, '', { fontFamily:'monospace', fontSize:'14px', color:'#ccc' }); }
    this.roomText.setText('Room: ' + index + (extractReady? ' (Extract Ready)' : ''));
    const roomDom=document.getElementById('hud-room'); if(roomDom) roomDom.textContent=String(index);
    if(extractReady){
      if(!this.extractText){ this.extractText = this.add.text(GAME_WIDTH/2, 30, 'Press ENTER to Extract / Next', { fontFamily:'monospace', fontSize:'14px', color:'#ffea00' }).setOrigin(0.5); }
      this.extractText.setVisible(true);
      if(!this.enterArmed){
        this.enterArmed = true;
        this.input.keyboard!.once('keydown-ENTER', ()=>{ this.socket.emit('room:next'); this.enterArmed = false; });
      }
    } else if(this.extractText){ this.extractText.setVisible(false); }
  }

  private anomalyText?: Phaser.GameObjects.Text;
  private renderAnomaly(anomaly: 'none'|'loopback'|'crossfade'|'flip'){
    if(anomaly==='none'){ if(this.anomalyText){ this.anomalyText.setVisible(false); } return; }
    if(!this.anomalyText){ this.anomalyText = this.add.text(GAME_WIDTH/2, GAME_HEIGHT-18, '', { fontFamily:'monospace', fontSize:'12px', color:'#8bf' }).setOrigin(0.5); }
    this.anomalyText.setText('Anomaly: '+anomaly).setVisible(true);
  }

  private bossPhaseText?: Phaser.GameObjects.Text; private redOverlay?: Phaser.GameObjects.Rectangle; private turretText?: Phaser.GameObjects.Text;
  private renderBossInfo(phase:number, redUntil:number, turretTarget?: 'A'|'B'){
    if(phase>0){
      if(!this.bossPhaseText){ this.bossPhaseText = this.add.text(GAME_WIDTH-8, 24, '', { fontFamily:'monospace', fontSize:'12px', color:'#f66' }).setOrigin(1,0).setDepth(200); }
      this.bossPhaseText.setText('Boss P'+phase).setVisible(true);
    } else if(this.bossPhaseText){ this.bossPhaseText.setVisible(false); }
    if(turretTarget){ if(!this.turretText){ this.turretText = this.add.text(GAME_WIDTH-8, 38, '', { fontFamily:'monospace', fontSize:'12px', color:'#faa' }).setOrigin(1,0).setDepth(200); } this.turretText.setText('Turret→ '+turretTarget).setVisible(true); }
    else if(this.turretText){ this.turretText.setVisible(false); }
    const now = this.time.now||0;
    const active = redUntil>0 && (Date.now() < redUntil);
    if(active){ if(!this.redOverlay){ this.redOverlay = this.add.rectangle(GAME_WIDTH/2, GAME_HEIGHT/2, GAME_WIDTH, GAME_HEIGHT, 0xff2222, 0.06).setDepth(90); } this.redOverlay.setVisible(true); }
    else if(this.redOverlay){ this.redOverlay.setVisible(false); }
    // Red Build cleanse hint and pads
    if(active){ this.ensureCleansePads(); this.showCleanseHint(); }
    else { this.hideCleanseHint(); this.destroyCleansePads(); }
  }

  // --- Controls Hint ---
  private controlsHint?: Phaser.GameObjects.Text; private controlsVisible = false;
  private toggleControlsHint(){
    this.controlsVisible = !this.controlsVisible;
    if(!this.controlsHint){
      const txt = [
        'Controls:',
        'Arrows: Move, LMB: Fire, RMB: Alt Fire',
        'Q/E: Swap Weapon, F: Phase, R: Fusion',
        'Enter: Extract/Next, C: Cleanse (on red pad)',
        'B: Blueprints menu'
      ].join('\n');
      this.controlsHint = this.add.text(GAME_WIDTH-8, GAME_HEIGHT-8, txt, { fontFamily:'monospace', fontSize:'12px', color:'#cfe', align:'right' })
        .setOrigin(1,1).setDepth(220);
      const bg = this.add.rectangle(GAME_WIDTH-10, GAME_HEIGHT-10, 360, 80, 0x000000, 0.45)
        .setOrigin(1,1).setDepth(219);
      this.controlsHint.setData('bg', bg);
    }
    const bg = this.controlsHint.getData('bg') as Phaser.GameObjects.Rectangle;
    this.controlsHint.setVisible(this.controlsVisible); if(bg) bg.setVisible(this.controlsVisible);
  }

  private cleanseHint?: Phaser.GameObjects.Text; private cleanseA?: Phaser.Types.Physics.Arcade.ImageWithStaticBody; private cleanseB?: Phaser.Types.Physics.Arcade.ImageWithStaticBody;
  private showCleanseHint(){ if(!this.cleanseHint){ this.cleanseHint = this.add.text(GAME_WIDTH/2, 12, 'Red Build: press C on pad to cleanse', { fontFamily:'monospace', fontSize:'12px', color:'#ffaaaa' }).setOrigin(0.5,0).setDepth(210); } this.cleanseHint.setVisible(true); }
  private hideCleanseHint(){ if(this.cleanseHint) this.cleanseHint.setVisible(false); }
  private ensureCleansePads(){ if(this.cleanseA && this.cleanseB) return; this.cleanseA = this.physics.add.staticImage(120, 220, 'player').setTint(0xff8888).setAlpha(0.35); this.cleanseB = this.physics.add.staticImage(680, 220, 'player').setTint(0xff8888).setAlpha(0.35); this.input.keyboard!.on('keydown-C', ()=>{ if(this.physics.overlap(this.player, this.cleanseA!) || this.physics.overlap(this.player, this.cleanseB!)){ (this.socket as any).emit('redbuild:cleanse'); } }); }
  private destroyCleansePads(){ this.cleanseA?.destroy(); this.cleanseB?.destroy(); this.cleanseA=undefined; this.cleanseB=undefined; }

  private renderSnapshot(players: NetPlayer[]){
    // Sync local branch from snapshot for accurate rules
    if(this.selfId){
      const me = players.find(p=>p.id===this.selfId);
      if(me && me.branch !== this.branch){
        this.branch = me.branch; this.applyBranchTint(true);
        // Phase Blink: dash on successful phase if patch is active
        if((this.patches as any).hasPatch?.('phase_blink')){
          const ptr = this.input.activePointer; let a = Phaser.Math.Angle.Between(this.player.x, this.player.y, ptr.worldX, ptr.worldY);
          let vx = 0, vy = 0; if(this.cursors.left?.isDown) vx-=1; if(this.cursors.right?.isDown) vx+=1; if(this.cursors.up?.isDown) vy-=1; if(this.cursors.down?.isDown) vy+=1; if(vx!==0||vy!==0){ a = Math.atan2(vy, vx); }
          const dist = 60; const tx = Phaser.Math.Clamp(this.player.x + Math.cos(a)*dist, 0, GAME_WIDTH);
          const ty = Phaser.Math.Clamp(this.player.y + Math.sin(a)*dist, 0, GAME_HEIGHT);
          this.tweens.add({ targets: this.player, x: tx, y: ty, duration: 120, ease: 'Sine.easeOut' });
          if((this.patches as any).hasPatch?.('phase_afterimage')){ const img = this.add.image(this.player.x, this.player.y, 'player').setAlpha(0.4).setTint(0xffffff).setDepth(3); this.tweens.add({ targets: img, alpha: 0, duration: 300, onComplete: ()=> img.destroy() }); }
        }
      }
    }
    const seen = new Set<string>();
    for(const p of players){
      if(p.id === this.selfId){ continue; }
      seen.add(p.id);
      let spr = this.remotes.get(p.id);
      if(!spr){
        spr = this.add.image(p.x, p.y, 'player');
        spr.setDepth(10).setAlpha(0.6);
        this.remotes.set(p.id, spr);
      }
      spr.setPosition(p.x, p.y);
      spr.setTint(p.branch==='A' ? 0x29d3c6 : 0x9b59ff);
      spr.setScale(0.9);
    }
    // Remove any not in snapshot
    for(const [id, sprite] of this.remotes){ if(!seen.has(id)){ sprite.destroy(); this.remotes.delete(id); } }
  }

  private enemiesMap: Map<string, Phaser.GameObjects.Image | Phaser.Physics.Arcade.Sprite> = new Map();
  private enemyCountText?: Phaser.GameObjects.Text;
  private updateEnemyBehaviorsPending = false;

  // Helper: face/animate a PixelLab enemy towards a target point.
  private faceAndAnimatePix(sprite: Phaser.Physics.Arcade.Sprite, targetX:number, targetY:number){
    const dx = targetX - sprite.x; const dy = targetY - sprite.y;
    const a = Math.atan2(-dy, dx);
    const dirs = ['east','north-east','north','north-west','west','south-west','south','south-east'] as const;
    const idx = (Math.round(a / (Math.PI/4)) + 8) % 8; const dir = dirs[idx];
    const base8: string | undefined = (sprite as any).getData?.('gen8base');
    if(!base8) return;
    const animKey = `${base8}-walk-${dir}`;
    if(this.anims.exists(animKey)){
      if(sprite.anims.currentAnim?.key !== animKey){ sprite.play(animKey, true); }
      return;
    }
    // Fallbacks: try mirrored west/east if specific diagonal missing
    const mirrorDir = (dir==='west') ? 'east' : (dir==='south-west' ? 'south-east' : (dir==='north-west' ? 'north-east' : undefined));
    if(mirrorDir){
      const mk = `${base8}-walk-${mirrorDir}`;
      if(this.anims.exists(mk)){
        if(sprite.anims.currentAnim?.key !== mk){ sprite.play(mk, true); }
        sprite.setFlipX(dir.indexOf('west')>=0);
        return;
      }
    }
    // Final fallback: static frame if no animation available
    const frameKey = this.textures.exists(`${base8}-walk-${dir}-0`) ? `${base8}-walk-${dir}-0` : `${base8}-walk-east-0`;
    if(sprite.texture?.key !== frameKey){ sprite.setTexture(frameKey); }
  }
  private pickAvailablePixEnemy(): string | null {
    const candidates = ['skeleton_knight','skeleton_archer','orc_brute','empire_knight','empire_knight_v2','empire_paladin_tower','clockwork_juggernaut'];
    for(const name of candidates){ if(this.textures.exists(`pix_${name}-walk-east-0`)) return name; }
    const winList = ((window as any).__enemyPixKeys || []) as string[];
    for(const k of winList){ const n=k.replace(/^pix_/,''); if(this.textures.exists(`pix_${n}-walk-east-0`)) return n; }
    return null;
  }
  private renderEnemies(enemies: NetEnemy[]){
    const seen = new Set<string>();
    // include local enemies in seen so they are not deleted by snapshot cleanup
    for(const id of this.localEnemyIds){ seen.add(id); }
    for(const e of enemies){
      seen.add(e.id);
      let spr = this.enemiesMap.get(e.id) as Phaser.Physics.Arcade.Sprite | Phaser.GameObjects.Image | undefined;
      if(!spr){
        if(e.id==='boss'){
          spr = this.physics.add.sprite(e.x, e.y, 'boss-walk-south-0');
          (spr as Phaser.Physics.Arcade.Sprite).play('boss-walk-south');
          spr.setDepth(6).setScale(1.0);
        } else {
          const pick = this.pickAvailablePixEnemy();
          if(pick){
            const base = `pix_${pick}`;
            const dirOrder = ['east','south','west','north','south-east','south-west','north-east','north-west'];
            let firstKey = `${base}-walk-east-0`;
            for(const d of dirOrder){ const k = `${base}-walk-${d}-0`; if(this.textures.exists(k)){ firstKey = k; break; } }
            if(!this.textures.exists(firstKey)){
              try{ console.warn('Enemy texture missing at spawn, expected:', firstKey); }catch{}
            }
            const s = this.physics.add.sprite(e.x, e.y, firstKey);
            const tryAnim = ()=>{
              let animKey = `${base}-walk-east`;
              for(const d of dirOrder){ const a = `${base}-walk-${d}`; if(this.anims.exists(a)){ animKey = a; break; } }
              if(this.anims.exists(animKey)){ s.play(animKey, true); } else { this.time.delayedCall(120, tryAnim); }
            };
            tryAnim();
            (s as any).setData?.('gen8base', base);
            const etype = (pick.indexOf('paladin')>=0) ? 'paladin' : (pick.indexOf('knight')>=0 ? 'knight' : (pick.indexOf('clockwork_juggernaut')>=0 ? 'juggernaut' : (pick.indexOf('orc_brute')>=0 ? 'brute' : (pick.indexOf('ranged_cultist')>=0 ? 'ranged' : pick))));
            (s as any).setData?.('etype', etype);
            // visual differentiation per type
            if(etype==='paladin'){ s.setScale(1.05); }
            else if(etype==='knight'){ s.setScale(1.0); }
            else if(etype==='juggernaut'){ s.setScale(1.1); }
            else { s.setScale(1.0); }
            // simple attack cooldown state
            (s as any).setData?.('nextAttackAt', 0);
            s.setDepth(5); spr = s;
          } else {
            // No known pix enemy textures found; use a visible fallback sprite to avoid green cubes
            const key = 'fallback_enemy_circle';
            if(!this.textures.exists(key)){
              const size = 24; const tex:any = this.textures.createCanvas(key, size, size);
              const ctx = tex.getContext(); ctx.clearRect(0,0,size,size); ctx.fillStyle = '#5de6ff'; ctx.beginPath(); ctx.arc(size/2, size/2, size/2-2, 0, Math.PI*2); ctx.fill(); ctx.strokeStyle = '#2a9dff'; ctx.lineWidth = 2; ctx.stroke(); tex.refresh();
            }
            const s = this.physics.add.sprite(e.x, e.y, key);
            (s as any).setData?.('species', 'fallback');
            s.setDepth(5).setScale(1.0); spr = s;
            try{ console.warn('Spawned fallback enemy sprite because no pix enemy was available'); }catch{}
          }
        }
        (spr as any).setImmovable?.(false);
        this.enemyGroup.add(spr as any);
        this.enemiesMap.set(e.id, spr);
      }
      (spr as any).setPosition(e.x, e.y);
      // Store branch on sprite for hit filtering
      (spr as any).setData?.('branch', e.branch);
      if(e.entangledId){ (spr as any).setData?.('entangledId', e.entangledId); }
      const body = ((spr as any).body as Phaser.Physics.Arcade.StaticBody|Phaser.Physics.Arcade.Body|undefined);
      if(body && (body as any).updateFromGameObject){ (body as any).updateFromGameObject(spr as any); }
      // Directional facing: choose closest dir and play corresponding walk anim
      if(e.id!=='boss'){
        const s = spr as Phaser.Physics.Arcade.Sprite;
        const dx = (this.player.x - s.x); const dy = (this.player.y - s.y);
        const a = Math.atan2(-dy, dx);
        const dirs8 = ['east','north-east','north','north-west','west','south-west','south','south-east'];
        const idx8 = (Math.round(a / (Math.PI/4)) + 8) % 8;
        const dir = dirs8[idx8];
        const species = (s as any).getData?.('species') || (s.anims.currentAnim?.key?.startsWith('enemygen_') ? 'gen' : 'nullpolyp');
        let base8 = (s as any).getData?.('gen8base');
        // Opportunistic upgrade: if a placeholder has gen8 available now, switch to it
        if(!base8 && (s as any).getData?.('upgradeToGen8')){
          const target = (s as any).getData('upgradeToGen8');
          if(this.textures.exists(`${target}-walk-${dir}-0`)){
            s.setTexture(`${target}-walk-${dir}-0`);
            const startAnim = `${target}-walk-${dir}`;
            if(this.anims.exists(startAnim)) s.play(startAnim, true);
            (s as any).setData?.('gen8base', target);
            (s as any).setData?.('upgradeToGen8', undefined);
            base8 = target;
          }
        }
        if(base8){
          // Special-case: skeleton_archer only has south/south-west/west frames in repo; use flip for east
          const base = (s as any).getData?.('gen8base');
          if(base==='pix_skeleton_archer'){
            const map4: Record<string,string> = { 'south':'south', 'south-west':'south-west', 'west':'west', 'south-east':'south', 'east':'west', 'north':'south', 'north-east':'south', 'north-west':'south-west' };
            const useDir = map4[dir] || 'south';
            const animKey = `${base}-walk-${useDir}`;
            if(this.anims.exists(animKey)){
              if(s.anims.currentAnim?.key !== animKey){ s.play(animKey, true); }
              s.setFlipX(dir==='east' || dir==='south-east');
            }
          } else {
            this.faceAndAnimatePix(s, this.player.x, this.player.y);
          }
        } else if(species==='gen'){
          const baseKey = (s.anims.currentAnim?.key && s.anims.currentAnim.key.startsWith('enemygen_')) ? s.anims.currentAnim.key : '';
          if(baseKey){ if(s.anims.currentAnim?.key !== baseKey){ s.play(baseKey, true); } }
          // Rotate to face the player
          const ang = (()=>{
            switch(dir){
              case 'east': return 0; case 'north-east': return -Math.PI/4; case 'north': return -Math.PI/2; case 'north-west': return -3*Math.PI/4;
              case 'west': return Math.PI; case 'south-west': return 3*Math.PI/4; case 'south': return Math.PI/2; case 'south-east': return Math.PI/4;
            }
          })();
          s.setRotation(ang||0);
        } else {
          const key = `${species==='wolf' ? 'pointerwolf' : 'nullpolyp'}-walk-${dir}`;
          if(s.anims.currentAnim?.key !== key){ s.play(key, true); }
        }
      } else {
        const s = spr as Phaser.Physics.Arcade.Sprite;
        const dx = (this.player.x - s.x); const dy = (this.player.y - s.y);
        const a = Math.atan2(-dy, dx);
        const dirs = ['east','north-east','north','north-west','west','south-west','south','south-east'];
        const idx = (Math.round(a / (Math.PI/4)) + 8) % 8;
        const dir = dirs[idx];
        const key = `boss-walk-${dir}`;
        if(s.anims.currentAnim?.key !== key && this.anims.exists(key)){ s.play(key, true); }
      }
    }
    for(const [id, sprite] of this.enemiesMap){ if(!seen.has(id)){ sprite.destroy(); this.enemyGroup.remove(sprite, true, true); this.enemiesMap.delete(id);
      // Temporal Refund when an enemy we recently hit vanishes
      const now = this.time.now||0; const recent = (now - (this.lastSelfHits.get((sprite as any).name||'')||0)) < 1200;
      if(recent && (this.patches as any).getKillRefundMs){ const delta = (this.patches as any).getKillRefundMs(); if(delta>0){ this.phaseCooldownUntil = Math.max(0, (this.phaseCooldownUntil||0) - delta); } }
      // Unlocks: track kills and boss defeat
      if(id === 'boss'){
        const newly = notifyBossDefeated(this.unlocks);
        if(newly.length>0){ newly.forEach(n=> this.showUnlockToast('Unlocked: '+n)); this.onUnlocksChanged(); }
        this.tryAwardBlueprint(true);
      } else if(recent){
        const newly = notifyKill(this.unlocks, 1);
        if(newly.length>0){ newly.forEach(n=> this.showUnlockToast('Unlocked: '+n)); this.onUnlocksChanged(); }
        const entId = (sprite as any).getData?.('entangledId');
        if(entId){
          const last = this.lastEntangledKill.get(entId)||0;
          if((now - last) < 1500){ this.tryAwardBlueprint(true); this.lastEntangledKill.delete(entId); }
          else { this.lastEntangledKill.set(entId, now); this.tryAwardBlueprint(false); }
        }
      }
    } }
    const totalEnemies = enemies.length + this.localEnemyIds.size;
    if(!this.enemyCountText){ this.enemyCountText = this.add.text(GAME_WIDTH-8, 6, '', { fontFamily:'monospace', fontSize:'12px', color:'#9cf' }).setOrigin(1,0).setDepth(200); }
    this.enemyCountText.setText('enemies: '+totalEnemies);
    const domE=document.getElementById('hud-enemies'); if(domE) domE.textContent=String(totalEnemies);
  }

  update(time:number){
    const fusionMul = (this.fusionActive && time < this.fusionUntil) ? 1.5 : 1.0;
    const speedMul = this.patches.getPlayerSpeedMultiplier();
    if(this.fusionActive && time >= this.fusionUntil){ this.fusionActive = false; }
    const speed = 180 * fusionMul * speedMul; let vx=0, vy=0; if(this.cursors.left?.isDown) vx-=1; if(this.cursors.right?.isDown) vx+=1; if(this.cursors.up?.isDown) vy-=1; if(this.cursors.down?.isDown) vy+=1;
    const len=Math.hypot(vx,vy)||1; this.player.setVelocity((vx/len)*speed,(vy/len)*speed);
    // Directional animation
    try{
      const spr = this.player as Phaser.Physics.Arcade.Sprite;
      const moving = Math.abs(vx) + Math.abs(vy) > 0.01;
      if(moving){
        const angle = Math.atan2(-vy, vx); // -PI..PI, 0 is east; invert Y to map screen coords to math coords
        // Map to 8 dirs: E, NE, N, NW, W, SW, S, SE
        const dirs = ['east','north-east','north','north-west','west','south-west','south','south-east'];
        const idx = (Math.round(angle / (Math.PI/4)) + 8) % 8;
        const dir = dirs[idx];
        const key = `player-walk-${dir}`;
        if(spr.anims.currentAnim?.key !== key){ spr.play(key, true); }
      } else {
        spr.stop();
      }
    }catch{}
    if(time - this.lastInputSend > 50){ this.lastInputSend = time; this.socket.emit('input',{ moveX:vx/len, moveY:vy/len }); }
    // Disable world freeze to avoid unintended pauses during dev
    // const freeze = this.patches.getWorldFreezeMs(time);
    // if(freeze>0){ this.scene.pause(); setTimeout(()=> this.scene.resume(), freeze); }

    // Update HUD DOM timers
    const cdLeft = Math.max(0, this.phaseCooldownUntil - (this.time.now||0));
    (window as any).__pbPhaseLeft = cdLeft;
    const cdDom = document.getElementById('hud-phase'); if(cdDom) cdDom.textContent = cdLeft>0 ? (Math.ceil(cdLeft/100)/10).toFixed(1)+'s' : 'ready';
    const mergeDom = document.getElementById('hud-merge'); if(mergeDom){
      if(this.mergeEndsAt && this.mergeOverlay?.visible){ const left = Math.max(0, this.mergeEndsAt - (this.time.now||0)); mergeDom.textContent = (left/1000).toFixed(1)+'s'; }
      else { mergeDom.textContent = '-'; }
    }
    if(this.mergeEndsAt && this.mergeOverlay?.visible && this.mergeTimerText){ const left = Math.max(0, this.mergeEndsAt - (this.time.now||0)); this.mergeTimerText.setText('MERGE ' + (left/1000).toFixed(1)+'s'); }

    // Council Pads ritual logic (solo-scaled)
    if(this.councilActive && this.padA){
      const onA = this.physics.overlap(this.player, this.padA);
      const onB = this.padB ? this.physics.overlap(this.player, this.padB) : false;
      // Solo: standing on either pad advances; if both, a bit faster
      let rate = onA && onB ? 1.8 : (onA || onB ? 1.0 : -0.6);
      if((this.patches as any).hasPatch?.('council_parallel')) rate *= 1.25;
      this.councilProgress = Phaser.Math.Clamp(this.councilProgress + rate, 0, 400);
      if(!this.councilText){ this.councilText = this.add.text(10,10,'Council: 0%',{ fontFamily:'monospace', fontSize:'14px', color:'#fff' }); }
      this.councilText.setText('Council: ' + Math.floor((this.councilProgress/400)*100) + '%');
      if(this.councilProgress>=400){ this.resolveCouncilStub(); }
    }
    // Per-enemy local behaviors
    this.updateEnemyBehaviors(time);
    // Spawn Director
    try{ this.runSpawnDirector(time); }catch{}
    // Stream chunks as camera moves (throttled to reduce load)
    const now = this.time.now||time; (this as any)._lastChunkAt = (this as any)._lastChunkAt||0;
    if(now - (this as any)._lastChunkAt > 250){ (this as any)._lastChunkAt = now; try{ this.ensureChunksAroundCamera(); }catch{} }
  }

  private updateEnemyBehaviors(time:number){
    const player = this.player as Phaser.Physics.Arcade.Sprite;
    for(const [, sprite] of this.enemiesMap){
      const s = sprite as Phaser.Physics.Arcade.Sprite;
      const etype = (s as any).getData?.('etype');
      // Always advance toward the player
      const speed = 60 + (etype==='juggernaut'? 30 : etype==='paladin'? 40 : 50);
      const dx = player.x - s.x; const dy = player.y - s.y; const len = Math.hypot(dx,dy)||1;
      const vx = (dx/len) * speed; const vy = (dy/len) * speed;
      if((s.body as any)?.velocity){ (s.body as any).velocity.x = vx; (s.body as any).velocity.y = vy; }

      // Face-and-animate toward player for local enemies (and as a backup for remotes)
      try{ this.faceAndAnimatePix(s, player.x, player.y); }catch{}
      // Boss behavior handling
      if((s as any).getData?.('boss')===true){
        const btype = (s as any).getData?.('bossType');
        if(btype==='mortar'){
          const next = (s as any).getData?.('nextCast')||0; if(time>=next){ (s as any).setData?.('nextCast', time+1400); this.castMortarVolley(s.x, s.y, player.x, player.y); }
        } else if(btype==='assassin'){
          const next = (s as any).getData?.('nextBlink')||0; if(time>=next){ (s as any).setData?.('nextBlink', time+1100); this.assassinBlinkStrike(s, player); }
        } else if(btype==='railgun'){
          const next = (s as any).getData?.('nextShot')||0; if(time>=next){ (s as any).setData?.('nextShot', time+1600); this.railgunTelegraphAndFire(s, player); }
        }
        continue;
      }
      if(!etype) continue;
      const nextAt = (s as any).getData?.('nextAttackAt') || 0;
      if(time < nextAt) continue;
      const dist = Math.hypot(dx, dy);
      if(etype==='knight'){
        if(dist < 68){
          (s as any).setData?.('nextAttackAt', time + 900);
          const ang = Math.atan2(dy, dx);
          this.spawnSlashArc(s.x, s.y, ang, 0x9bb8ff);
          const dash = 80; s.x += Math.cos(ang)*14; s.y += Math.sin(ang)*14;
          if(this.cameras?.main) this.cameras.main.shake(80, 0.002);
        }
      } else if(etype==='paladin'){
        if(dist < 84){
          (s as any).setData?.('nextAttackAt', time + 1300);
          this.spawnShockwave(s.x, s.y, 0xffe08a);
          const push = 30; const ang = Math.atan2(dy, dx);
          player.x += Math.cos(ang)*-push*0.2; player.y += Math.sin(ang)*-push*0.2;
        }
      } else if(etype==='juggernaut'){
        if(dist < 100){
          (s as any).setData?.('nextAttackAt', time + 1600);
          this.spawnShockwave(s.x, s.y, 0xffb000);
          // tiny screen shake to sell weight
          if(this.cameras?.main) this.cameras.main.shake(120, 0.004);
        }
      } else if(etype==='brute'){
        if(dist < 72){
          (s as any).setData?.('nextAttackAt', time + 1000);
          // Procedural lunge using existing walk frames
          const ang = Math.atan2(dy, dx);
          const ux = Math.cos(ang), uy = Math.sin(ang);
          const backX = s.x - ux*8, backY = s.y - uy*8;
          const strikeX = s.x + ux*56, strikeY = s.y + uy*56;
          const dirs8 = ['east','north-east','north','north-west','west','south-west','south','south-east'];
          const idx8 = (Math.round(Math.atan2(-dy, dx) / (Math.PI/4)) + 8) % 8; const dir = dirs8[idx8];
          const base8 = (s as any).getData?.('gen8base');
          const walkKey = base8 ? `${base8}-walk-${dir}` : undefined;
          if(walkKey && this.anims.exists(walkKey)) s.play(walkKey, true);
          this.tweens.add({ targets: s, x: backX, y: backY, duration: 100, ease: 'Sine.easeOut', onComplete: ()=>{
            if(walkKey && this.anims.exists(walkKey)) s.anims.timeScale = 1.8;
            const hit = this.add.rectangle(s.x+ux*10, s.y+uy*10, 28, 28, 0x00ff00, 0).setOrigin(0.5).setDepth(50);
            this.physics.add.existing(hit as any, false);
            const hb = (hit as any).body as Phaser.Physics.Arcade.Body; hb.enable = true;
            const ov = this.physics.add.overlap(hit as any, this.player, ()=>{ this.doHitStop(50); this.doShake(); });
            this.tweens.add({ targets: s, x: strikeX, y: strikeY, duration: 140, ease: 'Quad.easeIn', onComplete: ()=>{
              // impact VFX
              this.spawnShockwave(s.x, s.y, 0x9bff8a);
              hb.enable = false; ov.destroy(); (hit as any).destroy?.(); s.anims.timeScale = 1.0;
            }});
          }});
        }
      } else if(etype==='ranged'){
        // maintain spacing; fire bursts
        const desired = 220; const ang = Math.atan2(dy, dx); const d = Math.hypot(dx,dy);
        if(d < desired*0.8){ // back off slightly
          const ux = Math.cos(ang), uy = Math.sin(ang); s.x -= ux*12; s.y -= uy*12;
        }
        const next = (s as any).getData?.('nextShotAt')||0;
        if(time >= next){
          (s as any).setData?.('nextShotAt', time + 900);
          this.enemyFireBullet(s.x, s.y, player.x, player.y, 260);
        }
      }
      }
    }

  private runSpawnDirector(time:number){
    if(this.directorStartMs===0) this.directorStartMs = time;
    const elapsed = (time - this.directorStartMs) / 1000; // seconds
    const difficulty = Phaser.Math.Clamp(elapsed / (12*60), 0, 1); // ramps to 12 min
    const targetCount = Math.floor(6 + difficulty*70);

    // Roguelike progression stages
    const stage = this.getSpawnStage(elapsed);
    const table = this.getStageSpawnTable(stage);

    // Wave cadence
    const waveEveryMs = 4000 - Math.floor(difficulty*1800); // faster over time
    if(time - this.lastWaveAt >= waveEveryMs){
      this.lastWaveAt = time; this.waveIndex++;
      const eliteChance = Math.min(0.22, 0.04 + stage*0.04 + difficulty*0.08);
      const num = 2 + Math.floor(Math.random()*3) + Math.floor(this.waveIndex/6);
      for(let i=0;i<num;i++){
        const species = this.rollFromTable(table);
        const elite = Math.random() < eliteChance;
        this.spawnLocalEnemyNearPlayer(time, species, elite, stage, difficulty);
      }
    }

    // Maintain target population
    const current = this.localEnemyIds.size + [...this.enemiesMap.keys()].filter(k=>!this.localEnemyIds.has(k)).length;
    if(current < targetCount){
      const deficit = Math.min(6, targetCount - current);
      for(let i=0;i<deficit;i++){
        const species = this.rollFromTable(table);
        this.spawnLocalEnemyNearPlayer(time, species, false, stage, difficulty);
      }
    }

    // Boss cadence every ~2.5 minutes scaled earlier with difficulty
    const bossPeriod = 150 - difficulty*60; // 150s -> 90s
    if(elapsed > (this.bossScheduleIdx+1)*bossPeriod){
      this.bossScheduleIdx++;
      this.spawnLocalBossNearPlayer(time);
    }
    // Structure cadence: spawn a shrine every 3 waves
    if(this.waveIndex>0 && this.waveIndex % 3 === 0){
      const last = (this as any).lastShrineWave||0; if(last !== this.waveIndex){
        (this as any).lastShrineWave = this.waveIndex;
        this.time.delayedCall(600, ()=> this.spawnWarpShrineNearPlayer());
      }
    }
  }

  private getSpawnStage(elapsedSeconds:number): number{
    if(elapsedSeconds < 60) return 0; // skeletons only
    if(elapsedSeconds < 180) return 1; // add archers
    if(elapsedSeconds < 360) return 2; // add empire_knight_v2
    if(elapsedSeconds < 540) return 3; // add paladin tower
    return 4; // add juggernaut
  }

  // --- Structures ---
  private onStructureOverlap(st: Phaser.GameObjects.GameObject){
    const type = (st as any).getData?.('stype'); if(!type) return;
    if((st as any).getData?.('used')) return;
    if(type==='warp_shrine'){
      (st as any).setData?.('used', true);
      this.beginFusionLocal(8000);
      // simple VFX
      const g = this.add.graphics({ x: (st as any).x, y: (st as any).y }).setDepth(26);
      g.lineStyle(2, 0x9b59ff, 1); g.strokeCircle(0,0, 18);
      this.tweens.add({ targets:g, alpha:0, scaleX:1.8, scaleY:1.8, duration:500, onComplete:()=> g.destroy() });
      this.time.delayedCall(50, ()=> (st as any).destroy?.());
    } else if(type==='hazard_obelisk'){
      if((st as any).getData?.('used')) return; (st as any).setData?.('used', true);
      // stop idle FX if present
      const ev = (st as any).getData?.('idleEvent'); if(ev){ try{ ev.remove(false); }catch{} }
      this.triggerObeliskZap((st as any).x, (st as any).y);
      this.time.delayedCall(50, ()=> (st as any).destroy?.());
    } else if(type==='mystery_cube'){
      if((st as any).getData?.('used')) return; (st as any).setData?.('used', true);
      this.triggerCubeOverdrive(12000);
      const puff = this.add.graphics({ x:(st as any).x, y:(st as any).y }).setDepth(26); puff.fillStyle(0x78e6ff, 0.8); puff.fillCircle(0,0, 10); this.tweens.add({ targets:puff, alpha:0, scaleX:2, scaleY:2, duration:420, onComplete:()=>puff.destroy() });
      this.time.delayedCall(50, ()=> (st as any).destroy?.());
    }
  }

  private onStructureProximity(st: Phaser.GameObjects.GameObject){
    // show hint near player when within 48px and handle E press to activate
    const dx = (st as any).x - this.player.x; const dy = (st as any).y - this.player.y;
    const dist = Math.hypot(dx, dy);
    const canUse = dist < 56 && !(st as any).getData?.('used');
    if(this.structInteractHint){
      this.structInteractHint.setVisible(canUse);
      if(canUse){ this.structInteractHint.setPosition(this.cameras.main.width/2 - 36, this.cameras.main.height/2 + 28); }
    }
    if(canUse){
      const e = this.input.keyboard?.addKey('E');
      if(Phaser.Input.Keyboard.JustDown(e!)){
        this.onStructureOverlap(st);
      }
    }
  }

  private triggerObeliskZap(x:number, y:number){
    // Find nearest enemies and chain zap between them; deal 2 HP to locals
    const enemies = [...this.enemiesMap.entries()].map(([id,spr])=>({ id, spr: spr as Phaser.Physics.Arcade.Sprite, d: Math.hypot(spr.x-x, spr.y-y) }))
      .filter(o=> o.d < 360).sort((a,b)=> a.d-b.d).slice(0,5);
    if(enemies.length===0) return;
    // Fancy procedural bolts between points
    let last = { x, y };
    for(const e of enemies){ this.spawnLightningBolt(last.x, last.y, e.spr.x, e.spr.y); last = { x: e.spr.x, y: e.spr.y }; }
    // Apply damage to locals
    for(const e of enemies){ const isLocal = (e.spr as any).getData?.('local')===true; if(isLocal){ const hp=((e.spr as any).getData?.('hp')||1)-2; (e.spr as any).setData?.('hp', hp); if(hp<=0){ this.killLocalEnemy(e.id, e.spr as any); } } }
    this.doHitStop(40); this.doShake();
  }

  // Procedural lightning with jittered segments, glow, flicker, and small forks
  private spawnLightningBolt(x1:number, y1:number, x2:number, y2:number){
    const depth = 45;
    const bolts: Phaser.GameObjects.Graphics[] = [];
    const drawBolt = (sx:number, sy:number, ex:number, ey:number, thickness:number, alpha:number)=>{
      const g = this.add.graphics().setDepth(depth);
      g.lineStyle(thickness, 0x9fd0ff, alpha);
      const segments = 14; const points: Array<{x:number;y:number}> = [];
      for(let i=0;i<=segments;i++){
        const t = i/segments; const ix = sx + (ex-sx)*t; const iy = sy + (ey-sy)*t;
        const nx = -(ey-sy); const ny = (ex-sx); const len = Math.hypot(nx,ny)||1; const jitterMag = 6 * (1 - Math.abs(0.5 - t)*1.6);
        const jitter = (Math.random()*2-1) * jitterMag; const jx = ix + (nx/len)*jitter; const jy = iy + (ny/len)*jitter;
        points.push({ x: jx, y: jy });
      }
      g.beginPath(); g.moveTo(points[0].x, points[0].y); for(let i=1;i<points.length;i++){ g.lineTo(points[i].x, points[i].y); } g.strokePath();
      bolts.push(g);
      // occasional fork
      if(thickness>2 && Math.random()<0.6){
        const idx = 4 + Math.floor(Math.random()*(segments-8));
        const p = points[idx]; const forkLen = 40 + Math.random()*40; const ang = Math.atan2(ey-sy, ex-sx) + (Math.random()*0.8 - 0.4);
        const fx = p.x + Math.cos(ang)*forkLen; const fy = p.y + Math.sin(ang)*forkLen;
        drawBolt(p.x, p.y, fx, fy, Math.max(1, thickness-1), alpha*0.8);
      }
    };
    // core and glow layers
    drawBolt(x1,y1,x2,y2, 4, 0.95);
    drawBolt(x1,y1,x2,y2, 2, 1.0);
    const glow = this.add.graphics().setDepth(depth-1); glow.lineStyle(8, 0x6fb6ff, 0.25); glow.beginPath(); glow.moveTo(x1,y1); glow.lineTo(x2,y2); glow.strokePath();
    // flicker out
    const all = [...bolts, glow];
    this.time.delayedCall(50, ()=> all.forEach(g=> g.setAlpha(0.8)));
    this.time.delayedCall(100, ()=> all.forEach(g=> g.setAlpha(0.55)));
    this.time.delayedCall(160, ()=> all.forEach(g=> g.setAlpha(0.25)));
    this.time.delayedCall(220, ()=> all.forEach(g=> g.destroy()));
  }

  private triggerCubeOverdrive(ms:number){
    // Temporarily buff fire rate and add an extra spread bullet for primaries
    const until = (this.time.now||0) + ms; const baseGet = this.patches.getFireInterval.bind(this.patches);
    const boosted = (base:number, merged:boolean)=> Math.max(120, baseGet(base, merged) * 0.65);
    (this.patches as any).getFireInterval = boosted;
    // Visual timer ring near player
    const ring = this.add.graphics().setDepth(26); let rad=18; const timer = this.time.addEvent({ delay: 80, loop: true, callback: ()=>{ ring.clear(); ring.lineStyle(2, 0x78e6ff, 0.9); ring.strokeCircle(this.player.x, this.player.y-28, rad); rad = 18 + Math.sin((this.time.now||0)/120)*3; if((this.time.now||0)>=until){ timer.remove(false); ring.destroy(); (this.patches as any).getFireInterval = baseGet; } } });
  }

  private spawnWarpShrineNearPlayer(){
    const angle = Math.random()*Math.PI*2; const dist = 180 + Math.random()*60;
    const x = this.player.x + Math.cos(angle)*dist; const y = this.player.y + Math.sin(angle)*dist;
    const key = 'struct_green_fountain-0'; // first frame, will play anim
    let s:any;
    if(this.textures.exists(key)){
      s = this.structureGroup.get(x, y, key) as Phaser.Physics.Arcade.Sprite;
    } else {
      // Physics-friendly placeholder so overlap and E-to-interact work
      const phKey = 'struct_placeholder_warp';
      if(!this.textures.exists(phKey)){
        const size = 28; const cvs:any = this.textures.createCanvas(phKey, size, size); const ctx = cvs.getContext(); ctx.clearRect(0,0,size,size); ctx.fillStyle = '#2be37f'; ctx.beginPath(); ctx.arc(size/2,size/2, size/2-2, 0, Math.PI*2); ctx.fill(); ctx.strokeStyle = '#95ffd2'; ctx.lineWidth = 2; ctx.stroke(); cvs.refresh();
      }
      s = this.structureGroup.get(x, y, phKey) as Phaser.Physics.Arcade.Sprite;
    }
    if(!s) return; s.setActive(true).setVisible(true); s.setOrigin?.(0.5, 1); s.refreshBody?.(); s.setDepth?.(4); s.setAlpha?.(0.98);
    s.setData?.('stype','warp_shrine');
    const anim = 'struct_green_fountain-idle'; this.applyStructureAnimAndScale(s as Phaser.Physics.Arcade.Sprite, 'warp_shrine', anim, key);
  }

  private spawnRandomStructuresForRun(){
    // Place one of each structure using container + trimmed static hitbox
    const picks = [
      { keyPrefix: 'struct_arcane_cube', dx: 220, dy: 60, targetH: 96, meta:{ offsetY:-6, collisionOffset:{x:0,y:-8} } },
      { keyPrefix: 'struct_obelisk', dx: 300, dy: 40, targetH: 160, meta:{ offsetY:-6, collisionOffset:{x:0,y:-8} } },
      { keyPrefix: 'struct_green_fountain', dx: 260, dy: 100, targetH: 128, meta:{ offsetY:-6, collisionOffset:{x:0,y:-8} } },
    ];
    for(const p of picks){
      const x = this.player.x + p.dx; const y = this.player.y + p.dy;
      const cont = this.createStructureAt(p.keyPrefix, x, y, p.targetH, p.meta as any);
      (cont.list[0] as Phaser.GameObjects.Sprite).setAlpha(0.99);
    }
  }

  private startObeliskIdleFX(s:any){
    // periodic small arcs around the obelisk to feel energized
    const ev = this.time.addEvent({ delay: 420, loop: true, callback: ()=>{
      if(!s.active || (s.getData?.('used')===true)) return;
      const bursts = 1 + Math.floor(Math.random()*2);
      for(let i=0;i<bursts;i++){
        const ang = Math.random()*Math.PI*2; const len = 24 + Math.random()*22;
        const sx = s.x + Math.cos(ang)*8; const sy = s.y + Math.sin(ang)*8;
        const ex = s.x + Math.cos(ang)*len; const ey = s.y + Math.sin(ang)*len;
        this.spawnLightningBolt(sx, sy, ex, ey);
      }
    }});
    s.setData?.('idleEvent', ev);
  }

  private getStageSpawnTable(stage:number): Array<{id:string; w:number}>{
    // Late stages inherit previous ones
    const pool: string[] = [];
    if(stage>=0) pool.push('skeleton_knight');
    if(stage>=1) pool.push('skeleton_archer');
    if(stage>=2) pool.push('empire_knight_v2','orc_brute','ranged_cultist');
    if(stage>=3) pool.push('empire_paladin_tower');
    if(stage>=4) pool.push('clockwork_juggernaut');
    // weights favor earlier mobs to keep mix
    const weights: Record<string,number> = {
      skeleton_knight: 4,
      skeleton_archer: 3,
      empire_knight_v2: 3,
      orc_brute: 3,
      ranged_cultist: 3,
      empire_paladin_tower: 2,
      clockwork_juggernaut: 1
    };
    return pool.map(id=> ({ id, w: weights[id]||1 }));
  }

  private getCurrentBiomeSlug(): string{
    // approximate from camera chunk; falls back to primary slug
    const cam = this.cameras.main; const midX = cam.worldView.centerX || (cam.scrollX + cam.width/2); const midY = cam.worldView.centerY || (cam.scrollY + cam.height/2);
    const cx = Math.floor((midX) / (this.tileSize*this.tilesPerChunk));
    const cy = Math.floor((midY) / (this.tileSize*this.tilesPerChunk));
    // mirror chunk selection logic from buildChunk
    const chunkToSlugIdx = (ix:number, iy:number)=>{
      const s = 0.18; const fb = (x:number,y:number,oct=3)=>{ let amp=0.5,f=1,sum=0; const h=(xx:number,yy:number)=>{ const n = Math.sin(xx*127.1 + yy*311.7 + this.worldSeed*0.013)*43758.5453; return n - Math.floor(n); }; for(let i=0;i<oct;i++){ sum += amp*h(ix*s*f + this.worldSeed*0.001, iy*s*f - this.worldSeed*0.002); f*=2; amp*=0.5; } return sum; };
      const v = fb(ix,iy,3); const idx = Math.max(0, Math.min(this.activeSlugs.length-1, Math.floor(v * this.activeSlugs.length))); return idx; };
    const idx = this.activeSlugs.length>0 ? chunkToSlugIdx(cx,cy) : 0;
    return this.activeSlugs[idx] || this.primaryTilesetSlug || 'default';
  }

  private getBiomeSpawnTable(slug:string): Array<{id:string; w:number}>{
    // Simple themed tables; can expand later
    const base: Record<string, Array<{id:string; w:number}>> = {
      metal: [ {id:'clockwork_juggernaut', w:2}, {id:'empire_knight_v2', w:3}, {id:'empire_paladin_tower', w:1} ],
      dirt:  [ {id:'skeleton_knight', w:3}, {id:'skeleton_archer', w:3} ],
      default: [ {id:'skeleton_knight', w:3}, {id:'skeleton_archer', w:3}, {id:'empire_knight_v2', w:2} ]
    };
    // heuristic: map slug keyword to table
    const key = slug.includes('metal')||slug.includes('tech') ? 'metal' : slug.includes('dirt')||slug.includes('soil') ? 'dirt' : 'default';
    return base[key];
  }

  private rollFromTable(table: Array<{id:string; w:number}>): string{
    const total = table.reduce((a,b)=> a+b.w, 0);
    let roll = Math.random()*total;
    for(const row of table){ if((roll-=row.w) <= 0) return row.id; }
    return table[0].id;
  }

  private enemyFireBullet(fromX:number, fromY:number, toX:number, toY:number, speed:number){
    if(!this.enemyBullets) return;
    const key = 'enemy_proj_dart';
    if(!this.textures.exists(key)){
      const size = 8; const tex:any = this.textures.createCanvas(key, size, size);
      const ctx = tex.getContext(); ctx.clearRect(0,0,size,size);
      ctx.fillStyle = '#ff5555'; ctx.beginPath(); ctx.moveTo(size-1, size/2); ctx.lineTo(1,1); ctx.lineTo(1,size-1); ctx.closePath(); ctx.fill(); tex.refresh();
    }
    const b:any = this.enemyBullets.get(fromX, fromY, key);
    if(!b) return; b.setActive(true).setVisible(true).setDepth(5).setScale(1.0);
    const ang = Phaser.Math.Angle.Between(fromX, fromY, toX, toY);
    this.physics.velocityFromRotation(ang, speed, b.body.velocity);
    b.setRotation(ang);
    this.time.delayedCall(1500, ()=> b.destroy());
  }

  private spawnLocalEnemyNearPlayer(time:number, forcedSpecies?: string | null, elite:boolean=false, stage:number=0, difficulty:number=0){
    const pick = forcedSpecies || this.pickAvailablePixEnemy() || 'skeleton_knight';
    const base = `pix_${pick}`;
    const angle = Math.random()*Math.PI*2; const dist = 240 + Math.random()*180;
    const x = this.player.x + Math.cos(angle)*dist; const y = this.player.y + Math.sin(angle)*dist;
    const id = `L${++this.localIdSeq}`;
    const s = this.physics.add.sprite(x, y, `${base}-walk-east-0`);
    const startAnim = `${base}-walk-east`; if(this.anims.exists(startAnim)) s.play(startAnim, true);
    s.setDepth(5).setScale(elite ? 1.12 : 1.0);
    (s as any).setData?.('local', true);
    (s as any).setData?.('gen8base', base);
    // scale HP by stage/difficulty
    const baseHp = pick.includes('juggernaut') ? 8 : pick.includes('paladin') ? 6 : pick.includes('empire_knight') ? 5 : 3;
    const hp = Math.round(baseHp * (1 + stage*0.15 + difficulty*0.6)) + (elite ? 2 : 0);
    (s as any).setData?.('hp', hp);
    if(elite){ s.setTint(0xffe08a); (s as any).setData?.('etype', (pick.indexOf('paladin')>=0)?'paladin':(pick.indexOf('knight')>=0?'knight':(pick.indexOf('clockwork_juggernaut')>=0?'juggernaut':pick))); }
    this.enemyGroup.add(s as any);
    this.enemiesMap.set(id, s);
    this.localEnemyIds.add(id);
  }

  private spawnLocalBossNearPlayer(time:number){
    const archetypes = ['mortar_hive','blink_assassin','railgun_sentinel'] as const;
    const pick = archetypes[Math.floor(Math.random()*archetypes.length)];
    if(pick==='mortar_hive') return this.spawnBossMortarHive(time);
    if(pick==='blink_assassin') return this.spawnBossBlinkAssassin(time);
    return this.spawnBossRailgunSentinel(time);
  }

  // --- Boss: Mortar Hive ---
  private spawnBossMortarHive(time:number){
    const angle = Math.random()*Math.PI*2; const dist = 420; const x = this.player.x + Math.cos(angle)*dist; const y = this.player.y + Math.sin(angle)*dist;
    const id = `BM${++this.localIdSeq}`; const s = this.physics.add.sprite(x, y, 'boss-walk-south-0'); if(this.anims.exists('boss-walk-south')) s.play('boss-walk-south', true);
    s.setDepth(7).setScale(1.12).setTint(0xffb36b);
    (s as any).setData?.('local', true); (s as any).setData?.('boss', true); (s as any).setData?.('hp', 45);
    (s as any).setData?.('bossType', 'mortar'); (s as any).setData?.('nextCast', 0);
    this.enemyGroup.add(s as any); this.enemiesMap.set(id, s); this.localEnemyIds.add(id);
    const ring = this.vfxLoaded.has('hive_body') ? this.makeVfxAt('hive_body', x, y, 20) : this.add.graphics({ x, y }).setDepth(20).lineStyle(2, 0xffb36b, 1) as any;
    if((ring as any).strokeCircle){ (ring as any).strokeCircle(0,0,28); this.tweens.add({ targets:ring, alpha:0.9, duration:800, onComplete:()=>{ (ring as any).destroy?.(); } }); }
  }

  // --- Boss: Blink Assassin ---
  private spawnBossBlinkAssassin(time:number){
    const angle = Math.random()*Math.PI*2; const dist = 380; const x = this.player.x + Math.cos(angle)*dist; const y = this.player.y + Math.sin(angle)*dist;
    const id = `BA${++this.localIdSeq}`; const s = this.physics.add.sprite(x, y, 'boss-walk-south-0'); if(this.anims.exists('boss-walk-south')) s.play('boss-walk-south', true);
    s.setDepth(7).setScale(1.05).setTint(0xb38bff);
    (s as any).setData?.('local', true); (s as any).setData?.('boss', true); (s as any).setData?.('hp', 32);
    (s as any).setData?.('bossType', 'assassin'); (s as any).setData?.('nextBlink', 0);
    this.enemyGroup.add(s as any); this.enemiesMap.set(id, s); this.localEnemyIds.add(id);
    const ring = this.add.graphics({ x, y }).setDepth(20); ring.lineStyle(2, 0xb38bff, 1); ring.strokeCircle(0,0, 26); this.tweens.add({ targets:ring, alpha:0, duration:800, onComplete:()=>ring.destroy() });
  }

  // --- Boss: Railgun Sentinel ---
  private spawnBossRailgunSentinel(time:number){
    const angle = Math.random()*Math.PI*2; const dist = 460; const x = this.player.x + Math.cos(angle)*dist; const y = this.player.y + Math.sin(angle)*dist;
    const id = `BR${++this.localIdSeq}`; const s = this.physics.add.sprite(x, y, 'boss-walk-south-0'); if(this.anims.exists('boss-walk-south')) s.play('boss-walk-south', true);
    s.setDepth(7).setScale(1.2).setTint(0x7fd0ff);
    (s as any).setData?.('local', true); (s as any).setData?.('boss', true); (s as any).setData?.('hp', 55);
    (s as any).setData?.('bossType', 'railgun'); (s as any).setData?.('nextShot', 0);
    this.enemyGroup.add(s as any); this.enemiesMap.set(id, s); this.localEnemyIds.add(id);
    const ring = this.add.graphics({ x, y }).setDepth(20); ring.lineStyle(2, 0x7fd0ff, 1); ring.strokeCircle(0,0, 30); this.tweens.add({ targets:ring, alpha:0, duration:800, onComplete:()=>ring.destroy() });
  }

  private killLocalEnemy(id:string, spr: Phaser.GameObjects.GameObject){
    // on-death FX
    const poof = this.add.graphics({ x: (spr as any).x, y: (spr as any).y }).setDepth(18); poof.fillStyle(0xffffff, 0.8); poof.fillCircle(0,0, 8); this.tweens.add({ targets:poof, alpha:0, scaleX:2, scaleY:2, duration:220, onComplete:()=> poof.destroy() });
    ;(spr as any).destroy?.();
    this.enemyGroup.remove(spr as any, true, true);
    this.enemiesMap.delete(id);
    this.localEnemyIds.delete(id);
  }

  private spawnSlashArc(x:number, y:number, angle:number, color:number){
    const g = this.add.graphics({ x, y }).setDepth(30);
    g.fillStyle(color, 0.9);
    const r = 20; const w = Math.PI/6;
    g.beginPath(); g.moveTo(0,0);
    g.arc(0,0, r, angle - w, angle + w, false);
    g.closePath(); g.fillPath();
    this.tweens.add({ targets:g, alpha:0, scaleX:1.5, scaleY:1.5, duration:180, onComplete:()=> g.destroy() });
  }

  private spawnShockwave(x:number, y:number, color:number){
    const ring = this.add.graphics({ x, y }).setDepth(28);
    ring.lineStyle(2, color, 1);
    let rad = 6;
    const t = this.time.addEvent({ delay: 16, repeat: 12, callback: ()=>{
      ring.clear(); ring.lineStyle(2, color, 1); ring.strokeCircle(0,0, rad); rad += 4;
      if(t.getRepeatCount()<=0){ ring.destroy(); }
    }});
  }

  // Boss abilities
  private castMortarVolley(fromX:number, fromY:number, targetX:number, targetY:number){
    const waves = 6; const spread = 120; const dur = 700;
    for(let i=0;i<waves;i++){
      const tx = targetX + (Math.random()*2-1)*spread; const ty = targetY + (Math.random()*2-1)*spread;
      if(this.textures.exists('vfx_mortar_circle')){
        const mark = this.add.image(tx, ty, 'vfx_mortar_circle').setDepth(40).setAlpha(0.8);
        this.tweens.add({ targets: mark, alpha: 0.25, duration: dur });
        this.time.delayedCall(dur, ()=>{ mark.destroy(); const boom = this.add.image(tx, ty, 'vfx_mortar_circle').setDepth(41).setScale(1.2).setTint(0xffe2b0); this.tweens.add({ targets: boom, alpha:0, scaleX:2, scaleY:2, duration:220, onComplete:()=>boom.destroy() }); if(Math.hypot(this.player.x-tx, this.player.y-ty) < 26){ this.doHitStop(60); this.doShake(); } });
      } else {
        const mark = this.add.graphics({ x: tx, y: ty }).setDepth(40); mark.lineStyle(2, 0xffb36b, 1); mark.strokeCircle(0,0, 14);
        this.tweens.add({ targets: mark, alpha: 0.2, duration: dur });
        this.time.delayedCall(dur, ()=>{ mark.destroy(); const boom = this.add.graphics({ x: tx, y: ty }).setDepth(41); boom.fillStyle(0xffe2b0, 0.8); boom.fillCircle(0,0, 20); this.tweens.add({ targets: boom, alpha:0, scaleX:2, scaleY:2, duration:220, onComplete:()=>boom.destroy() }); if(Math.hypot(this.player.x-tx, this.player.y-ty) < 26){ this.doHitStop(60); this.doShake(); } });
      }
    }
  }

  private assassinBlinkStrike(s:Phaser.Physics.Arcade.Sprite, player:Phaser.Physics.Arcade.Sprite){
    const ang = Math.atan2(player.y - s.y, player.x - s.x);
    const dist = 120; const nx = player.x - Math.cos(ang)*dist; const ny = player.y - Math.sin(ang)*dist;
    const ghost = this.textures.exists('vfx_blink_trail') ? this.add.image(s.x, s.y, 'vfx_blink_trail').setAlpha(0.7).setDepth(6).setRotation(ang) : this.add.image(s.x, s.y, s.texture.key).setAlpha(0.4).setDepth(6);
    this.tweens.add({ targets: ghost, alpha:0, duration:300, onComplete:()=>ghost.destroy() });
    s.setPosition(nx, ny);
    this.spawnSlashArc(s.x, s.y, ang, 0xb38bff);
    if(Math.hypot(player.x - s.x, player.y - s.y) < 60){ this.doHitStop(60); this.doShake(); }
  }

  private railgunTelegraphAndFire(s:Phaser.Physics.Arcade.Sprite, player:Phaser.Physics.Arcade.Sprite){
    const ang = Math.atan2(player.y - s.y, player.x - s.x);
    const len = 520; const cos=Math.cos(ang), sin=Math.sin(ang);
    const tx = s.x + cos*len; const ty = s.y + sin*len;
    if(this.vfxLoaded.has('railgun_beam')){
      const tele:any = this.makeVfxAt('railgun_beam', s.x, s.y, 45); (tele as any).setOrigin?.(0,0.5); (tele as any).setRotation?.(ang); (tele as any).setScale?.(len/ (((this.textures.get('vfx_railgun_beam') as any).getSourceImage().width)||len), 1);
      this.time.delayedCall(380, ()=>{ (tele as any).destroy?.(); const blast:any = this.makeVfxAt('railgun_beam', s.x, s.y, 46); (blast as any).setOrigin?.(0,0.5); (blast as any).setRotation?.(ang); (blast as any).setTint?.(0xc8ecff); this.time.delayedCall(90, ()=> (blast as any).destroy?.()); if(this.lineHitsPlayer(s.x, s.y, tx, ty)){ this.doHitStop(90); this.doShake(); } });
    } else {
      const beam = this.add.graphics().setDepth(45); beam.lineStyle(2, 0x7fd0ff, 0.55); beam.beginPath(); beam.moveTo(s.x, s.y); beam.lineTo(tx, ty); beam.strokePath();
      this.time.delayedCall(380, ()=>{ beam.clear(); const blast = this.add.graphics().setDepth(46); blast.lineStyle(6, 0xc8ecff, 1); blast.beginPath(); blast.moveTo(s.x, s.y); blast.lineTo(tx, ty); blast.strokePath(); this.time.delayedCall(70, ()=> blast.destroy()); if(this.lineHitsPlayer(s.x, s.y, tx, ty)){ this.doHitStop(90); this.doShake(); } });
    }
  }

  private lineHitsPlayer(x1:number,y1:number,x2:number,y2:number):boolean{
    const px = this.player.x, py=this.player.y; const vx = x2-x1, vy=y2-y1; const wx = px-x1, wy=py-y1; const c1 = vx*wx + vy*wy; const c2 = vx*vx + vy*vy; const t = Phaser.Math.Clamp(c1/(c2||1),0,1); const dx = x1 + t*vx - px; const dy = y1 + t*vy - py; return Math.hypot(dx,dy) < 20;
  }

  private spawnCouncilStub(){
    if(this.councilActive) return; this.councilActive = true; this.councilProgress = 0;
    // Beacon visual
    const g = this.add.graphics(); g.fillStyle(0xffde59, 0.6); g.fillCircle(400, 120, 20); g.fillStyle(0xffffff, 0.25); g.fillCircle(400,120,30);
    // Pads
    this.padA = this.physics.add.staticImage(300, 220, 'player').setTint(0x42f57b).setAlpha(0.35);
    this.padB = this.physics.add.staticImage(500, 220, 'player').setTint(0x42f57b).setAlpha(0.35);
    this.events.once('council:cleanup', ()=>{ g.destroy(); this.padA?.destroy(); this.padB?.destroy(); this.councilText?.destroy(); this.councilText=undefined; });
  }

  private resolveCouncilStub(){
    this.councilActive = false; this.events.emit('council:resolve'); this.events.emit('council:cleanup');
    // Simple feedback
    const t = this.add.text(400, 60, 'Council Resolved', { fontFamily:'monospace', fontSize:'16px', color:'#9bffb0' }).setOrigin(0.5);
    this.time.delayedCall(1200, ()=> t.destroy());
  }

  // --- Council UI ---
  private councilUi?: { bg: Phaser.GameObjects.Rectangle; texts: Phaser.GameObjects.Text[] };
  private async showCouncilChoices(){
    const { width, height } = this.cameras.main;
    const choices = await this.rollThreePatches();
    const bg = this.add.rectangle(width/2, height/2, 420, 180, 0x000000, 0.7).setStrokeStyle(2, 0x8bf).setDepth(300);
    const texts: Phaser.GameObjects.Text[] = [];
    choices.forEach((p, i)=>{
      const tx = this.add.text(width/2 - 180 + i*180, height/2-40, `${p.name}\n${p.description}`,
        { fontFamily:'monospace', fontSize:'12px', color:'#fff', wordWrap:{ width:160 } }).setDepth(301);
      tx.setInteractive({ useHandCursor:true }).on('pointerdown', ()=>{
        this.patches.addPatchById(p.id as any);
        this.hideCouncilChoices();
      });
      texts.push(tx);
    });
    // DOM buttons for e2e selection
    const dom = document.createElement('div'); dom.id='council-ui'; dom.style.position='absolute'; dom.style.left='50%'; dom.style.top='50%'; dom.style.transform='translate(-50%,-50%)';
    choices.forEach((p)=>{ const b=document.createElement('button'); b.textContent=p.name; b.setAttribute('data-testid','council-choice'); b.onclick=()=>{ this.patches.addPatchById(p.id as any); this.hideCouncilChoices(); dom.remove(); }; dom.appendChild(b); });
    document.body.appendChild(dom);
    this.councilUi = { bg, texts };
  }
  private hideCouncilChoices(){
    if(!this.councilUi) return; this.councilUi.bg.destroy(); this.councilUi.texts.forEach(t=>t.destroy()); this.councilUi=undefined;
  }
  private async rollThreePatches(){
    // lazy import to avoid cycle (ESM)
    const mod = await import('../../content/patches');
    const pool = (mod.PATCH_POOL as Array<{id:string,name:string,description:string,requiresBlueprint?:boolean}>);
    const { filterPatchesByBlueprints } = await import('../../systems/Unlocks');
    const allowed = filterPatchesByBlueprints(pool);
    const picks: any[] = []; const used = new Set<string>();
    while(picks.length<3 && allowed.length>0){ const p = allowed[Math.floor(Math.random()*allowed.length)]; if(!used.has(p.id)){ used.add(p.id); picks.push(p); } }
    return picks;
  }

  private swapWeapon(delta:number){
    this.weaponIndex = (this.weaponIndex + delta + this.weapons.length) % this.weapons.length;
    this.weaponText?.setText('Weapon: ' + this.weapons[this.weaponIndex]);
  }

  private startFire(){ if(this.firing) return; this.firing = true; this.fireBullet(); this.fireTimer = this.time.addEvent({ delay: this.patches.getFireInterval(220, !!this.mergeOverlay?.visible), loop: true, callback: ()=> this.fireBullet() }); }
  private stopFire(){ this.firing = false; this.fireTimer?.remove(false); }

  private startAltFire(){ if(this.altFiring) return; this.altFiring = true; this.fireAlt(); this.altTimer = this.time.addEvent({ delay: 600, loop: true, callback: ()=> this.fireAlt() }); }
  private stopAltFire(){ this.altFiring = false; this.altTimer?.remove(false); }

  private fireBullet(){
    if(!this.bullets) return;
    const ptr = this.input.activePointer;
    const angle = Phaser.Math.Angle.Between(this.player.x, this.player.y, ptr.worldX, ptr.worldY);
    const weapon = this.weapons[this.weaponIndex];
    const speed = weapon==='Threadneedle' ? 460 : weapon==='Refactor Harpoon' ? 320 : weapon==='Garbage Collector' ? 340 : 360;
    const dir = this.getAimDir();
    // Pick an existing projectile texture or synthesize a tiny fallback immediately
    const texKey = this.getProjectileTextureOrFallback(weapon, dir);
    const bullet = this.bullets.get(this.player.x, this.player.y, texKey) as Phaser.Types.Physics.Arcade.ImageWithDynamicBody | null;
    if(!bullet) return;
    // Packet Loss: small chance to fizzle
    if((this.patches as any).activeByCategory?.get('weapons')?.id==='packet_loss' && Math.random() < 0.05){
      // fizzle visual: no bullet
      return;
    }
    bullet.setActive(true).setVisible(true).setDepth(5).setScale(0.4);
    if(weapon==='Threadneedle') bullet.setTint(this.branch==='A'? 0x9b59ff : 0x29d3c6); else bullet.clearTint();
    // Play sheet animation if available
    try{
      const animKey = (weapon==='Threadneedle' ? `proj_threadneedle-${dir}` : weapon==='Refactor Harpoon' ? `proj_harpoon-${dir}` : weapon==='Garbage Collector' ? `proj_orb-${dir}` : `proj_shader-${dir}`);
      if(!this.anims.exists(animKey) && this.textures.exists((weapon==='Threadneedle' ? `proj_threadneedle-${dir}-0` : weapon==='Refactor Harpoon' ? `proj_harpoon-${dir}-0` : weapon==='Garbage Collector' ? `proj_orb-${dir}-0` : `proj_shader-${dir}-0`))){
        const frames = Array.from({ length: 8 }, (_, i)=> ({ key: (weapon==='Threadneedle' ? `proj_threadneedle-${dir}-${i}` : weapon==='Refactor Harpoon' ? `proj_harpoon-${dir}-${i}` : weapon==='Garbage Collector' ? `proj_orb-${dir}-${i}` : `proj_shader-${dir}-${i}`) }));
        this.anims.create({ key: animKey, frames, frameRate: 16, repeat: -1 });
      }
      if(this.anims.exists(animKey)) (bullet as any).anims?.play?.(animKey, true);
      // rotate physics body/visual by dir approximate angle
      const angRad = (()=>{
        switch(dir){
          case 'east': return 0;
          case 'north-east': return -Math.PI/4;
          case 'north': return -Math.PI/2;
          case 'north-west': return -3*Math.PI/4;
          case 'west': return Math.PI;
          case 'south-west': return 3*Math.PI/4;
          case 'south': return Math.PI/2;
          case 'south-east': return Math.PI/4;
        }
      })();
      (bullet as any).setRotation?.(angRad||0);
    }catch{}
    if(weapon==='Refactor Harpoon'){ (bullet as any).setData?.('mode','harpoon'); }
    this.physics.velocityFromRotation(angle, speed, bullet.body.velocity);
    const addPreUpdate = (img:any, fn:(t:number,dt:number)=>void)=>{ const prev = img.preUpdate; img.preUpdate = (t:number,dt:number)=>{ if(prev) prev.call(img,t,dt); fn(t,dt); }; };
    if(this.patches.shouldWrapBullets()){ const b:any = bullet; addPreUpdate(b,(t,dt)=>{ const margin=1; if(b.x<-margin) b.x = GAME_WIDTH+margin; else if(b.x>GAME_WIDTH+margin) b.x=-margin; if(b.y<-margin) b.y = GAME_HEIGHT+margin; else if(b.y>GAME_HEIGHT+margin) b.y=-margin; }); }
    if(weapon==='Shader Scepter'){
      const b:any = bullet; const baseAngle = angle; let phase = 0;
      addPreUpdate(b,(t,dt)=>{ phase += dt; const offset = Math.sin(phase*0.015)*0.35; const a = baseAngle + offset; const v = b.body.velocity; const speedNow = Math.hypot(v.x,v.y)||speed; this.physics.velocityFromRotation(a, speedNow, b.body.velocity); });
    }
    // Ricochet (one bounce)
    if(this.patches.getRicochetCount()>0){ const b:any = bullet; b.setData?.('ric', this.patches.getRicochetCount()); addPreUpdate(b,()=>{ const m=2; if(b.x<m||b.x>GAME_WIDTH-m){ b.body.velocity.x *= -1; if((b.getData?.('ric')||1)>0){ b.setData?.('ric', (b.getData?.('ric')||1)-1); if((this.patches as any).hasPatch?.('split_threads')){ const ang = Math.atan2(b.body.velocity.y, b.body.velocity.x); for(const off of [-0.25,0.25]){ const sh = this.bullets!.get(b.x, b.y, 'bullet') as any; if(!sh) continue; sh.setActive(true).setVisible(true).setDepth(4).setScale(0.7).setTint(0x99e6ff); this.physics.velocityFromRotation(ang+off, 300, sh.body.velocity); this.time.delayedCall(700,()=> sh.destroy()); } } } } if(b.y<m||b.y>GAME_HEIGHT-m){ b.body.velocity.y *= -1; if((b.getData?.('ric')||1)>0){ b.setData?.('ric', (b.getData?.('ric')||1)-1); if((this.patches as any).hasPatch?.('split_threads')){ const ang = Math.atan2(b.body.velocity.y, b.body.velocity.x); for(const off of [-0.25,0.25]){ const sh = this.bullets!.get(b.x, b.y, 'bullet') as any; if(!sh) continue; sh.setActive(true).setVisible(true).setDepth(4).setScale(0.7).setTint(0x99e6ff); this.physics.velocityFromRotation(ang+off, 300, sh.body.velocity); this.time.delayedCall(700,()=> sh.destroy()); } } } } if((b.getData?.('ric')||0)<=0){ b.setData?.('ric',0); } }); }
    // Homing
    const homing = this.patches.getHomingStrength();
    if(homing>0){ const b:any = bullet; addPreUpdate(b,(t,dt)=>{ const enemies = [...this.enemiesMap.values()]; if(enemies.length===0) return; let target = enemies[0]; let best=Infinity; for(const e of enemies){ const d = Math.hypot(e.x-b.x, e.y-b.y); if(d<best){ best=d; target=e; } } const desired = Phaser.Math.Angle.Between(b.x,b.y,target.x,target.y); const v=b.body.velocity; const current = Math.atan2(v.y,v.x); const newA = Phaser.Math.Angle.RotateTo(current, desired, homing*dt); const sp = Math.hypot(v.x,v.y)||speed; this.physics.velocityFromRotation(newA, sp, b.body.velocity); }); }
    // overlap handled globally between groups
    this.time.delayedCall(1200, ()=> bullet.destroy());

    // Fusion combos: simple upgrades
    if(this.fusionActive){
      if(weapon==='Threadneedle'){
        const spread = 0.06;
        for(const off of [-spread, spread]){
          const b2 = this.bullets!.get(this.player.x, this.player.y, texKey) as Phaser.Types.Physics.Arcade.ImageWithDynamicBody | null;
          if(!b2) continue; b2.setActive(true).setVisible(true).setDepth(5).setScale(0.9).setTint(bullet.tintTopLeft);
          this.physics.velocityFromRotation(angle+off, speed, b2.body.velocity);
          this.time.delayedCall(900, ()=> b2.destroy());
        }
      }
      if(weapon==='Shader Scepter'){
        // Split after a short delay
        this.time.delayedCall(300, ()=>{
          if(!bullet.active) return; const pos = { x: bullet.x, y: bullet.y };
          for(const off of [-0.35, 0.35]){
            const b3 = this.bullets!.get(pos.x, pos.y, texKey) as Phaser.Types.Physics.Arcade.ImageWithDynamicBody | null;
            if(!b3) continue; b3.setActive(true).setVisible(true).setDepth(5).setScale(0.8);
            this.physics.velocityFromRotation(angle+off, speed, b3.body.velocity);
            this.time.delayedCall(700, ()=> b3.destroy());
          }
        });
      }
    }
  }

  private getProjectileTextureOrFallback(weapon:string, dir: ReturnType<RunScene['getAimDir']>): string{
    const perFrame = (weapon==='Threadneedle' ? `proj_threadneedle-${dir}-0` : weapon==='Refactor Harpoon' ? `proj_harpoon-${dir}-0` : weapon==='Garbage Collector' ? `proj_orb-${dir}-0` : `proj_shader-${dir}-0`);
    if(this.textures.exists(perFrame)) return perFrame;
    const rot = (weapon==='Threadneedle' ? `proj_threadneedle-rot-${dir}` : weapon==='Refactor Harpoon' ? `proj_harpoon-rot-${dir}` : weapon==='Garbage Collector' ? `proj_orb-rot-${dir}` : `proj_shader-rot-${dir}`);
    if(this.textures.exists(rot)) return rot;
    // Synthesize a small visible fallback right now
    const key = `proj_fallback_${weapon}_${dir}`;
    if(!this.textures.exists(key)){
      const size = 10;
      const tex:any = this.textures.createCanvas(key, size, size);
      const ctx = (tex as any).getContext() as CanvasRenderingContext2D;
      ctx.clearRect(0,0,size,size);
      const color = weapon==='Threadneedle' ? '#7fd0ff' : weapon==='Refactor Harpoon' ? '#dddddd' : weapon==='Garbage Collector' ? '#ffe066' : '#bca8ff';
      ctx.fillStyle = color;
      // draw diamond
      ctx.beginPath(); ctx.moveTo(size/2,1); ctx.lineTo(size-1,size/2); ctx.lineTo(size/2,size-1); ctx.lineTo(1,size/2); ctx.closePath(); ctx.fill();
      (tex as any).refresh();
    }
    return key;
  }

  private getAimDir(): 'east'|'north-east'|'north'|'north-west'|'west'|'south-west'|'south'|'south-east'{
    const ptr = this.input.activePointer;
    const angle = Phaser.Math.Angle.Between(this.player.x, this.player.y, ptr.worldX, ptr.worldY);
    // Convert to math coords (invert Y) to match our animation compass
    const a = Math.atan2(-(ptr.worldY - this.player.y), (ptr.worldX - this.player.x));
    const dirs = ['east','north-east','north','north-west','west','south-west','south','south-east'] as const;
    const idx = (Math.round(a / (Math.PI/4)) + 8) % 8;
    return dirs[idx];
  }

  private fireAlt(){
    if(!this.bullets) return;
    const weapon = this.weapons[this.weaponIndex];
    if(weapon==='Garbage Collector'){
      const ptr = this.input.activePointer;
      const angle = Phaser.Math.Angle.Between(this.player.x, this.player.y, ptr.worldX, ptr.worldY);
      const orb = this.bullets.get(this.player.x, this.player.y, 'proj_orb') as Phaser.Types.Physics.Arcade.ImageWithDynamicBody | null;
      if(!orb) return; orb.setActive(true).setVisible(true).setScale(1.6).setDepth(5).setTint(0xffe066);
      this.physics.velocityFromRotation(angle, 200, orb.body.velocity);
      this.time.delayedCall(1600, ()=> orb.destroy());
      if(this.fusionActive){ this.time.delayedCall(120, ()=>{ if(!this.bullets) return; const orb2 = this.bullets!.get(this.player.x, this.player.y, 'proj_orb') as Phaser.Types.Physics.Arcade.ImageWithDynamicBody | null; if(!orb2) return; orb2.setActive(true).setVisible(true).setScale(1.6).setDepth(5).setTint(0xffe066); this.physics.velocityFromRotation(angle, 200, orb2.body.velocity); this.time.delayedCall(1600, ()=> orb2.destroy()); }); }
    } else {
      for(let i=0;i<5;i++) this.time.delayedCall(i*30, ()=> this.fireBullet());
    }
  }

  private beginFusionLocal(ms:number){ this.fusionActive = true; this.fusionUntil = (this.time.now||0) + ms; }

  // Hit-stop and shake helpers
  private doHitStop(ms:number){ this.time.timeScale = 0.01; this.time.delayedCall(ms, ()=> this.time.timeScale = 1); }
  private doShake(){ if(this.opts.shake) this.cameras.main.shake(120, 0.004); }

  private ensureHudDom(){ if(!document.getElementById('hud')){ const hud=document.createElement('div'); hud.id='hud'; hud.style.position='absolute'; hud.style.left='10px'; hud.style.top='10px'; hud.style.color='#9cf'; hud.style.fontFamily='monospace'; hud.innerHTML='<div>Room: <span id="hud-room">1<\/span></div><div>Enemies: <span id="hud-enemies">0<\/span></div><div>Phase: <span id="hud-phase">ready<\/span></div><div>Merge: <span id="hud-merge">-<\/span></div><div>Blueprints: <span id="hud-bp">0\/0<\/span> • Tokens: <span id="hud-tokens">0<\/span> (B)<\/div>'; document.body.appendChild(hud); } }

  private async updateBlueprintHud(){
    try{
      const pool = (await import('../../content/patches')).PATCH_POOL as Array<{id:string;requiresBlueprint?:boolean}>;
      const total = pool.filter(p=>p.requiresBlueprint).length;
      const owned = (this.unlocks.blueprints||[]).length;
      const t = (this.unlocks.stats.bossTokens||0);
      const bp = document.getElementById('hud-bp'); if(bp) bp.textContent = `${owned}/${total}`;
      const tk = document.getElementById('hud-tokens'); if(tk) tk.textContent = String(t);
    }catch{}
  }

  private showUnlockToast(text: string){
    const t = this.add.text(GAME_WIDTH/2, 14, text, { fontFamily:'monospace', fontSize:'14px', color:'#ffeb7a' }).setOrigin(0.5,0).setDepth(250);
    this.tweens.add({ targets: t, y: 44, alpha: 0, duration: 1600, onComplete: ()=> t.destroy() });
  }

  private onUnlocksChanged(){
    try{ saveUnlocks(this.unlocks); }catch{}
    const all = ['Threadneedle','Refactor Harpoon','Garbage Collector','Shader Scepter'];
    const filtered = computeUnlockedWeapons(all);
    const current = this.weapons[this.weaponIndex];
    this.weapons = filtered.length>0 ? filtered : ['Threadneedle'];
    if(!this.weapons.includes(current)) this.weaponIndex = 0;
    this.weaponText?.setText('Weapon: ' + this.weapons[this.weaponIndex]);
  }

  private async tryAwardBlueprint(guaranteed:boolean){
    try{
      const pool = (await import('../../content/patches')).PATCH_POOL as Array<{id:string; name:string; requiresBlueprint?:boolean}>;
      const locked = pool.filter(p=> p.requiresBlueprint && !(this.unlocks.blueprints||[]).includes(p.id));
      if(locked.length===0) return;
      if(!guaranteed && Math.random() >= 0.03) return; // ~3% drop chance
      const pick = locked[Math.floor(Math.random()*locked.length)];
      if(grantBlueprint(this.unlocks, pick.id)){
        this.showUnlockToast('Blueprint: '+pick.name);
        saveUnlocks(this.unlocks);
      }
    }catch{}
  }

  private toggleBlueprintsMenu(){
    try{
      if(!this.bpMenu){ this.bpMenu = new BlueprintsMenu(this, this.unlocks, ()=> this.onUnlocksChanged()); }
      const isOpen = (this.bpMenu as any)?.isOpen?.();
      if(isOpen){ (this.bpMenu as any).close?.(); }
      else { (this.bpMenu as any).open?.(); }
    }catch{}
  }
}

