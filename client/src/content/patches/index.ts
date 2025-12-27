import edge_wrap from './edge_wrap.json';
import clock_skips from './clock_skips.json';
import merge_surge from './merge_surge.json';
import loot_multithread from './loot_multithread.json';
import nimble_ai from './nimble_ai.json';
import branch_bias from './branch_bias.json';
import topology_lock from './topology_lock.json';
import packet_loss from './packet_loss.json';
import rapid_reload from './rapid_reload.json';
import piercing_rounds from './piercing_rounds.json';
import phase_battery from './phase_battery.json';
import overclock from './overclock.json';
import ricochet_protocol from './ricochet_protocol.json';
import homing_jit from './homing_jit.json';
import entropy_burst from './entropy_burst.json';
import phase_blink from './phase_blink.json';
import temporal_refund from './temporal_refund.json';
import split_threads from './split_threads.json';
import branch_overload from './branch_overload.json';
import council_parallel from './council_parallel.json';
import phase_afterimage from './phase_afterimage.json';
import monolith_debug from './monolith_debug.json';
import sawtooth_barrel from './sawtooth_barrel.json';
import smart_missile from './smart_missile.json';
import quantum_drill from './quantum_drill.json';
import glacial_shards from './glacial_shards.json';

export type PatchId = string;
export interface PatchDef { id: PatchId; name: string; rarity: 'R'|'L'|'E'|'U'|'C'|string; description: string; requiresBlueprint?: boolean; }
export const PATCH_POOL: PatchDef[] = [edge_wrap, clock_skips, merge_surge, loot_multithread, nimble_ai, branch_bias, topology_lock, packet_loss, rapid_reload, piercing_rounds, phase_battery, overclock, ricochet_protocol, homing_jit, entropy_burst, phase_blink, temporal_refund, split_threads, branch_overload, council_parallel, phase_afterimage, monolith_debug, sawtooth_barrel, smart_missile, quantum_drill, glacial_shards];

