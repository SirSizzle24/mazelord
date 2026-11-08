shader_type canvas_item;
// Recolors a baked troop sprite (or its card portrait) at draw time, so every troop can wear its own
// colors from one set of pictures. The bake gives two pictures with the same layout:
//   the color picture: the troop as rendered (a red cap with white spots, a tan body),
//   the mask (one gray channel): 255 = cap, 128 = body, 0 = leave alone (eyes, brows).
// On the cap and body, the picture's own light and shade are kept (its brightness, measured against
// the base color's usual brightness) and laid over the troop's chosen color. Spots are found on the cap
// as its pale, unsaturated pixels; the spot style decides what they become.
// The colors are per troop: each troop's sprite and portrait get their own copy of this material
// (troop_look.gd makes them). The pictures themselves are shared, so extra troops cost almost nothing.

uniform sampler2D mask : filter_nearest, repeat_disable;
uniform vec4 cap_color : source_color = vec4(0.71, 0.34, 0.32, 1.0);
uniform vec4 body_color : source_color = vec4(0.43, 0.40, 0.31, 1.0);
uniform vec4 spot_color : source_color = vec4(0.95, 0.92, 0.88, 1.0);
uniform float spot_amount : hint_range(0.0, 1.0) = 1.0;  // 0: spots take the cap's color (no spots)
uniform float spot_glow : hint_range(0.0, 2.0) = 0.0;  // extra light the spots give off
uniform float glow_seconds = 3.0;  // one slow pulse of the glow
uniform float glow_phase = 0.0;  // so glowing troops don't all pulse together
// The baked colors' usual brightness: a pixel this bright gets exactly the chosen color.
uniform float cap_reference = 0.45;
uniform float body_reference = 0.40;
uniform float spot_reference = 0.85;

varying vec4 tint;  // the node's modulate (a downed troop is drawn darker, say)

void vertex() {
	tint = COLOR;
}

float brightness(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec4 picture = texture(TEXTURE, UV);
	float region = texture(mask, UV).r;
	vec3 rgb = picture.rgb;
	float light = brightness(picture.rgb);
	if (region > 0.75) {
		// Cap. A spot is pale (little color) and bright.
		float high = max(max(rgb.r, rgb.g), rgb.b);
		float low = min(min(rgb.r, rgb.g), rgb.b);
		float saturation = high > 0.0 ? (high - low) / high : 0.0;
		float spot = smoothstep(0.42, 0.22, saturation) * smoothstep(0.4, 0.6, high);
		// Shade each part against its own usual brightness, so a spot with no style just takes the
		// cap's color at the cap's shading, and vanishes.
		float shade = mix(light / cap_reference, light / spot_reference, spot);
		vec3 base = mix(cap_color.rgb, spot_color.rgb, spot * spot_amount);
		rgb = base * shade;
		float pulse = 0.65 + 0.35 * sin(TAU * (TIME / glow_seconds + glow_phase));
		rgb += spot_color.rgb * spot * spot_glow * pulse;
	} else if (region > 0.25) {
		rgb = body_color.rgb * (light / body_reference);
	}
	COLOR = vec4(min(rgb, vec3(1.0)), picture.a) * tint;
}
