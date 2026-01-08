shader_type canvas_item;

// Fullscreen "sci-fi frame" + spacey backdrop for the main menu.
// No textures required: SDF frame, corner brackets, subtle nebula noise, and cyan edge glow.

uniform vec4 space_a : source_color = vec4(0.03, 0.05, 0.08, 1.0);
uniform vec4 space_b : source_color = vec4(0.08, 0.10, 0.14, 1.0);
uniform vec4 accent  : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float vignette = 0.55;
uniform float grain = 0.06;

uniform float frame_thickness = 0.050;   // UV thickness
uniform float inner_thickness = 0.010;   // inner stroke
uniform float corner_size = 0.16;        // bracket size
uniform float glow = 1.0;

float hash(vec2 p) {
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

float rect_sdf(vec2 p, vec2 b) {
	// Signed distance to a rectangle centered at origin with half-size b.
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float ring(vec2 p, vec2 b, float w) {
	float d = rect_sdf(p, b);
	return 1.0 - smoothstep(0.0, w, abs(d));
}

float corner_brackets(vec2 uv) {
	// Draw thin "L" brackets at each corner.
	vec2 p = uv * 2.0 - 1.0;
	vec2 ap = abs(p);
	float in_corner = step(1.0 - corner_size, ap.x) * step(1.0 - corner_size, ap.y);
	if (in_corner <= 0.0) return 0.0;

	// Local corner space 0..1
	vec2 c = (ap - (1.0 - corner_size)) / max(0.0001, corner_size);
	// Two thin lines: one horizontal, one vertical
	float lw = 0.06;
	float h = 1.0 - smoothstep(0.0, lw, c.y);
	float v = 1.0 - smoothstep(0.0, lw, c.x);
	// Carve a notch so it feels like a bracket
	float notch = smoothstep(0.35, 0.55, c.x) * smoothstep(0.35, 0.55, c.y);
	return max(h, v) * (1.0 - 0.75 * notch);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;

	// Space gradient + subtle nebula
	vec4 col = mix(space_a, space_b, smoothstep(0.0, 1.0, uv.y));
	float n1 = noise(uv * 3.5 + vec2(t * 0.03, -t * 0.02));
	float n2 = noise(uv * 10.0 + vec2(-t * 0.05, t * 0.04));
	float neb = pow(n1 * 0.65 + n2 * 0.35, 2.2);
	col.rgb += accent.rgb * 0.18 * neb;

	// Frame rings
	vec2 p = uv * 2.0 - 1.0;
	float outer = ring(p, vec2(1.0, 1.0), frame_thickness);
	float inner = ring(p, vec2(0.90, 0.90), inner_thickness);

	// Corner brackets
	float br = corner_brackets(uv);

	// Edge glow intensity
	float edge = clamp(outer * 0.9 + inner * 0.6 + br * 0.9, 0.0, 1.0);
	float pulse = 0.80 + 0.20 * sin(t * 1.2 * 6.283);
	col.rgb += accent.rgb * edge * (0.55 * glow) * pulse;

	// Darken just inside the frame to create depth
	float inset = smoothstep(0.78, 0.95, max(abs(p.x), abs(p.y)));
	col.rgb *= 1.0 - 0.22 * inset;

	// Vignette
	vec2 q = uv - 0.5;
	float v = smoothstep(0.75, 0.20, dot(q, q));
	col.rgb *= mix(1.0 - vignette, 1.0, v);

	// Grain/scratches
	float g = noise(uv * 420.0 + vec2(t * 0.2, -t * 0.13));
	col.rgb += (g - 0.5) * grain;

	COLOR = col;
}






