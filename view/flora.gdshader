// Спрайты флоры из одного атласа-полосы (FloraView).
// INSTANCE_CUSTOM.x — номер спрайта в полосе, INSTANCE_CUSTOM.y — яркость.
shader_type canvas_item;

uniform float slots = 6.0;
varying float shade;

void vertex() {
	UV.x = (UV.x + INSTANCE_CUSTOM.x) / slots;
	shade = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb * shade, c.a);
}
