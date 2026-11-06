shader_type canvas_item;
// Surface texturing for ground, fog and walls. The tiles' own colors stay (lit or remembered, deposit,
// mark, face shading); this multiplies in texture detail looked up by WORLD position, so it flows across
// tile edges with no seams. Tops (and the ground) sample the top texture; wall faces sample the face
// texture along the wall's length and up its height, so a long wall's face is continuous.
// A large-scale variation texture breaks up the repetition of the smaller ones.

uniform bool use_mask = false;  // walls: a mask says which pixels are top or face; ground: all top
uniform bool top_alpha = false;  // mycelium: the top texture's own transparency lets the floor show through
// Mycelium's soft border. cover_tex has one pixel per cell: red where there's mycelium, green where
// it's the rival's. The rival's is turned toward red by rotating its hue.
uniform bool use_cover = false;
uniform sampler2D cover_tex : filter_linear;
uniform float rival_hue = 1.25;  // radians of hue turn for the rival's mycelium: about 70 degrees, purple to red
uniform float rival_saturation = 2.2;  // the purple is muted, so a plain turn gives brown; this makes it red
uniform sampler2D mask_tex : filter_nearest;
uniform sampler2D top_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D face_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D macro_tex : repeat_enable, filter_linear_mipmap;
// Scales are world pixels per repeat. A 2048 texture over 1024 world pixels = 2 texture pixels per world
// pixel, so 128 per 64-pixel cell: sharp even at the camera's 2x zoom.
uniform float top_scale = 1024.0;  // world pixels per repeat of the floor and wall-top textures
uniform float face_scale = 1024.0;  // world pixels along a wall per repeat of the face texture
uniform float face_height = 48.0;  // must match WALL_FACE_HEIGHT in fog.gd, to keep the same density
uniform float macro_scale = 3000.0;  // world pixels per repeat of the variation texture
uniform float macro_strength = 0.15;  // how much brightness drifts across big areas
uniform float hue_strength = 0.04;  // how much the color drifts warmer or cooler across big areas
uniform float ridge_highlight = 0.12;  // extra light along the top edge of faces

// Smooth fog edges. vis_tex has one pixel per cell, white where a troop can see; read with linear
// filtering, it blends between neighboring cells, giving a smooth value from 1 (in sight) to 0.
uniform int fog_mode = 0;  // 0: no fog effect; 1: the flat fog, fading out where visible; 2: walls, dimming where not
uniform sampler2D vis_tex : filter_linear;
uniform vec2 grid_cells = vec2(180.0, 180.0);  // the grid's size in cells
uniform float cell_size = 64.0;  // a cell's width in pixels
uniform float memory_brightness = 0.45;  // how bright remembered walls are, compared with lit ones

// Cell lines, for digging and building. Ground and fog only (walls never get them).
uniform bool show_lines = false;
uniform float line_darken = 0.35;  // how much darker a line is than the ground under it

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Rotates a 2D point; used to sample a second, turned copy of a texture.
vec2 turn(vec2 p, float angle) {
	return vec2(p.x * cos(angle) - p.y * sin(angle), p.x * sin(angle) + p.y * cos(angle));
}

// Reads a texture twice, at different scales and turns, and blends between the two copies by a slow
// noise. Wherever you look it's a different mix, so the repeat never lines up the same way twice.
vec4 blended(sampler2D tex, vec2 p, vec2 at) {
	vec4 first = texture(tex, p);
	vec4 second = texture(tex, turn(p, 0.6) * 0.73 + vec2(0.31, 0.77));
	float mix_amount = smoothstep(0.35, 0.65, texture(macro_tex, at / (macro_scale * 0.6) + vec2(0.5)).r);
	return mix(first, second, mix_amount);
}

// How visible a world position is, from 0 to 1, by turning it back into grid coordinates (the reverse
// of tile_to_screen) and reading the visibility image there.
float visibility(vec2 at) {
	vec2 scaled = at / (cell_size * 0.5);
	vec2 cell = vec2(scaled.x + scaled.y, scaled.y - scaled.x) * 0.5;
	return smoothstep(0.0, 1.0, texture(vis_tex, (cell + vec2(0.5)) / grid_cells).r);
}

// How much of a cell line is here, from 0 to 1. Lines stay about one screen pixel wide at any zoom,
// and fade out when zoomed so far out that cells are only a few pixels across.
float cell_lines(vec2 at) {
	vec2 scaled = at / (cell_size * 0.5);
	vec2 cell = vec2(scaled.x + scaled.y, scaled.y - scaled.x) * 0.5 + vec2(0.5);  // edges at whole numbers
	vec2 to_edge = abs(fract(cell + 0.5) - 0.5);  // distance to the nearest edge, in cells
	vec2 per_pixel = max(fwidth(cell), vec2(0.00001));  // how many cells one screen pixel spans
	vec2 pixels = to_edge / per_pixel;  // distance to the nearest edge, in screen pixels
	float line = 1.0 - smoothstep(0.5, 1.5, min(pixels.x, pixels.y));
	float fade = 1.0 - smoothstep(0.08, 0.2, max(per_pixel.x, per_pixel.y));
	return line * fade;
}

// How much mycelium shows here, from 0 to 1. Four smooth readings of the cover image, half a cell apart,
// averaged: the fade runs from the middle of the last mycelium cell (0.75) through the border (0.5) and
// the middle of the next cell (0.25) to that cell's far edge (0).
// Returns x: how much mycelium, y: how much of it is the rival's (both 0 to 1, faded the same way).
vec2 coverage(vec2 at) {
	vec2 scaled = at / (cell_size * 0.5);
	vec2 cell = vec2(scaled.x + scaled.y, scaled.y - scaled.x) * 0.5 + vec2(0.5);
	vec2 total = vec2(0.0);
	total += texture(cover_tex, (cell + vec2(-0.5, -0.5)) / grid_cells).rg;
	total += texture(cover_tex, (cell + vec2(0.5, -0.5)) / grid_cells).rg;
	total += texture(cover_tex, (cell + vec2(-0.5, 0.5)) / grid_cells).rg;
	total += texture(cover_tex, (cell + vec2(0.5, 0.5)) / grid_cells).rg;
	return total / 4.0;
}

// Turns a color's hue by angle radians, keeping its brightness: a rotation around the gray axis.
vec3 hue_turn(vec3 c, float angle) {
	const vec3 gray = vec3(0.57735);
	return c * cos(angle) + cross(gray, c) * sin(angle) + gray * dot(gray, c) * (1.0 - cos(angle));
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);  // the tile's tint: white, a gray for memory or shading, or a hue
	vec4 surface = blended(top_tex, world / top_scale, world);
	float ridge = 0.0;
	if (use_mask) {
		vec4 part = texture(mask_tex, UV);
		if (part.r < 0.5) {
			// A face. Distance along the wall runs down-right for a lower-left face and down-left for a
			// lower-right one; the mask's blue is the height up the face, at the same density.
			vec2 along = part.g < 0.5 ? vec2(0.7071, 0.7071) : vec2(-0.7071, 0.7071);
			float u = dot(world, along) / face_scale;
			surface = blended(face_tex, vec2(u, part.b * face_height / face_scale), world);
			ridge = smoothstep(0.85, 1.0, part.b);
		}
	}
	// Slow drifts across the map: brightness, and a touch warmer or cooler, from two different
	// readings of the variation texture.
	float bright = texture(macro_tex, world / macro_scale).r;
	float warm = texture(macro_tex, world / (macro_scale * 1.9) + vec2(0.23, 0.61)).r;
	vec3 color = base.rgb * surface.rgb;
	vec2 cover = vec2(1.0, 0.0);
	if (use_cover) {
		cover = coverage(world);
		vec3 turned = hue_turn(color, rival_hue);
		float average = (turned.r + turned.g + turned.b) / 3.0;
		turned = clamp(vec3(average) + (turned - vec3(average)) * rival_saturation, 0.0, 1.0);
		color = mix(color, turned, cover.y / max(cover.x, 0.0001));
	}
	color *= 1.0 - macro_strength / 2.0 + macro_strength * bright;
	color *= vec3(1.0) + hue_strength * (warm - 0.5) * vec3(2.0, 0.0, -2.0);
	color += ridge * ridge_highlight;
	if (show_lines && !use_mask) {
		color *= 1.0 - line_darken * cell_lines(world);
	}
	float alpha = base.a;
	if (top_alpha) {
		alpha *= surface.a;
	}
	if (use_cover) {
		alpha *= cover.x;
	}
	if (fog_mode == 1) {
		alpha *= 1.0 - visibility(world);  // the flat fog fades away where troops can see
	} else if (fog_mode == 2) {
		color *= mix(memory_brightness, 1.0, visibility(world));  // walls dim smoothly out of sight
	}
	COLOR = vec4(color, alpha);
}
