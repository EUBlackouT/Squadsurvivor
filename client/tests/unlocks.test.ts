import { loadUnlocks, saveUnlocks, notifyKill, notifyRoomCleared, notifyBossDefeated, computeUnlockedWeapons, grantBlueprint, filterPatchesByBlueprints, notifyCouncilCompleted, type StorageLike } from '../src/systems/Unlocks';

function makeMemoryStorage(): StorageLike {
  const map = new Map<string, string>();
  return {
    getItem: (k: string) => map.has(k) ? map.get(k)! : null,
    setItem: (k: string, v: string) => { map.set(k, v); },
    removeItem: (k: string) => { map.delete(k); }
  };
}

describe('Unlocks', () => {
  test('defaults include Threadneedle', () => {
    const s = makeMemoryStorage();
    const u = loadUnlocks(s);
    expect(u.unlockedWeapons).toContain('Threadneedle');
  });

  test('kills unlock Garbage Collector', () => {
    const s = makeMemoryStorage();
    const u = loadUnlocks(s);
    const newly = notifyKill(u, 20);
    expect(newly).toContain('Garbage Collector');
    saveUnlocks(u, s);
    const filtered = computeUnlockedWeapons(['Threadneedle','Refactor Harpoon','Garbage Collector','Shader Scepter'], s);
    expect(filtered).toContain('Garbage Collector');
  });

  test('room clear unlocks Harpoon', () => {
    const s = makeMemoryStorage();
    const u = loadUnlocks(s);
    // Now Harpoon is via council completions; room clear alone should not unlock
    const newly = notifyRoomCleared(u);
    expect(newly).not.toContain('Refactor Harpoon');
  });
  test('council completion unlocks Harpoon after 2 councils', () => {
    const s = makeMemoryStorage();
    const u = loadUnlocks(s);
    expect(notifyCouncilCompleted(u)).toHaveLength(0);
    const newly2 = notifyCouncilCompleted(u);
    expect(newly2).toContain('Refactor Harpoon');
  });

  test('boss defeat unlocks Shader Scepter', () => {
    const s = makeMemoryStorage();
    const u = loadUnlocks(s);
    const newly = notifyBossDefeated(u);
    expect(newly).toContain('Shader Scepter');
  });

  test('blueprint-gated patches filter correctly', () => {
    const s = makeMemoryStorage();
    const u = loadUnlocks(s);
    const pool = [
      { id: 'a', name: 'A', requiresBlueprint: false },
      { id: 'b', name: 'B', requiresBlueprint: true }
    ];
    const none = filterPatchesByBlueprints(pool, s);
    expect(none.find(p=>p.id==='b')).toBeUndefined();
    grantBlueprint(u, 'b');
    saveUnlocks(u, s);
    const yes = filterPatchesByBlueprints(pool, s);
    expect(yes.find(p=>p.id==='b')?.id).toBe('b');
  });
});


