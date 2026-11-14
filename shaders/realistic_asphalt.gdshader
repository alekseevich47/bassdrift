shader_type canvas_item;

uniform vec4 asphalt_a : source_color = vec4(0.07, 0.07, 0.08, 1.0);
uniform vec4 asphalt_b : source_color = vec4(0.16, 0.15, 0.15, 1.0);
uniform vec4 line_color : source_color = vec4(0.86, 0.82, 0.68, 1.0);
uniform vec4 edge_color : source_color = vec4(0.78, 0.76, 0.7, 1.0);
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float puddle : hint_range(0.0, 1.0) = 0.0;
uniform float groove : hint_range(0.0, 1.0) = 0.75;
uniform float night : hint_range(0.0, 1.0) = 0.55;
uniform float wear : hint_range(0.0, 1.0) = 0.35;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
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

void fragment() {
	vec2 uv = UV;
	float grain = vnoise(uv * vec2(48.0, 220.0));
	float coarse = vnoise(uv * vec2(7.0, 18.0) + 4.0);
	vec3 col = mix(asphalt_a.rgb, asphalt_b.rgb, grain * 0.85 + coarse * 0.15);
	float lanes = abs(fract(uv.x * 14.0) - 0.5);
	float grooves = smoothstep(0.46, 0.5, lanes);
	col *= mix(1.0, 0.78, grooves * groove);
	float worn = smoothstep(0.15, 0.85, coarse) * wear;
	col = mix(col, col * vec3(1.08, 1.05, 0.98), worn * (0.35 + 0.4 * smoothstep(0.2, 0.8, uv.x)));
	float edge = smoothstep(0.055, 0.012, uv.x) + smoothstep(0.945, 0.988, uv.x);
	col = mix(col, edge_color.rgb, clamp(edge, 0.0, 1.0));
	float dash = step(0.52, fract(uv.y * 7.0));
	float center = smoothstep(0.018, 0.0, abs(uv.x - 0.5));
	col = mix(col, line_color.rgb, center * dash * 0.92);
	float side_line = smoothstep(0.012, 0.0, abs(uv.x - 0.08)) + smoothstep(0.012, 0.0, abs(uv.x - 0.92));
	col = mix(col, edge_color.rgb, clamp(side_line, 0.0, 1.0) * 0.85);
	float pool = vnoise(uv * vec2(5.5, 13.0) + vec2(2.0, 8.0));
	float puddles = smoothstep(0.62, 0.86, pool) * puddle;
	vec3 water = vec3(0.45, 0.5, 0.56);
	col = mix(col, water, puddles * (0.35 + wet * 0.45));
	col *= mix(1.0, 0.34, night);
	col += vec3(0.03, 0.045, 0.06) * wet * (1.0 - abs(uv.x - 0.5) * 1.4);
	NORMAL = vec3(0.0, 0.0, 1.0);
	COLOR = vec4(col, 1.0);
}
