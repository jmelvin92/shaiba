"""Build the dry frond bush — three independent sizes.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_dry_fronds.py [-- --render]

Writes  assets/blender/dry_fronds.blend           (editable source of all three)
        assets/models/dry_frond_<size>.glb         one file per variant
        docs/references/dry_fronds_preview_*.png   (with --render)

The second dry plant, and deliberately the opposite of the first. Where
`dry_shrub` (tools/build_shrubs.py) is a stiff spiky spindle, this is a low
spreading rosette of feathery pinnate fronds — a dead palm sucker rather than a
thorn bush. Scattered together they cover both silhouettes a dry desert wants,
and they are tonal inverses of each other: the shrub is `wood` bleaching to
`sand_shadow`, this one is `sand_shadow` darkening to `wood`.

**Shape notes, from docs/references/ (Joshua's reference, 2026-08-14).**

The reference is wider than it is tall, roughly 3:2. Fronds spray almost flat
along the ground at the outside, lift through the middle of the clump, and a
few stand up steeply at the centre; every one of them droops at the tip. There
is no visible stem — the plant is all leaf.

Fronds come from `lowpoly.arched_frond`, shared with the palm's crown. What
differs is the pinch: a real pinnate frond is a row of leaflets, and narrowing
alternate rings hard (0.58 here against the palm's 0.86) saws the silhouette
into something feathery for no extra triangles. Individual leaflets are far
below ART_DIRECTION's ~10 cm floor at the gameplay camera and are not modelled;
the sawtooth is what suggests them.

**No collision**, matching the rocks and the spiky shrub: dead scrub is not
something to get snagged on.

Materials are named exactly after resources/palette/ entries; the colours set
here only drive Blender's viewport (tools/map_palette_materials.py wires each
.glb to the palette .tres files).
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
BLEND = os.path.join(PROJECT, "assets", "blender", "dry_fronds.blend")
MODELS = os.path.join(PROJECT, "assets", "models")
PREVIEW_DIR = os.path.join(PROJECT, "docs", "references")

STRAW = "sand_shadow"   # sun-bleached, the dominant tone
OLD = "wood"            # the older, darker fronds low in the clump
OLD_CHANCE = 0.30

PINCH = 0.58            # hard alternate-ring narrowing: the leaflet sawtooth
GOLDEN_ANGLE = 137.507

TRI_BUDGET = 500        # the small-prop cap, and this one uses it


# count, pitch, droop, length, half-width, segments, mount height — all the
# lengths normalised to the plant's own frond unit, scaled per variant below.
# Three segments per frond, not four or five. The plant needs to be *dense*
# above all — the reference is a mass, not a spray — and at 23 m a finer arch
# on each frond buys nothing while a fifth more fronds buys the whole read.
# Spending the triangles on count is the trade that matters.
TIERS = (
    (10, 4.0, 55.0, 1.00, 0.062, 3, 0.03),   # the skirt, spraying out flat
    (8, 32.0, 58.0, 0.92, 0.058, 3, 0.11),   # the body of the rosette
    (5, 68.0, 32.0, 0.86, 0.050, 3, 0.17),   # the few that stand up
)


def build_bush(name: str, spec: dict) -> Part:
    rng = random.Random(spec["seed"])
    part = Part(name)
    unit: float = spec["frond"]
    thin: float = spec["thin"]

    # A stub of a base, barely visible: in the reference the plant is all leaf,
    # and any core that shows is core the fronds failed to cover.
    part.drum((0.0, 0.0), -0.03, unit * 0.16, unit * 0.075, unit * 0.045,
              OLD, sides=5)

    index = 0
    for count, pitch, droop, length, width, segments, mount in TIERS:
        count = max(2, int(round(count * thin)))
        for _ in range(count):
            # Golden angle across the whole plant, not per tier, so the tiers
            # interleave instead of stacking into a rosette of neat rings.
            yaw = math.radians(index * GOLDEN_ANGLE + rng.uniform(-10.0, 10.0))
            index += 1
            origin = Vector((0.0, 0.0, unit * mount))
            origin += Vector((math.cos(yaw), math.sin(yaw), 0.0)) * unit * 0.05
            arched_frond(
                part,
                origin,
                yaw,
                pitch + rng.uniform(-7.0, 7.0),
                droop + rng.uniform(-8.0, 8.0),
                unit * length * rng.uniform(0.82, 1.14),
                unit * width * rng.uniform(0.88, 1.12),
                segments,
                OLD if rng.random() < OLD_CHANCE else STRAW,
                pinch=PINCH,
                fold_base=unit * 0.012,
            )
    return part


BUSHES: dict[str, dict] = {
    "dry_frond_small": dict(seed=911, frond=0.26, thin=0.55),
    "dry_frond_mid": dict(seed=922, frond=0.42, thin=0.78),
    "dry_frond_large": dict(seed=933, frond=0.64, thin=1.0),
}


def render_previews(objects: list) -> None:
    """Contact sheet, per build_shrubs.py — Workbench needs no GPU context in
    --background and renders flat material colour."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = True
    shading.show_cavity = False
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("preview")
    scene.world.color = (0.86, 0.88, 0.90)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens_unit = "FOV"
    camera_data.angle = math.radians(35.0)
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera

    cursor = 0.0
    tallest = 0.0
    for obj in objects:
        width = obj.dimensions.x
        cursor += width * 0.5 + 0.22
        obj.location.x = cursor
        cursor += width * 0.5
        tallest = max(tallest, obj.dimensions.z)
    span = cursor

    os.makedirs(PREVIEW_DIR, exist_ok=True)
    centre = Vector((span * 0.5, 0.0, tallest * 0.4))
    fit = (span * 0.5) / math.tan(math.radians(17.5)) * 1.12
    for name, (yaw, pitch) in {"set": (0.0, 15.0), "high": (18.0, 40.0)}.items():
        yaw_r, pitch_r = math.radians(yaw), math.radians(pitch)
        offset = Vector((
            math.sin(yaw_r) * math.cos(pitch_r),
            math.cos(yaw_r) * math.cos(pitch_r),
            math.sin(pitch_r),
        )) * fit
        camera.location = centre + offset
        direction = (centre - camera.location).normalized()
        camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(
            PREVIEW_DIR, "dry_fronds_preview_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("preview: %s" % scene.render.filepath)


def main() -> None:
    clear_scene()
    materials = all_materials()
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(MODELS, exist_ok=True)

    objects: list[bpy.types.Object] = []
    for name, spec in BUSHES.items():
        part = build_bush(name, spec)
        tris = part.triangle_count()
        if tris > TRI_BUDGET:
            raise SystemExit("%s is over its triangle budget (%d)" % (name, tris))
        obj = part.emit(materials, collide=False)
        size = obj.dimensions
        print("%-17s %3d tris   %.2f x %.2f x %.2f m" % (
            name, tris, size.x, size.y, size.z))
        objects.append(obj)

    for obj in objects:
        path = os.path.join(MODELS, "%s.glb" % obj.name)
        export_glb([obj], path)
        print("wrote %s (%.0f KB)" % (path, os.path.getsize(path) / 1024))

    bpy.ops.wm.save_as_mainfile(filepath=BLEND)

    if "--render" in sys.argv:
        render_previews(objects)


main()
