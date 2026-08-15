"""Build the carried torch and its stand (Phase 6.5 piece 3).

Run headless from the project root:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/build_torch.py

Writes  assets/blender/torch.blend      (both pieces, editable together)
        assets/models/torch.glb
        assets/models/torch_stand.glb

The torch's origin is the grip point: the handle continues a little below it
and the wrapped head rises above, so parenting the model to the player's hand
bone holds it naturally without per-frame offsets. No collision — it is either
in the stand or in a hand, never an obstacle.

The stand is a free-standing post with a tilted iron ring at the top; the
torch rests in the ring until taken (E) and reappears there when returned.
The ring's socket position/tilt are mirrored by constants in
scenes/props/torch/torch_stand.tscn — change one, change both.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lowpoly import Part, all_materials, clear_scene, export_glb  # noqa: E402

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND = os.path.join(PROJECT, "assets", "blender", "torch.blend")
MODELS = os.path.join(PROJECT, "assets", "models")

TRI_BUDGET = 500

# Torch proportions, metres. Origin = grip.
HANDLE_R = 0.022
HANDLE_BELOW = 0.14   # handle below the grip
HANDLE_ABOVE = 0.26   # handle above the grip, up to the head
HEAD_H = 0.11         # the wrapped, oil-soaked head
HEAD_R = 0.045

# Stand proportions.
STAND_H = 1.05        # post top
BASE_R = 0.16


def build_torch() -> Part:
    part = Part("torch")
    part.drum((0.0, 0.0), -HANDLE_BELOW, HANDLE_ABOVE, HANDLE_R, HANDLE_R * 0.85, "wood")
    # A thin binding collar where the head wrap starts.
    part.drum((0.0, 0.0), HANDLE_ABOVE - 0.015, HANDLE_ABOVE + 0.01,
              HANDLE_R * 1.5, HANDLE_R * 1.5, "clay")
    # The wrapped head, slightly barrel-shaped.
    part.drum((0.0, 0.0), HANDLE_ABOVE, HANDLE_ABOVE + HEAD_H, HEAD_R * 0.8, HEAD_R, "clay")
    part.drum((0.0, 0.0), HANDLE_ABOVE + HEAD_H, HANDLE_ABOVE + HEAD_H + 0.02,
              HEAD_R, HEAD_R * 0.55, "accent_gold")
    return part


def build_torch_stand() -> Part:
    part = Part("torch_stand")
    # A weighted base you can read from gameplay distance, then the post.
    part.drum((0.0, 0.0), 0.0, 0.06, BASE_R, BASE_R * 0.8, "clay")
    part.drum((0.0, 0.0), 0.06, STAND_H, 0.035, 0.028, "wood")
    # The holding ring: an open octagonal cup at the post top, offset toward
    # +Y so the torch leans out from the post rather than through it.
    ring_z = STAND_H
    part.drum((0.0, 0.055), ring_z, ring_z + 0.05, 0.062, 0.052, "accent_gold")
    part.drum((0.0, 0.055), ring_z + 0.001, ring_z + 0.051, 0.040, 0.034, "wood")
    return part


def main() -> None:
    clear_scene()
    materials = all_materials()
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(MODELS, exist_ok=True)

    print("--- torch ---")
    built: list[tuple[str, bpy.types.Object]] = []
    for name, builder in (("torch", build_torch), ("torch_stand", build_torch_stand)):
        part = builder()
        tris = part.triangle_count()
        if tris > TRI_BUDGET:
            print("OVER the %d-tri budget: %s (%d)" % (TRI_BUDGET, name, tris))
        # The torch has no collision (carried or racked); the stand does — a
        # post you can believably bump into.
        obj = part.emit(materials, collide=name == "torch_stand")
        built.append((name, obj))
        print("  %-12s %4d tris" % (name, tris))

    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    for name, obj in built:
        export_glb([obj], os.path.join(MODELS, "%s.glb" % name))
    print("wrote torch + stand to %s" % MODELS)


main()
