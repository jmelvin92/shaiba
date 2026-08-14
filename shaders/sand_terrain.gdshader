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

float sand_cap(float depth_alpha) {
	return min(depth_alpha * deform_cap_scale, 1.0);
}

varying vec2 deform_uv;

bool in_region(vec2 uv) {
	return uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0;
}

void vertex() {
	vec2 world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	deform_uv = (world_xz - deform_origin) / deform_size;
	if (deform_strength > 0.0 && in_region(deform_uv)) {
		float pressed = min(textureLod(deformation_map, deform_uv, 0.0).r, 1.0);
		VERTEX.y -= pressed * deform_strength * sand_cap(COLOR.a);
	}
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	if (deform_strength > 0.0 && in_region(deform_uv)) {
		// Sampled per-pixel, not per-vertex: the darkened compacted-sand tint
		// is what draws the crisp print shape at the gameplay camera — the
		// vertex dip underneath is soft at 1 m mesh resolution.
		float pressed = min(texture(deformation_map, deform_uv).r, 1.0);
		float press_show = pressed * deform_tint_strength * sand_cap(COLOR.a);
		albedo *= mix(vec3(1.0), deform_tint, press_show);
	}
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
}
