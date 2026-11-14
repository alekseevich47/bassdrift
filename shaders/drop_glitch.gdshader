shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time_scale = 1.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * time_scale;
	float n = fract(sin(dot(uv * 40.0 + t, vec2(12.9898, 78.233))) * 43758.5453);
	float slice = step(0.92, fract(uv.y * 28.0 + t * 3.0)) * intensity;
	float shift = (n - 0.5) * 0.012 * intensity + slice * 0.02;

	float r = texture(screen_texture, uv + vec2(shift, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(shift, 0.0)).b;

	vec3 col = vec3(r, g, b);
	// Magenta/cyan fringe boost on drops
	col.r += intensity * 0.04;
	col.b += intensity * 0.03;
	COLOR = vec4(col, 1.0);
}
