shader_type canvas_item;

uniform float bass_energy : hint_range(0.0, 1.0) = 0.0;
uniform vec4 grid_color : source_color = vec4(0.0, 0.55, 0.75, 0.35);
uniform float line_width : hint_range(0.001, 0.05) = 0.008;
uniform float cell_scale : hint_range(4.0, 64.0) = 18.0;
uniform float scroll_y = 0.0;
uniform float vanishing = 0.55;

void fragment() {
	vec2 uv = UV;
	// Pseudo-perspective floor grid
	float persp = mix(1.0, vanishing, uv.y);
	vec2 guv = vec2(uv.x - 0.5, uv.y);
	guv.x /= max(persp, 0.15);
	guv.y = (1.0 - uv.y) * cell_scale + scroll_y;
	guv.x = guv.x * cell_scale * 0.65;

	vec2 f = abs(fract(guv) - 0.5);
	float line = 1.0 - smoothstep(0.0, line_width + bass_energy * 0.01, min(f.x, f.y));
	float fade = smoothstep(0.05, 0.85, uv.y);
	float pulse = 0.55 + bass_energy * 0.85;
	vec3 col = grid_color.rgb * line * fade * pulse;
	float alpha = line * fade * grid_color.a * (0.4 + bass_energy * 0.6);
	COLOR = vec4(col, alpha);
}
