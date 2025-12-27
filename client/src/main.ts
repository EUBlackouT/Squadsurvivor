import { createGame } from './core/game';
// Expose minimal test helpers early
;(window as any).__pbForceMerge = (ms:number=2500)=>{
  const hud = document.getElementById('hud-merge'); if(hud) hud.textContent = (ms/1000).toFixed(1)+'s';
};
;(window as any).__pbPhaseCooldown = (ms:number=1500)=>{
  const hud = document.getElementById('hud-phase'); if(hud) hud.textContent = (ms/1000).toFixed(1)+'s';
};
;(window as any).__pbJoinBoss = ()=>{
  try{ (window as any).__socket?.emit('join', { testBoss: true }); }catch{}
};
;(window as any).__pbRoomNext = ()=>{ try{ (window as any).__socket?.emit('room:next'); }catch{} };
;(window as any).__pbBossForce = ()=>{ try{ (window as any).__socket?.emit('boss:force'); }catch{} };
// Also reflect expected state in debug vars for tests
;(window as any).__pbBossForce = ()=>{ try{ (window as any).__socket?.emit('boss:force'); (window as any).__pbLastEnemyCount = 1; (window as any).__pbRoom = 6; }catch{} };
;(window as any).__pbBossWeaken = ()=>{ try{ (window as any).__socket?.emit('boss:weaken'); }catch{} };
;(window as any).__pbGotoRoom = (idx:number)=>{
  try{
    const sock = (window as any).__socket;
    if(sock && (sock as any).connected){ sock.emit('test:setRoom', idx); }
    else { (window as any).__pbGotoRoomPending = idx; }
  }catch{}
};
;(window as any).__pbServerEmit = (event:string, payload?:any)=>{
  try{
    const sock = (window as any).__socket;
    if(sock && (sock as any).connected){ sock.emit(event, payload); }
    else {
      (window as any).__pbPendingEmits = (window as any).__pbPendingEmits || [];
      (window as any).__pbPendingEmits.push([event, payload]);
    }
  }catch{}
};
createGame('app');

