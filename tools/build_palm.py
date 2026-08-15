"""Build the date palm — the desert's first landmark plant.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_palm.py [-- --render]

Writes  assets/blender/palm.blend        (editable source of truth)
        assets/models/palm.glb           (what Godot imports)
        docs/references/palm_preview_*.png  (with --render)

Two objects, because they want different things from Godot:

  `trunk-col`  the `-col` suffix makes the glTF importer build a StaticBody3D
               with a trimesh shape from this mesh, so collision can never
               drift from the geometry. Only the trunk collides — a crown with
               collision would let the player stand on a frond.
  `crown`      no collision, and separate so a future wind shader can sway the
               fronds without dragging the trunk with them.

**Shape notes, from docs/references/ (Joshua's reference, 2026-08-14).**

The trunk is what says "date palm" rather than "generic palm": real ones keep
the sawn-off bases of old fronds as a diamond-patterned sleeve of scars. At the
19 deg / 23 m gameplay camera the diamonds themselves are far below the ~10 cm
detail floor, so the trunk is banded instead — each band a ring slightly wider
than the one above it, making a lip the flat shading catches, with every ring
twisted a few degrees so the lips spiral the way real scars do.

The trunk also leans. Date palms almost never grow plumb, and ART_DIRECTION
asks for slight imperfection; the lean is baked into the model (rather than
left to per-instance tilt) so the crown can be mounted square to the *trunk
tip* and the whole tree reads as one grown thing.

Each frond is a closed triangular prism swept along an arc — a V-fold, which
is how a real frond carries itself. That costs three faces per segment instead
of the one a flat card would, and it is worth every triangle: a card has a
single normal, so flat-shaded it reads as a painted cutout and vanishes
edge-on, while the V catches the warm sun differently on each face and gives
the crown actual volume. The frond's half-width pinches on alternate rings,
which buys a feathery sawtooth silhouette for zero extra triangles.

Materials are named exactly after resources/palette/ entries; the colours set
here only drive Blender's viewport (tools/map_palette_materials.py wires the
.glb to the palette .tres files, so a palette edit reaches this asset without
a re-export).
"""

import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lowpoly import (  # noqa: E402
    Part, all_materials, arched_frond, clear_scene, export_glb,
)

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND = os.path.join(PROJECT, "assets", "blender", "palm.blend")
GLB = os.path.join(PROJECT, "assets", "models", "palm.glb")
PREVIEW_DIR = os.path.join(PROJECT, "docs", "references")

TRUNK = "wood"          # ART_DIRECTION lists palm trunks under `wood`
FROND = "palm_green"    # green is scarce and precious — this is what spends it
FRUIT = "clay"          # ripe dates: terracotta, not gold (gold marks interactables)

# --- dimensions, metres ------------------------------------------------------
# The house tops out at 6.05 m (parapet 6.65) and the player is 1.75 m, so a
# ~7 m palm clears the homestead and reads as a landmark from across a dune
# without dwarfing the building it shades.
BURY = 0.30            # base sunk below z=0 so no gap shows on uneven sand
CROWN_Z = 5.40         # trunk top / where the fronds emerge
TRUNK_SIDES = 6        # a 0.25 m trunk at 23 m: six sides already reads round
BANDS = 7              # frond-scar lips up the trunk
BAND_LIP = 0.055       # how far a lip stands proud of the trunk above it
TWIST_PER_RING = 11.0  # degrees — makes the lips spiral
LEAN_X = 0.42          # how far the tip drifts off plumb
LEAN_Y = 0.12          # a gentle counter-curve, so the lean is not a straight tilt

# Landmark-scale prop, so the ≤ 500 tri small-prop cap does not apply: this is
# a 7 m tree, not a pouf. It still has to be cheap enough to scatter, so the
# ceiling sits well under the 2,500 the player costs and the 2,136 the house does.
TRI_BUDGET = 1000


# --- trunk -------------------------------------------------------------------

def trunk_axis(u: float) -> Vector:
    """The trunk's centreline at height fraction `u`, lean included."""
    return Vector((
        LEAN_X * u ** 1.7,
        LEAN_Y * math.sin(math.pi * 0.9 * u),
        -BURY + u * (CROWN_Z + BURY),
    ))


def trunk_radius(u: float) -> float:
    taper = 0.27 - 0.085 * u
    flare = 0.17 * max(0.0, 1.0 - u / 0.14) ** 2  # roots spreading into the sand
    return taper + flare


def build_trunk(materials: dict) -> tuple[Part, Vector]:
    part = Part("trunk")

    # Ring heights come in pairs: a wide one and, just above it, a narrow one.
    # The step between them is the lip of a frond scar.
    rings: list[tuple[float, float]] = []
    for band in range(BANDS):
        base = band / BANDS
        rings.append((base, BAND_LIP))
        rings.append((base + 0.055, 0.0))
    rings.append((1.0, 0.0))

    base_index = len(part.verts)
    for i, (u, bulge) in enumerate(rings):
        centre = trunk_axis(u)
        radius = trunk_radius(u) + bulge
        twist = math.radians(TWIST_PER_RING * i)
        for k in range(TRUNK_SIDES):
            angle = math.tau * k / TRUNK_SIDES + twist
            part.verts.append(Vector((
                centre.x + math.cos(angle) * radius,
                centre.y + math.sin(angle) * radius,
                centre.z,
            )))

    # Sides. Rings run counter-clockwise seen from +Z, so this winding puts the
    # normals outward.
    for i in range(len(rings) - 1):
        lower = base_index + i * TRUNK_SIDES
        upper = base_index + (i + 1) * TRUNK_SIDES
        for k in range(TRUNK_SIDES):
            k2 = (k + 1) % TRUNK_SIDES
            part.faces.append((lower + k, lower + k2, upper + k2, upper + k))
            part.face_materials.append(TRUNK)

    # Caps: the bottom is buried but closes the trimesh, the top is hidden by
    # the crown and only exists so nothing can be seen through it from above.
    part.faces.append(tuple(range(base_index + TRUNK_SIDES - 1, base_index - 1, -1)))
    part.face_materials.append(TRUNK)
    top = base_index + (len(rings) - 1) * TRUNK_SIDES
    part.faces.append(tuple(range(top, top + TRUNK_SIDES)))
    part.face_materials.append(TRUNK)

    # The tip direction, so the crown can be mounted square to the leaning trunk.
    tip = (trunk_axis(1.0) - trunk_axis(0.98)).normalized()
    return part, tip


# --- crown -------------------------------------------------------------------

# count, pitch, droop, length, half-width, segments, mount height, yaw phase
# Fronds are 0.8+ m across the leaflets on a real date palm; at 0.6 m the crown
# read as a spray of blades rather than a mass of foliage.
TIERS = (
    (7, -18.0, 75.0, 3.20, 0.42, 5, -0.08, 0.0),   # the skirt, sweeping out and down
    (8, 16.0, 85.0, 3.30, 0.42, 5, 0.08, 23.0),    # the body of the fountain
    (6, 52.0, 55.0, 2.70, 0.34, 5, 0.24, 12.0),    # the dome over the top
    (3, 80.0, 20.0, 1.50, 0.18, 3, 0.34, 45.0),    # young spears at the heart
)


def build_crown(materials: dict, rng: random.Random) -> Part:
    """The crown, built about its own origin with +Z up; the caller rotates it
    onto the trunk tip."""
    part = Part("crown")

    for count, pitch, droop, length, width, segments, dz, phase in TIERS:
        for i in range(count):
            yaw = math.radians(phase + 360.0 * i / count + rng.uniform(-7.0, 7.0))
            # Bases are pushed back inside the trunk top so no joint can show.
            origin = Vector((0.0, 0.0, dz)) - Vector(
                (math.cos(yaw), math.sin(yaw), 0.0)
            ) * 0.30
            arched_frond(
                part,
                origin,
                yaw,
                pitch + rng.uniform(-5.0, 5.0),
                droop + rng.uniform(-6.0, 6.0),
                length * rng.uniform(0.88, 1.08),
                width,
                segments,
                FROND,
            )

    # Date clusters, hanging clear of the trunk under the frond bases. They must
    # stay small and stay *out*: at 0.30 m across and hard against the trunk the
    # pair merged into one terracotta ring and the tree read as a potted plant.
    for yaw_deg in (35.0, 205.0):
        yaw = math.radians(yaw_deg)
        part.drum(
            (math.cos(yaw) * 0.72, math.sin(yaw) * 0.72),
            -1.25, -0.20, 0.05, 0.15, FRUIT, sides=5,
        )
    return part


def place_crown(crown: Part, tip: Vector, top: Vector) -> None:
    """Rotates the crown from +Z onto the trunk's tip direction, then sits it
    on the trunk top."""
    rotation = Vector((0.0, 0.0, 1.0)).rotation_difference(tip).to_matrix()
    crown.verts = [rotation @ v + top for v in crown.verts]


# --- previews ----------------------------------------------------------------

def render_previews(objects: list) -> None:
    """Workbench previews at roughly the gameplay camera, per build_house.py:
    no GPU context needed in --background, and flat material colour is what the
    game's look actually is. Proportion and silhouette only — the real colour
    check is a screenshot of the running game."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = True
    shading.show_cavity = False
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("preview")
    scene.world.color = (0.72, 0.78, 0.82)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens_unit = "FOV"
    camera_data.angle = math.radians(35.0)  # the game's diorama lens
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera

    os.makedirs(PREVIEW_DIR, exist_ok=True)
    centre = Vector((0.0, 0.0, 4.0))
    shots = {
        "gameplay": (25.0, 19.0, 30.0),  # the gameplay camera's own 19 deg pitch
        "lean": (115.0, 14.0, 28.0),     # across the lean, which reads best side-on
        "crown": (25.0, 44.0, 26.0),     # steep, to read the crown's fullness
        "trunk": (60.0, 6.0, 14.0),      # close and low, onto the scar banding
    }
    for name, (yaw, pitch, distance) in shots.items():
        yaw_r, pitch_r = math.radians(yaw), math.radians(pitch)
        offset = Vector((
            math.sin(yaw_r) * math.cos(pitch_r),
            math.cos(yaw_r) * math.cos(pitch_r),
            math.sin(pitch_r),
        )) * distance
        camera.location = centre + offset
        direction = (centre - camera.location).normalized()
        camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(PREVIEW_DIR, "palm_preview_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("preview: %s" % scene.render.filepath)


def add_scale_figure(materials: dict) -> None:
    """A 1.75 m stand-in for the player, for the previews only — never exported.
    'How big is it' is the first question a preview has to answer."""
    figure = Part("scale_figure")
    figure.drum((2.6, 1.4), 0.0, 1.45, 0.24, 0.20, "plaster", sides=8)
    figure.drum((2.6, 1.4), 1.45, 1.75, 0.22, 0.18, "plaster", sides=8)
    figure.emit(materials, collide=False)


# --- main --------------------------------------------------------------------

def main() -> None:
    clear_scene()
    materials = all_materials()
    rng = random.Random(20260814)  # fixed: the build must be reproducible

    trunk, tip = build_trunk(materials)
    crown = build_crown(materials, rng)
    place_crown(crown, tip, trunk_axis(1.0))

    tris = trunk.triangle_count() + crown.triangle_count()
    print("palm: %d tris (trunk %d + crown %d, budget %d)" % (
        tris, trunk.triangle_count(), crown.triangle_count(), TRI_BUDGET))
    if tris > TRI_BUDGET:
        raise SystemExit("palm is over its triangle budget")

    height = max(v.z for v in crown.verts)
    spread = 2.0 * max(math.hypot(v.x, v.y) for v in crown.verts)
    print("palm: %.2f m tall, crown spread %.2f m" % (height, spread))

    objects = [trunk.emit(materials, collide=True),
               crown.emit(materials, collide=False)]

    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(os.path.dirname(GLB), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    export_glb(objects, GLB)
    print("wrote %s (%.0f KB)" % (GLB, os.path.getsize(GLB) / 1024))

    if "--render" in sys.argv:
        add_scale_figure(materials)
        render_previews(objects)


main()
