import Phaser from 'phaser';
import type { UnlocksState, StorageLike } from '../systems/Unlocks';
import { saveUnlocks, grantBlueprint } from '../systems/Unlocks';

export class BlueprintsMenu {
  private scene: Phaser.Scene;
  private unlocks: UnlocksState;
  private group?: Phaser.GameObjects.Group;
  private bg?: Phaser.GameObjects.Rectangle;
  private frame?: Phaser.GameObjects.Rectangle;
  private title?: Phaser.GameObjects.Text;
  private tokensText?: Phaser.GameObjects.Text;
  private listTexts: Phaser.GameObjects.Text[] = [];
  private onChange?: () => void;

  constructor(scene: Phaser.Scene, unlocks: UnlocksState, onChange?: ()=>void){
    this.scene = scene;
    this.unlocks = unlocks;
    this.onChange = onChange;
  }

  isOpen(): boolean { return !!this.group; }

  open(){
    if(this.group) return;
    const { width, height } = this.scene.cameras.main;
    this.group = this.scene.add.group();
    this.bg = this.scene.add.rectangle(width/2, height/2, width, height, 0x000000, 0.45).setDepth(500);
    this.frame = this.scene.add.rectangle(width/2, height/2, 560, 320, 0x0b1020, 0.92).setStrokeStyle(2, 0x6ac9ff).setDepth(501);
    this.title = this.scene.add.text(width/2, height/2 - 140, 'Blueprints', { fontFamily:'monospace', fontSize:'20px', color:'#aee3ff' }).setOrigin(0.5,0).setDepth(502);
    this.tokensText = this.scene.add.text(width/2, height/2 - 110, this.getTokensLine(), { fontFamily:'monospace', fontSize:'14px', color:'#cfe' }).setOrigin(0.5,0).setDepth(502);

    this.group.addMultiple([this.bg, this.frame, this.title, this.tokensText!]);

    this.renderList();

    // Close on ESC or background click
    this.bg.setInteractive({ useHandCursor: true }).on('pointerdown', ()=> this.close());
    this.scene.input.keyboard?.once('keydown-ESC', ()=> this.close());
  }

  close(){
    if(!this.group) return;
    this.group.getChildren().forEach(obj=> obj.destroy());
    this.group.clear(true);
    this.group = undefined;
    this.bg = undefined; this.frame = undefined; this.title = undefined; this.tokensText = undefined;
    this.listTexts = [];
  }

  private getTokensLine(): string {
    const t = this.unlocks.stats.bossTokens || 0;
    return `Tokens: ${t}  (Spend 1 to research a random locked blueprint)`;
  }

  private renderList(){
    const mod = require('../content/patches') as any;
    const pool = (mod.PATCH_POOL as Array<{ id:string; name:string; requiresBlueprint?:boolean }>);
    const gated = pool.filter(p=> p.requiresBlueprint);
    const owned = new Set<string>((this.unlocks.blueprints||[]));

    // Clear existing
    for(const t of this.listTexts){ t.destroy(); }
    this.listTexts = [];

    const { width, height } = this.scene.cameras.main;
    const startY = height/2 - 80;
    const colX = [width/2 - 240, width/2];
    let idx = 0;
    for(const p of gated){
      const x = colX[Math.floor(idx/6)];
      const y = startY + (idx%6)*24;
      const have = owned.has(p.id);
      const color = have ? '#a5ffb5' : '#9bb0c4';
      const label = have ? `${p.name}` : '???';
      const t = this.scene.add.text(x, y, label, { fontFamily:'monospace', fontSize:'14px', color }).setDepth(503);
      this.listTexts.push(t);
      idx++;
    }

    // Research button
    const btnY = height/2 + 110;
    const btn = this.scene.add.rectangle(width/2, btnY, 220, 30, 0x12304a, 0.95).setStrokeStyle(2, 0x6ac9ff).setDepth(502).setInteractive({ useHandCursor: true });
    const btnText = this.scene.add.text(width/2, btnY-8, 'Research Random Blueprint (1 Token)', { fontFamily:'monospace', fontSize:'12px', color:'#dff6ff' }).setOrigin(0.5,0).setDepth(503);
    btn.on('pointerdown', ()=> this.researchOne());
    this.group?.addMultiple([btn, btnText]);
  }

  private researchOne(){
    const tokens = this.unlocks.stats.bossTokens||0;
    if(tokens <= 0){ return; }
    const mod = require('../content/patches') as any;
    const pool = (mod.PATCH_POOL as Array<{ id:string; name:string; requiresBlueprint?:boolean }>);
    const locked = pool.filter(p=> p.requiresBlueprint && !(this.unlocks.blueprints||[]).includes(p.id));
    if(locked.length === 0){ return; }
    const pick = locked[Math.floor(Math.random()*locked.length)];
    if(grantBlueprint(this.unlocks, pick.id)){
      this.unlocks.stats.bossTokens = (this.unlocks.stats.bossTokens||0) - 1;
      try{ saveUnlocks(this.unlocks); }catch{}
      if(this.tokensText){ this.tokensText.setText(this.getTokensLine()); }
      if(this.onChange){ this.onChange(); }
      // Refresh list
      this.renderList();
      // Toast via scene if available
      try{ const anyScene:any = this.scene as any; if(anyScene.showUnlockToast){ anyScene.showUnlockToast('Blueprint: '+pick.name); } }catch{}
    }
  }
}


