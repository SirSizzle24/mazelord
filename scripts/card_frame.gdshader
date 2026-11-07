shader_type canvas_item;
// The card frame's rank. The frame's gold veins are picked out by their color: the marble around them is
// nearly gray, the gold is strongly colored, so saturation tells them apart with no hand-painted mask.
//   tier 0, unnamed: the gold turns to dull bronze.
//   tier 1, named:   the gold as painted.
//   tier 2, hero:    the gold glows, breathing slowly, and its light spills a little past the veins
//                    (including onto the portrait's edge, through the frame's open window).
// The glow's spill reads a blurred copy of the frame from its mipmaps, so the frame texture needs
// Mipmaps on in its import settings, and the node's texture filter set to use them.

uniform int tier = 1;

// Picking out the gold: how saturated a pixel must be to start and to fully count as gold.
uniform float gold_from = 0.25;
uniform float gold_to = 0.45;

// Bronze: the gold's color is pulled toward gray, tinted, and darkened.
uniform vec3 bronze_tint : source_color = vec3(0.75, 0.55, 0.42);
uniform float bronze_saturation : hint_range(0.0, 1.0) = 0.3;
uniform float bronze_brightness : hint_range(0.0, 1.5) = 0.80;

// Hero glow.
uniform vec3 glow_color : source_color = vec3(1.0, 0.82, 0.45);
uniform float glow_strength : hint_range(0.0, 2.0) = 0.6;
uniform float spill_strength : hint_range(0.0, 2.0) = 0.9;  // light past the veins, from the blurred copy
uniform float spill_blur : hint_range(0.0, 6.0) = 4.5;  // which mipmap level to read: higher spreads wider
uniform float breath_seconds = 3.5;  // one slow pulse
uniform float breath_depth : hint_range(0.0, 1.0) = 0.8;  // how much the glow dims between pulses (1 = fully out)

float gold_amount(vec4 c) {
	float high = max(c.r, max(c.g, c.b));
	float low = min(c.r, min(c.g, c.b));
	float saturation = (high - low) / max(high, 0.0001);
	return smoothstep(gold_from, gold_to, saturation) * c.a;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float gold = gold_amount(c);
	vec3 color = c.rgb;
	float alpha = c.a;
	if (tier == 0) {
		float gray = dot(color, vec3(0.299, 0.587, 0.114));
		vec3 bronze = mix(vec3(gray), color, bronze_saturation) * bronze_tint * 1.6 * bronze_brightness;
		color = mix(color, bronze, gold);
	} else if (tier == 2) {
		float breath = 1.0 - breath_depth * (0.5 + 0.5 * cos(TIME * 6.2832 / breath_seconds));
		color += glow_color * gold * glow_strength * breath;
		// The spill: gold nearby, blurred, as soft light. Where the frame is see-through (the window),
		// this is all there is, so it shows as light falling on the portrait's edge.
		float nearby = gold_amount(textureLod(TEXTURE, UV, spill_blur));
		float spill = nearby * spill_strength * breath;
		color += glow_color * spill * alpha;
		vec3 lit = mix(glow_color, color, alpha);
		alpha = max(alpha, spill * 0.8);
		color = lit;
	}
	COLOR = vec4(color, alpha);
}
