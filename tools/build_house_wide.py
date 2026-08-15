"""Build the wide adobe house — one long room, pointed portal, oversailing roof.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_house_wide.py [-- --render] [-- --wall <palette>]

Writes  assets/blender/house_wide.blend            (editable source of truth)
        assets/models/house_wide.glb                (what Godot imports)
        docs/references/house_wide_preview_*.png    (with --render)

The homestead's third building. The set now reads as a village because each
one differs where it counts:

    house        two storeys, clay, square heads, external stair, vigas
    house_small  one storey, plaster, round arch, protruding portal, parapet
    house_wide   one long room, clay, pointed arch, recessed portal, cornice

**Shape notes, from docs/references/ (Joshua's reference, 2026-08-14).**

Three things separate this from the small house, and all three are structural
rather than decorative. The roof is a slab that *oversails* the walls instead
of sitting inside a parapet, so the building is capped by a shadow line rather
than by a rim. The doorway is *recessed* — the wall is rebated back around a
wider arch, and the real opening sits inside that reveal — instead of standing
proud in a surround. And the arch is *pointed*: two arcs struck from offset
centres meeting at a point, not a semicircle.

There are no vigas, which is the reference's own choice and a welcome one:
without them the roofline is a single clean line, which is exactly the contrast
the small house's beam-studded parapet needs next to it.

**Why a pointed arch is the safer doorway.** ART_DIRECTION's rule is 2.10 m of
clear height over the threshold, and an arch is at its lowest where the usable
width ends, not at its crown. A two-centred arch on the same 1.50 m span stands
2.462 m at that point against a semicircle's 2.424 m — it buys headroom exactly
where the rule bites.

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
BLEND = os.path.join(PROJECT, "assets", "blender", "house_wide.blend")
GLB = os.path.join(PROJECT, "assets", "models", "house_wide.glb")
PREVIEW_DIR = os.path.join(PROJECT, "docs", "references")

DEFAULT_WALL = "clay"
WALL = "clay"
CORNICE = "sand_shadow"   # the oversailing roof slab, dust over mud
TRIM = "wood"             # window lattice
DARK = "night_blue"       # window recesses, read as shadow
STONE = "sand_shadow"     # exposed stonework: a shade off the clay, not a
                          # contrast. In plaster it read as white tiles stuck on.

# --- dimensions, metres ------------------------------------------------------
HALF_X = 4.00          # 8.00 m long
HALF_Y = 3.00          # 6.00 m deep
WALL_T = 0.42
FOUNDATION = 0.25
FLOOR_LIFT = 0.12      # ART_DIRECTION: interior floors stand proud of the sand

CEILING = 3.35         # 3.23 m of real headroom over the lifted floor
ROOF_T = 0.34
ROOF_TOP = CEILING + ROOF_T
OVERSAIL = 0.35        # how far the roof slab projects past the wall

DOOR_W = 1.50          # opening; jambs intrude 0.10 a side for 1.30 m clear
DOOR_R = DOOR_W / 2.0
DOOR_SPRING = 2.05
DOOR_POINT = 0.15      # how far each arc's centre sits past the middle
REBATE = 0.11          # the recess around the opening, a side
REBATE_DEPTH = 0.16    # how deep the wall is rebated back

WIN_W = 0.55
WIN_GAP = 0.34         # between the pair
WIN_SILL = 1.10
WIN_SPRING = 2.00
WIN_R = WIN_W / 2.0
WIN_POINT = 0.06

ARCH_STEPS = 7
TRI_BUDGET = 3200      # house cap is 4,000


def arg_value(flag: str, fallback: str) -> str:
    if flag in sys.argv:
        index = sys.argv.index(flag)
        if index + 1 < len(sys.argv):
            return sys.argv[index + 1]
    return fallback


def preview_tag() -> str:
    return "" if WALL == DEFAULT_WALL else "_" + WALL


def door_arch(half_span: float, springing: float = DOOR_SPRING,
              centre: float = 0.0) -> list[tuple[float, float]]:
    return adobe.pointed_arch(centre, springing, half_span, DOOR_POINT, ARCH_STEPS)


def window_arch(centre: float) -> list[tuple[float, float]]:
    return adobe.pointed_arch(centre, WIN_SPRING, WIN_R, WIN_POINT, ARCH_STEPS)


def crown_of(arc: list[tuple[float, float]]) -> float:
    return max(z for _, z in arc)


DOOR_CROWN = crown_of(door_arch(DOOR_R))
REBATE_CROWN = crown_of(door_arch(DOOR_R + REBATE))
WIN_CROWN = crown_of(window_arch(0.0))


def lattice(
    part: Part, axis: str, outer: float, inner: float,
    centre: float, sill: float, top: float,
) -> None:
    """A diagonal lattice over a window, as the reference has.

    Each bar is a thin parallelogram built corner-to-corner, so it lands inside
    the opening by construction. The first pass drew long diagonals and clipped
    them to the window's width, which sheared them into chevrons — clipping a
    parallelogram in one axis does not give you a shorter parallelogram.

    Three bars, not a full trellis: at the gameplay camera a real mashrabiya
    grid is well under the ~10 cm detail floor, and what has to survive is the
    *impression* of a lattice, which an X and a mullion give for 36 triangles.
    """
    facing = 1.0 if outer > inner else -1.0
    back = outer - facing * 0.10
    front = outer - facing * 0.04
    half = 0.024
    s0, s1 = centre - WIN_R + 0.05, centre + WIN_R - 0.05

    def bar(a: tuple[float, float], b: tuple[float, float]) -> None:
        ds, dz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(ds, dz)
        if length < 1e-4:
            return
        nx, nz = -dz / length * half, ds / length * half
        adobe.prism(part, [
            (a[0] - nx, a[1] - nz), (b[0] - nx, b[1] - nz),
            (b[0] + nx, b[1] + nz), (a[0] + nx, a[1] + nz),
        ], axis, front, back, TRIM)

    bar((s0, sill), (s1, top))
    bar((s1, sill), (s0, top))
    bar((centre, sill), (centre, top))


def pointed_window(
    part: Part, axis: str, outer: float, inner: float, centre: float,
) -> None:
    """Recess, lattice and sill for one pointed window."""
    facing = 1.0 if outer > inner else -1.0
    s0, s1 = centre - WIN_R, centre + WIN_R
    recess = outer - facing * 0.12

    def place(a0: float, a1: float, b0: float, b1: float,
              c0: float, c1: float, material: str) -> None:
        lo_c, hi_c = min(c0, c1), max(c0, c1)
        if axis == "x":
            part.box((lo_c, a0, b0), (hi_c, a1, b1), material)
        else:
            part.box((a0, lo_c, b0), (a1, hi_c, b1), material)

    place(s0, s1, WIN_SILL, WIN_CROWN, recess, recess - facing * 0.05, DARK)
    lattice(part, axis, outer, inner, centre, WIN_SILL, WIN_CROWN - 0.06)
    place(s0 - 0.09, s1 + 0.09, WIN_SILL - 0.10, WIN_SILL,
          outer + facing * 0.09, outer - facing * 0.05, WALL)


# --- the building ------------------------------------------------------------

def build_floor(materials: dict) -> bpy.types.Object:
    part = Part("floor")
    part.box((-HALF_X, -HALF_Y, -FOUNDATION), (HALF_X, HALF_Y, FLOOR_LIFT), WALL)
    return part.emit(materials)


def build_walls(materials: dict) -> list[bpy.types.Object]:
    inner_x, inner_y = HALF_X - WALL_T, HALF_Y - WALL_T
    rebate_face = HALF_Y - REBATE_DEPTH

    # Front: a rebated reveal in the outer skin, the real opening behind it.
    front = Part("wall_front")
    adobe.wall_with_openings(
        front, "y", HALF_Y, rebate_face, (-HALF_X, HALF_X), (0.0, CEILING),
        [(-DOOR_R - REBATE, DOOR_R + REBATE, 0.0, REBATE_CROWN)], WALL)
    adobe.arched_opening(front, "y", door_arch(DOOR_R + REBATE),
                         HALF_Y, rebate_face, WALL)
    adobe.wall_with_openings(
        front, "y", rebate_face, inner_y, (-HALF_X, HALF_X), (0.0, CEILING),
        [(-DOOR_R, DOOR_R, 0.0, DOOR_CROWN)], WALL)
    adobe.arched_opening(front, "y", door_arch(DOOR_R), rebate_face, inner_y, WALL)
    adobe.stone_patch(front, "y", HALF_Y, 1.0, (-2.05, 1.15), STONE)

    back = Part("wall_back")
    adobe.wall_with_openings(
        back, "y", -HALF_Y, -inner_y, (-HALF_X, HALF_X), (0.0, CEILING),
        [(1.20 - WIN_R, 1.20 + WIN_R, WIN_SILL, WIN_CROWN)], WALL)
    adobe.arched_opening(back, "y", window_arch(1.20), -HALF_Y, -inner_y, WALL)
    pointed_window(back, "y", -HALF_Y, -inner_y, 1.20)

    # The paired windows the reference puts on its end wall.
    pair = (-(WIN_W + WIN_GAP) / 2.0, (WIN_W + WIN_GAP) / 2.0)
    right = Part("wall_right")
    adobe.wall_with_openings(
        right, "x", HALF_X, inner_x, (-HALF_Y, HALF_Y), (0.0, CEILING),
        [(c - WIN_R, c + WIN_R, WIN_SILL, WIN_CROWN) for c in pair], WALL)
    for c in pair:
        adobe.arched_opening(right, "x", window_arch(c), HALF_X, inner_x, WALL)
        pointed_window(right, "x", HALF_X, inner_x, c)
    adobe.stone_patch(right, "x", HALF_X, 1.0, (-1.95, 2.45), STONE)

    left = Part("wall_left")
    adobe.wall_with_openings(
        left, "x", -HALF_X, -inner_x, (-HALF_Y, HALF_Y), (0.0, CEILING), [], WALL)

    return [front.emit(materials), back.emit(materials),
            left.emit(materials), right.emit(materials)]


def build_roof(materials: dict) -> bpy.types.Object:
    """The oversailing roof slab.

    Its own object so the interior cutaway can lift it. Because it projects
    past the walls rather than sitting inside a parapet, hiding it takes the
    building's whole cap away — which is the read this house wants, and the
    reason it looks different from the small house at a distance even before
    you notice the arch.
    """
    part = Part("roof")
    part.box((-HALF_X - OVERSAIL, -HALF_Y - OVERSAIL, CEILING),
             (HALF_X + OVERSAIL, HALF_Y + OVERSAIL, ROOF_TOP), CORNICE)
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
    scene.world.color = (0.86, 0.88, 0.90)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens_unit = "FOV"
    camera_data.angle = math.radians(35.0)
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera

    os.makedirs(PREVIEW_DIR, exist_ok=True)
    centre = Vector((0.0, 0.0, 1.8))
    shots = {
        "front": (32.0, 19.0, 26.0),   # the gameplay camera's own 19 deg pitch
        "door": (-4.0, 13.0, 17.0),    # onto the recessed portal
        "windows": (86.0, 14.0, 17.0),  # along the paired-window end
        "high": (30.0, 44.0, 25.0),
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
            PREVIEW_DIR, "house_wide_preview_%s%s.png" % (name, preview_tag()))
        bpy.ops.render.render(write_still=True)
        print("preview: %s" % scene.render.filepath)


def main() -> None:
    global WALL
    WALL = arg_value("--wall", DEFAULT_WALL)
    if WALL not in PALETTE:
        raise SystemExit("--wall must name a palette entry, got %r" % WALL)
    clear_scene()
    materials = all_materials()

    print("door arch: crown %.3f m, clear height at the jamb %.3f m "
          "(needs 2.10)" % (
              DOOR_CROWN,
              DOOR_SPRING + math.sqrt(
                  (DOOR_R + DOOR_POINT) ** 2 - (0.65 + DOOR_POINT) ** 2)))

    objects: list[bpy.types.Object] = [build_floor(materials)]
    objects.extend(build_walls(materials))
    objects.append(build_roof(materials))

    total = report(objects)
    if total > TRI_BUDGET:
        raise SystemExit("house_wide is over its triangle budget")

    if WALL != DEFAULT_WALL:
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
