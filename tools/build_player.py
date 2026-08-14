"""Condition the Meshy character into the game's player asset.

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_player.py

Reads   assets/blender/player_source.glb   (the untouched Meshy download)
Writes  assets/blender/player.blend        (editable source of truth)
        assets/models/player.glb           (what Godot imports)

Every change the asset needs is made here rather than by hand, so the export is
reproducible: same input, same output, every time. docs/ART_DIRECTION.md
explains the conventions; the comments below explain the asset-specific fixes.
"""

import math
import os

import bpy
from mathutils import Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(PROJECT, "assets", "blender", "player_source.glb")
BLEND = os.path.join(PROJECT, "assets", "blender", "player.blend")
GLB = os.path.join(PROJECT, "assets", "models", "player.glb")

FPS = 30
BASE_COLOR_SIZE = 1024

# Straight renames of clips that need no surgery.
RENAMES = {"Idle_11": "idle", "Walking": "walk", "Running": "run"}

# Meshy's vault clip, which we cut into our three air states. It runs 0.90 s:
# rise to an apex at 0.35 s, descend to 0.80 s, then settle. Our own jump is
# 0.40 s up and 0.40 s down, so the phases line up closely.
JUMP_SOURCE = "Jump_Over_Obstacle_2"
JUMP_RISE = (0.00, 0.38)
FALL_HOLD = 0.50
LAND_RANGE = (0.58, 0.90)

# The crouch clips. "Cautious_Crouch_Walk_Right" is a lateral strafe (its
# planted foot travels 1.01 m/s sideways and 0.00 m/s forward), so it cannot
# serve as a forward crouch walk. CrouchLookAroundBow is used instead: it sits
# at head height 1.10-1.20 m, which matches the 1.15 m crouch capsule the
# controller already uses, so no collider retuning is needed.
CROUCH_SOURCE = "CrouchLookAroundBow"
CROUCH_IDLE_SECONDS = 2.0

HOLD_FRAMES = 10
# Share of the vault's own 0.52 m hip rise to keep. The CharacterBody supplies
# a 1.1 m arc of its own; stacking the clip's full rise on top would read as a
# 1.6 m leap. A quarter keeps the push-off and absorption without the height.
VERTICAL_KEEP = 0.25


def fcurves_of(action):
    """F-curves of a layered (Blender 4.4+) action.

    Actions grew layers/strips/channelbags and lost the flat `.fcurves`
    shortcut, so every caller has to walk down to the channelbag.
    """
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                return bag.fcurves
    return []


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for collection in (
        bpy.data.actions,
        bpy.data.meshes,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.images,
    ):
        for item in list(collection):
            collection.remove(item)


def slice_action(source, name, start_frame, end_frame):
    """Copy `source` keeping only [start_frame, end_frame], rebased to 0."""
    action = source.copy()
    action.name = name
    for curve in fcurves_of(action):
        for key in reversed(list(curve.keyframe_points)):
            if key.co.x < start_frame - 1e-4 or key.co.x > end_frame + 1e-4:
                curve.keyframe_points.remove(key)
        for key in curve.keyframe_points:
            key.co.x -= start_frame
            key.handle_left.x -= start_frame
            key.handle_right.x -= start_frame
        curve.update()
    return action


def hold_action(source, name, frame):
    """Copy `source` frozen at a single pose, held for HOLD_FRAMES."""
    action = source.copy()
    action.name = name
    for curve in fcurves_of(action):
        value = curve.evaluate(frame)
        for key in reversed(list(curve.keyframe_points)):
            curve.keyframe_points.remove(key)
        for at in (0, HOLD_FRAMES):
            curve.keyframe_points.insert(at, value).interpolation = "LINEAR"
        curve.update()
    return action


def damp_rise(action, armature, bone_name="Hips"):
    """Cut how far a root bone rises above its starting height.

    Only upward excursion is damped. The downward part is a landing absorbing
    the impact, which we want at full strength -- it is the compression that
    sells the landing.
    """
    curves = fcurves_of(action)
    path = 'pose.bones["%s"].location' % bone_name
    location = {c.array_index: c for c in curves if c.data_path == path}
    if len(location) != 3:
        return
    basis = armature.data.bones[bone_name].matrix_local.to_3x3()
    up = (basis.inverted() @ Vector((0.0, 0.0, 1.0))).normalized()
    frames = sorted({k.co.x for c in location.values() for k in c.keyframe_points})
    start = Vector([location[i].evaluate(frames[0]) for i in range(3)])

    wanted = {}
    for frame in frames:
        offset = Vector([location[i].evaluate(frame) for i in range(3)]) - start
        climb = offset.dot(up)
        if climb > 0.0:
            offset -= up * climb * (1.0 - VERTICAL_KEEP)
        wanted[frame] = start + offset

    for axis in range(3):
        curve = location[axis]
        for key in curve.keyframe_points:
            target = wanted.get(min(wanted, key=lambda f: abs(f - key.co.x)))
            key.co.y = target[axis]
            key.interpolation = "LINEAR"
        curve.update()


def flatten_horizontal(action, armature, bone_name="Hips"):
    """Subtract a root bone's net horizontal travel, keeping its vertical arc."""
    curves = fcurves_of(action)
    path = 'pose.bones["%s"].location' % bone_name
    location = {c.array_index: c for c in curves if c.data_path == path}
    if len(location) != 3:
        return 0.0
    basis = armature.data.bones[bone_name].matrix_local.to_3x3()
    up = (basis.inverted() @ Vector((0.0, 0.0, 1.0))).normalized()
    frames = sorted({k.co.x for c in location.values() for k in c.keyframe_points})
    first, last = frames[0], frames[-1]
    if last - first < 1e-4:
        return 0.0
    start = Vector([location[i].evaluate(first) for i in range(3)])
    drift = Vector([location[i].evaluate(last) for i in range(3)]) - start
    horizontal = drift - up * drift.dot(up)
    for axis in range(3):
        curve = location[axis]
        for key in curve.keyframe_points:
            ratio = (key.co.x - first) / (last - first)
            key.co.y -= horizontal[axis] * ratio
            key.interpolation = "LINEAR"
        curve.update()
    return horizontal.length


def quietest_window(armature, action, seconds):
    """Start frame of the calmest `seconds`-long window in an action.

    CrouchLookAroundBow is a long fidget with big head turns; the calmest
    stretch of it reads as a crouched idle rather than a performance.
    """
    armature.animation_data.action = action
    scene = bpy.context.scene
    first, last = (int(round(v)) for v in action.frame_range)
    width = int(round(seconds * FPS))
    if last - first <= width:
        return first

    head = []
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        head.append((armature.matrix_world @ armature.pose.bones["Head"].matrix).translation)

    best, best_start = None, first
    for start in range(0, len(head) - width):
        window = head[start : start + width]
        spread = max((p - window[0]).length for p in window)
        if best is None or spread < best:
            best, best_start = spread, first + start
    return best_start


def fix_material():
    """Make Meshy's material obey our lighting.

    As exported it is fully emissive, fully metallic, alpha-blended and
    double-sided, so it ignores the sun entirely and renders as a flat cut-out
    that sorts badly against terrain. The texture itself is kept -- a
    deliberate exception to the palette-only rule -- and only these settings
    change.
    """
    material = bpy.data.materials[0]
    material.name = "player"
    tree = material.node_tree
    bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")

    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Emission Strength"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0

    # Read the graph fully before touching it: removing a link invalidates the
    # other link pointers, so a single interleaved pass silently misses things.
    base_image = None
    doomed = []
    # Compare with != , not `is not`: Blender hands back a fresh wrapper object
    # on every attribute access, so identity checks never match.
    for link in tree.links:
        if link.to_node != bsdf:
            continue
        if link.to_socket.name == "Base Color":
            base_image = link.from_node.image
        elif link.to_socket.name.startswith("Emission") or link.to_socket.name == "Alpha":
            doomed.append((link.from_node.name, link.to_socket.name))
    if base_image is None:
        raise RuntimeError("no Base Color texture found on %s" % material.name)

    for from_name, socket in doomed:
        for link in list(tree.links):
            if link.from_node.name == from_name and link.to_socket.name == socket:
                tree.links.remove(link)
                break

    material.blend_method = "OPAQUE"
    material.use_backface_culling = True

    for node in list(tree.nodes):
        if node.type == "TEX_IMAGE" and node.image != base_image:
            tree.nodes.remove(node)
    for image in list(bpy.data.images):
        if image != base_image:
            bpy.data.images.remove(image)
    if base_image is not None and base_image.size[0] > BASE_COLOR_SIZE:
        base_image.scale(BASE_COLOR_SIZE, BASE_COLOR_SIZE)


def report_heights(armature):
    """Print head height per clip, so a bad bake is obvious in the log."""
    scene = bpy.context.scene
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        armature.animation_data.action = action
        first, last = (int(round(v)) for v in action.frame_range)
        tops = []
        for frame in range(first, last + 1):
            scene.frame_set(frame)
            tops.append(
                (armature.matrix_world @ armature.pose.bones["head_end"].matrix).translation.z
            )
        print("  %-12s frames %3d..%-3d  head %.2f..%.2f m" % (
            action.name, first, last, min(tops), max(tops)))


def main():
    clear_scene()
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=SOURCE)

    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    for obj in list(bpy.data.objects):
        if obj not in (armature, mesh):
            bpy.data.objects.remove(obj, do_unlink=True)
    armature.name = armature.data.name = "Armature"
    mesh.name = mesh.data.name = "Traveler"

    # Meshy faces the character +Y in Blender, which exports to glTF +Z -- the
    # opposite of Godot's -Z forward. Rotating the object rather than applying
    # the rotation into the rest pose leaves every action untouched; the
    # exporter bakes the rotation into the node. The importer leaves the object
    # in quaternion mode, where assigning rotation_euler would do nothing.
    armature.rotation_mode = "XYZ"
    armature.rotation_euler.z += math.pi

    source = {a.name: a for a in bpy.data.actions}
    jump_source = source[JUMP_SOURCE]
    crouch_source = source[CROUCH_SOURCE]

    # Condition the vault once, as a whole, and cut the air states out of the
    # result. Doing it the other way round would give each slice its own ground
    # reference, and the character would jolt vertically between states.
    air = jump_source.copy()
    air.name = "air_source"
    removed = flatten_horizontal(air, armature)
    damp_rise(air, armature)
    print("vault: removed %.2f m of forward travel, kept %.0f%% of the rise"
          % (removed * armature.scale.x, VERTICAL_KEEP * 100))

    built = [
        slice_action(air, "jump", *[round(s * FPS) for s in JUMP_RISE]),
        hold_action(air, "fall", round(FALL_HOLD * FPS)),
        slice_action(air, "land", *[round(s * FPS) for s in LAND_RANGE]),
    ]
    bpy.data.actions.remove(air)

    calm = quietest_window(armature, crouch_source, CROUCH_IDLE_SECONDS)
    built.append(
        slice_action(
            crouch_source, "crouch_idle", calm, calm + round(CROUCH_IDLE_SECONDS * FPS)
        )
    )
    # No forward crouch locomotion exists in the source set, so crouch movement
    # holds the crouched pose. Logged as a known gap in docs/DECISIONS.md.
    built.append(hold_action(crouch_source, "crouch_walk", calm))
    print("crouch clips taken from frame %d of %s" % (calm, CROUCH_SOURCE))

    for old, new in RENAMES.items():
        source[old].name = new

    keep = set(RENAMES.values()) | {a.name for a in built}
    for action in list(bpy.data.actions):
        if action.name in keep:
            action.use_fake_user = True
        else:
            bpy.data.actions.remove(action)

    fix_material()

    armature.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(0)
    print("clip heights (standing should read ~1.75 m, crouched ~1.15 m):")
    report_heights(armature)
    armature.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(0)

    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(os.path.dirname(GLB), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)

    for obj in bpy.data.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=GLB,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_bake_animation=True,
        export_optimize_animation_size=False,
    )
    print("exported: %s" % sorted(a.name for a in bpy.data.actions))
    print("wrote %s (%.1f MB)" % (GLB, os.path.getsize(GLB) / 1048576))


main()
