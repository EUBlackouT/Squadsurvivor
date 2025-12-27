export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface UnlocksState {
  version: number;
  unlockedWeapons: string[];
  stats: {
    killsTotal: number;
    roomsClearedTotal: number;
    bossesDefeatedTotal: number;
    councilsCompletedTotal?: number;
    shotsAbsorbedTotal?: number;
    syncKillsTotal?: number;
    bossTokens?: number;
  };
  blueprints?: string[]; // ids of patches/weapons unlocked via rare drops
}

const STORAGE_KEY = 'pb_unlocks_v1';

const DEFAULT_STATE: UnlocksState = {
  version: 1,
  unlockedWeapons: ['Threadneedle'],
  stats: { killsTotal: 0, roomsClearedTotal: 0, bossesDefeatedTotal: 0, councilsCompletedTotal: 0, shotsAbsorbedTotal: 0, syncKillsTotal: 0, bossTokens: 0 },
  blueprints: []
};

export function loadUnlocks(storage?: StorageLike): UnlocksState {
  const s = storage || (typeof window !== 'undefined' ? (window.localStorage as unknown as StorageLike) : undefined);
  try{
    const raw = s?.getItem(STORAGE_KEY);
    if(!raw) return { ...DEFAULT_STATE };
    const parsed = JSON.parse(raw) as UnlocksState;
    // Ensure at least default
    if(!parsed.unlockedWeapons?.includes('Threadneedle')) parsed.unlockedWeapons = ['Threadneedle', ...(parsed.unlockedWeapons||[])];
    return parsed;
  }catch{
    return { ...DEFAULT_STATE };
  }
}

export function saveUnlocks(state: UnlocksState, storage?: StorageLike): void {
  const s = storage || (typeof window !== 'undefined' ? (window.localStorage as unknown as StorageLike) : undefined);
  try{ s?.setItem(STORAGE_KEY, JSON.stringify(state)); }catch{}
}

export function hasWeaponUnlocked(name: string, storage?: StorageLike): boolean {
  const st = loadUnlocks(storage);
  return st.unlockedWeapons.includes(name);
}

export function computeUnlockedWeapons(allWeapons: string[], storage?: StorageLike): string[] {
  const st = loadUnlocks(storage);
  // Always ensure base weapon is present
  if(!st.unlockedWeapons.includes('Threadneedle')) st.unlockedWeapons.unshift('Threadneedle');
  return allWeapons.filter(w => st.unlockedWeapons.includes(w));
}

export function unlockWeapon(state: UnlocksState, name: string): boolean {
  if(state.unlockedWeapons.includes(name)) return false;
  state.unlockedWeapons.push(name);
  return true;
}

export function notifyRoomCleared(state: UnlocksState): string[] {
  state.stats.roomsClearedTotal += 1;
  const newly: string[] = [];
  return newly;
}

export function notifyKill(state: UnlocksState, count: number = 1): string[] {
  state.stats.killsTotal += Math.max(0, count);
  const newly: string[] = [];
  if(state.stats.killsTotal >= 20){ if(unlockWeapon(state, 'Garbage Collector')) newly.push('Garbage Collector'); }
  return newly;
}

export function notifyBossDefeated(state: UnlocksState): string[] {
  state.stats.bossesDefeatedTotal += 1;
  state.stats.bossTokens = (state.stats.bossTokens||0) + 1;
  const newly: string[] = [];
  if(state.stats.bossesDefeatedTotal >= 1){ if(unlockWeapon(state, 'Shader Scepter')) newly.push('Shader Scepter'); }
  return newly;
}

export function notifyCouncilCompleted(state: UnlocksState): string[] {
  state.stats.councilsCompletedTotal = (state.stats.councilsCompletedTotal||0) + 1;
  const newly: string[] = [];
  if((state.stats.councilsCompletedTotal||0) >= 2){ if(unlockWeapon(state, 'Refactor Harpoon')) newly.push('Refactor Harpoon'); }
  return newly;
}

export function grantBlueprint(state: UnlocksState, id: string): boolean {
  state.blueprints = state.blueprints || [];
  if(state.blueprints.includes(id)) return false;
  state.blueprints.push(id);
  return true;
}

export function hasBlueprint(state: UnlocksState, id: string): boolean {
  return !!state.blueprints && state.blueprints.includes(id);
}

export function filterPatchesByBlueprints<T extends { id: string; requiresBlueprint?: boolean }>(
  pool: T[],
  storage?: StorageLike
): T[] {
  const st = loadUnlocks(storage);
  return pool.filter(p => !p.requiresBlueprint || (st.blueprints||[]).includes(p.id));
}



