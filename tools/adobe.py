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
