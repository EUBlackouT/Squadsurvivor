shader_type canvas_item;

// Sub-pixel smooth Ken Burns pan for menu map previews.
uniform vec2 pan = vec2(0.0, 0.0);
uniform float zoom = 1.05;
uniform vec2 tex_size = vec2(1280.0, 720.0);
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform float vignette_strength = 0.12;
uniform float brightness = 1.14;
uniform float saturation = 1.18;

vec2 cover_uv(vec2 screen_uv) {
	if (tex_size.x <= 1.0 || tex_size.y <= 1.0 || rect_size.x <= 1.0 || rect_size.y <= 1.0) {
		return screen_uv;
	}
	float tex_aspect = tex_size.x / tex_size.y;
	float view_aspect = rect_size.x / rect_size.y;
	vec2 uv = screen_uv;
	if (tex_aspect > view_aspect) {
		float fit = view_aspect / tex_aspect;
		uv.x = (screen_uv.x - 0.5) * fit / zoom + 0.5 + pan.x;
		uv.y = (screen_uv.y - 0.5) / zoom + 0.5 + pan.y;
	} else {
		float fit = tex_aspect / view_aspect;
		uv.y = (screen_uv.y - 0.5) * fit / zoom + 0.5 + pan.y;
		uv.x = (screen_uv.x - 0.5) / zoom + 0.5 + pan.x;
	}
	return uv;
}

void fragment() {
	vec2 uv = clamp(cover_uv(UV), vec2(0.001), vec2(0.999));
	vec4 col = texture(TEXTURE, uv);
	float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(vec3(lum), col.rgb, saturation) * brightness;
	float d = distance(UV, vec2(0.5));
	col.rgb *= 1.0 - vignette_strength * smoothstep(0.25, 0.95, d);
	COLOR = col;
}
