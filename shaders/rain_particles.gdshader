shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float density : hint_range(0.0, 1.0) = 0.0;
uniform float slant = 0.18;
uniform vec4 drop_color : source_color = vec4(0.72, 0.8, 0.88, 0.55);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	if (density <= 0.001) {
		COLOR = vec4(0.0);
	} else {
	uv.x += uv.y * slant;
	float columns = mix(80.0, 170.0, density);
	float col = floor(uv.x * columns);
	float n = hash(vec2(col, 3.7));
	float x = fract(uv.x * columns);
	float width = smoothstep(0.06 + n * 0.05, 0.0, abs(x - 0.5));
	float speed = 0.45 + n * 1.35;
	float fall = fract(uv.y * mix(9.0, 20.0, n) - TIME * speed + n * 5.0);
	float streak = smoothstep(0.28, 0.0, fall);
	float gate = step(n, mix(0.35, 1.0, density));
	float mist = hash(floor(uv * vec2(18.0, 10.0) + TIME * vec2(0.2, 0.8)));
	mist = smoothstep(0.72, 1.0, mist);
	float alpha = (streak * width * gate + mist * 0.35) * drop_color.a * density;
	COLOR = vec4(drop_color.rgb, clamp(alpha, 0.0, 0.85));
	}
}
