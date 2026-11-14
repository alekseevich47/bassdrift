shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float strength : hint_range(0.0, 1.0) = 0.42;
uniform float speed : hint_range(0.0, 1.6) = 0.4;
uniform vec4 edge_color : source_color = vec4(0.01, 0.012, 0.02, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(0.82, 1.08));
	float vig = smoothstep(0.28, 0.78, d);
	vig *= strength * (0.55 + speed * 0.85);
	float lines = sin((uv.y + 0.5) * 180.0 - TIME * (8.0 + 28.0 * speed)) * 0.5 + 0.5;
	float side = smoothstep(0.18, 0.48, abs(uv.x));
	vig += side * lines * speed * 0.18;
	COLOR = vec4(edge_color.rgb, clamp(vig, 0.0, 0.82));
}
