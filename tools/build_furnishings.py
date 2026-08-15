"""Build the reusable furnishing assets.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_furnishings.py

Writes  assets/blender/furnishings.blend   (all pieces, editable together)
        assets/models/<piece>.glb          (one file per piece)

**Every piece is its own asset.** Joshua's call, and the right one: a bed, a
rug or a tapestry that lives inside house.glb can only ever be in that house,
can never be made interactable on its own, and turns "move the table" into a
re-export. As separate .glb files they drop into any building we ever make,
and rearranging a room is a scene edit.

Shapes come from docs/references/house_interior_majlis.png — low seating along
the walls, a patterned rug, poufs and floor cushions, a low table. The
reference's fabrics are photographic reds, greens and blues; here the pattern
is carried by whole faces in palette colours instead, which is what keeps a
majlis full of textiles inside the flat-shaded, palette-only rule.

Scale is real: the player is 1.75 m, so seating sits at 0.40 m and the table
top at 0.38 m, and a standing character reads correctly beside them.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lowpoly import Part, all_materials, clear_scene, export_glb  # noqa: E402

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND = os.path.join(PROJECT, "assets", "blender", "furnishings.blend")
MODELS = os.path.join(PROJECT, "assets", "models")

# Pieces small enough to step over, or flat against a surface, carry no
# collision — walking into an invisible floor cushion is worse than clipping a
# visible one. Everything you could believably bump into does.
NO_COLLISION = {"rug", "tapestry", "floor_cushion", "oil_lamp"}

# The kilim palette. Alternating these across a cushion's width is what reads
# as a woven stripe at gameplay distance without a single texel.
STRIPES = ["clay", "night_blue", "plaster", "clay", "accent_gold", "night_blue"]


def build_rug() -> Part:
    """A flat woven rug, built as stacked slabs rather than one textured
    plane: each layer is a hair above the last so nothing z-fights."""
    part = Part("rug")
    half_x, half_y = 1.30, 0.90
    part.box((-half_x, -half_y, 0.0), (half_x, half_y, 0.012), "clay")
    part.box((-half_x + 0.16, -half_y + 0.16, 0.012),
             (half_x - 0.16, half_y - 0.16, 0.016), "night_blue")
    # A row of lozenges down the middle — the one motif that survives being
    # seen from 23 m, because it breaks the field into rhythm rather than detail.
    for i in range(5):
        cx = -0.88 + i * 0.44
        part.box((cx - 0.13, -0.20, 0.016), (cx + 0.13, 0.20, 0.019),
                 "accent_gold" if i % 2 == 0 else "plaster")
    return part


def build_low_sofa() -> Part:
    """Majlis seating: a long floor cushion with a row of bolsters behind it.

    Modelled straight, 2.2 m long. Two of them at right angles make the corner
    the reference shows, so one asset furnishes a whole wall run.
    """
    part = Part("low_sofa")
    length, depth = 2.20, 0.78
    seat_h = 0.34
    part.box((-length / 2, -depth / 2, 0.0), (length / 2, depth / 2, seat_h), "clay")
    # Seat cushions: separate blocks so the stripes read as woven panels.
    span = length / 4.0
    for i in range(4):
        x0 = -length / 2 + span * i
        part.box((x0 + 0.02, -depth / 2 + 0.03, seat_h),
                 (x0 + span - 0.02, depth / 2 - 0.03, seat_h + 0.10),
                 STRIPES[i % len(STRIPES)])
    # Bolsters along the back, leaning against the wall.
    for i in range(3):
        x0 = -length / 2 + (length / 3.0) * i
        part.box((x0 + 0.04, depth / 2 - 0.24, seat_h + 0.06),
                 (x0 + length / 3.0 - 0.04, depth / 2 - 0.02, seat_h + 0.40),
                 STRIPES[(i + 2) % len(STRIPES)])
    return part


def build_pouf() -> Part:
    part = Part("pouf")
    part.drum((0.0, 0.0), 0.0, 0.36, 0.30, 0.27, "accent_gold")
    part.drum((0.0, 0.0), 0.36, 0.39, 0.27, 0.24, "clay")
    return part


def build_floor_cushion() -> Part:
    part = Part("floor_cushion")
    part.box((-0.32, -0.32, 0.0), (0.32, 0.32, 0.14), "night_blue")
    part.box((-0.26, -0.26, 0.14), (0.26, 0.26, 0.17), "plaster")
    return part


def build_low_table() -> Part:
    part = Part("low_table")
    top_h = 0.36
    part.box((-0.58, -0.34, top_h), (0.58, 0.34, top_h + 0.05), "wood")
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            part.box((sx * 0.50 - 0.05, sy * 0.26 - 0.05, 0.0),
                     (sx * 0.50 + 0.05, sy * 0.26 + 0.05, top_h), "wood")
    # A tray, because the reference has one and it gives the top a silhouette.
    part.box((-0.26, -0.18, top_h + 0.05), (0.26, 0.18, top_h + 0.09), "accent_gold")
    return part


def build_pottery() -> Part:
    """A water jar. Three stacked frusta make a believable belly and neck at
    24 sides' worth of cost rather than a lathe's."""
    part = Part("pottery")
    part.drum((0.0, 0.0), 0.0, 0.10, 0.10, 0.17, "clay")
    part.drum((0.0, 0.0), 0.10, 0.34, 0.17, 0.12, "clay")
    part.drum((0.0, 0.0), 0.34, 0.44, 0.12, 0.08, "oasis_teal")
    part.drum((0.0, 0.0), 0.44, 0.48, 0.09, 0.09, "clay")
    return part


def build_hookah() -> Part:
    part = Part("hookah")
    part.drum((0.0, 0.0), 0.0, 0.16, 0.14, 0.11, "oasis_teal")
    part.drum((0.0, 0.0), 0.16, 0.52, 0.045, 0.035, "accent_gold")
    part.drum((0.0, 0.0), 0.52, 0.62, 0.09, 0.07, "clay")
    return part


def build_oil_lamp() -> Part:
    part = Part("oil_lamp")
    part.drum((0.0, 0.0), 0.0, 0.04, 0.09, 0.08, "accent_gold")
    part.drum((0.0, 0.0), 0.04, 0.14, 0.06, 0.07, "accent_gold")
    part.drum((0.0, 0.0), 0.14, 0.19, 0.05, 0.03, "clay")
    return part


def build_bed() -> Part:
    """The upper floor's sleeping mat: a low wooden frame with a mattress and
    a folded blanket across the foot."""
    part = Part("bed")
    length, width = 2.00, 1.30
    frame_h = 0.22
    part.box((-length / 2, -width / 2, 0.0), (length / 2, width / 2, frame_h), "wood")
    part.box((-length / 2 + 0.06, -width / 2 + 0.06, frame_h),
             (length / 2 - 0.06, width / 2 - 0.06, frame_h + 0.16), "plaster")
    part.box((-length / 2 + 0.10, -width / 2 + 0.10, frame_h + 0.16),
             (-length / 2 + 0.50, width / 2 - 0.10, frame_h + 0.26), "plaster")
    part.box((length / 2 - 0.70, -width / 2 + 0.04, frame_h + 0.16),
             (length / 2 - 0.10, width / 2 - 0.04, frame_h + 0.22), "clay")
    return part


def build_tapestry() -> Part:
    """A hung wall textile. Modelled in the XZ plane with its back at y=0, so
    placing it is "put it against this wall" with no offset arithmetic."""
    part = Part("tapestry")
    half_x, height = 0.80, 1.10
    part.box((-half_x, 0.0, 0.0), (half_x, 0.04, height), "clay")
    for i in range(5):
        z0 = 0.10 + i * 0.19
        part.box((-half_x + 0.09, 0.04, z0), (half_x - 0.09, 0.055, z0 + 0.11),
                 STRIPES[i % len(STRIPES)])
    return part


BUILDERS = {
    "rug": build_rug,
    "low_sofa": build_low_sofa,
    "pouf": build_pouf,
    "floor_cushion": build_floor_cushion,
    "low_table": build_low_table,
    "pottery": build_pottery,
    "hookah": build_hookah,
    "oil_lamp": build_oil_lamp,
    "bed": build_bed,
    "tapestry": build_tapestry,
}

# Soft cap from ART_DIRECTION for small props.
TRI_BUDGET = 500


def main() -> None:
    clear_scene()
    materials = all_materials()
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(MODELS, exist_ok=True)

    print("--- furnishings ---")
    over_budget: list[str] = []
    built: list[tuple[str, bpy.types.Object]] = []
    for name, builder in BUILDERS.items():
        part = builder()
        tris = part.triangle_count()
        if tris > TRI_BUDGET:
            over_budget.append("%s (%d tris)" % (name, tris))
        obj = part.emit(materials, collide=name not in NO_COLLISION)
        built.append((name, obj))
        print("  %-16s %4d tris%s" % (
            name, tris, "" if name not in NO_COLLISION else "   (no collision)"
        ))

    # One .blend holding every piece keeps them editable side by side and
    # honestly comparable in scale; the .glb files are what the game loads.
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    for name, obj in built:
        export_glb([obj], os.path.join(MODELS, "%s.glb" % name))

    print("wrote %d pieces to %s" % (len(built), MODELS))
    if over_budget:
        print("OVER the %d-tri prop budget: %s" % (TRI_BUDGET, ", ".join(over_budget)))


main()
