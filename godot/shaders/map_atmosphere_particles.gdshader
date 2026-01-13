shader_type canvas_item;

// Procedural atmosphere overlay (no textures): motes / embers / wisps.
// Designed to be subtle and readable, not noisy.
//
// Style:
// 0 = motes (arcane dust)
// 1 = embers (foundry)
// 2 = wisps (graveyard)
uniform float u_style : hint_range(0.0, 2.0) = 0.0;

uniform vec4 u_color : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float u_strength : hint_range(0.0, 1.0) = 0.22;
uniform float u_density : hint_range(0.0, 2.0) = 1.0;
uniform float u_scale : hint_range(0.002, 0.05) = 0.010;
uniform float u_speed : hint_range(0.0, 2.0) = 0.35;
uniform float u_time = 0.0;

uniform vec2 u_world_origin = vec2(0.0, 0.0);
uniform vec2 u_world_size = vec2(1280.0, 720.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

// Soft circular particle
float circ(vec2 p, float r) {
	return smoothstep(r, 0.0, length(p));
}

// Cheap value noise
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 wp = u_world_origin + UV * u_world_size;

	// Parallax drift
	vec2 drift = vec2(u_time * 140.0 * u_speed, -u_time * 90.0 * u_speed);
	if (u_style > 1.5) { // wisps feel slower + floatier
		drift = vec2(sin(u_time * 0.7) * 120.0, cos(u_time * 0.6) * 90.0);
	}
	vec2 p = (wp + drift) * u_scale;

	// Grid of candidate particles
	float dens = max(0.001, u_density);
	vec2 g = p * (38.0 * dens);
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5;

	float h = hash21(cell);
	// Sparsity (most cells empty)
	float gate = smoothstep(0.85, 1.0, h);

	// Particle center jitter in cell
	vec2 j = vec2(hash21(cell + 11.3), hash21(cell + 47.7)) - 0.5;
	vec2 pp = f - j * 0.75;

	// Size + softness varies per style
	float base_r = 0.075;
	float glow = 1.0;
	if (u_style < 0.5) { // motes: tiny, twinkly
		base_r = mix(0.035, 0.070, hash21(cell + 19.1));
		glow = 0.8 + 0.6 * vnoise(p * 2.1 + cell * 0.03 + u_time * 0.9);
	} else if (u_style < 1.5) { // embers: larger + streak-ish upward
		base_r = mix(0.050, 0.105, hash21(cell + 23.7));
		pp.y += (hash21(cell + 3.2) - 0.5) * 0.35;
		pp.x *= 0.7;
		glow = 0.9 + 0.7 * vnoise(p * 1.4 + u_time * 1.2);
	} else { // wisps: soft blobs, low frequency
		base_r = mix(0.090, 0.160, hash21(cell + 5.6));
		glow = 0.7 + 0.6 * vnoise(p * 0.7 + u_time * 0.25);
	}

	float a = circ(pp, base_r) * gate * glow;

	// Reduce center clutter: keep middle clearer
	vec2 uv = UV * 2.0 - 1.0;
	float center = smoothstep(0.15, 1.05, length(uv));
	a *= mix(0.35, 1.0, center);

	// Final alpha
	float alpha = clamp(a * u_strength * 0.55, 0.0, 1.0);
	COLOR = vec4(u_color.rgb, alpha);
}





