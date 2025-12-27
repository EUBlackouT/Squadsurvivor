import fs from "node:fs";
import path from "node:path";

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function weightedPick(rng, items) {
  let total = 0;
  for (const it of items) total += it.w;
  let r = rng() * total;
  for (const it of items) {
    r -= it.w;
    if (r <= 0) return it.id;
  }
  return items[0].id;
}

// Deterministic rng
function mulberry32(seed) {
  let t = seed >>> 0;
  return function () {
    t += 0x6d2b79f5;
    let x = t;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

const root = path.resolve(process.cwd(), "..");
const balancePath = path.join(root, "godot", "data", "unit_balance.json");
const balance = readJson(balancePath);

const runs = Number(process.argv.includes("--runs") ? process.argv[process.argv.indexOf("--runs") + 1] : 60);
const minutes = Number(process.argv.includes("--minutes") ? process.argv[process.argv.indexOf("--minutes") + 1] : 12);
const dt = 0.25;

function build(context, rng, elapsedMinutes) {
  const rarities = balance.rarities.map((r) => {
    const w0 = r.weight?.[context] ?? 1;
    let bonus = 0;
    if (context === "recruit") {
      if (r.id === "rare") bonus = Math.floor(elapsedMinutes * 0.4);
      else if (r.id === "epic") bonus = Math.floor(elapsedMinutes * 0.2);
      else if (r.id === "legendary") bonus = Math.floor(elapsedMinutes * 0.08);
    }
    return { id: r.id, w: Math.max(1, w0 + bonus), r };
  });
  const rarityId = weightedPick(rng, rarities);
  const rarity = balance.rarities.find((r) => r.id === rarityId) ?? balance.rarities[0];
  const arch = balance.archetypes[Math.floor(rng() * balance.archetypes.length)];
  const base = arch.base;

  let hp = base.max_hp;
  let dmg = base.attack_damage;
  let cd = base.attack_cooldown;
  let range = base.attack_range;

  const ctx = balance.context_stat_mult?.[context] ?? {};
  hp *= ctx.max_hp ?? 1.0;
  dmg *= ctx.attack_damage ?? 1.0;

  const mult = rarity.stat_mult ?? {};
  hp *= mult.max_hp ?? 1.0;
  dmg *= mult.attack_damage ?? 1.0;

  if (context === "enemy") {
    const sc = balance.enemy_scaling ?? {};
    hp *= 1 + (sc.hp_per_minute_mult ?? 0) * elapsedMinutes;
    dmg *= 1 + (sc.damage_per_minute_mult ?? 0) * elapsedMinutes;
  }

  // attack style roll
  const melee = rng() < 0.38;
  if (melee) {
    range = Math.min(220, Math.max(80, range * 0.55));
    dmg *= 1.22;
    cd *= 0.9;
    hp *= 1.12;
  } else {
    range = Math.min(680, Math.max(240, range * 1.05));
  }

  return {
    rarity: rarityId,
    archetype: arch.id,
    melee,
    hp: Math.round(hp),
    dmg: Math.round(dmg),
    cd: Math.max(0.15, cd),
    range,
  };
}

function simOne(seed) {
  const rng = mulberry32(seed);
  // 3 squad units
  const squad = [build("recruit", rng, 0), build("recruit", rng, 0), build("recruit", rng, 0)];
  let t = 0;
  let elapsed = 0;
  let enemies = [];
  let spawnT = 0;
  let kills = 0;

  const maxAlive = 90;
  const spawnInterval = 1.15;
  const spawnBurst = 1;

  // simplistic: squad dps = sum(dmg/cd). enemies hp pool vs squad dps.
  const squadDps = squad.reduce((a, u) => a + u.dmg / u.cd, 0);

  while (t < minutes * 60) {
    elapsed = t / 60;
    spawnT += dt;
    if (spawnT >= spawnInterval) {
      spawnT = 0;
      for (let i = 0; i < spawnBurst; i++) {
        if (enemies.length >= maxAlive) break;
        enemies.push(build("enemy", rng, elapsed));
      }
    }

    // damage enemies
    let dmgThisTick = squadDps * dt;
    while (dmgThisTick > 0 && enemies.length > 0) {
      const e = enemies[0];
      if (e.hp <= dmgThisTick) {
        dmgThisTick -= e.hp;
        enemies.shift();
        kills++;
      } else {
        e.hp -= dmgThisTick;
        dmgThisTick = 0;
      }
    }

    // crude overwhelm check: if enemies too many too early, mark fail
    if (t < 120 && enemies.length > 80) return { ok: false, reason: "swarm_early", kills, enemies: enemies.length };

    t += dt;
  }
  return { ok: true, kills, enemies: enemies.length, squadDps: Number(squadDps.toFixed(1)) };
}

let ok = 0;
let fail = 0;
const reasons = {};
let avgKills = 0;
for (let i = 0; i < runs; i++) {
  const r = simOne(1337 + i * 17);
  avgKills += r.kills;
  if (r.ok) ok++;
  else {
    fail++;
    reasons[r.reason] = (reasons[r.reason] ?? 0) + 1;
  }
}
avgKills /= runs;

console.log(JSON.stringify({ runs, minutes, ok, fail, reasons, avgKills: Number(avgKills.toFixed(1)) }, null, 2));


