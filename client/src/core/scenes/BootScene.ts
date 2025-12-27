import Phaser from 'phaser';
export class BootScene extends Phaser.Scene {
  constructor(){ super('Boot'); }
  preload(){
    this.load.image('player','/sprites/player_placeholder.png');
    this.load.image('bullet','/sprites/bullet_placeholder.png');
    this.load.tilemapTiledJSON('room1','/tilemaps/room1.tmj');
    this.load.image('tiles','/tilemaps/tilesheet.png');

    // Preload Player SysOp walking frames (8 directions × 8 frames)
    const dirs = ['south','south-east','east','north-east','north','north-west','west','south-west'];
    const bust = Date.now();
    for(const dir of dirs){
      for(let i=0;i<8;i++){
        const key = `player-walk-${dir}-${i}`;
        if(this.textures.exists(key)) this.textures.remove(key);
        const idx=String(i).padStart(3,'0');
        this.load.image(key, `/sprites/player/animations/walking-8-frames/${dir}/frame_${idx}.png?v=${bust}`);
      }
    }

    // Cleaned: remove legacy Scenario/Leonardo enemy preloads; PixelLab-only below
    // Boss: Monolith CI idle frames (south only) and walking frames (8 dirs × 4 frames)
    for(let i=0;i<4;i++){
      const idx = String(i).padStart(3,'0');
      this.load.image(`boss-idle-south-${i}`, `/sprites/boss/monolith_ci/animations/breathing-idle/south/frame_${idx}.png`);
    }
    for(const dir of dirs){ for(let i=0;i<4;i++){ const idx=String(i).padStart(3,'0'); this.load.image(`boss-walk-${dir}-${i}`, `/sprites/boss/monolith_ci/animations/walking-4-frames/${dir}/frame_${idx}.png`); } }

    // Projectiles (hand-drawn, if present): 8 dirs × 8 frames under /sprites/projectiles/<name>/animations/fireball-8-frames/
    // If Scenario sheets exist (8-frame single-row), slice them to textures
    const sliceSheet = (keyBase:string, path:string)=>{
      this.load.image(`${keyBase}-sheet`, path);
      this.load.once(Phaser.Loader.Events.COMPLETE, ()=>{
        const baseTex = this.textures.get(`${keyBase}-sheet`) as any;
        if(baseTex && baseTex.getSourceImage){
          const img: HTMLImageElement = baseTex.getSourceImage();
          const doSlice = ()=>{
            if(!img.width || !img.height){ setTimeout(doSlice, 30); return; }
            const frameW = Math.floor(img.width/8); const frameH = img.height;
            // Create a spritesheet texture by slicing the single row
            const cvs:any = this.textures.createCanvas(keyBase+'-east', img.width, img.height);
            const ctx: CanvasRenderingContext2D = cvs.getContext();
            ctx.clearRect(0,0,img.width,img.height);
            ctx.drawImage(img, 0, 0);
          // Heuristic alpha cleanup: remove near-background and dark pixels; increase transparency on soft edges
          try{
            const id = ctx.getImageData(0,0,img.width,img.height);
            const data = id.data;
            const samp = (x:number,y:number)=>{ const i=(y*img.width+x)*4; return { r:data[i], g:data[i+1], b:data[i+2] }; };
            const c1=samp(0,0), c2=samp(img.width-1,0), c3=samp(0,img.height-1), c4=samp(img.width-1,img.height-1);
            const r0=(c1.r+c2.r+c3.r+c4.r)/4, g0=(c1.g+c2.g+c3.g+c4.g)/4, b0=(c1.b+c2.b+c3.b+c4.b)/4;
            const bgLum = 0.2126*r0 + 0.7152*g0 + 0.0722*b0;
            for(let p=0;p<data.length;p+=4){
              const r=data[p], g=data[p+1], b=data[p+2];
              const lum = 0.2126*r + 0.7152*g + 0.0722*b;
              // remove very dark and near background
              if(lum < bgLum + 10){ data[p+3]=0; continue; }
              // soften edges
              const a = Math.max(0, Math.min(255, (lum - (bgLum+10)) * 3));
              data[p+3] = Math.min(data[p+3], a);
            }
            ctx.putImageData(id,0,0);
          }catch{}
          for(let i=0;i<8;i++){
            cvs.add(String(i), 0, i*frameW, 0, frameW, frameH);
          }
          cvs.refresh();
          };
          try{ (img as any).decode ? (img as any).decode().then(()=> doSlice()).catch(()=> doSlice()) : doSlice(); }catch{ doSlice(); }
        }
      });
    };
    try{ sliceSheet('proj_sheet_threadneedle', '/sprites/projectiles/threadneedle_sheet.png'); }catch{}
    try{ sliceSheet('proj_sheet_harpoon', '/sprites/projectiles/harpoon_sheet.png'); }catch{}
    try{ sliceSheet('proj_sheet_orb', '/sprites/projectiles/orb_sheet.png'); }catch{}
    try{ sliceSheet('proj_sheet_shader', '/sprites/projectiles/shader_sheet.png'); }catch{}

    // PixelLab enemies: per-frame PNGs. Only load characters that exist locally.
    const pixEnemies = ['skeleton_knight','skeleton_archer','orc_brute'];
    const dir4 = ['east','north-east','north','north-west','west','south-west','south','south-east'];
    for(const name of pixEnemies){
      for(const dir of dir4){ for(let i=0;i<4;i++){ const idx=String(i).padStart(3,'0'); this.load.image(`pix_${name}-walk-${dir}-${i}`, `/sprites/enemies/${name}/animations/walking-4-frames/${dir}/frame_${idx}.png`); } }
    }
    // Empire Knight v2 (8-dir × 6 frames)
    for(const dir of dirs){ for(let i=0;i<6;i++){ const idx=String(i).padStart(3,'0'); this.load.image(`pix_empire_knight_v2-walk-${dir}-${i}`, `/sprites/enemies/empire_knight_v2/animations/walking-8-frames/${dir}/frame_${idx}.png`); } }
    // Empire Paladin (Tower) (8-dir × 6 frames)
    for(const dir of dirs){ for(let i=0;i<6;i++){ const idx=String(i).padStart(3,'0'); this.load.image(`pix_empire_paladin_tower-walk-${dir}-${i}`, `/sprites/enemies/empire_paladin_tower/animations/walking-8-frames/${dir}/frame_${idx}.png`); } }
    // Clockwork Juggernaut (8-dir × 6 frames)
    for(const dir of dirs){ for(let i=0;i<6;i++){ const idx=String(i).padStart(3,'0'); this.load.image(`pix_clockwork_juggernaut-walk-${dir}-${i}`, `/sprites/enemies/clockwork_juggernaut/animations/walking-8-frames/${dir}/frame_${idx}.png`); } }
    // Removed Scenario/Leonardo loaders and slicing; PixelLab frames only

    // --- Structures: 8-frame animated sprites (single facing) ---
    // Load either pre-cut frames or slice from a single sheet (auto-detection)
    const structDefs = [
      { keyPrefix: 'struct_arcane_cube', path: '/sprites/structures/arcane_cube/animations/idle-8-frames', sheet: '/sprites/structures/sheets/arcane_cube_sheet.png' },
      { keyPrefix: 'struct_obelisk', path: '/sprites/structures/obelisk/animations/idle-8-frames', sheet: '/sprites/structures/sheets/obelisk_sheet.png' },
      { keyPrefix: 'struct_green_fountain', path: '/sprites/structures/green_fountain/animations/idle-8-frames', sheet: '/sprites/structures/sheets/green_fountain_sheet.png' },
    ];
    // helper to slice structure sheet into 8 frames (supports 1x8, 2x4, 4x2, 8x1)
    const sliceStructSheet = (keyPrefix:string, sheetKey:string)=>{
      const tex:any = this.textures.get(sheetKey); if(!tex || !tex.getSourceImage) return;
      const img:any = tex.getSourceImage(); const W = img.naturalWidth||img.width; const H = img.naturalHeight||img.height;
      const pickLayout = ()=>{
        // Force known layout for provided sheets to avoid mis-detection jitter
        const forced: Record<string,[number,number]> = {
          'struct_arcane_cube': [2,4],
          'struct_obelisk': [2,4],
          'struct_green_fountain': [2,4],
        };
        if(forced[keyPrefix]) return forced[keyPrefix];
        const cands = [ [1,8], [8,1], [2,4], [4,2] ] as Array<[number,number]>;
        const canvas = document.createElement('canvas'); canvas.width=W; canvas.height=H; const ctx = canvas.getContext('2d')!; ctx.clearRect(0,0,W,H); ctx.drawImage(img,0,0);
        const id = ctx.getImageData(0,0,W,H); const data = id.data;
        const alphaAt = (x:number,y:number)=> data[(y*W + x)*4 + 3];
        let best:[number,number] = [8,1]; let bestScore = Number.POSITIVE_INFINITY; let bestActive = -1;
        for(const [c,r] of cands){
          const cw = Math.floor(W/c), ch = Math.floor(H/r);
          const ratios:number[] = [];
          for(let ry=0; ry<r; ry++){
            for(let cx=0; cx<c; cx++){
              let cnt=0; let tot=0;
              for(let y=ry*ch; y<Math.min((ry+1)*ch,H); y+=Math.max(1, Math.floor(ch/48))){
                for(let x=cx*cw; x<Math.min((cx+1)*cw,W); x+=Math.max(1, Math.floor(cw/48))){ tot++; if(alphaAt(Math.floor(x),Math.floor(y))>16) cnt++; }
              }
              ratios.push(cnt/(tot||1));
            }
          }
          const active = ratios.filter(v=> v>0.02).length;
          const mean = ratios.reduce((a,b)=>a+b,0)/(ratios.length||1);
          const variance = ratios.reduce((a,b)=> a + (b-mean)*(b-mean), 0)/(ratios.length||1);
          const score = variance + (8-active)*0.5;
          if(active>bestActive || (active===bestActive && score<bestScore)){ best=[c,r]; bestScore=score; bestActive=active; }
        }
        return best;
      };
      let [cols, rows] = pickLayout(); if(W===0||H===0) return;
      if(W % cols !== 0 || H % rows !== 0){
        const frameKey = `${keyPrefix}-0`;
        if(!this.textures.exists(frameKey)){
          const cvs:any = this.textures.createCanvas(frameKey, W, H);
          const ctx = cvs.getContext(); ctx.clearRect(0,0,W,H); ctx.drawImage(img, 0, 0); cvs.refresh();
        }
        return;
      }
      const cw = Math.floor(W/cols), ch = Math.floor(H/rows);
      // Strict equal-grid slicing: draw each cell directly, no trimming or shifts
      let idx=0; for(let ry=0; ry<rows; ry++){
        for(let cx=0; cx<cols; cx++){
          if(idx>=8) break;
          const sx = cx*cw, sy = ry*ch;
          const frameKey = `${keyPrefix}-${idx}`;
          if(this.textures.exists(frameKey)) { try{ this.textures.remove(frameKey); }catch{} }
          const cvs:any = this.textures.createCanvas(frameKey, cw, ch);
          const ctx = cvs.getContext(); ctx.clearRect(0,0,cw,ch);
          ctx.drawImage(img, sx, sy, cw, ch, 0, 0, cw, ch);
          cvs.refresh(); idx++;
        }
      }
    };
    for(const def of structDefs){
      for(let i=0;i<8;i++){ const idx = String(i).padStart(3,'0'); const key = `${def.keyPrefix}-${i}`; this.load.image(key, `${def.path}/frame_${idx}.png?v=${Date.now()}`); }
      const sheetKey = `${def.keyPrefix}-sheet`; this.load.image(sheetKey, `${def.sheet}?v=${Date.now()}`);
      this.load.on(`filecomplete-image-${sheetKey}`, ()=>{ try{ const tex:any = this.textures.get(sheetKey); const img:any = tex && tex.getSourceImage ? tex.getSourceImage() : undefined; const doSlice = ()=>{ try{ sliceStructSheet(def.keyPrefix, sheetKey); }catch{} }; if(img && img.decode){ img.decode().then(()=> doSlice()).catch(()=> doSlice()); } else { doSlice(); } }catch{} });
    }
  }
  create(){
    // Build animations for player walking in 8 directions
    const dirs = ['south','south-east','east','north-east','north','north-west','west','south-west'];
    for(const dir of dirs){
      // Filter out any stale/mismatched frames (size mismatch indicates cached/old asset)
      const baseKey = `player-walk-${dir}-0`;
      const baseTex: any = this.textures.get(baseKey);
      const bw = (baseTex && baseTex.getSourceImage) ? baseTex.getSourceImage().naturalWidth || baseTex.getSourceImage().width : undefined;
      const bh = (baseTex && baseTex.getSourceImage) ? baseTex.getSourceImage().naturalHeight || baseTex.getSourceImage().height : undefined;
      const frames = [] as Array<{ key:string }>;
      for(let i=0;i<8;i++){
        const k = `player-walk-${dir}-${i}`;
        const tex: any = this.textures.get(k);
        const img = tex && tex.getSourceImage ? tex.getSourceImage() : undefined;
        const iw = img ? (img.naturalWidth||img.width) : bw;
        const ih = img ? (img.naturalHeight||img.height) : bh;
        if(!bw || !bh || (iw===bw && ih===bh)) frames.push({ key: k });
      }
      this.anims.create({ key: `player-walk-${dir}`, frames, frameRate: 10, repeat: -1 });
    }
    // Removed legacy nullpolyp/pointerwolf animations to prevent missing texture spam
    // Boss idle animation + directional walk animations
    this.anims.create({ key: 'boss-idle', frames: [0,1,2,3].map(i=>({ key: `boss-idle-south-${i}` })), frameRate: 6, repeat: -1 });
    for(const dir of dirs){ const frames = Array.from({length:4},(_,i)=>({ key:`boss-walk-${dir}-${i}` })); this.anims.create({ key:`boss-walk-${dir}`, frames, frameRate: 6, repeat:-1 }); }
    // PixelLab directional animations
    try{
      const dirOrder = ['east','north-east','north','north-west','west','south-west','south','south-east'];
      for(const name of ['skeleton_knight','skeleton_archer','orc_brute']){
        for(const dir of dirOrder){
          const base0 = `pix_${name}-walk-${dir}-0`;
          if(!this.textures.exists(base0)) continue; // only create anims for existing directions
          const frames = [0,1,2,3]
            .map(i=> `pix_${name}-walk-${dir}-${i}`)
            .filter(k=> this.textures.exists(k))
            .map(k=> ({ key: k }));
          if(frames.length>0){ this.anims.create({ key: `pix_${name}-walk-${dir}`, frames, frameRate: 8, repeat: -1 }); }
        }
      }
      // Empire Knight v2 animations (6 frames per direction)
      for(const dir of dirOrder){
        const frames = [0,1,2,3,4,5].map(i=> ({ key: `pix_empire_knight_v2-walk-${dir}-${i}` }));
        this.anims.create({ key: `pix_empire_knight_v2-walk-${dir}`, frames, frameRate: 10, repeat: -1 });
      }
      // Empire Paladin (Tower) animations (6 frames per direction)
      for(const dir of dirOrder){
        const frames = [0,1,2,3,4,5].map(i=> ({ key: `pix_empire_paladin_tower-walk-${dir}-${i}` }));
        this.anims.create({ key: `pix_empire_paladin_tower-walk-${dir}`, frames, frameRate: 9, repeat: -1 });
      }
      // Clockwork Juggernaut animations (6 frames per direction)
      for(const dir of dirOrder){
        const frames = [0,1,2,3,4,5].map(i=> ({ key: `pix_clockwork_juggernaut-walk-${dir}-${i}` }));
        this.anims.create({ key: `pix_clockwork_juggernaut-walk-${dir}`, frames, frameRate: 9, repeat: -1 });
      }
      (window as any).__enemyPixKeys = ['skeleton_knight','skeleton_archer','orc_brute','empire_knight_v2','empire_paladin_tower','clockwork_juggernaut'].map((n:string)=> `pix_${n}`);
    }catch{}

    // Structure animations (idle 8 frames) with rebuild pass after slicing completes
    const buildStructAnims = ()=>{
      try{
        const structs = [
          { keyPrefix: 'struct_arcane_cube' },
          { keyPrefix: 'struct_obelisk' },
          { keyPrefix: 'struct_green_fountain' },
        ];
        for(const s of structs){
          const frames = [] as Array<{key:string}>;
          for(let i=0;i<8;i++){
            const k = `${s.keyPrefix}-${i}`;
            if(this.textures.exists(k)) frames.push({ key: k });
          }
          if(frames.length>0){
            const animKey = `${s.keyPrefix}-idle`;
            if(this.anims.exists(animKey)) this.anims.remove(animKey);
            this.anims.create({ key: animKey, frames, frameRate: 10, repeat: -1 });
          }
        }
      }catch{}
    };
    buildStructAnims();
    try{ this.time.delayedCall(150, buildStructAnims); }catch{}


    // Load 8-direction enemies and register directional animations
    try{
      const names8 = ['skeleton_knight','skeleton_archer','skeleton_mage'];
      const dirOrder = ['east','north-east','north','north-west','west','south-west','south','south-east'];
      const keys8:string[] = [];
      // slicing per-file via filecomplete handler above
    }catch{}

    // Projectiles are loaded on-demand in RunScene with decode + addImage to avoid race conditions
    this.scene.start('MainMenu');
    // Silence Phaser cache warnings by avoiding missing texture lookups
    console.clear?.();
  }
}

