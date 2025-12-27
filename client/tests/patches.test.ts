import { PatchesManager } from '../src/systems/PatchesManager';

test('rarity overrides recency in conflict resolver', ()=>{
  const pm = new PatchesManager();
  // merge_surge (U) should override packet_loss (C) in weapons category when added later
  (pm as any).addPatchById('packet_loss', 10_000);
  (pm as any).addPatchById('merge_surge', 10_000);
  expect(pm.getFireInterval(200, true)).toBeLessThan(200);
});

test('edge_wrap enables bullet wrap', ()=>{
  const pm = new PatchesManager();
  (pm as any).addPatchById('edge_wrap', 10_000);
  expect(pm.shouldWrapBullets()).toBe(true);
});

test('ttl expires patches', ()=>{
  const pm = new PatchesManager();
  (pm as any).addPatchById('edge_wrap', 1); // very short ttl
  pm.tick(Date.now()+5_000);
  expect(pm.shouldWrapBullets()).toBe(false);
});

