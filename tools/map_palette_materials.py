"""Point an imported .glb's materials at the palette .tres files.

    python3 tools/map_palette_materials.py [assets/models/foo.glb ...]

With no arguments it does every .glb in assets/models/ that uses palette
material names. Run it after adding a model, then re-import.

Why this exists: docs/ART_DIRECTION.md says hand-modelled assets use the
resources/palette/ materials, and the surest way to honour that is to let the
palette .tres files *be* the materials rather than shipping a Blender copy of
each colour. Godot's scene importer supports exactly this per material
("use external"), so a glb whose materials are named `clay`, `wood` and so on
is wired straight to the palette. The payoff is that retuning a palette colour
reaches every building and prop at once, with no re-export, and an asset can
never drift a few percent off-palette through a colour-space mistake in the
export path.

The Blender-side colours therefore only ever drive Blender's own viewport.
"""

import json
import os
import struct
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(PROJECT, "assets", "models")
PALETTE_DIR = os.path.join(PROJECT, "resources", "palette")


def glb_materials(path: str) -> list[str]:
    with open(path, "rb") as handle:
        data = handle.read()
    json_length = struct.unpack("<I", data[12:16])[0]
    document = json.loads(data[20:20 + json_length])
    return [m.get("name", "") for m in document.get("materials", [])]


def palette_names() -> set:
    return {
        entry[:-5]
        for entry in os.listdir(PALETTE_DIR)
        if entry.endswith(".tres")
    }


def subresource_block(materials: list[str]) -> str:
    lines = ['_subresources={', '"materials": {']
    body = []
    for name in sorted(materials):
        body.append(
            '"%s": {\n"use_external/enabled": true,\n'
            '"use_external/path": "res://resources/palette/%s.tres"\n}'
            % (name, name)
        )
    lines.append(",\n".join(body))
    lines.append("}")
    lines.append("}")
    return "\n".join(lines)


def rewrite(import_path: str, materials: list[str]) -> bool:
    with open(import_path) as handle:
        text = handle.read()
    start = text.index("_subresources=")
    # The value is a Godot dictionary literal; find its matching close brace.
    depth = 0
    end = start
    for index in range(text.index("{", start), len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    replacement = subresource_block(materials)
    if text[start:end] == replacement:
        return False
    with open(import_path, "w") as handle:
        handle.write(text[:start] + replacement + text[end:])
    return True


def main() -> None:
    targets = sys.argv[1:]
    if not targets:
        targets = [
            os.path.join(MODELS, entry)
            for entry in sorted(os.listdir(MODELS))
            if entry.endswith(".glb")
        ]

    known = palette_names()
    for path in targets:
        import_path = path + ".import"
        if not os.path.exists(import_path):
            print("skip %s (no .import yet — run Godot --import first)"
                  % os.path.basename(path))
            continue
        materials = glb_materials(path)
        mapped = [name for name in materials if name in known]
        if not mapped:
            print("skip %s (no palette materials: %s)"
                  % (os.path.basename(path), ", ".join(materials) or "none"))
            continue
        changed = rewrite(import_path, mapped)
        print("%-18s %s -> palette%s" % (
            os.path.basename(path), ", ".join(sorted(mapped)),
            "" if changed else " (already mapped)",
        ))


main()
