"""Build the wooden door leaf every building shares.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_door.py

Writes  assets/blender/door.blend   (editable source of truth)
        assets/models/door.glb      (what Godot imports)

The door is a *prop*, not part of any building's model: scenes/props/door/
wraps this leaf with a hinge, collision and an Interactable so the same asset
serves every doorway we ever cut (docs/PLAN.md Phase 6 — interior items are
independent, reusable assets). The mesh is sized to the standard doorway from
tools/build_house.py (DOOR_W 1.30 x DOOR_H 2.40, jambs intruding 0.10 a side),
hung just behind the jambs so it seals the reveal without touching the frame.

**The origin is the hinge.** The leaf grows along +X from a 0.01 m hinge gap,
so the Godot scene swings the whole model by rotating its parent about Y —
no pivot offsets to transcribe into a .tscn.

Five planks with alternating face depths give the flat-shaded surface its
plank lines (coplanar boxes shade as one slab; an 8 mm step reads as a groove),
two battens brace each face, and a gold pull marks the free edge — the same
accent the interact prompt points at.

Materials are named exactly after resources/palette/ entries; the colours set
here only drive Blender's viewport (tools/map_palette_materials.py wires the
.glb to the palette .tres files).

No `-col` suffix: a door moves, so the Godot scene gives it a hand-authored
BoxShape3D on an AnimatableBody3D instead of an imported static trimesh.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lowpoly import Part, all_materials, clear_scene, export_glb  # noqa: E402

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND = os.path.join(PROJECT, "assets", "blender", "door.blend")
GLB = os.path.join(PROJECT, "assets", "models", "door.glb")

WOOD = "wood"
PULL = "accent_gold"

# --- dimensions, metres ------------------------------------------------------
# Matched to the standard doorway in tools/build_house.py: opening 1.30 wide,
# jambs intrude 0.10 a side, floor slab stands FLOOR_LIFT above the opening's
# base. The wrapping scene sits at floor-top height on the hinge jamb, so the
# leaf starts 0.02 above the floor and stops 0.04 short of the 2.40 lintel.
HINGE_GAP = 0.01       # daylight at the hinge edge
LEAF_W = 1.26          # covers the 1.30 opening to 0.02 shy of each reveal
LEAF_H = 2.22
LEAF_Z0 = 0.02         # bottom clearance over the threshold
LEAF_T = 0.06          # thickness, split evenly about the hinge plane (y=0)
PLANKS = 5

TRI_BUDGET = 500       # the furnishing budget; a door is furniture that swings


def build_leaf() -> Part:
    part = Part("leaf")
    x0 = HINGE_GAP
    x1 = HINGE_GAP + LEAF_W
    z1 = LEAF_Z0 + LEAF_H

    # Planks: alternating front/back face depths, so every seam is a real step
    # the flat shading can catch. Bottoms are ragged by a centimetre — sawn by
    # hand, like the vigas — while the top stays sealed against the lintel.
    plank_w = LEAF_W / PLANKS
    bottom_jitter = (0.000, 0.012, 0.005, 0.015, 0.008)
    for i in range(PLANKS):
        px0 = x0 + plank_w * i
        px1 = px0 + plank_w
        front = 0.030 if i % 2 == 0 else 0.022
        back = -0.022 if i % 2 == 0 else -0.030
        part.box((px0, back, LEAF_Z0 + bottom_jitter[i]), (px1, front, z1), WOOD)

    # Battens: one pair bracing each face, clear of the pull.
    for y_lo, y_hi in ((0.030, 0.072), (-0.072, -0.030)):
        for z_lo in (0.52, 1.62):
            part.box((x0 + 0.04, y_lo, z_lo), (x1 - 0.04, y_hi, z_lo + 0.14), WOOD)

    # The pull, on both faces at the free edge: the one glint of gold, which is
    # also what the interact prompt hangs over.
    for y_lo, y_hi in ((0.030, 0.092), (-0.092, -0.030)):
        part.box((x1 - 0.22, y_lo, 1.02), (x1 - 0.14, y_hi, 1.10), PULL)
    return part


def main() -> None:
    clear_scene()
    materials = all_materials()

    leaf = build_leaf()
    tris = leaf.triangle_count()
    obj = leaf.emit(materials, collide=False)
    print("door leaf: %d tris  (budget %d)" % (tris, TRI_BUDGET))
    if tris > TRI_BUDGET:
        raise SystemExit("door leaf is over its triangle budget")

    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(os.path.dirname(GLB), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    export_glb([obj], GLB)
    print("wrote %s (%.0f KB)" % (GLB, os.path.getsize(GLB) / 1024))


main()
