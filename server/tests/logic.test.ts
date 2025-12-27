import { applyEntangledDamage, shouldDie, nextRoomIndex, isBossRoom, pullToward, chaseStep, canPhase, hasPhaseClearance } from '../src/logic';

test('entangled damage reduces pool and kills at zero', ()=>{
  let p = { hp: 30, max: 30 };
  p = applyEntangledDamage(p, 10); expect(p.hp).toBe(20); expect(shouldDie(p)).toBe(false);
  p = applyEntangledDamage(p, 25); expect(p.hp).toBe(0); expect(shouldDie(p)).toBe(true);
});

test('nextRoomIndex increments by 1', ()=>{
  expect(nextRoomIndex(1)).toBe(2);
  expect(nextRoomIndex(5)).toBe(6);
});

test('boss room from 6 onward', ()=>{
  expect(isBossRoom(5)).toBe(false);
  expect(isBossRoom(6)).toBe(true);
  expect(isBossRoom(10)).toBe(true);
});

test('pullToward moves target closer to origin', ()=>{
  const p = pullToward({x:0,y:0},{x:10,y:0}, 5);
  expect(p.x).toBeGreaterThan(0);
  expect(p.x).toBeLessThan(10);
});

test('chaseStep moves toward target with max step', ()=>{
  const p = chaseStep({x:0,y:0},{x:10,y:0}, 3);
  expect(Math.round(p.x)).toBe(3);
});

test('canPhase respects cooldown window', ()=>{
  const cd = 1500;
  expect(canPhase(10_000, 8_500, cd)).toBe(true); // exactly cooldown elapsed
  expect(canPhase(9_900, 8_500, cd)).toBe(false); // still on cooldown
});

test('hasPhaseClearance blocks when enemy too close on target branch', ()=>{
  const p = { x: 0, y: 0, branch: 'A' as const };
  const enemies = [ { x: 10, y: 0, branch: 'B' as const }, { x: 100, y: 0, branch: 'A' as const } ];
  expect(hasPhaseClearance(p, enemies, 'B', 24)).toBe(false);
  expect(hasPhaseClearance(p, enemies, 'A', 24)).toBe(true);
});

