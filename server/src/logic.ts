export interface Pool { hp: number; max: number }

export function applyEntangledDamage(pool: Pool, dmg: number): Pool {
  const hp = Math.max(0, pool.hp - Math.max(0, dmg));
  return { hp, max: pool.max };
}

export function shouldDie(pool: Pool): boolean { return pool.hp <= 0; }

export function nextRoomIndex(current: number): number { return current + 1; }

export function isBossRoom(roomIndex: number): boolean {
  return roomIndex >= 6;
}

export function pullToward(target:{x:number;y:number}, origin:{x:number;y:number}, strength:number){
  const dx = origin.x - target.x; const dy = origin.y - target.y; const len = Math.hypot(dx,dy) || 1;
  return { x: target.x + (dx/len)*strength, y: target.y + (dy/len)*strength };
}

export function chaseStep(target:{x:number;y:number}, toward:{x:number;y:number}, maxStep:number){
  const dx = toward.x - target.x; const dy = toward.y - target.y; const dist = Math.hypot(dx,dy);
  if(dist <= maxStep) return { x: toward.x, y: toward.y };
  const nx = dx / (dist || 1); const ny = dy / (dist || 1);
  return { x: target.x + nx*maxStep, y: target.y + ny*maxStep };
}

export function canPhase(nowMs:number, lastPhaseAtMs:number, cooldownMs:number){
  return nowMs - lastPhaseAtMs >= cooldownMs;
}

export function hasPhaseClearance(
  player:{x:number;y:number;branch:'A'|'B'},
  enemies:Array<{x:number;y:number;branch:'A'|'B'}>,
  targetBranch:'A'|'B',
  minDistance:number
){
  for(const e of enemies){
    if(e.branch !== targetBranch) continue;
    const dx = e.x - player.x; const dy = e.y - player.y;
    if(Math.hypot(dx,dy) < minDistance) return false;
  }
  return true;
}

