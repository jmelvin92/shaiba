"""Build the sandstone scatter set — six independent ground rocks.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_rocks.py [-- --render]

Writes  assets/blender/rocks.blend          (editable source of all six)
        assets/models/rock_<name>.glb        one file per rock
        docs/references/rocks_preview_*.png  (with --render)

**Six separate .glb files, on purpose.** Each rock is its own asset so a level
can scatter them independently and mix them freely — the same rule PLAN.md
sets for furnishings. They share one .blend because editing them side by side
is how you keep a *set* looking like a set; they are separate objects in it,
so any one can be edited or re-exported alone.

**These are scatter texture, not landmarks** (Joshua, 2026-08-14). The whole
set is ankle-to-knee height: stones that break up bare sand and give the ground
something to read against, not boulders that block a path. The first pass built
them at 2–6 m and they dominated every shot they were in.

That size drives the modelling. ART_DIRECTION puts the detail floor at ~10 cm
at the gameplay camera, so a 0.3 m stone sliced into six strata is six 5 cm
bands that merge into mush. Small rocks therefore get two or three *chunky*
slabs and spend everything on silhouette instead.

**Shape notes, from docs/references/ (Joshua's reference, 2026-08-14).**

What makes these read as sandstone rather than as generic boulders is
horizontal stratification: the rock is a stack of slabs, each eroded back to
its own outline, and crucially some slabs are *wider* than the one below, so
the stack undercuts and overhangs instead of tapering like a cairn. Every rock
here is therefore built as a run of rings — two per slab, plus a zero-height
step between slabs that becomes the lip. Flat shading then does the work for
free: the near-horizontal lip and the near-vertical slab face take the warm
sun at completely different angles, so the strata read from across a dune with
no texture involved.

The outline is where the variation lives. Each rock draws one smooth harmonic
outline that every slab shares — that is what makes it one weathered rock
rather than a pile of unrelated discs — and each slab then deviates from it
slightly. Radii are also elongated per rock, so the set runs from a flat chip
to a low shelf without any two sharing a silhouette.

**No collision.** These are surface texture the player walks straight over —
the tallest is 0.38 m, under the 0.35 m step-up plus its own burial, so
colliding would only make walking across a scattered field feel lumpy, and a
few hundred static bodies is a real cost for no gain. Anything meant to block
movement wants to be its own, larger asset.

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
BLEND = os.path.join(PROJECT, "assets", "blender", "rocks.blend")
MODELS = os.path.join(PROJECT, "assets", "models")
PREVIEW_DIR = os.path.join(PROJECT, "docs", "references")

# Sandstone sits in the sand tones, which keeps `clay` reading as the built
# environment (the house) rather than as geology. `clay` still appears, but as
# the occasional iron-rich band — which is exactly what it is in real sandstone.
# A slab's top shelf takes its *own* slab's colour, not a lighter one. Giving
# lips their own pale material was the first pass and it was the single worst
# thing about it: a bright horizontal stripe at every stratum turned each rock
# into a stack of dinner plates. Flat shading already lights a horizontal shelf
# and a vertical face completely differently — the strata need no help.
STONE = "clay"          # the terracotta body, as in the reference
BAND = "sand_shadow"    # one recessed band per rock, where the stone is darker
CAP = "sand_mid"        # only the summit, which is genuinely sun-bleached

TRI_BUDGET = 250        # well under the 500 small-prop cap: these are tiny


def outline(sides: int, rng: random.Random, roughness: float) -> list[float]:
    """A closed per-vertex radius multiplier built from a few harmonics.

    Harmonics rather than per-vertex noise because noise gives a spiky star and
    weathered rock is lumpy: dividing each term by its own frequency keeps the
    high harmonics as small dents on big lobes.
    """
    # k=1 is the important one: it pushes the whole outline off-centre, which is
    # what stops a rock reading as a stack of concentric discs. Dividing by
    # sqrt(k) rather than k leaves the high harmonics strong enough to be
    # actual broken edges instead of a faint ripple.
    # k=1 is held back: it is what puts the outline off-centre, but at full
    # strength on an elongated rock it bows the whole thing into a crescent.
    weights = {1: 0.55, 2: 1.0, 3: 1.0, 5: 0.9}
    terms = [
        (rng.uniform(0.5, 1.0) * roughness * weights[k], rng.uniform(0.0, math.tau), k)
        for k in (1, 2, 3, 5)
    ]
    values: list[float] = []
    for i in range(sides):
        angle = math.tau * i / sides
        multiplier = 1.0
        for amplitude, phase, harmonic in terms:
            multiplier += amplitude * math.sin(harmonic * angle + phase) / math.sqrt(harmonic)
        values.append(max(0.45, multiplier))
    return values


def ring(
    centre: tuple[float, float],
    z: float,
    radius: float,
    shape: list[float],
    elongation: tuple[float, float],
) -> list[Vector]:
    sides = len(shape)
    points: list[Vector] = []
    for i in range(sides):
        angle = math.tau * i / sides
        r = radius * shape[i]
        points.append(Vector((
            centre[0] + math.cos(angle) * r * elongation[0],
            centre[1] + math.sin(angle) * r * elongation[1],
            z,
        )))
    return points


def stitch(part: Part, rings: list[list[Vector]], materials: list[str]) -> None:
    """Joins a run of same-sized rings into one closed solid.

    Rings run counter-clockwise seen from +Z and each is above the last, so
    this winding puts every normal outward — the same rule the palm's trunk
    uses. A pair of rings at the *same* z simply produces a horizontal band,
    which is how a slab's overhanging lip is made.
    """
    sides = len(rings[0])
    base = len(part.verts)
    for points in rings:
        part.verts.extend(points)

    for i in range(len(rings) - 1):
        lower = base + i * sides
        upper = base + (i + 1) * sides
        for k in range(sides):
            k2 = (k + 1) % sides
            part.faces.append((lower + k, lower + k2, upper + k2, upper + k))
            part.face_materials.append(materials[i])

    part.faces.append(tuple(range(base + sides - 1, base - 1, -1)))  # bottom
    part.face_materials.append(materials[0])
    top = base + (len(rings) - 1) * sides
    part.faces.append(tuple(range(top, top + sides)))
    part.face_materials.append(CAP)


def build_rock(name: str, spec: dict) -> Part:
    """One rock: a run of slabs sharing a single weathered outline.

    A slab is given one nominal radius and flares to `overhang` either side of
    it — wider at its foot, narrower at its shoulder. Because the nominal radii
    themselves shrink up the rock, each slab's foot lands proud of the shoulder
    below it and the overhang falls out for free, while the silhouette stays a
    convex mass. Setting the two radii by hand instead (the first pass) let the
    profile wander, and the rocks came out as pagodas.
    """
    rng = random.Random(spec["seed"])
    part = Part(name)
    sides: int = spec["sides"]
    overhang: float = spec["overhang"]
    base_shape = outline(sides, rng, spec["roughness"])

    rings: list[list[Vector]] = []
    materials: list[str] = []
    z = -spec["bury"]
    centre = [0.0, 0.0]

    slabs = [
        (thickness, radius * (1.0 + overhang), radius * (1.0 - overhang * 0.55))
        for thickness, radius in spec["profile"]
    ]
    # Pull the summit in hard. Left broad, the top cap is a flat disc, and at
    # the 19 deg camera you look straight down onto it — the whole field read
    # as little stools rather than stones.
    thickness, r_low, r_high = slabs[-1]
    slabs[-1] = (thickness, r_low, r_high * spec.get("top_taper", 0.5))
    for index, (thickness, r_low, r_high) in enumerate(slabs):
        # Each slab deviates a little from the rock's own outline, so the
        # strata differ without the rock coming apart into unrelated discs.
        wobble = outline(sides, rng, spec["roughness"] * 0.38)
        shape = [b * w for b, w in zip(base_shape, wobble)]
        body = spec.get("band", BAND) if index in spec["bands"] else spec.get("body", STONE)

        if rings:
            # Zero-height step from the slab below: this is the lip, and it is
            # what makes an overhang possible at all. It wears the *lower*
            # slab's colour, because it is that slab's own top surface.
            rings.append(ring(centre, z, r_low, shape, spec["elongation"]))
            materials.append(materials[-1])
        else:
            rings.append(ring(centre, z, r_low, shape, spec["elongation"]))

        # Slabs drift sideways as they stack — weathered rock leans, and a
        # perfectly co-axial stack reads as a cairn somebody built.
        centre[0] += rng.uniform(-1.0, 1.0) * spec["drift"]
        centre[1] += rng.uniform(-1.0, 1.0) * spec["drift"]
        z += thickness
        rings.append(ring(centre, z, r_high, shape, spec["elongation"]))
        materials.append(body)

    stitch(part, rings, materials)
    return part


# thickness and nominal radius per slab, bottom to top; `overhang` turns each
# pair into a flared slab (see build_rock). Radii are pre-elongation, so the
# finished width is roughly 2 * radius * elongation * 1.15 for the outline's
# average peak — the printed dimensions are the thing to tune against.
#
# Everything here is ankle-to-knee scale. Two or three slabs, because at this
# size a fourth is below the ~10 cm detail floor and just adds triangles.
ROCKS: dict[str, dict] = {
    "rock_pebble": dict(
        body=BAND, band=STONE,
        seed=101, sides=6, roughness=0.34, bury=0.030, drift=0.010,
        elongation=(1.30, 0.90), overhang=0.09, bands=(),
        profile=[(0.055, 0.085), (0.045, 0.070)],
    ),
    "rock_chip": dict(
        body=STONE, band=BAND,
        seed=202, sides=7, roughness=0.38, bury=0.025, drift=0.012,
        elongation=(1.25, 1.00), overhang=0.10, bands=(),
        profile=[(0.045, 0.125), (0.035, 0.105)],
    ),
    "rock_stone": dict(
        body=STONE, band=BAND,
        seed=303, sides=7, roughness=0.32, bury=0.060, drift=0.020,
        elongation=(1.20, 0.92), overhang=0.08, bands=(1,),
        profile=[(0.110, 0.175), (0.070, 0.170), (0.080, 0.130)],
    ),
    "rock_nub": dict(
        body=BAND, band=STONE,
        seed=404, sides=7, roughness=0.34, bury=0.060, drift=0.030,
        elongation=(1.05, 0.95), overhang=0.09, bands=(1,),
        profile=[(0.170, 0.155), (0.080, 0.148), (0.190, 0.112)],
    ),
    "rock_slab": dict(
        body=STONE, band=BAND,
        seed=505, sides=9, roughness=0.28, bury=0.050, drift=0.018,
        elongation=(1.90, 0.85), overhang=0.07, bands=(1,),
        profile=[(0.090, 0.215), (0.050, 0.212), (0.060, 0.178)],
    ),
    "rock_shelf": dict(
        body=BAND, band=STONE,
        seed=606, sides=10, roughness=0.26, bury=0.080, drift=0.025,
        elongation=(1.85, 1.00), overhang=0.07, bands=(2,),
        profile=[
            (0.140, 0.310), (0.080, 0.305),
            (0.100, 0.280), (0.060, 0.225),
        ],
    ),
}


def render_previews(objects: list) -> None:
    """A contact sheet of the whole set, laid out like the reference sheet.

    Workbench rather than EEVEE: no GPU context is needed in --background and
    it renders flat material colour, which is what the game's look actually is.
    """
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
    scene.world.color = (0.72, 0.78, 0.82)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens_unit = "FOV"
    camera_data.angle = math.radians(35.0)
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera

    # Spread the set along X so one shot reads as an assortment.
    cursor = 0.0
    for obj in objects:
        width = obj.dimensions.x
        cursor += width * 0.5 + 0.55
        obj.location.x = cursor
        cursor += width * 0.5
    span = cursor

    os.makedirs(PREVIEW_DIR, exist_ok=True)
    centre = Vector((span * 0.5, 0.0, 0.9))
    # A 35 deg horizontal lens needs (span/2) / tan(17.5 deg) to fit the row,
    # plus a margin — computing it beat guessing, which cropped the set in half.
    fit = (span * 0.5) / math.tan(math.radians(17.5)) * 1.12
    shots = {
        "set": (0.0, 17.0, fit),        # the gameplay camera's 19 deg-ish
        "high": (12.0, 40.0, fit),      # steeper, to read the strata tops
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
        scene.render.filepath = os.path.join(PREVIEW_DIR, "rocks_preview_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("preview: %s" % scene.render.filepath)


def main() -> None:
    clear_scene()
    materials = all_materials()
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(MODELS, exist_ok=True)

    objects: list[bpy.types.Object] = []
    for name, spec in ROCKS.items():
        part = build_rock(name, spec)
        tris = part.triangle_count()
        if tris > TRI_BUDGET:
            raise SystemExit("%s is over its triangle budget (%d)" % (name, tris))
        obj = part.emit(materials, collide=False)  # scatter texture: see module docstring
        size = obj.dimensions
        print("%-14s %3d tris   %.2f x %.2f x %.2f m" % (
            name, tris, size.x, size.y, size.z))
        objects.append(obj)

    # One .glb each: independently scatterable, mixed freely by a level.
    for obj in objects:
        clean = obj.name.removesuffix("-col")
        path = os.path.join(MODELS, "%s.glb" % clean)
        export_glb([obj], path)
        print("wrote %s (%.0f KB)" % (path, os.path.getsize(path) / 1024))

    bpy.ops.wm.save_as_mainfile(filepath=BLEND)

    if "--render" in sys.argv:
        render_previews(objects)


main()
