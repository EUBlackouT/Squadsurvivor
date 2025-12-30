shader_type canvas_item;

// Soft drifting fog overlay. Keep it subtle; it's just a richness layer.
uniform vec4 u_fog_color : source_color = vec4(0.55, 0.70, 0.80, 1.0);
uniform float u_strength : hint_range(0.0, 1.0) = 0.16;
uniform float u_scale = 0.012;
uniform float u_speed = 0.035;

uniform vec2 u_world_origin = vec2(0.0, 0.0);
uniform vec2 u_world_size = vec2(1280.0, 720.0);
uniform float u_time = 0.0;

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
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p *= 2.01;
		a *= 0.55;
	}
	return s;
}

void fragment() {
	vec2 p = u_world_origin + UV * u_world_size;

	// Drift in two directions to avoid obvious scrolling.
	vec2 drift = vec2(u_time * 120.0 * u_speed, -u_time * 80.0 * u_speed);
	vec2 drift2 = vec2(-u_time * 60.0 * u_speed, u_time * 140.0 * u_speed);

	float n = fbm((p + drift) * u_scale);
	float n2 = fbm((p + drift2 + vec2(900.0, 200.0)) * (u_scale * 1.35));
	float fog = smoothstep(0.35, 0.85, (n * 0.65 + n2 * 0.35));

	// Keep center slightly clearer for readability.
	vec2 uv = UV * 2.0 - 1.0;
	float center_clear = smoothstep(0.0, 0.85, length(uv));
	fog *= mix(0.55, 1.0, center_clear);

	float a = clamp(fog * u_strength, 0.0, 1.0);
	COLOR = vec4(u_fog_color.rgb, a);
}


