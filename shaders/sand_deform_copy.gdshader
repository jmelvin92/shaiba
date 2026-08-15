// The deformation texture's "carry forward" pass. Each update renders the
// previous accumulation into the other viewport of a ping-pong pair through
// this shader: shifted by however far the region was recentred (whole texels
// only, so the copy is exact and repeated shifts cannot blur old prints) and
// reduced by the decay accumulated since the last pass — which is what makes
// footprints slowly fill back in. New stamps draw additively on top of the
// ColorRect running this shader.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D prev_map : hint_default_black, filter_nearest, repeat_disable;
uniform vec2 uv_shift = vec2(0.0);
uniform float decay_amount = 0.0;

void fragment() {
	vec2 uv = UV + uv_shift;
	float carried = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		carried = texture(prev_map, uv).r;
	}
	COLOR = vec4(max(carried - decay_amount, 0.0), 0.0, 0.0, 1.0);
}
