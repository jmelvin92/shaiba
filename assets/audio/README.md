# Sound sourcing checklist

Drop sourced files into these folders using the exact names below — the game
wires them up by itself at launch from the naming convention. Missing sounds
are simply silent; nothing breaks, nothing needs wiring by hand. (New files do
need one Godot import pass before a run picks them up: opening the editor does
it, or ask Claude to relaunch the game.)

## Format rules (apply to everything)

- **One-shots** (footsteps, doors, clunks): `.wav`, 44.1 kHz, 16-bit, **mono**.
  Positional 3D sounds must be mono to pan correctly.
- **Loops** (fire, ambience beds, shuffle): `.ogg`, seamless loop points.
  Ambience beds may be **stereo**; anything played *at a place* (torch, lamp,
  gusts) must be **mono**.
- **Dry recordings only** — no baked-in echo/reverb. Room sound comes from the
  game's Interior bus, so a reverberant source file would double up.
- Numbered variations start at `_01`. More takes = less repetition; the counts
  below are minimums, feel free to bring extras (the system uses all it finds).

## footsteps/ — sets of 4–6 takes each

Run sets (`*_run`) are **optional**: a surface without one automatically
reuses its walk takes at run loudness. Sourcing a real run set for a surface
overrides the fallback the moment its files land.

Preferred (Joshua's design, 2026-08-15): give a surface **one sample per
foot** — `<surface>_left.wav` + `<surface>_right.wav` — and each plays
exactly when that foot's print stamps; running keeps the identical samples,
slightly louder. Per-foot samples beat the numbered take sets when both
exist. Sand works this way.

| Files | What it should sound like |
|---|---|
| `sand_walk_01..04+.wav` | Soft, deep dry sand underfoot — muffled crunch |
| `sand_run_01..04+.wav` | Same sand, heavier and faster impact |
| `packed_walk_01..04+.wav` | Firm packed earth (the courtyard) — drier, harder than sand |
| `packed_run_01..04+.wav` | Packed earth at a run |
| `stone_walk_01..04+.wav` | Hard adobe/stone — the ground floor and the outside stair. Record dry |
| `stone_run_01..04+.wav` | Stone at a run |
| `wood_walk_01..04+.wav` | Upper-storey plank floor — hollow wooden knock |
| `wood_run_01..04+.wav` | Wood at a run |

## movement/

| Files | What it should sound like |
|---|---|
| `crouch_shuffle_loop.ogg` | Very quiet cloth + sand shuffle, loopable — the sneak sound |
| `jump_01..03.wav` | Takeoff scuff/effort (no voice) |
| `land_soft_01..03.wav` | Landing from a small hop |
| `land_hard_01..03.wav` | Landing from a real fall — heavy thud |

## doors/

| Files | What it should sound like |
|---|---|
| `door_open_01..02.wav` | Old wooden door creaking open |
| `door_close_01..02.wav` | Solid wood thud + latch |

## fire/

| Files | What it should sound like |
|---|---|
| `torch_loop.ogg` | Healthy torch crackle, loopable, mono |
| `torch_take.wav` | Scrape off the stand + a fire whoosh |
| `torch_return.wav` | Wood clunk back into the bracket |
| `torch_whoosh_01..02.wav` | Flame flutter through air (played when running with the torch) |
| `lamp_light.wav` | Strike + soft fwoomp of a small flame catching |
| `lamp_snuff.wav` | Short breath puff |
| `lamp_loop.ogg` | Tiny oil-lamp flame, much quieter than the torch, loopable, mono |

## ambience/

| Files | What it should sound like |
|---|---|
| `wind_day_loop.ogg` | Warm daytime desert wind bed, 1–2 min seamless loop, stereo OK |
| `wind_night_loop.ogg` | Night desert — sparser, colder, slightly unsettling, seamless loop |
| `gust_01..04.wav` | Individual wind gusts that can sweep past, mono, ~3–8 s |
| `ocean_surf_loop.ogg` | Ocean surf from the beach (Phase 6.7): steady waves breaking and washing, 1–2 min seamless loop, stereo OK. Fades in on the walk west; a distant murmur at the homestead. |

## ui/ — menu feedback (sourced 2026-08-15)

| Files | What it should sound like |
|---|---|
| `hover_01..NN.wav` | Soft tick when the pointer crosses a menu control |
| `click_01..NN.wav` | Confirming tap when a control is pressed |

## music/

| Files | What it should sound like |
|---|---|
| `ambient_01..NN.ogg` | Quiet instrumental beds, seamless loops. `ambient_01` loops solo for now; when more land, they become a random rotation with silent gaps between tracks. |

## creatures/ — the buried things (Phase 6.8)

| Files | What it should sound like |
|---|---|
| `worm_rumble_loop.wav` | The sand worm passing underground: a deep, felt-more-than-heard rumble with slow grinding movement in it, seamless loop, mono. It plays from the worm's position — distance and doppler are the engine's job, so the file itself should be close-up and steady. |

## Later (do NOT source yet — listed so the plan stays in one place)

Water wading steps + splashes (footsteps in the swash, entering/leaving the
sea — the footstep system will grow a `wet`/`water` surface when these land) ·
gulls for the coast · Camel (grunts, steps, chewing) · sand-slide on steep dunes · night creature ·
music · **weather system sounds** (the current wind bed is a deliberately
subtle stopgap; a future weather system brings sandstorm/gust-front/calm
variants and takes over the ambience). This file is the ever-growing list:
new features add their rows here before their sounds are sourced.
