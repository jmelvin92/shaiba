# Decisions Log — Shaiba

Append-only log of decisions with reasoning, so future sessions don't re-litigate or accidentally reverse them. Newest at the bottom. Format: date, decision, why, alternatives rejected.

---

**2026-08-13 — Angled top-down perspective camera, not true orthographic isometric.**
A perspective camera pitched ~50–55° with a narrow FOV (~35°) gives the "almost isometric" diorama feel Joshua asked for while keeping depth cues (parallax, dune scale) that pure orthographic loses in an open desert. Rejected: orthographic (flattens dunes), free third-person camera (wrong genre feel).

**2026-08-13 — Chunked streamed terrain from the first terrain implementation (Phase 4).**
The game is open-world on a large map; retrofitting chunking onto a monolithic terrain later would mean rebuilding terrain, collision, prop scattering, and the sand-deformation integration twice. Cost of chunking early is modest; cost of retrofitting is a rewrite.

**2026-08-13 — Sand footprints via world-space deformation texture + vertex-displacement shader, not geometry edits or decals.**
Editing chunk meshes per footstep fights the streaming system and is expensive; plain decals can't depress the surface so prints look painted-on at an angled camera. A SubViewport-accumulated deformation texture is the standard, cheap, fade-able approach. To be validated with a prototype at the start of Phase 5.

**2026-08-13 — Typed GDScript only; no C# unless profiling forces it.**
One language keeps every session's code uniform and godot-mcp-friendly; typed GDScript catches most novice mistakes at parse time. If a hot path (likely chunk generation) ever profiles too slow, revisit here.

**2026-08-13 — Repo root = Godot project root; .blend sources committed alongside .glb exports.**
godot-mcp and version control cover everything with zero path indirection; committed .blend files keep every asset re-editable in later sessions. Git LFS deferred until repo size demands it (~1 GB threshold).

**2026-08-13 — One autoload (`Game`) to start; new autoloads require a logged justification.**
Global singletons are the main spaghetti vector in small Godot projects. Signals + composition first; the log entry requirement forces the discussion.

**2026-08-13 — GitHub repo `jmelvin92/shaiba`, private; `main` (stable) + `development` (integration) + per-phase feature branches, `--no-ff` merges.**
Joshua asked for main to stay protected until testing passes; --no-ff keeps each phase's work legible as one unit in history. Private by default — flip to public anytime.
