"""Build the small adobe house — one room, arched portal, flat roof.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_house_small.py [-- --render] [-- --wall <palette>]

Writes  assets/blender/house_small.blend            (editable source of truth)
        assets/models/house_small.glb                (what Godot imports)
        docs/references/house_small_preview_*.png    (with --render)

The homestead's second building, and deliberately not a smaller copy of the
first. `tools/build_house.py` is a two-storey clay block with a square-headed
door and an external stair; this is a single whitewashed room with an arched
portal. A settlement made of one repeated house reads as a texture, not a
place — the two need to differ in silhouette, in tone, and in the shape of
their openings.

**Shape notes, from docs/references/ (Joshua's reference, 2026-08-14).**

Everything characteristic about the reference is at the openings and the
parapet: an arched doorway inside a surround that stands proud of the wall, a
tall arched window with a timber grille and a jutting sill, rows of protruding
viga ends near the roofline, and patches where the plaster has fallen away to
show the stone beneath. The walls themselves are plain — which is the point,
because it means every triangle can go to the details that carry the read.

The parapet runs above the roof slab on all four sides. That is what makes the
roof-off cutaway work here: hide one slab and you are looking down into a
walled room, exactly as the reference presents itself.

**Gameplay dimensions, per ART_DIRECTION — these bind, and an arch makes them
subtle.** The doorway must clear 2.10 m above the threshold (1.75 m player plus
the 0.35 m the step-up probe lifts the capsule) across the *whole* usable width,
and an arch is lowest at its edges. The arch here springs at 2.05 m over a
1.50 m opening, so at the jambs — 0.65 m off centre, where the clear 1.30 m
width ends — it still stands at 2.42 m. A shallower arch on the same opening
would look identical from outside and quietly become a locked door.

Materials are named exactly after resources/palette/ entries; the colours set
here only drive Blender's viewport (tools/map_palette_materials.py wires the
.glb to the palette .tres files).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import adobe  # noqa: E402
from lowpoly import PALETTE, Part, all_materials, clear_scene, export_glb  # noqa: E402

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND = os.path.join(PROJECT, "assets", "blender", "house_small.blend")
GLB = os.path.join(PROJECT, "assets", "models", "house_small.glb")
PREVIEW_DIR = os.path.join(PROJECT, "docs", "references")

# Whitewashed rather than clay: the first house already owns clay, and a
# village wants more than one wall tone. `--wall <palette>` renders a
# comparison ladder without touching the committed asset.
DEFAULT_WALL = "plaster"
WALL = "plaster"
SURROUND = "clay"       # the portal, the sill and the parapet coping
TRIM = "wood"           # vigas, door, window grille
DARK = "night_blue"     # window recess and door reveal, read as shadow
STONE = "sand_shadow"   # the exposed stonework where plaster has fallen away

# --- dimensions, metres ------------------------------------------------------
HALF_X = 3.30          # 6.60 m wide
HALF_Y = 2.80          # 5.60 m deep
WALL_T = 0.42
FOUNDATION = 0.25      # slab buried below z=0 so no gap can show under a wall
FLOOR_LIFT = 0.12      # ART_DIRECTION: interior floors stand proud of the sand

CEILING = 2.90         # wall top / roof underside — 2.78 m of real headroom
ROOF_T = 0.26
ROOF_TOP = CEILING + ROOF_T
PARAPET_TOP = ROOF_TOP + 0.62
COPING = 0.12          # the band of clay capping the parapet

DOOR_W = 1.50          # opening; jambs intrude 0.10 a side for 1.30 m clear
DOOR_SPRING = 2.05     # where the arch starts — see the headroom note above
DOOR_R = DOOR_W / 2.0
DOOR_CROWN = DOOR_SPRING + DOOR_R          # 2.80
PORTAL_BAND = 0.30     # width of the surround around the opening
PORTAL_OUT = 0.22      # how far it stands proud of the wall

WIN_W = 0.62
WIN_SILL = 0.95
WIN_SPRING = 1.95
WIN_R = WIN_W / 2.0
WIN_CROWN = WIN_SPRING + WIN_R             # 2.26

ARCH_STEPS = 7         # per quarter arc; 7 reads round at the gameplay camera

TRI_BUDGET = 2800      # house cap is 4,000; the two-storey one costs 2,136


def arg_value(flag: str, fallback: str) -> str:
    argv = sys.argv
    if flag in argv:
        index = argv.index(flag)
        if index + 1 < len(argv):
            return argv[index + 1]
    return fallback


def preview_tag() -> str:
    return "" if WALL == DEFAULT_WALL else "_" + WALL


# --- arches ------------------------------------------------------------------

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
    part: Part, axis: str, centre: float, springing: float, radius: float,
    outer: float, inner: float, material: str,
) -> None:
    """Turns a square-headed opening into an arched one.

    The wall is cut as a plain rectangle up to the arch's crown — which
    `wall_with_openings` can already do — and these two spandrels then fill the
    upper corners back in, leaving the arch. Much cheaper than cutting a curve,
    and every face stays a flat quad.
    """
    crown = springing + radius
    right = arc_points(centre, springing, radius, ARCH_STEPS, 0.0, math.pi / 2.0)
    left = arc_points(centre, springing, radius, ARCH_STEPS, math.pi / 2.0, math.pi)
    # The arc, then out to the square corner. prism re-winds each one.
    prism(part, right + [(centre + radius, crown)], axis, outer, inner, material)
    prism(part, left + [(centre - radius, crown)], axis, outer, inner, material)


def arch_band(
    part: Part, centre_x: float, springing: float,
    inner_r: float, outer_r: float, y0: float, y1: float, material: str,
) -> None:
    """The protruding arched surround: a band swept over the arch, rectangular
    in section. Built by stitching consecutive cross-sections, the same way the
    palm's trunk stitches its rings."""
    inner = arc_points(centre_x, springing, inner_r, ARCH_STEPS * 2)
    outer = arc_points(centre_x, springing, outer_r, ARCH_STEPS * 2)
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


# --- details -----------------------------------------------------------------

def stone_patch(
    part: Part, axis: str, face: float, outward: float,
    centre: tuple[float, float], stones: list[tuple[float, float, float, float]],
) -> None:
    """A patch where the plaster has fallen away. Each stone stands a
    centimetre or two proud, so flat shading catches an edge on it rather than
    leaving a flat decal that reads as a stain."""
    for ds, dz, w, h in stones:
        s0, s1 = centre[0] + ds, centre[0] + ds + w
        z0, z1 = centre[1] + dz, centre[1] + dz + h
        near, far = sorted((face, face + outward * 0.035))
        if axis == "x":
            part.box((near, s0, z0), (far, s1, z1), STONE)
        else:
            part.box((s0, near, z0), (s1, far, z1), STONE)


PATCH_STONES = [
    (0.00, 0.00, 0.22, 0.15), (0.24, 0.03, 0.17, 0.13),
    (0.05, 0.17, 0.19, 0.14), (0.26, 0.19, 0.20, 0.12),
    (0.14, 0.33, 0.16, 0.11),
]


def arched_window(
    part: Part, axis: str, outer: float, inner: float, centre_s: float,
) -> None:
    """Recess, grille and sill for one arched window."""
    facing = 1.0 if outer > inner else -1.0
    s0, s1 = centre_s - WIN_R, centre_s + WIN_R
    recess = outer - facing * 0.13
    grille = outer - facing * 0.05

    def place(a0: float, a1: float, b0: float, b1: float,
              c0: float, c1: float, material: str) -> None:
        lo_c, hi_c = min(c0, c1), max(c0, c1)
        if axis == "x":
            part.box((lo_c, a0, b0), (hi_c, a1, b1), material)
        else:
            part.box((a0, lo_c, b0), (a1, hi_c, b1), material)

    # The dark panel set back in the reveal, which is what reads as glass at
    # the gameplay camera — the same trick the two-storey house uses.
    place(s0, s1, WIN_SILL, WIN_CROWN, recess, recess - facing * 0.05, DARK)
    # Grille: two uprights and three rails. A real mashrabiya diamond would be
    # a couple of centimetres across and invisible at 23 m.
    for frac in (0.34, 0.66):
        s = s0 + (s1 - s0) * frac
        place(s - 0.028, s + 0.028, WIN_SILL, WIN_CROWN - 0.05,
              recess, grille, TRIM)
    for z in (1.25, 1.60, 1.95):
        place(s0, s1, z - 0.026, z + 0.026, recess, grille, TRIM)
    # Sill, proud of the wall and wider than the opening so it throws a line of
    # shadow that reads at distance.
    place(s0 - 0.11, s1 + 0.11, WIN_SILL - 0.13, WIN_SILL,
          outer + facing * 0.13, outer - facing * 0.05, SURROUND)


# --- the building ------------------------------------------------------------

def build_floor(materials: dict) -> bpy.types.Object:
    """The floor slab, in the wall tone. ART_DIRECTION: a floor level with the
    terrain leaves sand drawn over it, which looks exactly like having chosen a
    sand-coloured floor and survives 'fixing' the material."""
    part = Part("floor")
    part.box((-HALF_X, -HALF_Y, -FOUNDATION), (HALF_X, HALF_Y, FLOOR_LIFT), WALL)
    return part.emit(materials)


def build_walls(materials: dict) -> list[bpy.types.Object]:
    inner_x, inner_y = HALF_X - WALL_T, HALF_Y - WALL_T
    door = (-DOOR_R, DOOR_R)

    # Front: the doorway, cut square to the crown and arched by its spandrels.
    front = Part("wall_front")
    adobe.wall_with_openings(
        front, "y", HALF_Y, inner_y, (-HALF_X, HALF_X), (0.0, PARAPET_TOP),
        [(door[0], door[1], 0.0, DOOR_CROWN)], WALL)
    arched_opening(front, "y", 0.0, DOOR_SPRING, DOOR_R, HALF_Y, inner_y, WALL)
    arch_band(front, 0.0, DOOR_SPRING, DOOR_R, DOOR_R + PORTAL_BAND,
              HALF_Y, HALF_Y + PORTAL_OUT, SURROUND)
    for side in (-1.0, 1.0):
        front.box((side * DOOR_R, HALF_Y, 0.0),
                  (side * (DOOR_R + PORTAL_BAND), HALF_Y + PORTAL_OUT,
                   DOOR_SPRING), SURROUND)
    # No dark panel in the doorway. A window's recess *should* be an opaque
    # dark plane — that is the whole trick — but the same idea applied to a door
    # walls the entrance up: it read as a blue door from outside, and because
    # this object carries the building's collision it was solid to walk into as
    # well. A doorway is a hole. It stays a hole.
    adobe.vigas(front, "y", HALF_Y, (-HALF_X, HALF_X), CEILING - 0.30, 6, 1.0,
                TRIM, skip=(-1.2, 1.2))
    stone_patch(front, "y", HALF_Y, 1.0, (-2.55, 1.05), PATCH_STONES)

    back = Part("wall_back")
    adobe.wall_with_openings(
        back, "y", -HALF_Y, -inner_y, (-HALF_X, HALF_X), (0.0, PARAPET_TOP),
        [(-0.9 - WIN_R, -0.9 + WIN_R, WIN_SILL, WIN_CROWN)], WALL)
    arched_opening(back, "y", -0.9, WIN_SPRING, WIN_R, -HALF_Y, -inner_y, WALL)
    arched_window(back, "y", -HALF_Y, -inner_y, -0.9)
    adobe.vigas(back, "y", -HALF_Y, (-HALF_X, HALF_X), CEILING - 0.30, 6, -1.0,
                TRIM)

    left = Part("wall_left")
    adobe.wall_with_openings(
        left, "x", -HALF_X, -inner_x, (-HALF_Y, HALF_Y), (0.0, PARAPET_TOP),
        [(0.55 - WIN_R, 0.55 + WIN_R, WIN_SILL, WIN_CROWN)], WALL)
    arched_opening(left, "x", 0.55, WIN_SPRING, WIN_R, -HALF_X, -inner_x, WALL)
    arched_window(left, "x", -HALF_X, -inner_x, 0.55)
    adobe.vigas(left, "x", -HALF_X, (-HALF_Y, HALF_Y), CEILING - 0.30, 5, -1.0,
                TRIM)
    stone_patch(left, "x", -HALF_X, -1.0, (-1.85, 1.95), PATCH_STONES)

    right = Part("wall_right")
    adobe.wall_with_openings(
        right, "x", HALF_X, inner_x, (-HALF_Y, HALF_Y), (0.0, PARAPET_TOP),
        [(-0.35 - WIN_R, -0.35 + WIN_R, WIN_SILL, WIN_CROWN)], WALL)
    arched_opening(right, "x", -0.35, WIN_SPRING, WIN_R, HALF_X, inner_x, WALL)
    arched_window(right, "x", HALF_X, inner_x, -0.35)
    adobe.vigas(right, "x", HALF_X, (-HALF_Y, HALF_Y), CEILING - 0.30, 5, 1.0,
                TRIM)

    # Coping: a band of clay capping the parapet all the way round, which is
    # what stops the whitewashed walls reading as a plain white box from above.
    cap = Part("coping")
    for lo, hi in (
        ((-HALF_X, HALF_Y - WALL_T), (HALF_X, HALF_Y)),
        ((-HALF_X, -HALF_Y), (HALF_X, -HALF_Y + WALL_T)),
        ((-HALF_X, -HALF_Y), (-HALF_X + WALL_T, HALF_Y)),
        ((HALF_X - WALL_T, -HALF_Y), (HALF_X, HALF_Y)),
    ):
        # Sits *on* the parapet and oversails it slightly. Capping it flush
        # instead put the coping's outer face in the same plane as the wall's
        # and its top in the same plane as the wall top, and two coplanar faces
        # z-fight — which reads as a shimmering dashed line along the roofline.
        cap.box((lo[0] - 0.04, lo[1] - 0.04, PARAPET_TOP),
                (hi[0] + 0.04, hi[1] + 0.04, PARAPET_TOP + COPING), SURROUND)

    return [front.emit(materials), back.emit(materials), left.emit(materials),
            right.emit(materials), cap.emit(materials)]


def build_roof(materials: dict) -> bpy.types.Object:
    """The roof slab. Its own object so the interior cutaway can hide it and
    leave the player looking down into a walled room."""
    part = Part("roof")
    inner_x, inner_y = HALF_X - WALL_T, HALF_Y - WALL_T
    part.box((-inner_x - 0.02, -inner_y - 0.02, CEILING),
             (inner_x + 0.02, inner_y + 0.02, ROOF_TOP), STONE)
    return part.emit(materials)


def build_niches(materials: dict) -> bpy.types.Object:
    """Two recessed alcoves in the back interior wall.

    Joshua asked for the first house's interior as the reference, and what that
    interior actually is, is bare wall furnished by separate instanced props.
    Niches are the one thing the *shell* can contribute: they give the room a
    focal point, and they are where a level puts the oil lamp and the pottery
    that already exist as their own assets.
    """
    part = Part("niches")
    inner_y = HALF_Y - WALL_T
    for centre_x in (-1.35, 1.35):
        s0, s1 = centre_x - 0.30, centre_x + 0.30
        z0, z1 = 1.05, 1.80
        # The dark back panel, then a proud frame — the same recess idiom the
        # windows use, which reads as depth without cutting into the wall.
        part.box((s0, inner_y - 0.03, z0), (s1, inner_y - 0.01, z1), DARK)
        part.box((s0 - 0.08, inner_y - 0.10, z0 - 0.08),
                 (s0, inner_y - 0.02, z1 + 0.08), SURROUND)
        part.box((s1, inner_y - 0.10, z0 - 0.08),
                 (s1 + 0.08, inner_y - 0.02, z1 + 0.08), SURROUND)
        part.box((s0 - 0.08, inner_y - 0.10, z1),
                 (s1 + 0.08, inner_y - 0.02, z1 + 0.08), SURROUND)
        part.box((s0 - 0.08, inner_y - 0.12, z0 - 0.10),
                 (s1 + 0.08, inner_y - 0.02, z0 - 0.02), SURROUND)
    return part.emit(materials)


def report(objects: list) -> int:
    total = 0
    for obj in objects:
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        total += tris
        print("  %-22s %4d tris" % (obj.name, tris))
    print("  %-22s %4d tris  (budget %d)" % ("TOTAL", total, TRI_BUDGET))
    return total


def render_previews(objects: list) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = True
    shading.show_cavity = False
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 950
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("preview")
    scene.world.color = (0.72, 0.78, 0.82)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens_unit = "FOV"
    camera_data.angle = math.radians(35.0)
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera

    os.makedirs(PREVIEW_DIR, exist_ok=True)
    centre = Vector((0.0, 0.0, 1.7))
    shots = {
        "front": (18.0, 19.0, 22.0),   # the gameplay camera's own 19 deg pitch
        "door": (-6.0, 12.0, 13.0),    # close on the arched portal
        "window": (72.0, 15.0, 15.0),  # along the window wall
        "high": (26.0, 46.0, 22.0),    # into the room, roof notwithstanding
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
        scene.render.filepath = os.path.join(
            PREVIEW_DIR, "house_small_preview_%s%s.png" % (name, preview_tag()))
        bpy.ops.render.render(write_still=True)
        print("preview: %s" % scene.render.filepath)


def main() -> None:
    global WALL
    WALL = arg_value("--wall", DEFAULT_WALL)
    if WALL not in PALETTE:
        raise SystemExit("--wall must name a palette entry, got %r" % WALL)
    clear_scene()
    materials = all_materials()

    objects: list[bpy.types.Object] = [build_floor(materials)]
    objects.extend(build_walls(materials))
    objects.append(build_roof(materials))
    objects.append(build_niches(materials))

    total = report(objects)
    if total > TRI_BUDGET:
        raise SystemExit("house_small is over its triangle budget")

    if WALL != DEFAULT_WALL:
        # A ladder run exists only to be looked at; it must never overwrite the
        # committed asset with an unapproved wall tone.
        print("ladder run (--wall %s): rendering only, no export" % WALL)
        render_previews(objects)
        return

    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(os.path.dirname(GLB), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    export_glb(objects, GLB)
    print("wrote %s (%.0f KB)" % (GLB, os.path.getsize(GLB) / 1024))

    if "--render" in sys.argv:
        render_previews(objects)


main()
