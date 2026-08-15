"""Build the desert house from scratch.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_house.py [-- --render]

Writes  assets/blender/house.blend   (editable source of truth)
        assets/models/house.glb      (what Godot imports)
        docs/references/house_preview_*.png   (with --render)

The house is modelled procedurally out of boxes rather than by hand. Two
reasons: the export stays reproducible the way docs/ART_DIRECTION.md asks, and
a low-poly flat-shaded adobe building genuinely *is* a pile of boxes — every
edge in the reference (docs/references/house_exterior.png) is a right angle
except the awning.

Shape follows that reference: a two-story ochre cube, flat roof behind a
parapet, protruding roof-beam ends (vigas) in a row under each roofline,
wood-framed windows with sills, a cloth awning on poles over the door, and an
external stair up the right-hand side.

Two deliberate departures from the reference, both for gameplay:

* The stair stops at a landing outside the **upper-floor door** instead of
  continuing to the roof. It is the only way upstairs, which keeps an internal
  staircase out of a small floor plan, and the roof stays decorative for now.
* Doorways are open passages. The player walks in; the interior is real.

Objects are emitted **one per wall side per story**, not one per building. The
camera never moves to avoid geometry (docs/DECISIONS.md) — an OccluderFader
ghosts whatever blocks the shot — and it fades a whole GeometryInstance3D at a
time. One object per side means the wall between camera and player ghosts by
itself instead of taking the room's far wall and floor with it.

Materials are named exactly after resources/palette/ entries. The colours set
here are for Blender's viewport only: house.glb.import maps every material to
its palette .tres, so the game's colours come from the palette itself and a
palette edit reaches the house without a re-export.
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
BLEND = os.path.join(PROJECT, "assets", "blender", "house.blend")
GLB = os.path.join(PROJECT, "assets", "models", "house.glb")
PREVIEW_DIR = os.path.join(PROJECT, "docs", "references")

# Which palette entry each part of the house is made of. Kept here at the top
# because the wall tone is the one real art choice in the build and Joshua
# compares it as a ladder — swapping WALL changes every wall and the stair.
DEFAULT_WALL = "clay"
WALL = "clay"          # adobe mass: walls, parapet, stair (--wall <palette name>)
TRIM = "wood"          # vigas, window frames, sills, door jambs
DECK = "sand_shadow"   # the roof terrace, which really is dust over the slab
# (Window recesses used to carry a night_blue "shadow" panel; the openings are
# real holes since 2026-08-15 so interior lamplight can pass — see DECISIONS.)
CLOTH = "plaster"      # the awning

# --- dimensions, metres ------------------------------------------------------
# The player is 1.75 m tall (2.6 m interior clears them comfortably), and the
# camera sits 23 m out, so nothing below ~10 cm is modelled.
HALF_X = 4.0           # ground story is 8.0 m wide
HALF_Y = 3.5           # ... and 7.0 m deep
WALL_T = 0.4           # chunky adobe walls
INSET = 0.15           # upper story steps in this far: the batter of a mud wall

GROUND_TOP = 2.75      # top of the ground story's walls
SLAB_T = 0.30          # floor/ceiling slab between the stories
UPPER_BASE = GROUND_TOP + SLAB_T          # 3.05
UPPER_TOP = UPPER_BASE + 2.75             # 5.80
ROOF_T = 0.25
ROOF_TOP = UPPER_TOP + ROOF_T             # 6.05
PARAPET_H = 0.60
PARAPET_T = 0.30
FOUNDATION = 0.25      # slab buried below z=0 so no gap can show under a wall
# The interior floor stands this far proud of the ground the house is placed
# on. Two jobs: a floor exactly level with the terrain z-fights with it, and
# any residual unevenness in the ground leaves sand standing through the floor
# — which is precisely what happened when this was 0. It also gives the
# doorway an honest threshold to step over, the way a real adobe house does.
FLOOR_LIFT = 0.12

UPPER_HALF_X = HALF_X - INSET
UPPER_HALF_Y = HALF_Y - INSET

DOOR_W = 1.30
# Tall enough for the step-up probe, not just for the player. Crossing the
# threshold makes the controller raise the capsule by max_step_height (0.35 m)
# and push it forward to feel for the tread — so the doorway has to clear the
# player's 1.75 m *plus* that lift, above the threshold, or the raised capsule
# hits the lintel, the probe calls the step a wall, and the door is shut. At
# 2.10 m it was exactly that: passable with a flush floor, blocked the moment
# the floor was lifted 12 cm.
DOOR_H = 2.40
WIN_W = 1.20
WIN_H = 1.20
GROUND_SILL = 1.00     # window sill height on the ground floor
UPPER_SILL = UPPER_BASE + 0.95

# Stair: 11 risers from the ground to the upper floor landing.
#
# The tread is the load-bearing number, and it is set by the player's step-up
# rather than by taste. That probe raises the capsule and pushes it forward by
# its own radius plus the probe margin (0.35 + 0.06 m) to find the tread; if
# the next riser is inside that reach, the probe hits it and concludes the step
# is a wall, so the player stops dead at the bottom of the flight. Treads must
# therefore clear ~0.41 m. At 0.34 m — a perfectly normal-looking stair — this
# staircase was unclimbable, which is exactly the kind of failure that only a
# scripted walk finds (tools/verify_house.gd). 0.48 m leaves real margin and
# gives a 30 deg flight, gentler than the steep exterior stairs of the
# reference but the one that can actually be used.
STAIR_STEPS = 11
STAIR_RISE = UPPER_BASE / STAIR_STEPS
STAIR_TREAD = 0.48
# Wide enough that the 0.70 m-wide player has room to drift. The flight runs
# against the house wall on one side and its own parapet on the other, so the
# usable lane is the width less a body diameter — at 1.30 m that left 0.60 m,
# which is easy to wander out of half way up.
STAIR_W = 1.50
STAIR_Y0 = 3.30        # bottom step starts here and the flight climbs toward -Y
LANDING_D = 1.30

# The awning hangs just under the ground story's roofline, and the viga row
# steps around it — beams and cloth cannot occupy the same 20 cm.
AWNING_SPAN = (-2.45, 0.10)


def arg_value(flag: str, fallback: str) -> str:
    """Read `--flag value` from the args after Blender's own `--`."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if flag in argv and argv.index(flag) + 1 < len(argv):
        return argv[argv.index(flag) + 1]
    return fallback


def preview_tag() -> str:
    """Suffix that keeps a wall-tone ladder's renders from overwriting each
    other, so the variants can be flipped through side by side."""
    return "" if WALL == DEFAULT_WALL else "_wall_%s" % WALL


# --- openings ----------------------------------------------------------------
# A wall is built as the solid pieces *around* its openings rather than as a
# box with holes cut in it: fewer triangles, no boolean, and every face stays a
# clean quad for flat shading.

def wall_with_openings(
    part: Part,
    axis: str,
    outer: float,
    inner: float,
    span: tuple[float, float],
    height: tuple[float, float],
    openings: list[tuple[float, float, float, float]],
) -> None:
    """This building's walls, in this building's wall tone.

    The implementation moved to tools/adobe.py when the second house wanted it.
    The adapter stays because WALL is rebound at runtime by the `--wall` ladder,
    so the tone has to be read per call rather than bound once.
    """
    adobe.wall_with_openings(part, axis, outer, inner, span, height,
                             openings, WALL)


def window_furniture(
    part: Part,
    axis: str,
    outer: float,
    inner: float,
    span: tuple[float, float],
    height: tuple[float, float],
) -> None:
    """Frame, sill, mullion cross and shadowed recess for one window."""
    s0, s1 = span
    z0, z1 = height
    facing = 1.0 if outer > inner else -1.0
    face = outer
    recess = face - facing * 0.14
    frame_out = face - facing * 0.04
    frame_in = face + facing * 0.02

    def place(a0: float, a1: float, b0: float, b1: float, c0: float, c1: float,
              material: str) -> None:
        lo_c, hi_c = min(c0, c1), max(c0, c1)
        if axis == "x":
            part.box((lo_c, a0, b0), (hi_c, a1, b1), material)
        else:
            part.box((a0, lo_c, b0), (a1, hi_c, b1), material)

    # No panel fills the opening: windows are real holes, so lamplight from
    # inside spills out at night (Joshua's call, 2026-08-15 — supersedes the
    # original shadowed-recess panel).
    # Frame: four bars around the opening edge.
    place(s0, s0 + 0.09, z0, z1, frame_out, frame_in, TRIM)
    place(s1 - 0.09, s1, z0, z1, frame_out, frame_in, TRIM)
    place(s0, s1, z1 - 0.09, z1, frame_out, frame_in, TRIM)
    place(s0, s1, z0, z0 + 0.09, frame_out, frame_in, TRIM)
    # Mullion cross, on the recess plane so it silhouettes against the dark.
    mid_s = (s0 + s1) / 2
    mid_z = (z0 + z1) / 2
    place(mid_s - 0.035, mid_s + 0.035, z0, z1, recess, frame_out, TRIM)
    place(s0, s1, mid_z - 0.035, mid_z + 0.035, recess, frame_out, TRIM)
    # Sill: proud of the wall and wider than the opening, so it throws a line
    # of shadow that reads at gameplay distance.
    place(s0 - 0.10, s1 + 0.10, z0 - 0.12, z0,
          face + facing * 0.14, face - facing * 0.05, TRIM)


def door_furniture(
    part: Part,
    axis: str,
    outer: float,
    inner: float,
    span: tuple[float, float],
    top: float,
) -> None:
    """Jambs and a heavy lintel around an open doorway."""
    s0, s1 = span
    facing = 1.0 if outer > inner else -1.0
    frame_out = outer - facing * 0.04
    frame_in = outer + facing * 0.03

    def place(a0: float, a1: float, b0: float, b1: float, material: str) -> None:
        lo_c, hi_c = min(frame_out, frame_in), max(frame_out, frame_in)
        if axis == "x":
            part.box((lo_c, a0, b0), (hi_c, a1, b1), material)
        else:
            part.box((a0, lo_c, b0), (a1, hi_c, b1), material)

    place(s0 - 0.06, s0 + 0.10, 0.0, top, TRIM)
    place(s1 - 0.10, s1 + 0.06, 0.0, top, TRIM)
    place(s0 - 0.06, s1 + 0.06, top - 0.16, top + 0.10, TRIM)


def vigas(part: Part, axis: str, face: float, span: tuple[float, float],
          z_centre: float, count: int, outward: float,
          skip: tuple[float, float] | None = None) -> None:
    """This building's roof-beam ends, in its trim tone. See tools/adobe.py."""
    adobe.vigas(part, axis, face, span, z_centre, count, outward, TRIM, skip)


# --- the building ------------------------------------------------------------

def build_ground_floor(materials: dict) -> bpy.types.Object:
    """The ground storey's floor slab.

    Laid in WALL, the same tone as the slab overhead, so both storeys read as
    one building and a wall-tone change carries the floors with it. In
    `sand_shadow` this was a sand tone indoors — you walked through the door
    and still appeared to be standing on the desert.
    """
    part = Part("ground_floor")
    part.box((-HALF_X, -HALF_Y, -FOUNDATION), (HALF_X, HALF_Y, FLOOR_LIFT), WALL)
    return part.emit(materials)


def build_ground_walls(materials: dict) -> list[bpy.types.Object]:
    objects = []

    # Front (+Y): the door, with a window to its right.
    door_x = (-1.75, -1.75 + DOOR_W)
    win_x = (1.30, 1.30 + WIN_W)
    front = Part("ground_wall_front")
    wall_with_openings(
        front, "y", HALF_Y, HALF_Y - WALL_T, (-HALF_X, HALF_X), (0.0, GROUND_TOP),
        [(door_x[0], door_x[1], 0.0, DOOR_H),
         (win_x[0], win_x[1], GROUND_SILL, GROUND_SILL + WIN_H)],
    )
    door_furniture(front, "y", HALF_Y, HALF_Y - WALL_T, door_x, DOOR_H)
    window_furniture(front, "y", HALF_Y, HALF_Y - WALL_T, win_x,
                     (GROUND_SILL, GROUND_SILL + WIN_H))
    vigas(front, "y", HALF_Y, (-HALF_X, HALF_X), GROUND_TOP - 0.28, 7, 1.0,
          skip=AWNING_SPAN)
    objects.append(front.emit(materials))

    # Back (-Y): one window.
    back = Part("ground_wall_back")
    back_win = (-0.6, 0.6)
    wall_with_openings(
        back, "y", -HALF_Y, -HALF_Y + WALL_T, (-HALF_X, HALF_X), (0.0, GROUND_TOP),
        [(back_win[0], back_win[1], GROUND_SILL, GROUND_SILL + WIN_H)],
    )
    window_furniture(back, "y", -HALF_Y, -HALF_Y + WALL_T, back_win,
                     (GROUND_SILL, GROUND_SILL + WIN_H))
    vigas(back, "y", -HALF_Y, (-HALF_X, HALF_X), GROUND_TOP - 0.28, 7, -1.0)
    objects.append(back.emit(materials))

    # Left (-X): one window.
    left = Part("ground_wall_left")
    left_win = (-0.6, 0.6)
    wall_with_openings(
        left, "x", -HALF_X, -HALF_X + WALL_T, (-HALF_Y, HALF_Y), (0.0, GROUND_TOP),
        [(left_win[0], left_win[1], GROUND_SILL, GROUND_SILL + WIN_H)],
    )
    window_furniture(left, "x", -HALF_X, -HALF_X + WALL_T, left_win,
                     (GROUND_SILL, GROUND_SILL + WIN_H))
    vigas(left, "x", -HALF_X, (-HALF_Y, HALF_Y), GROUND_TOP - 0.28, 6, -1.0)
    objects.append(left.emit(materials))

    # Right (+X): the stair climbs this face, so the window goes behind it and
    # the viga row is left off — beams would spear the flight.
    right = Part("ground_wall_right")
    right_win = (-2.60, -1.40)
    wall_with_openings(
        right, "x", HALF_X, HALF_X - WALL_T, (-HALF_Y, HALF_Y), (0.0, GROUND_TOP),
        [(right_win[0], right_win[1], GROUND_SILL, GROUND_SILL + WIN_H)],
    )
    window_furniture(right, "x", HALF_X, HALF_X - WALL_T, right_win,
                     (GROUND_SILL, GROUND_SILL + WIN_H))
    objects.append(right.emit(materials))
    return objects


def build_upper_slab(materials: dict) -> bpy.types.Object:
    """The floor between the stories.

    Made of WALL, not DECK: its edge is exposed all the way round where the
    upper story steps in, and in a contrasting tone that ledge reads as a
    painted stripe wrapping the building instead of as one adobe mass.
    """
    part = Part("upper_slab")
    part.box((-HALF_X, -HALF_Y, GROUND_TOP), (HALF_X, HALF_Y, UPPER_BASE), WALL)
    return part.emit(materials)


def build_upper_walls(materials: dict) -> list[bpy.types.Object]:
    objects = []
    hx, hy = UPPER_HALF_X, UPPER_HALF_Y
    sill = UPPER_SILL
    top = sill + WIN_H

    front = Part("upper_wall_front")
    win_a = (-2.40, -1.20)
    win_b = (1.20, 2.40)
    wall_with_openings(
        front, "y", hy, hy - WALL_T, (-hx, hx), (UPPER_BASE, UPPER_TOP),
        [(win_a[0], win_a[1], sill, top), (win_b[0], win_b[1], sill, top)],
    )
    window_furniture(front, "y", hy, hy - WALL_T, win_a, (sill, top))
    window_furniture(front, "y", hy, hy - WALL_T, win_b, (sill, top))
    vigas(front, "y", hy, (-hx, hx), UPPER_TOP - 0.28, 7, 1.0)
    objects.append(front.emit(materials))

    back = Part("upper_wall_back")
    back_win = (-0.6, 0.6)
    wall_with_openings(
        back, "y", -hy, -hy + WALL_T, (-hx, hx), (UPPER_BASE, UPPER_TOP),
        [(back_win[0], back_win[1], sill, top)],
    )
    window_furniture(back, "y", -hy, -hy + WALL_T, back_win, (sill, top))
    vigas(back, "y", -hy, (-hx, hx), UPPER_TOP - 0.28, 7, -1.0)
    objects.append(back.emit(materials))

    left = Part("upper_wall_left")
    left_win = (-0.6, 0.6)
    wall_with_openings(
        left, "x", -hx, -hx + WALL_T, (-hy, hy), (UPPER_BASE, UPPER_TOP),
        [(left_win[0], left_win[1], sill, top)],
    )
    window_furniture(left, "x", -hx, -hx + WALL_T, left_win, (sill, top))
    vigas(left, "x", -hx, (-hy, hy), UPPER_TOP - 0.28, 6, -1.0)
    objects.append(left.emit(materials))

    # Right (+X): the door the external stair delivers you to.
    right = Part("upper_wall_right")
    door_y = (-1.60, -1.60 + DOOR_W)
    wall_with_openings(
        right, "x", hx, hx - WALL_T, (-hy, hy), (UPPER_BASE, UPPER_TOP),
        [(door_y[0], door_y[1], UPPER_BASE, UPPER_BASE + DOOR_H)],
    )
    door_upper = Part("_tmp")
    door_furniture(door_upper, "x", hx, hx - WALL_T, door_y, DOOR_H)
    # door_furniture builds from z=0; lift its boxes to the upper floor.
    for vert in door_upper.verts:
        vert.z += UPPER_BASE
    right.verts.extend(door_upper.verts)
    offset = len(right.verts) - len(door_upper.verts)
    right.faces.extend(
        tuple(i + offset for i in face) for face in door_upper.faces
    )
    right.face_materials.extend(door_upper.face_materials)
    vigas(right, "x", hx, (-hy, hy), UPPER_TOP - 0.28, 6, 1.0)
    objects.append(right.emit(materials))
    return objects


def build_roof(materials: dict) -> bpy.types.Object:
    part = Part("roof")
    hx, hy = UPPER_HALF_X, UPPER_HALF_Y
    part.box((-hx, -hy, UPPER_TOP), (hx, hy, ROOF_TOP), DECK)
    top = ROOF_TOP + PARAPET_H
    part.box((-hx, hy - PARAPET_T, ROOF_TOP), (hx, hy, top), WALL)
    part.box((-hx, -hy, ROOF_TOP), (hx, -hy + PARAPET_T, top), WALL)
    part.box((-hx, -hy + PARAPET_T, ROOF_TOP),
             (-hx + PARAPET_T, hy - PARAPET_T, top), WALL)
    part.box((hx - PARAPET_T, -hy + PARAPET_T, ROOF_TOP),
             (hx, hy - PARAPET_T, top), WALL)
    return part.emit(materials)


def build_stair(materials: dict) -> bpy.types.Object:
    """The external flight up the right-hand wall to the upper-floor landing.

    Steps are solid to the ground rather than floating treads, which is both
    how an adobe stair is built and one fewer way for the player to fall
    through. Each tread is yawed a fraction of a degree for the same hand-built
    look as the vigas.
    """
    part = Part("stair")
    x0 = HALF_X
    x1 = HALF_X + STAIR_W
    for i in range(STAIR_STEPS):
        top = STAIR_RISE * (i + 1)
        y_hi = STAIR_Y0 - STAIR_TREAD * i
        y_lo = y_hi - STAIR_TREAD
        yaw = (0.5, -0.7, 0.3, -0.4)[i % 4]
        part.box((x0, y_lo, -FOUNDATION), (x1, y_hi, top), WALL, yaw)

    # Landing outside the upper door, reaching back to the inset upper wall so
    # there is no gap to step over.
    landing_hi = STAIR_Y0 - STAIR_TREAD * STAIR_STEPS
    landing_lo = landing_hi - LANDING_D
    part.box((UPPER_HALF_X, landing_lo, UPPER_BASE - 0.30),
             (x1, landing_hi, UPPER_BASE), WALL)

    # Outer parapet: one solid with a cleanly sloped top following the flight,
    # levelling off along the landing — the diagonal wedge that reads as "stair"
    # from across the courtyard, long before the treads themselves resolve.
    #
    # The slope needs its knee at the stair head. Drawn as one straight line to
    # the far end of the landing (as it first was), the top sags below the
    # treads' rise and is only ~0.15 m above them near the head — which the
    # player's step-up rightly reads as a step, so drifting against the rail
    # walked you over it and off the outside of the flight. A rail only guards
    # what stays more than max_step_height above the walking surface beside it.
    rail = 0.85
    profile = [
        (STAIR_Y0, -FOUNDATION),
        (STAIR_Y0, STAIR_RISE + rail),
        (landing_hi, UPPER_BASE + rail),
        (landing_lo - 0.28, UPPER_BASE + rail),
        (landing_lo - 0.28, -FOUNDATION),
    ]
    part.extruded_profile(profile, x1, x1 + 0.28, WALL)
    # Return across the head of the landing, so it is walled on both sides.
    part.box((UPPER_HALF_X, landing_lo - 0.28, -FOUNDATION),
             (x1 + 0.28, landing_lo, UPPER_BASE + rail), WALL)
    return part.emit(materials)


def build_awning(materials: dict) -> bpy.types.Object:
    """Cloth on two poles over the front door.

    The sheet is a grid so it can sag: it leaves the wall high, falls to the
    poles, and dips between them the way a slack cloth does. It is the only
    curve on the building, which is exactly why it earns its triangles — it
    keeps the front from reading as pure box.
    """
    part = Part("awning")
    x_lo, x_hi = AWNING_SPAN
    y_wall = HALF_Y
    y_out = HALF_Y + 1.40
    # Hung high, just under the roofline, and shallow: slung any lower it hides
    # the doorway it is supposed to advertise at the 19 deg gameplay camera.
    z_wall, z_out = 2.70, 2.44
    cols, rows = 7, 4
    grid = []
    for r in range(rows):
        v = r / (rows - 1)
        y = y_wall + (y_out - y_wall) * v
        row = []
        for c in range(cols):
            u = c / (cols - 1)
            x = x_lo + (x_hi - x_lo) * u
            z = z_wall + (z_out - z_wall) * v
            # Sag: strongest at the free edge and mid-span, zero at the wall
            # and at the poles that hold the corners up.
            sag = 0.20 * v * math.sin(math.pi * u)
            row.append(Vector((x, y, z - sag)))
        grid.append(row)
    part.quad_grid(grid, CLOTH, thickness=0.05)

    for x in (x_lo + 0.12, x_hi - 0.12):
        part.box((x - 0.065, y_out - 0.13, 0.0),
                 (x + 0.065, y_out + 0.00, z_out - 0.02), TRIM)
    return part.emit(materials)


def report(objects: list[bpy.types.Object]) -> None:
    total = 0
    print("--- house parts ---")
    for obj in objects:
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        total += tris
        print("  %-22s %5d tris" % (obj.name, tris))
    print("  %-22s %5d tris  (budget 4000)" % ("TOTAL", total))

    lowest = min(min(v.co.z for v in o.data.vertices) for o in objects)
    highest = max(max(v.co.z for v in o.data.vertices) for o in objects)
    print("height: %.2f m  (foundation %.2f m below grade)" % (highest, -lowest))


def render_previews(objects: list[bpy.types.Object]) -> None:
    """Workbench previews at roughly the gameplay camera.

    Workbench rather than EEVEE because it needs no GPU context in --background
    and renders flat material colour, which is what the game's look actually
    is. These are for proportion and silhouette; the real colour check is a
    screenshot of the running game.
    """
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
    centre = Vector((0.0, 0.0, 2.6))
    # The house faces +Y, so a camera in front of it stands at positive Y and
    # swings toward +X to bring the stair side into shot.
    shots = {
        "front": (20.0, 19.0, 30.0),   # the gameplay camera's own 19 deg pitch
        "door": (-28.0, 16.0, 21.0),   # swung the other way, onto the entrance
        "stair": (62.0, 20.0, 30.0),   # along the stair side
        "high": (28.0, 40.0, 28.0),    # steeper, for reading proportion
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
            PREVIEW_DIR, "house_preview_%s%s.png" % (name, preview_tag())
        )
        bpy.ops.render.render(write_still=True)
        print("preview: %s" % scene.render.filepath)


def main() -> None:
    global WALL
    WALL = arg_value("--wall", DEFAULT_WALL)
    if WALL not in PALETTE:
        raise SystemExit("--wall must name a palette entry, got %r" % WALL)
    clear_scene()
    materials = all_materials()

    objects: list[bpy.types.Object] = []
    objects.append(build_ground_floor(materials))
    objects.extend(build_ground_walls(materials))
    objects.append(build_upper_slab(materials))
    objects.extend(build_upper_walls(materials))
    objects.append(build_roof(materials))
    objects.append(build_stair(materials))
    objects.append(build_awning(materials))

    report(objects)

    if WALL != DEFAULT_WALL:
        # A ladder run only exists to be looked at; it must never overwrite the
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
