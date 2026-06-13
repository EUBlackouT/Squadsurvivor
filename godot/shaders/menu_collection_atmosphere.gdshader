shader_type canvas_item;

// Edge-only rim light + ember sparks — center stays clear so the map shows through.
uniform vec4 tint = vec4(0.55, 0.32, 0.22, 0.45);
uniform float time = 0.0;
uniform float spark_strength = 0.85;

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - vec2(0.5);
	float dist = length(c);

	// Only paint the rim — no grey wash over the middle.
	float rim = smoothstep(0.38, 0.92, dist);
	rim *= smoothstep(0.98, 0.62, dist);

	vec2 g_uv = floor(uv * vec2(480.0, 270.0));
	float spark_field = fract(sin(dot(g_uv * 1.9 + vec2(time * 0.4, time * 0.27), vec2(127.1, 311.7))) * 43758.5453);
	float spark = step(0.993, spark_field) * rim * spark_strength;

	vec3 glow = tint.rgb * rim * tint.a;
	vec3 col = glow + vec3(1.0, 0.58, 0.22) * spark;

	float alpha = clamp(rim * tint.a * 0.85 + spark * 0.35, 0.0, 0.62);
	COLOR = vec4(col, alpha);
}
