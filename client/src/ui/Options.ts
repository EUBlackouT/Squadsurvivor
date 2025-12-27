export interface OptionsState { shake: boolean; }

const KEY = 'pb_options_v1';

export function loadOptions(): OptionsState{
  try{ const raw = localStorage.getItem(KEY); if(!raw) return { shake: true }; const o = JSON.parse(raw); return { shake: !!o.shake }; }catch{ return { shake: true }; }
}

export function saveOptions(o: OptionsState){ try{ localStorage.setItem(KEY, JSON.stringify(o)); }catch{} }

