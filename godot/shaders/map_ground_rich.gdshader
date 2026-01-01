shader_type canvas_item;

// Rich but readable procedural ground. No external textures, easy to remove later.
uniform vec4 u_base_color : source_color = vec4(0.08, 0.10, 0.12, 1.0);
uniform vec4 u_alt_color  : source_color = vec4(0.12, 0.13, 0.16, 1.0);
uniform vec4 u_accent_color : source_color = vec4(0.18, 0.22, 0.18, 1.0); // mossy tint

uniform float u_scale = 0.020;          // world->noise scale
uniform float u_detail_scale = 0.092;   // smaller features
uniform float u_crack_strength : hint_range(0.0, 2.0) = 1.05;
uniform float u_grit_strength : hint_range(0.0, 2.0) = 0.85;
uniform float u_vignette : hint_range(0.0, 1.0) = 0.40;

uniform vec2 u_world_origin = vec2(0.0, 0.0);
uniform vec2 u_world_size = vec2(1280.0, 720.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.02;
		a *= 0.55;
	}
	return s;
}

float crack_field(vec2 p) {
	float n1 = vnoise(p);
	float n2 = vnoise(p + vec2(17.0, 9.0));
	float r = abs(n1 - n2);
	return smoothstep(0.12, 0.42, r);
}

void fragment() {
	vec2 p = u_world_origin + UV * u_world_size;

	float n = fbm(p * u_scale);
	float n2 = fbm((p + vec2(200.0, 80.0)) * (u_scale * 1.7));

	// Subtle block hint (kept mild to avoid "tileset" look)
	vec2 g = p * (u_scale * 80.0);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float edge = smoothstep(0.0, 0.08, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	float cell_jitter = hash21(cell);
	float blocks = mix(0.85, 1.08, cell_jitter) * edge;

	float cracks = crack_field(p * u_detail_scale) * u_crack_strength;
	float grit = (vnoise(p * (u_detail_scale * 2.4)) - 0.5) * u_grit_strength;

	vec3 col = mix(u_base_color.rgb, u_alt_color.rgb, clamp(n * 1.2, 0.0, 1.0));
	col = mix(col, u_accent_color.rgb, clamp(n2 * 0.8, 0.0, 1.0) * 0.35);

	col *= (1.0 - cracks * 0.22);
	col += grit * 0.08;
	col *= blocks;

	// Vignette
	vec2 uv = UV * 2.0 - 1.0;
	float v = 1.0 - smoothstep(0.55, 1.25, length(uv));
	col = mix(col, col * 0.72, u_vignette * (1.0 - v));

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
