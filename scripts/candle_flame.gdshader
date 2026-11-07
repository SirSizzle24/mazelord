shader_type canvas_item;
render_mode blend_add;
// A candle flame, drawn by math (no art): a teardrop that sways and stretches with slow noise, white-gold
// at its heart and orange at its edge. Put it on a ColorRect sitting on the wick, taller than wide.

uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.75);
uniform vec3 edge_color : source_color = vec3(1.0, 0.55, 0.15);
uniform float sway = 0.18;  // how far the tip wanders sideways
uniform float speed = 1.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {
	float i = floor(x);
	return mix(hash(i), hash(i + 1.0), smoothstep(0.0, 1.0, fract(x)));
}

void fragment() {
	float t = TIME * speed;
	float up = 1.0 - UV.y;  // 0 at the wick, 1 at the top of the rect
	float height = 0.8 + 0.2 * noise(t * 6.0 + 2.0);  // the flame stretches and shrinks
	float across = UV.x - 0.5 - (noise(t * 2.5) - 0.5) * sway * up * up;  // the tip sways most
	// The teardrop's half-width at this height: round at the bottom, tapering to a point at the top.
	float shape = clamp(up / height, 0.0, 1.0);
	float half_width = 0.42 * pow(1.0 - shape, 0.7) * smoothstep(0.0, 0.18, shape + 0.04);
	float edge = abs(across) / max(half_width, 0.0001);
	float alpha = smoothstep(1.0, 0.55, edge) * step(up, height);
	float heart = smoothstep(0.7, 0.0, edge) * smoothstep(0.75, 0.1, shape);
	vec3 color = mix(edge_color, core_color, heart);
	COLOR = vec4(color * alpha, alpha);
}
