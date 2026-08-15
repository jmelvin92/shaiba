"""Shared adobe-building vocabulary for the Blender build scripts.

Extracted when the second house appeared (CLAUDE.md: extract on the second
user, not before). `tools/build_house.py` builds the two-storey homestead and
`tools/build_house_small.py` the single-room house; both need walls with holes
in them and both need the row of protruding roof beams, so those two live here.

Everything else stays with its building. An arched portal is one house's idea
until a second house wants one.

Materials are passed in rather than read from a global, because each caller
owns its own palette choices — and because build_house.py's `--wall` ladder
rebinds its wall tone at runtime, so a value captured at import time would be
the wrong one.
"""

import math

from mathutils import Vector

from lowpoly import Part


def wall_with_openings(
    part: Part,
    axis: str,
    outer: float,
    inner: float,
    span: tuple[float, float],
    height: tuple[float, float],
    openings: list[tuple[float, float, float, float]],
    material: str,
) -> None:
    """Fill `span` x `height` with wall, skipping each opening.

    A wall is built as the solid pieces *around* its openings rather than as a
    box with holes cut in it: fewer triangles, no boolean, and every face stays
    a clean quad for flat shading.

    `axis` is the wall's normal ("x" or "y"); `outer`/`inner` are its two face
    positions along that axis. Each opening is (span_lo, span_hi, z_lo, z_hi).
    """
    lo_a, hi_a = min(outer, inner), max(outer, inner)

    def block(s0: float, s1: float, z0: float, z1: float) -> None:
        if s1 - s0 < 1e-6 or z1 - z0 < 1e-6:
            return
        if axis == "x":
            part.box((lo_a, s0, z0), (hi_a, s1, z1), material)
        else:
            part.box((s0, lo_a, z0), (s1, hi_a, z1), material)

    ordered = sorted(openings)
    cursor = span[0]
    for s0, s1, z0, z1 in ordered:
        block(cursor, s0, height[0], height[1])   # full-height pier before it
        block(s0, s1, height[0], z0)              # under the opening
        block(s0, s1, z1, height[1])              # lintel over the opening
        cursor = s1
    block(cursor, span[1], height[0], height[1])


def vigas(
    part: Part,
    axis: str,
    face: float,
    span: tuple[float, float],
    z_centre: float,
    count: int,
    outward: float,
    material: str,
    skip: tuple[float, float] | None = None,
) -> None:
    """The row of protruding roof-beam ends. Each is yawed a degree or two:
    hand-hewn timber never lines up, and the jitter is what keeps the row from
    reading as a machined comb.

    `skip` leaves a gap in the rhythm — used over an entrance, where beams
    would otherwise run straight through whatever is hung beneath them.
    """
    half = 0.085
    s0, s1 = span
    step = (s1 - s0) / (count + 1)
    for i in range(1, count + 1):
        centre = s0 + step * i
        if skip is not None and skip[0] <= centre <= skip[1]:
            continue
        yaw = (-1.6, 2.1, -0.9, 1.3, -2.2, 0.8)[i % 6]
        length = 0.50 + (0.03 if i % 2 else -0.02)
        if axis == "x":
            near, far = sorted((face, face + outward * length))
            part.box((near, centre - half, z_centre - half),
                     (far, centre + half, z_centre + half), material, yaw)
        else:
            near, far = sorted((face, face + outward * length))
            part.box((centre - half, near, z_centre - half),
                     (centre + half, far, z_centre + half), material, yaw)


# --- arches ------------------------------------------------------------------
#
# Moved here when the second arched building appeared. Both the small house and
# the wide one cut arched openings, and the wide one's are pointed rather than
# round, so the spandrel builder takes a ready-made arc instead of computing a
# semicircle itself.

def arc_points(
    centre_x: float, springing: float, radius: float, steps: int,
    start: float = 0.0, end: float = math.pi,
) -> list[tuple[float, float]]:
    """Points along an arch, from `start` to `end` radians (0 = right springing,
    pi = left). Returned as (x, z)."""
    return [
        (
            centre_x + radius * math.cos(start + (end - start) * i / steps),
            springing + radius * math.sin(start + (end - start) * i / steps),
        )
        for i in range(steps + 1)
    ]


def prism(
    part: Part, profile: list[tuple[float, float]], axis: str,
    outer: float, inner: float, material: str,
) -> None:
    """A closed solid from a (span, z) profile extruded through a wall.

    The one shape a stack of boxes cannot make cleanly — here, the spandrel
    between an arch and the square opening it sits in. `axis` is the wall's
    normal, matching adobe.wall_with_openings, and `profile`'s first coordinate
    is the wall's span direction.

    Two things are normalised rather than trusted to the caller, because both
    were wrong on the first pass and neither is visible in a solid render:

    * The profile is re-wound counter-clockwise. Mirrored pairs are where
      hand-wound profiles go wrong — this arch's left spandrel came out
      clockwise while its right came out counter-clockwise, inverting one.
    * The extrusion runs a different way for each axis. (span, z, x) is
      right-handed where (span, z, y) is left-handed, so the same winding that
      faces outward on a front wall faces inward on a side wall.
    """
    twice_area = sum(
        profile[i][0] * profile[(i + 1) % len(profile)][1]
        - profile[(i + 1) % len(profile)][0] * profile[i][1]
        for i in range(len(profile))
    )
    if twice_area < 0.0:
        profile = list(reversed(profile))

    a0, a1 = min(outer, inner), max(outer, inner)
    if axis == "x":
        a0, a1 = a1, a0

    def vert(span: float, across: float, z: float) -> Vector:
        return Vector((across, span, z)) if axis == "x" else Vector((span, across, z))

    count = len(profile)
    base = len(part.verts)
    for span, z in profile:
        part.verts.append(vert(span, a0, z))
    for span, z in profile:
        part.verts.append(vert(span, a1, z))

    for i in range(count):
        j = (i + 1) % count
        part.faces.append((base + i, base + count + i, base + count + j, base + j))
        part.face_materials.append(material)

    part.faces.append(tuple(range(base + count - 1, base - 1, -1)))
    part.face_materials.append(material)
    part.faces.append(tuple(range(base + count, base + 2 * count)))
    part.face_materials.append(material)


def arched_opening(
    part: Part, axis: str, arc: list[tuple[float, float]],
    outer: float, inner: float, material: str,
) -> None:
    """Turns a square-headed opening into an arched one.

    The wall is cut as a plain rectangle up to the arch's crown — which
    `wall_with_openings` can already do — and these two spandrels then fill the
    upper corners back in, leaving the arch. Much cheaper than cutting a curve,
    and every face stays a flat quad.

    `arc` runs from one springing to the other, so any arch shape works: pass
    `round_arch` for a semicircle or `pointed_arch` for a two-centred one.
    """
    crown_index = max(range(len(arc)), key=lambda i: arc[i][1])
    crown_z = arc[crown_index][1]
    first_span, last_span = arc[0][0], arc[-1][0]
    prism(part, arc[:crown_index + 1] + [(first_span, crown_z)],
          axis, outer, inner, material)
    prism(part, arc[crown_index:] + [(last_span, crown_z)],
          axis, outer, inner, material)


def round_arch(
    centre: float, springing: float, radius: float, steps: int,
) -> list[tuple[float, float]]:
    """A semicircle, springing to springing."""
    return arc_points(centre, springing, radius, steps * 2)


def pointed_arch(
    centre: float, springing: float, half_span: float, offset: float, steps: int,
) -> list[tuple[float, float]]:
    """A two-centred arch: each half struck from a centre offset toward the
    *other* side, so the two arcs meet at a point rather than a tangent.

    A pointed arch is taller at the crown but also stands *higher over its
    jambs* than a semicircle on the same span, which is what makes it the safer
    shape for a doorway — the clear height where the usable width ends is the
    number that has to clear the player, and that is the arch's weakest point.
    """
    radius = half_span + offset
    limit = math.acos(offset / radius)
    right = [
        (centre - offset + radius * math.cos(limit * i / steps),
         springing + radius * math.sin(limit * i / steps))
        for i in range(steps + 1)
    ]
    left = [
        (centre + offset - radius * math.cos(limit * i / steps),
         springing + radius * math.sin(limit * i / steps))
        for i in range(steps, -1, -1)
    ]
    return right + left[1:]


def arch_band(
    part: Part, centre_x: float, springing: float,
    inner_r: float, outer_r: float, y0: float, y1: float, material: str,
) -> None:
    """The protruding arched surround: a band swept over the arch, rectangular
    in section. Built by stitching consecutive cross-sections, the same way the
    palm's trunk stitches its rings."""
    inner = arc_points(centre_x, springing, inner_r, 7 * 2)
    outer = arc_points(centre_x, springing, outer_r, 7 * 2)
    base = len(part.verts)
    for (ix, iz), (ox, oz) in zip(inner, outer):
        part.verts.extend([
            Vector((ix, y0, iz)), Vector((ox, y0, oz)),
            Vector((ox, y1, oz)), Vector((ix, y1, iz)),
        ])
    sections = len(inner)
    for i in range(sections - 1):
        a = base + i * 4
        b = base + (i + 1) * 4
        for k in range(4):
            k2 = (k + 1) % 4
            part.faces.append((a + k, b + k, b + k2, a + k2))
            part.face_materials.append(material)
    part.faces.append((base, base + 3, base + 2, base + 1))
    part.face_materials.append(material)
    last = base + (sections - 1) * 4
    part.faces.append((last, last + 1, last + 2, last + 3))
    part.face_materials.append(material)


PATCH_STONES = [
    (0.00, 0.00, 0.22, 0.15), (0.24, 0.03, 0.17, 0.13),
    (0.05, 0.17, 0.19, 0.14), (0.26, 0.19, 0.20, 0.12),
    (0.14, 0.33, 0.16, 0.11),
]


def stone_patch(
    part: Part, axis: str, face: float, outward: float,
    centre: tuple[float, float], material: str,
) -> None:
    """A patch where the plaster has fallen away. Each stone stands a
    centimetre or two proud, so flat shading catches an edge on it rather than
    leaving a flat decal that reads as a stain."""
    for ds, dz, w, h in PATCH_STONES:
        s0, s1 = centre[0] + ds, centre[0] + ds + w
        z0, z1 = centre[1] + dz, centre[1] + dz + h
        near, far = sorted((face, face + outward * 0.035))
        if axis == "x":
            part.box((near, s0, z0), (far, s1, z1), material)
        else:
            part.box((s0, near, z0), (s1, far, z1), material)


PATCH_STONES = [
    (0.00, 0.00, 0.22, 0.15), (0.24, 0.03, 0.17, 0.13),
    (0.05, 0.17, 0.19, 0.14), (0.26, 0.19, 0.20, 0.12),
    (0.14, 0.33, 0.16, 0.11),
]
