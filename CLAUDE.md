# SHAIBA — 3D Game Project

A cozy low-poly open-world game set in the Arabic desert of **Shaiba**, built collaboratively: Claude Code drives **Blender** (assets) and **Godot 4.7** (game) through MCP. Joshua is not a 3D artist or game programmer — Claude does the modeling and coding; explain decisions in plain terms and keep workflows hands-off for the user.

## ⚠️ Session protocol — read this first, every session

Each Claude Code session works on **exactly one phase** of the plan. Before touching anything:

1. **Read `PLAN.md`** — the status board tells you which phase is current. Read that phase's deliverables and quality gate in full.
2. **Read `docs/ARCHITECTURE.md`** and **`docs/ART_DIRECTION.md`** if the phase touches code structure or visuals (it almost always does).
3. **Skim `docs/DECISIONS.md`** so you don't re-decide something already settled.
4. **Git setup:** `git checkout development && git pull`, then create/switch to the phase's feature branch (named in PLAN.md's status board). Never commit directly to `main` or `development`.
5. Mark the phase 🟡 In progress in PLAN.md's status board (commit that early).

A phase is **done** only when every quality-gate checkbox in PLAN.md is verified — actually run the project, actually look at screenshots, actually profile if the gate says so. "Top notch and fully implemented" is the bar; a phase that half-works stays 🟡 with honest notes for the next session.

**Before ending a session** (finished or not):
- Update PLAN.md: status board + check off gate items completed; if unfinished, add a short "Handoff notes" block under the phase saying exactly where things stand and what's next.
- Append any new decisions (with reasoning) to `docs/DECISIONS.md`.
- Commit everything on the feature branch. If the gate fully passed: merge to `development` (see Git workflow), mark ✅.

## Git workflow

- **`main`** — stable, playable, tested. Only receives merges from `development` after testing (Phase 7 pattern: playtest → merge → tag).
- **`development`** — integration branch. Feature branches merge here when their quality gate passes.
- **`feature/phase-N-name`** — one per phase, branched off `development`.
- Merge with `git checkout development && git merge --no-ff feature/phase-N-name`, then push. `--no-ff` keeps each phase visible as one unit in history.
- Remote: `https://github.com/jmelvin92/shaiba` (created 2026-08-13). Push both `main` and `development` after merges.
- Commit messages: short imperative summary line, e.g. `Add chunk manager with threaded loading`. Commit small and often on feature branches.
- **Binary assets** (`.blend`, `.glb`, textures) are committed normally for now; if the repo grows past ~1 GB revisit Git LFS (note it in DECISIONS.md).

## Repository layout

Repo root **is** the Godot project root. Full rationale in `docs/ARCHITECTURE.md`; summary:

```
project.godot
CLAUDE.md / PLAN.md          # process docs (this file + roadmap)
docs/                        # ARCHITECTURE, ART_DIRECTION, DECISIONS
autoload/                    # singletons — keep to a minimum (game.gd only, until justified)
scenes/                      # one folder per feature; script lives NEXT TO its scene
  player/    player.tscn + player.gd
  camera/    camera_rig.tscn + camera_rig.gd
  world/     world.tscn, graybox.tscn, terrain/ (chunk system)
  props/     one subfolder per prop/creature (house/, camel/, …)
resources/                   # shared .tres — palette/ materials, curves, noise settings
shaders/                     # .gdshader files
assets/
  blender/                   # .blend sources (always committed — models must stay editable)
  models/                    # exported .glb
  textures/                  # rare — palette-only style needs few textures
```

## Code conventions (avoid spaghetti from day one)

- **Typed GDScript everywhere**: `var speed: float = 4.0`, typed function signatures, `class_name` where a type is referenced elsewhere. Target zero warnings in the Godot output panel.
- **Scene-owned scripts**: a script lives beside the scene it drives, named the same (`player.tscn`/`player.gd`). snake_case files/folders, PascalCase `class_name`s, node names PascalCase.
- **Communication rules** (the anti-spaghetti core): a node may call **down** into its own children; it must never reach **up** or **sideways** with `get_parent()`/`get_node("../..")`. Going up = emit a **signal**; the parent connects it. Cross-feature coordination goes through the `Game` autoload only when a signal genuinely can't work — and each new autoload needs a DECISIONS.md entry justifying it.
- **Tunable values** are `@export` vars with sensible ranges, not magic numbers buried in code.
- **Scenes are self-contained**: any .tscn should run standalone (F6) without crashing — guard external references.
- Prefer built-in Godot solutions (CharacterBody3D, AnimationTree, NavigationAgent) over hand-rolled systems; prefer boring, readable code over clever code.
- No premature abstraction: build the thing the current phase needs; extract shared code only when a *second* real user appears.

## Art conventions

Everything visual obeys `docs/ART_DIRECTION.md` — the fixed color palette (hex values + matching `resources/palette/` materials), flat-shaded low-poly rules, tri budgets, and the exact Blender→glb export checklist. Never introduce off-palette colors or textured/realistic materials.

## Toolchain

| Tool | Version | Location |
|------|---------|----------|
| Blender | 5.2.0 LTS | `/Applications/Blender.app` (Homebrew cask) |
| Godot | 4.7.1 stable | `/Applications/Godot.app` (Homebrew cask) |
| uv/uvx | 0.12.x | `/opt/homebrew/bin/uvx` |
| godot-mcp server | Coding-Solo/godot-mcp | cloned + built at `~/tools/godot-mcp` |
| gh CLI | authenticated as `jmelvin92` | `/opt/homebrew/bin/gh` |

## MCP servers (user scope, in `~/.claude.json`)

- **`blender`** — `uvx blender-mcp` (ahujasid/blender-mcp). Talks to an addon *inside* Blender that auto-starts a socket server on `127.0.0.1:9876` whenever Blender runs with a GUI. **Blender must be open** for these tools to work: `open -a Blender`. Check with `lsof -nP -iTCP:9876 -sTCP:LISTEN`.
- **`godot`** — `node ~/tools/godot-mcp/build/index.js` with `GODOT_PATH=/Applications/Godot.app/Contents/MacOS/Godot`. Can create/edit scenes and scripts, launch the editor, run the project, and read debug output.

## Environment quirks

- `~/.npm/_cacache` contains root-owned files (old `sudo npm` run), so plain `npm install` fails with `EACCES`. Workaround: `npm install --cache <scratch-dir>`. Permanent fix (needs Joshua): `sudo chown -R joshua ~/.npm`.
- The blender-mcp addon predates Blender 5.x but installs and registers cleanly on 5.2. If a Blender API call fails, suspect a 4.x→5.x API change before anything else; patching the addon (`~/tools/blender-mcp-addon.py`, installed copy in `~/Library/Application Support/Blender/5.2/scripts/addons/blender_mcp_addon.py`) is fair game.
