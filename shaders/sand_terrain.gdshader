// Sand terrain surface. Albedo comes from per-vertex palette tones baked by
// the chunk builder; the faceted low-poly look comes from computing the
// normal per-pixel from screen-space derivatives, which makes every triangle
// a flat facet without duplicating vertices per face. Because the normal is
// derived from the rendered position, it stays correct for any vertex
// displacement — which is exactly what the footprint deformation below relies
// on: pressed vertices get correctly faceted lighting for free.
//
// COLOR.a carries normalised sand depth (0 = hard ground, 1 = deepest sand).
// It caps how far a footprint can press the surface down — plenty of sand
// takes a full print, a thin dusting a faint one, bare hard ground none.
//
// Deformation: SandDeformation (scenes/world/terrain/) accumulates stamps in
// a world-anchored texture covering deform_size metres from deform_origin and
// keeps these uniforms current. deform_strength = 0 (the default) makes the
// whole system inert — levels without a SandDeformation node never touch it.
shader_type spatial;

uniform sampler2D deformation_map : hint_default_black, filter_linear, repeat_disable;
uniform vec2 deform_origin = vec2(0.0);
uniform float deform_size = 1.0;
uniform float deform_strength = 0.0;
uniform float deform_tint_strength = 0.55;
// Raised sand (Phase 6.8): the deformation map's B channel lifts the surface
// instead of pressing it — the sand worm's traveling mound. Metres at full
// raise; 0 (the default) keeps the whole path inert, like deform_strength.
uniform float deform_raise = 0.0;
// B below this moves nothing: flat shading flips a whole 1 m facet's tone
// over a few centimetres of lift, so a nearly-settled mound must release the
// surface completely instead of leaving a facet-noise patchwork behind.
const float RAISE_FLOOR = 0.12;

float raise_of(float b) {
	// Soft saturation (x/(1+x)), never a hard clamp: overlapping wake stamps
	// sum well past 1, and clamping flat turned the mound into a mesa whose
	// edges the 1 m flat-shaded mesh drew as terraced cliffs.
	float x = max(b - RAISE_FLOOR, 0.0);
	return x / (1.0 + x);
}
// How strongly fully raised sand darkens toward the churned tint. Freshly
// heaved sand reads disturbed, not sun-bleached — same ratio as prints, its
// own strength.
uniform float deform_raise_tint = 0.35;
// Multiplicative darkening of a fully pressed print (linear-space colour
// ratio, sand_shadow / sand_light — set by SandDeformation). Multiplying
// instead of mixing toward a fixed colour keeps prints visible on every base
// tone: the colour ramp already paints thin sand nearly sand_shadow, where a
// mix toward sand_shadow would vanish.
uniform vec3 deform_tint = vec3(0.8);
// COLOR.a is normalised against the colour ramp's full depth (metres of sand
// where the tone maxes out), but a footprint is fully formed in far less
// sand. This rescales alpha so the cap saturates at print_full_depth instead:
// tone_full_depth / print_full_depth, kept current by SandDeformation.
uniform float deform_cap_scale = 1.0;

// Wind ripples: the fine parallel ridges wind combs into open sand. Purely a
// shading effect — an analytic asymmetric wave in the wind frame perturbs the
// facet normal (long lit windward slope, short shaded lee) and darkens the
// troughs slightly, so ripples catch the actual sun from any orbit angle.
// No vertex displacement, so collision and the footprint system are
// untouched, and the pattern stays crisp at any wavelength the 1 m mesh
// could never hold. Ripples fade out where the sand is thin (COLOR.a), on
// the pressed floor of footprints, and with camera distance (past ripple
// scale, they'd only alias). ripple_strength = 0 disables everything.
uniform vec2 ripple_wind_dir = vec2(1.0, 0.0);
uniform float ripple_strength = 0.0;
uniform float ripple_wavelength = 2.2;
uniform float ripple_trough_tint = 0.10;
// COLOR.a below which ripples are fully gone / above which fully formed.
uniform float ripple_alpha_fade_lo = 0.03;
uniform float ripple_alpha_fade_hi = 0.16;
// View distance, metres, where ripples finish fading out.
uniform float ripple_view_fade = 55.0;

float sand_cap(float depth_alpha) {
	return min(depth_alpha * deform_cap_scale, 1.0);
}

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

// Asymmetric ripple profile over one period: height in x, d(height)/d(phase)
// in y. Windward rise takes 0.68 of the period, lee fall the remaining 0.32.
vec2 ripple_wave(float phase) {
	const float crest = 0.68;
	float t = fract(phase);
	if (t < crest) {
		float s = t / crest;
		return vec2(s * s * (3.0 - 2.0 * s), 6.0 * s * (1.0 - s) / crest);
	}
	float s = (t - crest) / (1.0 - crest);
	return vec2(
		1.0 - s * s * (3.0 - 2.0 * s), -6.0 * s * (1.0 - s) / (1.0 - crest)
	);
}

varying vec2 deform_uv;
varying vec2 world_xz;

bool in_region(vec2 uv) {
	return uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0;
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	deform_uv = (world_xz - deform_origin) / deform_size;
	if ((deform_strength > 0.0 || deform_raise > 0.0) && in_region(deform_uv)) {
		vec3 marks = textureLod(deformation_map, deform_uv, 0.0).rgb;
		float pressed = min(marks.r, 1.0);
		float raised = raise_of(marks.b);
		// Both directions cap by the sand actually here: hard ground neither
		// takes a print nor heaves a mound — there is no sand to move.
		VERTEX.y += (raised * deform_raise - pressed * deform_strength)
			* sand_cap(COLOR.a);
	}
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	float pressed = 0.0;
	float raised = 0.0;
	if ((deform_strength > 0.0 || deform_raise > 0.0) && in_region(deform_uv)) {
		// Sampled per-pixel, not per-vertex: the darkened compacted-sand tint
		// is what draws the crisp print shape at the gameplay camera — the
		// vertex dip underneath is soft at 1 m mesh resolution. The mound's
		// churn tint rides the same ratio at its own strength.
		vec3 marks = texture(deformation_map, deform_uv).rgb;
		pressed = min(marks.r, 1.0);
		raised = raise_of(marks.b);
		float show = min(
			pressed * deform_tint_strength + raised * deform_raise_tint, 1.0
		) * sand_cap(COLOR.a);
		albedo *= mix(vec3(1.0), deform_tint, show);
	}
	vec3 normal = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	if (ripple_strength > 0.0) {
		vec2 wind = normalize(ripple_wind_dir);
		float along = dot(world_xz, wind);
		float across = dot(world_xz, vec2(-wind.y, wind.x));
		// Bend the crests so they read as wind-combed sand, not a grating: a
		// slow sine plus one octave of value noise, both across-wind. Warp is
		// kept under ~a wavelength — more and the ridges dissolve into mottle.
		float warp = sin(across * 0.15) * 0.8
			+ (value_noise(world_xz * 0.07) - 0.5) * 1.6;
		vec2 wave = ripple_wave((along + warp) / ripple_wavelength);
		// Ripples die on pressed print floors and on freshly churned mounds
		// alike — heaved sand has no wind-combed surface left.
		float fade = smoothstep(ripple_alpha_fade_lo, ripple_alpha_fade_hi, COLOR.a)
			* (1.0 - smoothstep(ripple_view_fade * 0.55, ripple_view_fade, length(VERTEX)))
			* (1.0 - max(pressed, raised));
		vec3 wind_view = mat3(VIEW_MATRIX) * vec3(wind.x, 0.0, wind.y);
		normal = normalize(
			normal - wind_view * (wave.y * ripple_strength / ripple_wavelength * fade)
		);
		// pow narrows the darkening to a thin line along the trough — real
		// ripples separate along crisp shadow lines, not wide dark bands.
		albedo *= 1.0 - ripple_trough_tint * pow(1.0 - wave.x, 1.7) * fade;
	}
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	NORMAL = normal;
}
