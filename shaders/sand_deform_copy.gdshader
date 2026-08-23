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
// Wet-sand decay class (Phase 6.7): G carries press × wetness, so G/R is how
// wet the print was when stamped. Wet prints decay at this fraction of the
// dry rate, and G scales with R so the class survives every pass unchanged.
uniform float wet_decay_scale = 0.3;
// Raised sand (Phase 6.8): B carries the sand worm's mound, which settles in
// seconds and decays by its own per-pass amount — NOT decay_amount scaled.
// The two clocks separate for float16 reasons: at high pass rates the print
// decay per pass falls below the texture's precision and must be applied in
// accumulated quanta (SandDeformation carries the remainder), while the
// mound's much larger per-pass decay stays continuous so its collapse never
// steps.
uniform float mound_decay_amount = 0.0;

void fragment() {
	vec2 uv = UV + uv_shift;
	vec3 carried = vec3(0.0);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		carried = texture(prev_map, uv).rgb;
	}
	float wet = carried.r > 0.0005 ? clamp(carried.g / carried.r, 0.0, 1.0) : 0.0;
	float pressed = max(carried.r - decay_amount * mix(1.0, wet_decay_scale, wet), 0.0);
	float raised = max(carried.b - mound_decay_amount, 0.0);
	COLOR = vec4(pressed, wet * pressed, raised, 1.0);
}
