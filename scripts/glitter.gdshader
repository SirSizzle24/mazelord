shader_type canvas_item;
render_mode blend_add;
// Now and then, a coin catches the light: a small four-pointed glint appears, swells and fades. The
// area is cut into a grid; each cell rolls a die every so often, and only a few win, so glints are rare
// and never in step. glint_mask (the coins' shape, cut from the painting) keeps them on the gold.

uniform sampler2D glint_mask : filter_linear;
uniform vec2 cells = vec2(9.0, 7.0);  // grid across and down
uniform float chance = 0.06;  // share of cells that glint in each round
uniform float rounds_per_second = 0.7;
uniform vec3 glint_color : source_color = vec3(1.0, 0.92, 0.65);
uniform float strength = 1.3;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 grid = UV * cells;
	vec2 cell = floor(grid);
	float offset = hash(cell) * 10.0;  // each cell keeps its own clock, so glints never line up
	float clock = TIME * rounds_per_second + offset;
	float round_number = floor(clock);
	float light = 0.0;
	if (hash(cell + round_number * 7.31) < chance) {
		float life = sin(fract(clock) * 3.14159);  // swells then fades within its round
		vec2 spot = vec2(hash(cell + round_number), hash(cell - round_number)) * 0.6 + 0.2;
		vec2 p = (fract(grid) - spot) * vec2(1.0, cells.x / cells.y);
		float ray_x = smoothstep(0.05, 0.0, abs(p.y)) * smoothstep(0.4 * life, 0.0, abs(p.x));
		float ray_y = smoothstep(0.05, 0.0, abs(p.x)) * smoothstep(0.4 * life, 0.0, abs(p.y));
		float core = smoothstep(0.12 * life, 0.0, length(p));
		float on_gold = texture(glint_mask, (cell + spot) / cells).a;  // only where a coin is
		light = (ray_x + ray_y + core) * life * on_gold;
	}
	light *= strength;
	COLOR = vec4(glint_color * light, clamp(light, 0.0, 1.0));
}
