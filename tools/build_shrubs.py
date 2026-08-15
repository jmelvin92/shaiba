"""Build the dry desert shrub — three independent sizes.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_shrubs.py [-- --render]

Writes  assets/blender/shrubs.blend            (editable source of all three)
        assets/models/dry_shrub_<size>.glb      one file per variant
        docs/references/shrubs_preview_*.png    (with --render)

**Three separate .glb files**, same rule as the rocks: each is its own asset so
a level can scatter and mix them, and a clump of three different sizes reads as
a plant that grows rather than as one model stamped repeatedly. They share a
.blend because they are one family and want editing side by side.

**Shape notes, from docs/references/ (Joshua's reference, 2026-08-14).**

The reference is a dead, sun-dried shrub: a short woody core almost completely
hidden under a mass of stiff spikes that radiate out and up, dense and near
horizontal at the foot, steep and sparse at the crown, so the whole thing reads
as a spindle. Nothing about it is soft — the spikes are straight and rigid, and
that rigidity is the character.

Each spike is therefore the cheapest solid that can come to a point: a
three-sided pyramid, four triangles, one of which is the hidden base. Straight
edges and three flat faces is exactly what the reference looks like, so the
cheap answer is also the right one — 38 spikes cost 152 triangles.

Spikes are placed on a golden-angle spiral up the core rather than in rings.
Rings read as tiers of a pagoda from any angle that catches them side-on; the
spiral never lines up with itself, which is what plants actually do.

Individual spikes are below ART_DIRECTION's ~10 cm detail floor at the gameplay
camera and are not meant to read separately — the spiky *silhouette* is what
carries, the same bargain the palm's fronds make.

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

from lowpoly import Part, all_materials, clear_scene, export_glb  # noqa: E402

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND = os.path.join(PROJECT, "assets", "blender", "shrubs.blend")
MODELS = os.path.join(PROJECT, "assets", "models")
PREVIEW_DIR = os.path.join(PROJECT, "docs", "references")

WOOD = "wood"                # the dead woody body
BLEACHED = "sand_shadow"     # the straw-pale stems the reference has a few of
BLEACH_CHANCE = 0.22

GOLDEN_ANGLE = 137.507       # degrees — the spiral that never repeats

TRI_BUDGET = 250             # scatter vegetation, well under the 500 prop cap


def add_spike(
    part: Part,
    origin: Vector,
    direction: Vector,
    length: float,
    width: float,
    material: str,
    bend: Vector,
) -> None:
    """One stiff spike: a three-sided pyramid from `origin` to a point.

    Four triangles, three of them visible. `bend` displaces only the tip, which
    is enough to stop a stand of spikes looking machined without costing a
    second segment.
    """
    forward = direction.normalized()
    # Any perpendicular will do for the base triangle's orientation; Z fails
    # only when the spike points straight up, so fall back to X there.
    reference = Vector((0.0, 0.0, 1.0))
    if abs(forward.dot(reference)) > 0.98:
        reference = Vector((1.0, 0.0, 0.0))
    side = forward.cross(reference).normalized()
    other = forward.cross(side)

    base = len(part.verts)
    for i in range(3):
        angle = math.tau * i / 3.0
        part.verts.append(
            origin + (side * math.cos(angle) + other * math.sin(angle)) * width
        )
    part.verts.append(origin + forward * length + bend)

    apex = base + 3
    for i in range(3):
        part.faces.append((base + i, base + (i + 1) % 3, apex))
        part.face_materials.append(material)
    part.faces.append((base, base + 2, base + 1))   # base cap, facing back
    part.face_materials.append(material)


def build_shrub(name: str, spec: dict) -> Part:
    rng = random.Random(spec["seed"])
    part = Part(name)
    height: float = spec["height"]
    count: int = spec["spikes"]

    # The woody core. Short and thin: in the reference you can barely see it,
    # and every bit of it that shows is a bit the spikes failed to cover.
    core_top = height * 0.62
    part.drum((0.0, 0.0), -0.04, core_top, height * 0.085, height * 0.022,
              WOOD, sides=5)

    for i in range(count):
        # Cluster the spikes low — the reference is dense at the foot and
        # opens out toward the crown.
        t = (i / max(1, count - 1)) ** 1.35
        azimuth = math.radians(i * GOLDEN_ANGLE + rng.uniform(-9.0, 9.0))
        # Angled up even at the foot, steeper at the crown: this alone makes
        # the spindle, because a spike's reach is length * cos(pitch). Starting
        # nearly horizontal splayed the plant into a thistle; the reference
        # hugs its own core much more closely than that.
        pitch = math.radians(26.0 + 52.0 * t + rng.uniform(-8.0, 8.0))
        length = height * spec["spike_length"] * rng.uniform(0.78, 1.16) * (1.0 - 0.22 * t)
        width = height * spec["spike_width"] * rng.uniform(0.85, 1.15)

        attach = Vector((0.0, 0.0, -0.02 + core_top * t * 0.98))
        attach += Vector((math.cos(azimuth), math.sin(azimuth), 0.0)) * height * 0.05
        direction = Vector((
            math.cos(azimuth) * math.cos(pitch),
            math.sin(azimuth) * math.cos(pitch),
            math.sin(pitch),
        ))
        bend = Vector((
            rng.uniform(-1.0, 1.0), rng.uniform(-1.0, 1.0), rng.uniform(-0.6, 0.3)
        )) * length * 0.13
        material = BLEACHED if rng.random() < BLEACH_CHANCE else WOOD
        add_spike(part, attach, direction, length, width, material, bend)

    # The shaggy skirt: short spikes lying out and slightly down at the foot,
    # which is what stops the plant looking like it was pushed into the sand.
    for i in range(spec["skirt"]):
        azimuth = math.radians(i * GOLDEN_ANGLE * 2.0 + rng.uniform(-14.0, 14.0))
        pitch = math.radians(rng.uniform(-22.0, 2.0))
        length = height * spec["spike_length"] * rng.uniform(0.55, 0.85)
        direction = Vector((
            math.cos(azimuth) * math.cos(pitch),
            math.sin(azimuth) * math.cos(pitch),
            math.sin(pitch),
        ))
        attach = Vector((
            math.cos(azimuth) * height * 0.05,
            math.sin(azimuth) * height * 0.05,
            height * rng.uniform(0.01, 0.07),
        ))
        add_spike(
            part, attach, direction, length, height * spec["spike_width"] * 0.9,
            BLEACHED if rng.random() < BLEACH_CHANCE * 1.6 else WOOD,
            Vector((0.0, 0.0, -length * 0.12)),
        )
    return part


SHRUBS: dict[str, dict] = {
    # Spikes are deliberately thick. Needle-thin ones looked closer to the
    # reference in Blender and vanished entirely at the gameplay camera, where
    # anything under ~10 cm stops existing.
    "dry_shrub_small": dict(
        seed=811, height=0.42, spikes=19, skirt=7,
        spike_length=0.38, spike_width=0.070,
    ),
    "dry_shrub_mid": dict(
        seed=822, height=0.68, spikes=30, skirt=9,
        spike_length=0.34, spike_width=0.062,
    ),
    "dry_shrub_large": dict(
        seed=833, height=1.02, spikes=42, skirt=11,
        spike_length=0.31, spike_width=0.055,
    ),
}


def render_previews(objects: list) -> None:
    """A contact sheet of the family, per build_rocks.py — Workbench needs no
    GPU context in --background and renders flat material colour."""
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
        cursor += width * 0.5 + 0.30
        obj.location.x = cursor
        cursor += width * 0.5
        tallest = max(tallest, obj.dimensions.z)
    span = cursor

    os.makedirs(PREVIEW_DIR, exist_ok=True)
    centre = Vector((span * 0.5, 0.0, tallest * 0.45))
    fit = (span * 0.5) / math.tan(math.radians(17.5)) * 1.12
    shots = {
        "set": (0.0, 14.0, fit),
        "high": (18.0, 38.0, fit),
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
        scene.render.filepath = os.path.join(PREVIEW_DIR, "shrubs_preview_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("preview: %s" % scene.render.filepath)


def main() -> None:
    clear_scene()
    materials = all_materials()
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(MODELS, exist_ok=True)

    objects: list[bpy.types.Object] = []
    for name, spec in SHRUBS.items():
        part = build_shrub(name, spec)
        tris = part.triangle_count()
        if tris > TRI_BUDGET:
            raise SystemExit("%s is over its triangle budget (%d)" % (name, tris))
        # No collision: dry scrub the player walks straight through, the same
        # call the rocks make and for the same reasons.
        obj = part.emit(materials, collide=False)
        size = obj.dimensions
        print("%-16s %3d tris   %.2f x %.2f x %.2f m" % (
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
