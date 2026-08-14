// Sand terrain surface. Albedo comes from per-vertex palette tones baked by
// the chunk builder; the faceted low-poly look comes from computing the
// normal per-pixel from screen-space derivatives, which makes every triangle
// a flat facet without duplicating vertices per face. Because the normal is
// derived from the rendered position, it stays correct for any vertex
// displacement — Phase 5's footprint deformation plugs into vertex() and the
// lighting follows for free.
//
// COLOR.a carries normalised sand depth (0 = hard ground, 1 = deepest sand).
// Unused here; Phase 5 caps footprint depth with it per-fragment.
shader_type spatial;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
}
