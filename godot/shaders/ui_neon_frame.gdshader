shader_type canvas_item;

// Neon frame glow for Panel/PanelContainer via CanvasItem material.
// Draws a soft border glow around the rect.

uniform vec4 base_color : source_color = vec4(0.12, 0.17, 0.21, 1.0);
uniform vec4 glow_color : source_color = vec4(0.25, 0.80, 0.82, 0.55);
uniform float glow_width = 0.018;     // UV space (~0.01-0.04)
uniform float glow_strength = 0.85;
uniform float pulse_speed = 0.9;

float rect_sdf(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv * 2.0 - 1.0; // -1..1
	// Signed distance to a unit rectangle
	float d = rect_sdf(p, vec2(1.0, 1.0));

	// Convert distance to edge intensity
	float edge = 1.0 - smoothstep(0.0, glow_width, abs(d));
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed * 6.283);

	vec4 col = base_color;
	col.rgb += glow_color.rgb * edge * glow_color.a * glow_strength * pulse;

	COLOR = col;
}


