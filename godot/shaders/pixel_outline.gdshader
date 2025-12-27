shader_type canvas_item;

// Simple pixel outline for sprites.
// Works best for crisp pixel art (nearest filter).

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_px = 1.0; // 1-2 recommended

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float inside = step(0.01, c.a);

	// Sample neighbors for alpha.
	vec2 px = TEXTURE_PIXEL_SIZE * outline_px;
	float a = 0.0;
	a = max(a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(px.x, px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-px.x, px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(px.x, -px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-px.x, -px.y)).a);

	float edge = step(0.01, a) * (1.0 - inside);
	vec4 out_col = vec4(outline_color.rgb, outline_color.a) * edge;
	COLOR = mix(out_col, c, inside);
}


