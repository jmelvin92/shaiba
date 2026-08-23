"""Build the sand worm — the titan (Phase 6.8, Part 2).

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_worm.py

Writes  assets/blender/worm.blend
        assets/models/worm.glb

Design source: Joshua's reference (docs/references/worm_reference.png) — a
Dune-style worm of shingled ring plates, a head slightly wider than the body,
and a tri-lobed mouth opening around teeth rings and a dark gullet — rebuilt
in the palette at the picked titan scale: 26 m long, 3.4 m body diameter.

Rig: one spine chain (spine_00 at the mouth rim back to spine_15 at the
tail) plus three mouth-lip bones (lip_0/1/2) parented to spine_00. Skinning
is RIGID — every vertex belongs 100% to one bone — so the plates hinge at
the joints like armor instead of stretching, which is the flat-shaded look.
The body is driven procedurally in Godot (sand_worm.gd positions every bone
along the burrow path each tick), so there are no actions to export.

Geometry constants below are mirrored by scenes/props/sand_worm/sand_worm.gd
(bone arc offsets, lip hinge points) — change one, change both.

Facing: nose toward +Y in Blender (the checklist's forward), spine along the
Y axis at Z = 0 (a burrower has no "feet on ground" plane; the node never
stands, its bones are posed in world space).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lowpoly import all_materials, clear_scene, export_glb  # noqa: E402

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND = os.path.join(PROJECT, "assets", "blender", "worm.blend")
GLB = os.path.join(PROJECT, "assets", "models", "worm.glb")

TRI_BUDGET = 6000

# --- the titan's proportions, metres (the Part 1 ladder pick) --------------
NOSE_LEN = 2.3        # mouth lips, rim to tip
HEAD_LEN = 1.6        # the flared head plate behind the rim
BODY_RINGS = 14
RING_PITCH = 1.45     # spine distance between body-ring boundaries
TAIL_LEN = 1.8        # tail cone
TOTAL_LEN = NOSE_LEN + HEAD_LEN + BODY_RINGS * RING_PITCH + TAIL_LEN  # 26.0

BODY_R = 1.7          # max body radius (3.4 m diameter)
HEAD_R = 1.85         # head flare, slightly wider than the body
RIM_R = 1.55          # mouth rim circle the lips hinge on
TAIL_R = 0.55         # last ring before the tail cone
SIDES = 12            # ring facets: reads round at 23 m, cheap

LIP_COUNT = 3
LIP_GAP = 0.10        # radians of gap between lip lobes
LIP_THICK = 0.24      # shell thickness (inner face offset)
LIP_ROWS = 4
LIP_COLS = 5

TEETH = [
    # (y, base circle radius, count, tooth length, tooth base radius)
    (-0.15, 1.30, 14, 0.55, 0.16),
    (-0.75, 1.00, 10, 0.45, 0.13),
]
THROAT_DEPTH = 2.8    # gullet reaches this far behind the rim
THROAT_END_R = 0.55


class WormMesh:
    """One mesh, faces tagged with material and vertex group names."""

    def __init__(self) -> None:
        self.verts: list[Vector] = []
        self.faces: list[tuple[int, ...]] = []
        self.face_materials: list[str] = []
        self.groups: dict[str, list[int]] = {}

    def vert(self, x: float, y: float, z: float, group: str) -> int:
        index = len(self.verts)
        self.verts.append(Vector((x, y, z)))
        self.groups.setdefault(group, []).append(index)
        return index

    def face(self, indices: tuple[int, ...], material: str) -> None:
        self.faces.append(indices)
        self.face_materials.append(material)

    def ring(self, y: float, radius: float, group: str) -> list[int]:
        return [
            self.vert(
                math.cos(math.tau * i / SIDES) * radius,
                y,
                math.sin(math.tau * i / SIDES) * radius,
                group,
            )
            for i in range(SIDES)
        ]

    def tube(self, a: list[int], b: list[int], material: str,
             inward: bool = False) -> None:
        n = len(a)
        for i in range(n):
            j = (i + 1) % n
            quad = (a[i], a[j], b[j], b[i])
            self.face(quad[::-1] if inward else quad, material)

    def triangle_count(self) -> int:
        return sum(len(f) - 2 for f in self.faces)


def spine_y(bone: int) -> float:
    """Spine bone positions along Y: 0 at the rim, negative toward the tail."""
    if bone == 0:
        return 0.0
    return -HEAD_LEN - (bone - 1) * RING_PITCH


def lip_hinge(index: int) -> tuple[float, Vector, Vector]:
    """One lip's hinge: (arc centre angle, hinge point on the rim, outward)."""
    angle = math.tau * index / LIP_COUNT + math.pi / 2.0
    outward = Vector((math.cos(angle), 0.0, math.sin(angle)))
    return angle, outward * RIM_R, outward


def body_radius(i: int) -> float:
    """Body stays near-full through most of its length, tapering late — the
    reference is a blunt column, not a spike."""
    t = max(0.0, (i - 8) / float(BODY_RINGS - 8))
    return BODY_R * (1.0 - 0.62 * t * t)


def build_body(mesh: WormMesh) -> None:
    # Head: a flared hood, wider than the body, its rim curling forward over
    # the mouth (the reference's cowl). Front face from the mouth rim out to
    # the flare edge, then the hood wall running back.
    lip_edge = mesh.ring(0.35, RIM_R * 1.02, "spine_00")
    flare = mesh.ring(0.0, HEAD_R, "spine_00")
    mesh.tube(lip_edge, flare, "sand_shadow")  # shaded underside of the cowl
    hood_mid = mesh.ring(-HEAD_LEN * 0.45, HEAD_R * 1.03, "spine_00")
    hood_back = mesh.ring(-HEAD_LEN, BODY_R * 0.92, "spine_00")
    mesh.tube(flare, hood_mid, "plaster")
    mesh.tube(hood_mid, hood_back, "plaster")

    # Body rings: each plate bulges outward between two dark recessed
    # grooves, and each front lip stands proud of the plate behind it —
    # that step plus the groove shadow is what draws the segmentation.
    prev_recess = hood_back
    for i in range(BODY_RINGS):
        y_front = -HEAD_LEN - i * RING_PITCH
        group = "spine_%02d" % (i + 1)
        radius = body_radius(i)
        lip = mesh.ring(y_front - 0.06, radius * 1.04, group)
        mesh.tube(prev_recess, lip, "sand_shadow")  # groove climbing to the lip
        bulge = mesh.ring(y_front - RING_PITCH * 0.45, radius * 1.09, group)
        rear = mesh.ring(y_front - RING_PITCH * 0.92, radius * 0.98, group)
        mesh.tube(lip, bulge, "plaster")
        mesh.tube(bulge, rear, "plaster")
        recess = mesh.ring(y_front - RING_PITCH, radius * 0.88, group)
        mesh.tube(rear, recess, "sand_shadow")  # falling into the next groove
        prev_recess = recess

    # Tail: two shrinking plates then the cone tip.
    y = -HEAD_LEN - BODY_RINGS * RING_PITCH
    last = body_radius(BODY_RINGS - 1)
    plate = mesh.ring(y - 0.10, last * 0.9, "spine_15")
    mesh.tube(prev_recess, plate, "sand_shadow")
    plate_rear = mesh.ring(y - TAIL_LEN * 0.55, last * 0.62, "spine_15")
    mesh.tube(plate, plate_rear, "plaster")
    tip = mesh.vert(0.0, -TOTAL_LEN + NOSE_LEN, 0.0, "spine_15")
    for i in range(SIDES):
        j = (i + 1) % SIDES
        mesh.face((plate_rear[i], plate_rear[j], tip), "plaster")


def build_mouth(mesh: WormMesh) -> None:
    # Throat: an inward-facing funnel from the rim down the gullet.
    rim = mesh.ring(0.0, RIM_R, "spine_00")
    mid = mesh.ring(-THROAT_DEPTH * 0.45, RIM_R * 0.72, "spine_00")
    end = mesh.ring(-THROAT_DEPTH, THROAT_END_R, "spine_00")
    mesh.tube(rim, mid, "night_blue", inward=True)
    mesh.tube(mid, end, "night_blue", inward=True)
    cap = mesh.vert(0.0, -THROAT_DEPTH - 0.3, 0.0, "spine_00")
    for i in range(SIDES):
        j = (i + 1) % SIDES
        mesh.face((end[j], end[i], cap), "night_blue")

    # Teeth: concentric rings of inward-leaning pyramids.
    for y, circle_r, count, length, base_r in TEETH:
        for k in range(count):
            angle = math.tau * k / count + (0.5 if y < -0.5 else 0.0)
            outward = Vector((math.cos(angle), 0.0, math.sin(angle)))
            side = Vector((-outward.z, 0.0, outward.x))
            root = outward * circle_r + Vector((0.0, y, 0.0))
            # Tip leans inward and slightly back — the reference's rings of
            # recurved hooks.
            tip_at = root - outward * (length * 0.8) + Vector((0.0, -length * 0.5, 0.0))
            b0 = root + side * base_r + Vector((0.0, base_r, 0.0))
            b1 = root - side * base_r + Vector((0.0, base_r, 0.0))
            b2 = root + Vector((0.0, -base_r * 1.2, 0.0))
            base = [mesh.vert(v.x, v.y, v.z, "spine_00") for v in (b0, b1, b2)]
            apex = mesh.vert(tip_at.x, tip_at.y, tip_at.z, "spine_00")
            mesh.face((base[0], base[1], apex), "plaster")
            mesh.face((base[1], base[2], apex), "plaster")
            mesh.face((base[2], base[0], apex), "plaster")


def build_lips(mesh: WormMesh) -> None:
    """Three closed lobes forming the nose cone; each is a shell (outer
    plaster, inner sand_shadow, side walls) in its own lip group so the bone
    can swing it open."""
    lobe_span = math.tau / LIP_COUNT - LIP_GAP
    for lip in range(LIP_COUNT):
        centre_angle, _, _ = lip_hinge(lip)
        group = "lip_%d" % lip
        outer_rows: list[list[int]] = []
        inner_rows: list[list[int]] = []
        for row in range(LIP_ROWS + 1):
            t = row / float(LIP_ROWS)
            y = NOSE_LEN * t
            radius = (RIM_R * (1.0 - t) + 0.14 * t) * (1.0 + 0.16 * math.sin(math.pi * t))
            out_ring: list[int] = []
            in_ring: list[int] = []
            for col in range(LIP_COLS + 1):
                s = col / float(LIP_COLS) - 0.5
                angle = centre_angle + s * lobe_span
                x, z = math.cos(angle), math.sin(angle)
                out_ring.append(mesh.vert(x * radius, y, z * radius, group))
                inner_r = max(radius - LIP_THICK, 0.03)
                in_ring.append(mesh.vert(x * inner_r, y, z * inner_r, group))
            outer_rows.append(out_ring)
            inner_rows.append(in_ring)
        for row in range(LIP_ROWS):
            for col in range(LIP_COLS):
                o0, o1 = outer_rows[row][col], outer_rows[row][col + 1]
                o2, o3 = outer_rows[row + 1][col + 1], outer_rows[row + 1][col]
                mesh.face((o0, o1, o2, o3), "plaster")
                i0, i1 = inner_rows[row][col], inner_rows[row][col + 1]
                i2, i3 = inner_rows[row + 1][col + 1], inner_rows[row + 1][col]
                mesh.face((i3, i2, i1, i0), "sand_shadow")
        # Side and rim walls sealing the shell (seen when the mouth opens).
        for row in range(LIP_ROWS):
            for side_col in (0, LIP_COLS):
                o0, o1 = outer_rows[row][side_col], outer_rows[row + 1][side_col]
                i0, i1 = inner_rows[row][side_col], inner_rows[row + 1][side_col]
                quad = (o0, o1, i1, i0)
                mesh.face(quad if side_col == 0 else quad[::-1], "sand_shadow")
        for col in range(LIP_COLS):
            o0, o1 = outer_rows[0][col], outer_rows[0][col + 1]
            i0, i1 = inner_rows[0][col], inner_rows[0][col + 1]
            mesh.face((o1, o0, i0, i1), "sand_shadow")


def build_armature() -> bpy.types.Object:
    armature = bpy.data.armatures.new("WormRig")
    arm_obj = bpy.data.objects.new("WormRig", armature)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    edit = armature.edit_bones
    previous = None
    for k in range(16):
        bone = edit.new("spine_%02d" % k)
        y = spine_y(k)
        bone.head = (0.0, y, 0.0)
        bone.tail = (0.0, y - (RING_PITCH if k > 0 else HEAD_LEN), 0.0)
        if previous is not None:
            bone.parent = previous
        previous = bone
    head_bone = edit["spine_00"]
    for lip in range(LIP_COUNT):
        _, hinge, outward = lip_hinge(lip)
        bone = edit.new("lip_%d" % lip)
        bone.head = tuple(hinge)
        bone.tail = tuple(hinge + Vector((0.0, 1.2, 0.0)) - outward * 0.4)
        bone.parent = head_bone
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def main() -> None:
    clear_scene()
    materials = all_materials()

    mesh_data = WormMesh()
    build_body(mesh_data)
    build_mouth(mesh_data)
    build_lips(mesh_data)

    tris = mesh_data.triangle_count()
    print("worm: %d tris (budget %d), length %.1f m, body %.1f m dia" % (
        tris, TRI_BUDGET, TOTAL_LEN, BODY_R * 2.0
    ))
    assert tris <= TRI_BUDGET, "over the tri budget"
    assert abs(TOTAL_LEN - 26.0) < 1e-6, "the titan is 26 m — the rig contract"

    mesh = bpy.data.meshes.new("Worm")
    mesh.from_pydata([tuple(v) for v in mesh_data.verts], [], mesh_data.faces)
    used: list[str] = []
    for name in mesh_data.face_materials:
        if name not in used:
            used.append(name)
            mesh.materials.append(materials[name])
    index_of = {name: i for i, name in enumerate(used)}
    for polygon, name in zip(mesh.polygons, mesh_data.face_materials):
        polygon.material_index = index_of[name]
        polygon.use_smooth = False
    mesh.update()
    mesh_obj = bpy.data.objects.new("Worm", mesh)
    bpy.context.collection.objects.link(mesh_obj)

    arm_obj = build_armature()
    for group_name, indices in mesh_data.groups.items():
        group = mesh_obj.vertex_groups.new(name=group_name)
        group.add(indices, 1.0, "REPLACE")
    mesh_obj.parent = arm_obj
    modifier = mesh_obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm_obj

    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    export_glb([mesh_obj, arm_obj], GLB)
    print("wrote %s and %s" % (BLEND, GLB))


main()
