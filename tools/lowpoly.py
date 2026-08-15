"""Shared low-poly modelling helpers for the Blender build scripts.

Extracted when the furnishings became the second real user of the house's box
builder (CLAUDE.md: extract on the second user, not before). Everything here is
deliberately dumb — boxes, drums and extruded profiles — because a flat-shaded
low-poly asset in this project genuinely is a small pile of primitives, and
building the mesh data directly keeps it all safe in Blender's --background
mode, where bpy.ops depends on a context that barely exists.

Materials are named exactly after resources/palette/ entries. The colours set
here only drive Blender's viewport: each .glb.import maps every material to its
palette .tres, so the game's colours come from the palette itself and a palette
edit reaches every asset without re-exporting anything.
"""

import math

import bpy
from mathutils import Vector

# The palette, from docs/ART_DIRECTION.md. The only colours in the game.
PALETTE = {
    "sand_light": "EFD9A7",
    "sand_mid": "DFB878",
    "sand_shadow": "C4914E",
    "clay": "B97350",
    "plaster": "F2E7CF",
    "wood": "8A5A3B",
    "palm_green": "7FA05B",
    "oasis_teal": "5FA8A0",
    "night_blue": "34455E",
    "accent_gold": "E2A93B",
}


def srgb_to_linear(channel: float) -> float:
    """Blender works in linear light; the palette is written as sRGB hex."""
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def make_material(name: str) -> bpy.types.Material:
    """A flat palette material: roughness 1, metallic 0, no textures."""
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    principled = material.node_tree.nodes["Principled BSDF"]
    hex_value = PALETTE[name]
    rgb = [int(hex_value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    linear = [srgb_to_linear(c) for c in rgb]
    principled.inputs["Base Color"].default_value = (*linear, 1.0)
    principled.inputs["Roughness"].default_value = 1.0
    principled.inputs["Metallic"].default_value = 0.0
    material.diffuse_color = (*linear, 1.0)  # what Workbench previews use
    return material


def all_materials() -> dict:
    return {name: make_material(name) for name in PALETTE}


def clear_scene() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for collection in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras,
                       bpy.data.lights):
        for item in list(collection):
            collection.remove(item)


class Part:
    """Accumulates primitives into a single flat-shaded mesh object."""

    def __init__(self, name: str):
        self.name = name
        self.verts: list[Vector] = []
        self.faces: list[tuple[int, ...]] = []
        self.face_materials: list[str] = []

    def box(
        self,
        lo: tuple[float, float, float],
        hi: tuple[float, float, float],
        material: str,
        yaw: float = 0.0,
    ) -> None:
        """An axis-aligned box from `lo` to `hi`, optionally yawed about its
        own centre — a degree or two of yaw is how the hand-made parts get the
        slight imperfection ART_DIRECTION asks for."""
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        corners = [
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
        ]
        if yaw != 0.0:
            centre = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
            angle = math.radians(yaw)
            cos_a, sin_a = math.cos(angle), math.sin(angle)
            corners = [
                (
                    centre.x + (cx - centre.x) * cos_a - (cy - centre.y) * sin_a,
                    centre.y + (cx - centre.x) * sin_a + (cy - centre.y) * cos_a,
                    cz,
                )
                for cx, cy, cz in corners
            ]

        base = len(self.verts)
        self.verts.extend(Vector(c) for c in corners)
        for face in (
            (0, 3, 2, 1), (4, 5, 6, 7),
            (0, 1, 5, 4), (2, 3, 7, 6),
            (1, 2, 6, 5), (3, 0, 4, 7),
        ):
            self.faces.append(tuple(base + i for i in face))
            self.face_materials.append(material)

    def drum(
        self,
        centre: tuple[float, float],
        z0: float,
        z1: float,
        radius_low: float,
        radius_high: float,
        material: str,
        sides: int = 8,
        twist: float = 0.0,
    ) -> None:
        """A prism/frustum on its end — poufs, pots, lamp bodies.

        Eight sides by default: at the gameplay camera anything rounder is
        wasted, and eight already reads as "round" rather than "boxy".
        """
        base = len(self.verts)
        for i in range(sides):
            angle = math.tau * i / sides + math.radians(twist)
            self.verts.append(Vector((
                centre[0] + math.cos(angle) * radius_low,
                centre[1] + math.sin(angle) * radius_low,
                z0,
            )))
        for i in range(sides):
            angle = math.tau * i / sides + math.radians(twist)
            self.verts.append(Vector((
                centre[0] + math.cos(angle) * radius_high,
                centre[1] + math.sin(angle) * radius_high,
                z1,
            )))
        self.faces.append(tuple(range(base + sides - 1, base - 1, -1)))
        self.face_materials.append(material)
        self.faces.append(tuple(range(base + sides, base + 2 * sides)))
        self.face_materials.append(material)
        for i in range(sides):
            j = (i + 1) % sides
            self.faces.append((base + i, base + j, base + sides + j, base + sides + i))
            self.face_materials.append(material)

    def extruded_profile(
        self,
        profile: list[tuple[float, float]],
        x0: float,
        x1: float,
        material: str,
    ) -> None:
        """A solid from a 2-D profile in the YZ plane, extruded along X — the
        one shape a stack of boxes cannot make cleanly, such as a stair's
        sloped parapet."""
        base = len(self.verts)
        count = len(profile)
        for y, z in profile:
            self.verts.append(Vector((x0, y, z)))
        for y, z in profile:
            self.verts.append(Vector((x1, y, z)))
        self.faces.append(tuple(range(base + count - 1, base - 1, -1)))
        self.face_materials.append(material)
        self.faces.append(tuple(range(base + count, base + 2 * count)))
        self.face_materials.append(material)
        for i in range(count):
            j = (i + 1) % count
            self.faces.append((base + i, base + j,
                               base + count + j, base + count + i))
            self.face_materials.append(material)

    def quad_grid(
        self,
        points: list[list[Vector]],
        material: str,
        thickness: float = 0.0,
    ) -> None:
        """A surface through a grid of points — draped cloth. With a thickness
        the sheet is doubled downward so it is solid from below."""
        rows, cols = len(points), len(points[0])
        base = len(self.verts)
        for row in points:
            self.verts.extend(row)
        for r in range(rows - 1):
            for c in range(cols - 1):
                self.faces.append((
                    base + r * cols + c,
                    base + r * cols + c + 1,
                    base + (r + 1) * cols + c + 1,
                    base + (r + 1) * cols + c,
                ))
                self.face_materials.append(material)
        if thickness <= 0.0:
            return
        under = len(self.verts)
        for row in points:
            self.verts.extend(Vector((p.x, p.y, p.z - thickness)) for p in row)
        for r in range(rows - 1):
            for c in range(cols - 1):
                self.faces.append((
                    under + (r + 1) * cols + c,
                    under + (r + 1) * cols + c + 1,
                    under + r * cols + c + 1,
                    under + r * cols + c,
                ))
                self.face_materials.append(material)

    def lift(self, dz: float) -> None:
        """Raises everything built so far — used to reuse a sub-builder that
        works from z=0 at some other height."""
        for vert in self.verts:
            vert.z += dz

    def absorb(self, other: "Part") -> None:
        """Merges another Part's geometry into this one."""
        offset = len(self.verts)
        self.verts.extend(other.verts)
        self.faces.extend(tuple(i + offset for i in face) for face in other.faces)
        self.face_materials.extend(other.face_materials)

    def triangle_count(self) -> int:
        return sum(len(face) - 2 for face in self.faces)

    def emit(self, materials: dict, collide: bool = True) -> bpy.types.Object:
        """Realise the accumulated primitives as one object.

        `collide` appends Godot's `-col` suffix, which makes the glTF importer
        generate a StaticBody3D with a trimesh shape from this very mesh. That
        beats hand-authored collision boxes: the shape cannot drift from the
        geometry, and nobody has to transcribe box transforms into a .tscn
        (where, per CLAUDE.md, a row-major Transform3D typo produces collision
        that is wrong in a way screenshots don't show).
        """
        name = self.name + ("-col" if collide else "")
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        used: list[str] = []
        for material_name in self.face_materials:
            if material_name not in used:
                used.append(material_name)
                mesh.materials.append(materials[material_name])
        index_of = {material_name: i for i, material_name in enumerate(used)}
        for polygon, material_name in zip(mesh.polygons, self.face_materials):
            polygon.material_index = index_of[material_name]
            polygon.use_smooth = False  # flat shading is the whole art direction
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def export_glb(objects: list, path: str) -> None:
    """Exports the given objects, following the ART_DIRECTION checklist."""
    for obj in bpy.data.objects:
        obj.select_set(obj in objects)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=False,
    )
