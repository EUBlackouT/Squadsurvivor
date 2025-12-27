import { PATCH_POOL, type PatchDef, type PatchId } from '../content/patches';

export interface PatchHooks {
  getFireInterval(baseMs: number, mergeActive: boolean): number;
  shouldWrapBullets(): boolean;
  getWorldFreezeMs(now: number): number; // 0 if none
  getPhaseCooldown(baseMs: number): number;
  getPlayerSpeedMultiplier(): number;
  getBulletPierceBonus(): number;
  getRicochetCount(): number;
  getHomingStrength(): number; // radians per ms scaled small, e.g., 0.001
  getShardCount(): number; // shards to spawn on hit
  getKillRefundMs(): number; // reduce phase cooldown on kill
  hasPatch(id: PatchId): boolean;
}

export class PatchesManager implements PatchHooks {
  private active: Map<PatchId, { def: PatchDef; expiresAt: number } > = new Map();
  private lastFreezeAt = 0;
  // Track by category for basic conflict resolution
  private categoryByPatch: Record<string, 'projectiles'|'weapons'|'time'|'phase'|'movement'|'meta'|'other'> = {
    edge_wrap: 'projectiles',
    merge_surge: 'weapons',
    clock_skips: 'time',
    packet_loss: 'weapons',
    rapid_reload: 'weapons',
    piercing_rounds: 'projectiles',
    phase_battery: 'phase',
    overclock: 'movement',
    ricochet_protocol: 'projectiles',
    homing_jit: 'projectiles',
    entropy_burst: 'projectiles',
    phase_blink: 'phase',
    temporal_refund: 'meta',
    split_threads: 'projectiles',
    branch_overload: 'projectiles',
    council_parallel: 'other',
    phase_afterimage: 'phase',
    monolith_debug: 'weapons',
    sawtooth_barrel: 'projectiles',
    smart_missile: 'projectiles',
    quantum_drill: 'projectiles',
    glacial_shards: 'projectiles'
  } as const;
  private rarityRank: Record<string, number> = { R: 5, U: 4, E: 3, L: 2, C: 1 };
  private activeByCategory: Map<string, { def: PatchDef; expiresAt: number }> = new Map();
  private defaultTtlMs = 120_000;

  tick(now:number){ this.pruneExpired(now); }
  private pruneExpired(now:number){
    for(const [id, entry] of this.active){ if(entry.expiresAt <= now){ this.active.delete(id); } }
    for(const [cat, entry] of this.activeByCategory){ if(entry.expiresAt <= now){ this.activeByCategory.delete(cat); } }
  }

  addPatchById(id: PatchId, ttlMs: number = this.defaultTtlMs){
    const def = (PATCH_POOL as PatchDef[]).find((p:PatchDef)=>p.id===id); if(!def) return;
    const expiresAt = Date.now() + Math.max(1_000, ttlMs);
    this.active.set(id, { def, expiresAt });
    const cat = this.categoryByPatch[id] ?? 'other';
    const current = this.activeByCategory.get(cat);
    if(!current){ this.activeByCategory.set(cat, { def, expiresAt }); return; }
    // Conflict resolver: rarity > recency
    const curRank = this.rarityRank[(current.def.rarity||'').toUpperCase()] ?? 0;
    const newRank = this.rarityRank[(def.rarity||'').toUpperCase()] ?? 0;
    if(newRank >= curRank){ this.activeByCategory.set(cat, { def, expiresAt }); }
  }

  // hooks
  getFireInterval(baseMs: number, mergeActive: boolean): number{
    let interval = baseMs;
    this.pruneExpired(Date.now());
    const w = this.activeByCategory.get('weapons');
    if(mergeActive && (w?.def.id === 'merge_surge')) interval = Math.floor(interval * 0.75);
    if(w?.def.id === 'rapid_reload') interval = Math.floor(interval * 0.85);
    return interval;
  }
  shouldWrapBullets(): boolean{ this.pruneExpired(Date.now()); return (this.activeByCategory.get('projectiles')?.def.id === 'edge_wrap'); }
  getWorldFreezeMs(now: number): number{
    this.pruneExpired(now);
    if(this.activeByCategory.get('time')?.def.id !== 'clock_skips') return 0;
    if(now - this.lastFreezeAt >= 5000){ this.lastFreezeAt = now; return 120; }
    return 0;
  }
  getPhaseCooldown(baseMs: number): number{
    this.pruneExpired(Date.now());
    const p = this.activeByCategory.get('phase');
    if(p?.def.id === 'phase_battery') return Math.floor(baseMs * 0.8);
    return baseMs;
  }
  getPlayerSpeedMultiplier(): number{
    this.pruneExpired(Date.now());
    const m = this.activeByCategory.get('movement');
    if(m?.def.id === 'overclock') return 1.15;
    return 1.0;
  }
  getBulletPierceBonus(): number{
    this.pruneExpired(Date.now());
    const p = this.activeByCategory.get('projectiles');
    if(p?.def.id === 'piercing_rounds') return 1;
    if(p?.def.id === 'quantum_drill') return 1;
    if(p?.def.id === 'branch_overload') return 1; // applied conditionally by caller during merge
    return 0;
  }
  getRicochetCount(): number{
    this.pruneExpired(Date.now());
    const id = this.activeByCategory.get('projectiles')?.def.id;
    if(id === 'sawtooth_barrel') return 2;
    if(id === 'ricochet_protocol') return 1;
    return 0;
  }
  getHomingStrength(): number{
    this.pruneExpired(Date.now());
    const id = this.activeByCategory.get('projectiles')?.def.id;
    if(id === 'smart_missile') return 0.004;
    if(id === 'homing_jit') return 0.002;
    return 0;
  }
  getShardCount(): number{
    this.pruneExpired(Date.now());
    const id = this.activeByCategory.get('projectiles')?.def.id;
    if(id === 'glacial_shards') return 3;
    if(id === 'entropy_burst') return 2;
    return 0;
  }
  getKillRefundMs(): number{
    this.pruneExpired(Date.now());
    return this.activeByCategory.get('meta')?.def.id === 'temporal_refund' ? 500 : 0;
  }
  hasPatch(id: PatchId): boolean{ return this.active.has(id); }
}

