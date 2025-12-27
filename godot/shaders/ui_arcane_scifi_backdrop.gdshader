shader_type canvas_item;

// Animated arcane sci-fi backdrop for UI modals.

uniform vec4 base_a : source_color = vec4(0.08, 0.09, 0.11, 1.0);
uniform vec4 base_b : source_color = vec4(0.12, 0.14, 0.18, 1.0);
uniform vec4 glow_color : source_color = vec4(0.35, 0.85, 1.0, 1.0);

uniform float scanline_strength = 0.10;
uniform float noise_strength = 0.07;
uniform float band_strength = 0.20;
uniform float band_speed = 0.40;

float hash(vec2 p) {
	// Cheap 2D hash
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;

	// Vertical gradient.
	vec4 col = mix(base_a, base_b, smoothstep(0.0, 1.0, uv.y));

	// Scanlines.
	float sl = sin((uv.y * 720.0) + t * 18.0) * 0.5 + 0.5;
	col.rgb *= 1.0 - scanline_strength * (0.25 + 0.75 * sl);

	// Energy bands.
	float band = sin((uv.x * 6.0) + (uv.y * 3.0) + t * (band_speed * 6.283)) * 0.5 + 0.5;
	float band2 = sin((uv.x * 11.0) - (uv.y * 2.0) + t * (band_speed * 4.1)) * 0.5 + 0.5;
	float g = pow(band, 5.0) + 0.6 * pow(band2, 6.0);
	col.rgb += glow_color.rgb * (band_strength * g);

	// Subtle noise.
	float n = noise(uv * 220.0 + vec2(t * 0.2, -t * 0.13));
	col.rgb += (n - 0.5) * noise_strength;

	COLOR = col;
}


