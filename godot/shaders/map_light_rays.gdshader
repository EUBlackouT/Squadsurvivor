shader_type canvas_item;

// Subtle diagonal light rays / wash for depth.
// Intentionally mild (should never fight gameplay readability).
uniform vec4 u_color : source_color = vec4(0.80, 0.92, 1.00, 1.0);
uniform float u_strength : hint_range(0.0, 1.0) = 0.14;
uniform float u_time = 0.0;
uniform float u_speed : hint_range(0.0, 2.0) = 0.25;
uniform float u_scale : hint_range(0.2, 4.0) = 1.0;

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
		p *= 2.01;
		a *= 0.55;
	}
	return s;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;

	// Diagonal ray coordinates.
	vec2 ruv = vec2(uv.x * 0.65 + uv.y * 0.95, -uv.x * 0.95 + uv.y * 0.65);
	ruv *= u_scale;

	float t = u_time * u_speed;
	float band = sin((ruv.x + t) * 6.0) * 0.5 + 0.5;
	float noise = fbm(ruv * 1.6 + vec2(t * 0.35, -t * 0.22));

	float rays = smoothstep(0.55, 0.92, band) * smoothstep(0.35, 0.85, noise);

	// Fade edges; keep center readable.
	float edge = smoothstep(1.25, 0.15, length(uv));
	float alpha = clamp(rays * edge * u_strength, 0.0, 1.0);
	COLOR = vec4(u_color.rgb, alpha);
}


