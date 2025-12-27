// Leonardo API refs:
// - Overview: https://leonardo.ai/api/
// - Create generation: https://docs.leonardo.ai/reference/creategeneration
// - Get generation: https://docs.leonardo.ai/reference/getgenerationbyid
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import fetch from 'node-fetch';

const API_KEY = process.env.LEONARDO_API_KEY;
if (!API_KEY) {
	console.log('[AI] Leonardo key missing; skipping');
	process.exit(0);
}

const OUT = (...p) => path.join('client', 'assets', 'ai_ready', ...p);
fs.mkdirSync(OUT('tiles'), { recursive: true });
fs.mkdirSync(OUT('ui'), { recursive: true });

async function createGeneration(prompt, width = 512, height = 512, modelId = process.env.LEONARDO_MODEL_ID) {
	const res = await fetch('https://cloud.leonardo.ai/api/rest/v1/generations', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${API_KEY}` },
		body: JSON.stringify({ prompt, width, height, modelId })
	});
	if (!res.ok) throw new Error(`Leonardo create failed: ${res.status} ${await res.text()}`);
	const data = await res.json();
	return data?.sdGenerationJob?.generationId || data?.generationId;
}

async function getGeneration(id) {
	const res = await fetch(`https://cloud.leonardo.ai/api/rest/v1/generations/${id}`, {
		headers: { Authorization: `Bearer ${API_KEY}` }
	});
	if (!res.ok) throw new Error(`Leonardo get failed: ${res.status} ${await res.text()}`);
	return res.json();
}

async function main() {
	// Tileset
	const tilesPrompt =
		'Pixel art tileset, 32x32, "Deprecated Dungeon" biome, corroded metal floors, warning stripes, server racks, patch beacons, cable trenches, 8x8 grid spritesheet, seamless tiling, consistent palette (cool gray + neon teal/purple), transparent PNG.';
	try {
		const id = await createGeneration(tilesPrompt, 512, 512);
		console.log('[AI] Leonardo tiles job:', id);
		let done = false,
			tries = 0,
			data;
		while (!done && tries++ < 30) {
			await new Promise((r) => setTimeout(r, 4000));
			data = await getGeneration(id);
			done = !!data?.generations_by_pk?.generated_images?.length;
		}
		const img = data?.generations_by_pk?.generated_images?.[0];
		if (img?.url) {
			const png = await fetch(img.url).then((r) => r.arrayBuffer());
			fs.writeFileSync(OUT('tiles', 'tilesheet.png'), Buffer.from(png));
			console.log('[AI] Leonardo tiles saved');
		}
	} catch (e) {
		console.warn('[AI] Leonardo tiles failed:', e.message);
	}

	// UI icons
	const uiPrompt =
		'Pixel art UI icons, 16x16, high readability: patch, council pad, beacon, merge window, sync meter, shard, shop, boss skull, pause, settings. Transparent PNG, 2px outer border.';
	try {
		const id = await createGeneration(uiPrompt, 256, 128);
		console.log('[AI] Leonardo ui job:', id);
		let done = false,
			tries = 0,
			data;
		while (!done && tries++ < 30) {
			await new Promise((r) => setTimeout(r, 4000));
			data = await getGeneration(id);
			done = !!data?.generations_by_pk?.generated_images?.length;
		}
		const img = data?.generations_by_pk?.generated_images?.[0];
		if (img?.url) {
			const png = await fetch(img.url).then((r) => r.arrayBuffer());
			fs.writeFileSync(OUT('ui', 'icons.png'), Buffer.from(png));
			console.log('[AI] Leonardo ui saved');
		}
	} catch (e) {
		console.warn('[AI] Leonardo ui failed:', e.message);
	}
}

main();
