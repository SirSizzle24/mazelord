shader_type canvas_item;
// Draws a flat picture (here, a tray's card stack, rendered offscreen) as if it lay on a surface seen in
// perspective: the picture's corners land on four given points, and everything between follows, with the
// far end narrower, as a camera would see it. A straight stretch or tilt can't do that.
// to_picture turns a spot on this node (0 to 1 across, 0 to 1 down) into a spot on the picture; it's
// worked out in deck_spot.gd from the four corners. Outside the picture, nothing is drawn.

uniform sampler2D picture : filter_linear, repeat_disable;
uniform mat3 to_picture;

void fragment() {
	vec3 p = to_picture * vec3(UV, 1.0);
	vec2 at = p.xy / p.z;
	if (p.z <= 0.0 || at.x < 0.0 || at.x > 1.0 || at.y < 0.0 || at.y > 1.0) {
		discard;
	}
	COLOR = texture(picture, at);
}
