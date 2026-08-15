// The desert sky (Phase 6.5 piece 3): ProceduralSkyMaterial's gradient and
// sun-halo math reproduced verbatim, plus a sparse starfield for the dark
// nights. The swap from the stock material must be invisible by day — the
// 16:00 golden hour is the calibration anchor the whole cycle hangs off —
// so the gradient formulas below are Godot's own, with the same defaults.
// star_strength is driven by DesertEnvironment: 0 all day, fading to 1 as
// the night deepens.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.56, 0.72, 0.79);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.94, 0.84);
uniform vec3 ground_bottom_color : source_color = vec3(0.77, 0.57, 0.31);
uniform vec3 ground_horizon_color : source_color = vec3(1.0, 0.94, 0.84);
uniform float sky_curve = 0.09;
uniform float ground_curve = 0.02;
// Halo reach and falloff around the sun/moon, ProceduralSky defaults.
uniform float sun_angle_max = 0.523599; // 30 degrees, radians
uniform float sun_curve = 0.15;
// 0 = no stars (day), 1 = full night sky.
uniform float star_strength = 0.0;
// Stars per radian of sky, roughly. Higher = denser.
uniform float star_density = 22.0;

// Cheap 2D hash, stable per cell.
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

vec3 halo(vec3 sky, vec3 eyedir, vec3 light_dir, vec3 light_color, float light_energy, float light_size) {
	float sun_angle = acos(clamp(dot(light_dir, eyedir), -1.0, 1.0));
	if (sun_angle < light_size) {
		return light_color * light_energy;
	} else if (sun_angle < sun_angle_max) {
		float c = (sun_angle - light_size) / (sun_angle_max - light_size);
		return mix(light_color * light_energy, sky,
			clamp(1.0 - pow(1.0 - c, 1.0 / sun_curve), 0.0, 1.0));
	}
	return sky;
}

void sky() {
	float v_angle = acos(clamp(EYEDIR.y, -1.0, 1.0));
	vec3 color;
	if (EYEDIR.y >= 0.0) {
		float c = 1.0 - v_angle / (PI * 0.5);
		color = mix(horizon_color, top_color,
			clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
		if (LIGHT0_ENABLED) {
			color = halo(color, EYEDIR, LIGHT0_DIRECTION, LIGHT0_COLOR, LIGHT0_ENERGY, LIGHT0_SIZE);
		}
		if (LIGHT1_ENABLED) {
			color = halo(color, EYEDIR, LIGHT1_DIRECTION, LIGHT1_COLOR, LIGHT1_ENERGY, LIGHT1_SIZE);
		}
		// Stars: one candidate point per cell of an azimuth/elevation grid,
		// most cells dark, brightness hashed, a slow independent twinkle.
		// They fade out toward the horizon (the haze band would swallow
		// them anyway) and vanish entirely by day via star_strength.
		// Stars: cellular field over an azimuth/elevation grid, checking the
		// 3×3 neighborhood so stars can sit anywhere in their cell with no
		// dead bands.
		//
		// KNOWN LIMIT (measured 2026-08-15): at the fixed gameplay camera
		// (19° pitch, 35° FOV) the top of frame reaches only 1.5° above
		// horizontal, and the horizon there is always fog-melted terrain by
		// design — the player never sees actual sky in normal play, so these
		// stars are effectively invisible in-game today. They are kept
		// because they are correct, nearly free, and any future view that
		// tilts up (photo mode, cutscenes, a pitch revisit) gets a starry
		// desert night without new work.
		if (star_strength > 0.001) {
			vec2 grid = vec2(atan(EYEDIR.x, EYEDIR.z), v_angle) * star_density;
			vec2 base_cell = floor(grid);
			// Fade only right at the terrain edge; full strength within the
			// visible sliver (every seen sky pixel has EYEDIR.y < ~0.03).
			float horizon_fade = smoothstep(0.0, 0.008, EYEDIR.y);
			for (int cx = -1; cx <= 1; cx++) {
				for (int cy = -1; cy <= 1; cy++) {
					vec2 cell = base_cell + vec2(float(cx), float(cy));
					vec2 rnd = hash2(cell);
					// ~40% of cells hold a star.
					if (rnd.x <= 0.6) { continue; }
					vec2 center = cell + hash2(cell + 17.0);
					float dist = length(grid - center);
					float radius = 0.05 + 0.06 * rnd.y;
					// NOTE: smoothstep with reversed edges is undefined in GLSL
					// (and returns 0 on Metal) — invert the result instead.
					float star = 1.0 - smoothstep(radius * 0.3, radius, dist);
					float twinkle = 0.75 + 0.25 * sin(TIME * (0.8 + 2.2 * rnd.y) + rnd.x * 6.2831);
					color += vec3(0.9, 0.93, 1.0) * star * twinkle * horizon_fade
						* star_strength * (0.35 + 0.65 * rnd.y);
				}
			}
		}
	} else {
		float c = (v_angle - PI * 0.5) / (PI * 0.5);
		color = mix(ground_horizon_color, ground_bottom_color,
			clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
	}
	COLOR = color;
}
