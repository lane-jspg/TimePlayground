shader_type canvas_item;

// The uploaded SVG has slightly irregular transparent outer edges. Repeat only
// its opaque interior, keeping the source artwork and the floor's tint intact.
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	vec2 inset = 8.0 * TEXTURE_PIXEL_SIZE;
	vec2 tiled_uv = mix(inset, vec2(1.0) - inset, fract(UV));
	COLOR = texture(TEXTURE, tiled_uv) * item_tint;
}
