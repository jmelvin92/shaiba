extends Node
## Global game state singleton (`Game`).
## Keep this deliberately small — see docs/ARCHITECTURE.md before adding
## anything here; new global state usually belongs in a scene instead.

## Seed for all deterministic world generation (terrain, prop scatter).
var world_seed: int = 20260813
