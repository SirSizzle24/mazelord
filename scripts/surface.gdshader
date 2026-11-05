shader_type canvas_item;
// Surface texturing for ground, fog and walls. The tiles' own colors stay (lit or remembered, deposit,
// mark, face shading); this multiplies in texture detail looked up by WORLD position, so it flows across
// tile edges with no seams. Tops (and the ground) sample the top texture; wall faces sample the face
// texture along the wall's length and up its height, so a long wall's face is continuous.
// A large-scale variation texture breaks up the repetition of the smaller ones.

uniform bool use_mask = false;  // walls: a mask says which pixels are top or face; ground: all top
uniform sampler2D mask_tex : filter_nearest;
uniform sampler2D top_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D face_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D macro_tex : repeat_enable, filter_linear_mipmap;
uniform float top_scale = 512.0;  // world pixels per repeat of the top texture
uniform float face_scale = 256.0;  // world pixels along a wall per repeat of the face texture
uniform float macro_scale = 3000.0;  // world pixels per repeat of the variation texture
uniform float detail_strength = 0.3;  // how strongly the textures change the base colors
uniform float macro_strength = 0.15;
uniform float ridge_highlight = 0.12;  // extra light along the top edge of faces

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float detail = texture(top_tex, world / top_scale).r;
	float ridge = 0.0;
	if (use_mask) {
		vec4 part = texture(mask_tex, UV);
		if (part.r < 0.5) {
			// A face. Distance along the wall runs down-right for a lower-left face and down-left for a
			// lower-right one; the mask's blue is the height up the face.
			vec2 along = part.g < 0.5 ? vec2(0.7071, 0.7071) : vec2(-0.7071, 0.7071);
			float u = dot(world, along) / face_scale;
			detail = texture(face_tex, vec2(u, part.b * 0.25)).r;
			ridge = smoothstep(0.85, 1.0, part.b);
		}
	}
	float macro = texture(macro_tex, world / macro_scale).r;
	vec3 color = base.rgb * (1.0 - detail_strength / 2.0 + detail_strength * detail);
	color *= 1.0 - macro_strength / 2.0 + macro_strength * macro;
	color += ridge * ridge_highlight;
	COLOR = vec4(color, base.a);
}
