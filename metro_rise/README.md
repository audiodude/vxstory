# metro_rise

A 3D city grows from empty land at dawn into a lit night metropolis. The sun's
single arc across the sky is metaphorical time: brick low-rises go up in the
morning light, concrete mid-rises by midday, glass towers through the
afternoon — old stock is demolished and replaced as eras advance — and dusk
pays off with thousands of lit windows, streetlamps, neon storefronts, and
headlight streams. A slow orbiting camera rises and pulls back so the skyline
always just-fills the frame. Tower cranes work whatever is currently rising.

Everything structural is a pure function of two dials: drag `development` in
the tweak panel and the whole city grows (or ungrows) live; drag `day_phase`
and the sun, sky, shadows, and window lights follow. Scrubbing in the Designer
reconstructs the city exactly at any playhead position.

## Superparameters (macros)

- **development** — the master build-out dial. 0 is empty land with dirt
  tracks; 1 is the finished metropolis. The whole per-lot construction /
  demolition / replacement timeline is evaluated at this value.
- **day_phase** — the sun's arc. ~0.04 dawn, ~0.45 noon, ~0.86 dusk, then
  night with stars, moonlight, and lit windows.
- **density** — how much of each block is built (lot fill).
- **verticality** — height distributions and the share of core blocks that
  merge lots into big era-3 tower parcels.
- **sprawl** — city radius (how far the grid reaches).
- **traffic** — car density on the paved network (cars appear from the
  concrete era on).
- **nightlife** — window lit-fraction and neon intensity after dark.

`development`, `day_phase`, `traffic`, and `nightlife` are live; the others
are structural — they are frozen into the city plan at restart, so tweening
them mid-run is a documented no-op. Hit Restart (or edit and let the Designer
restart) to re-plan.

## Notable parameters

- `city_radius`, `lot_fill`, `height_scale`, `tower_share`, `block_min/max`,
  `boulevard_count`, `park_pct` — structural plan inputs.
- `era1_end`, `era2_end`, `era_overlap` — where (in development-P) brick
  yields to concrete and concrete to glass; overlap widths blend the
  transitions.
- `demolish_core` / `demolish_edge` — replacement pressure by district.
- `construct_speed` — construction window length per floor (P-space).
- `orbit_rate`, `cam_pull`, `cam_height`, `cam_fov` — live camera dials.
- `lit_fraction`, `neon_amount`, `glow`, `fog_amount`, `star_density` — live
  look dials.
- `palette` — `daybreak` (warm naturalistic), `sodium` (amber dusk-heavy),
  `overcast` (desaturated cool).
- `hue_drift` — deg/min rotation of accent/neon hues (repo convention).
- `car_speed`, `light_cycle` — traffic feel.
- `topout_floors` — minimum height for a completion to fire the `topout`
  event.

## Events (for envelope modulation)

- `topout` — a building of at least `topout_floors` completes.
- `demolish` — a demolition starts (also puffs dust in the view).
- `era` — development crosses an era band edge (~2x per full run).

Restarts and scrubs never fire event storms: the first evaluation after a
rebuild is silent.

## Presets

- `default` — mid-build afternoon; cranes, traffic, and district contrast.
- `boomtown` — dense vertical sodium dusk, heavy traffic, era-3 skyline.
- `garden_city` — low-rise parks-heavy morning, sparse traffic.
- `century` — the 300 s long-form piece: development tweens 0→1 while the sun
  makes its full arc; traffic ramps in mid-run; nightlife eases in for the
  night payoff; envelopes pip `glow` on topouts and swell `fog_amount` at era
  transitions; a slow LFO breathes the camera radius.

Preview: `godot --path metro_rise -- --preset presets/century.json`
Render: `scripts/render.sh metro_rise century 300`
Tests: `godot --headless --path metro_rise --script res://tests/run_tests.gd`
