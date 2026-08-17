// The sea surface (Phase 6.7). One large plane at sea level, following the
// player; everything below is real seabed terrain, and this shader draws the
// water over it in the game's language: flat facets, palette colors.
//
// - Waves are a sum of three world-space directional sines travelling toward
//   the shore (the coast always lies west, so the swell runs +X). They are
//   visual only — the analytic sea level never moves — and they fade out with
//   distance so the far water never shimmers against the fog.
// - Color and opacity come from the *optical thickness* of the water: the
//   depth buffer gives the view-space depth of the seabed behind each
//   fragment, and the difference to the water fragment's own depth is how
//   much water the eye looks through. Thin water is clear turquoise showing
//   the pale seabed; thick water saturates to the deep tone. No terrain data
//   reaches the shader — the depth buffer already knows.
// - Foam is two parts: contact foam where the water thins to nothing (the
//   waterline and anything poking through), and rolling foam lines that ride
//   bands of equal thickness toward the shore — reading as waves coming in,
//   again without knowing where the shore is.
// - The faceted look comes from screen-space-derivative normals exactly like
//   sand_terrain.gdshader; low roughness on those flat facets is what makes
//   the golden-hour sun break into sparkle.
//
// Palette: shallow = oasis_teal, deep = night_blue, foam = plaster. The
// exact tint values are Joshua's to ladder; these are the palette defaults.
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.373, 0.659, 0.627);
uniform vec3 deep_color : source_color = vec3(0.204, 0.271, 0.369);
uniform vec3 foam_color : source_color = vec3(0.949, 0.906, 0.812);

// Peak amplitude of the wave sum, metres. Must stay under the clearance
// between sea level and the lowest inland desert hollow (see TerrainSettings
// sea_level) so a crest can never lap into a dry basin.
uniform float wave_amplitude = 0.09;
uniform float wave_speed = 0.9;
// Direction the swell travels (toward the shore). The coast lies west, so
// waves run +X; the Ocean node keeps this pointed sensibly.
uniform vec2 swell_dir = vec2(1.0, 0.0);
// View distance, metres, over which the vertex waves fade to a calm plane.
uniform float wave_fade_start = 150.0;
uniform float wave_fade_end = 290.0;

// Optical thickness, metres along the view ray, at which the water color has
// mostly saturated toward deep_color / full opacity.
uniform float murk_depth = 4.5;
uniform float opaque_depth = 11.0;
uniform float shallow_alpha = 0.30;
uniform float deep_alpha = 0.94;

// Contact foam: view-space thickness below which the water froths white.
uniform float foam_thickness = 0.9;
// Rolling foam lines: spacing between bands (in thickness metres), their
// shoreward speed (bands per second), and the thickness beyond which they
// fade out — they only live near the shore.
uniform float roll_spacing = 8.0;
uniform float roll_speed = 0.14;
uniform float roll_reach = 30.0;
uniform float roll_strength = 0.55;

uniform float water_roughness : hint_range(0.0, 1.0) = 0.14;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 world_pos;

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

float wave_height(vec2 p, float t) {
	vec2 d1 = normalize(swell_dir);
	vec2 d2 = normalize(swell_dir + vec2(0.0, 0.55));
	vec2 d3 = normalize(swell_dir + vec2(0.0, -0.7));
	float h = 0.62 * sin(dot(p, d1) * (TAU / 13.0) - t * wave_speed * 1.00);
	h += 0.28 * sin(dot(p, d2) * (TAU / 6.3) - t * wave_speed * 1.45 + 1.7);
	h += 0.10 * sin(dot(p, d3) * (TAU / 3.4) - t * wave_speed * 2.10 + 4.1);
	return h * wave_amplitude;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Local XZ length is the distance from the (player-following) node centre,
	// which is what the far-water fade should key off.
	float fade = 1.0 - smoothstep(wave_fade_start, wave_fade_end, length(VERTEX.xz));
	float h = wave_height(world_pos.xz, TIME) * fade;
	VERTEX.y += h;
	world_pos.y += h;
}

void fragment() {
	// How much water the eye looks through at this fragment: the seabed's
	// linear view depth (from the opaque prepass) minus the water's own.
	float scene_raw = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_raw);
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene_view.xyz /= scene_view.w;
	float thickness = max(-scene_view.z - (-VERTEX.z), 0.0);

	float murk = 1.0 - exp(-thickness / murk_depth);
	vec3 albedo = mix(shallow_color, deep_color, murk);
	float alpha = mix(shallow_alpha, deep_alpha, 1.0 - exp(-thickness / opaque_depth));

	// Foam. Contact foam hugs the waterline (and anything standing in the
	// water); rolling lines ride equal-thickness bands shoreward, warped by
	// noise so they read as surf, not stripes.
	float warp = (value_noise(world_pos.xz * 0.11) - 0.5) * 4.0;
	float contact = 1.0 - smoothstep(0.0, foam_thickness + warp * 0.12, thickness);
	float roll_phase = fract((thickness + warp) / roll_spacing + TIME * roll_speed);
	float roll_line = pow(0.5 + 0.5 * sin(roll_phase * TAU), 6.0);
	float roll = roll_line * roll_strength * (1.0 - smoothstep(roll_reach * 0.4, roll_reach, thickness));
	float froth = 0.72 + 0.28 * value_noise(world_pos.xz * 1.7 + vec2(TIME * 0.35, -TIME * 0.22));
	float foam = clamp((contact + roll) * froth, 0.0, 1.0);
	albedo = mix(albedo, foam_color, foam);
	alpha = clamp(alpha + foam * 0.75, 0.0, 0.96);

	// Fresnel: grazing water reads more like a surface, less like a window.
	vec3 facet = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	float grazing = pow(1.0 - clamp(dot(facet, VIEW), 0.0, 1.0), 3.0);
	alpha = clamp(alpha + grazing * 0.30, 0.0, 0.96);

	ALBEDO = albedo;
	ALPHA = alpha;
	ROUGHNESS = mix(water_roughness, 0.85, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	NORMAL = facet;
}
