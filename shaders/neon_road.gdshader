shader_type canvas_item;

uniform vec4 color_deep : source_color = vec4(0.03, 0.02, 0.07, 1.0);
uniform vec4 color_magenta : source_color = vec4(0.72, 0.08, 0.36, 1.0);
uniform vec4 color_cyan : source_color = vec4(0.08, 0.45, 0.58, 1.0);
uniform float speed = 0.18;

void fragment() {
	vec2 uv = UV;
	float pulse = sin(uv.y * 10.0 - TIME * speed) * 0.5 + 0.5;
	float edge = smoothstep(0.15, 0.85, abs(uv.x - 0.5) * 2.0);
	vec3 col = mix(color_deep.rgb, color_magenta.rgb, uv.y * 0.85);
	col = mix(col, color_cyan.rgb, edge * pulse * 0.45);
	float lane = smoothstep(0.04, 0.0, abs(uv.x - 0.5));
	col += vec3(0.12, 0.35, 0.42) * lane * (0.35 + 0.25 * pulse);
	COLOR = vec4(col, 1.0);
}
