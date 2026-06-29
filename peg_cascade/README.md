# peg_cascade

A Peggle-style physics sandbox: balls drop from the top, carom off a field of glowing pegs, and occasionally trigger chain detonations that blast nearby pegs off the board and kick every ball in range. Destroyed pegs respawn on a slow cycle, so the board is always evolving. The palette leans additive — pegs overexpose white when struck, and explosions bloom into hot particle bursts.

## Superparameters

The 0..1 macro dials — each shifts many low-level params at once.

- **complexity** — 0 gives a sparse field (40 pegs, no spinners); 1 packs the board (200 pegs, 4 rotating arm clusters). Drives visual density and collision frequency.
- **ball_rate** — 0 fires one ball roughly every 1.2 seconds; 1 fires at near-continuous pace (~0.12 s interval). Controls how busy the sim feels.
- **bounciness** — 0 gives deadened, low-restitution collisions (bounce ≈ 0.45); 1 makes the physics elastic and ricochety (bounce ≈ 0.98).
- **fx** — scales the chain-blast radius (100 → 320 px) and the impulse kick applied to nearby balls (100 → 1200). Low = small local pops; high = screen-wide demolitions with violent ball scatter.

## Parameters

Low-level knobs (pin exact values via a preset's `overrides`). Parameters marked *(restart)* take effect only on scene restart — they cannot be hot-patched mid-run.

- **layout** (`enum`, default `"mixed"`) *(restart)* — peg arrangement pattern. Options: `rings` (concentric circles centred on screen), `grid` (staggered rows), `spinners` (rotating arm clusters only), `mixed` (rings + grid border + spinners combined).
- **peg_count** (`int`, 20–240, default `110`) *(restart)* — total number of pegs on the board; layout shapes are top-up/trimmed to hit this budget.
- **peg_radius** (`float`, 8.0–26.0, default `14.0`) *(restart)* — collision radius of each peg in pixels; also governs draw size.
- **spinner_count** (`int`, 0–4, default `2`) *(restart)* — number of rotating peg-arm hubs (each hub carries 12 pegs on two radii, alternating CW/CCW). Has no effect if `layout` is `rings` or `grid`.
- **spinner_speed** (`float`, 0.2–3.0, default `1.0`) *(restart)* — base angular speed of spinner hubs in rad/s (even hubs go CW, odd go CCW). 25% seeded jitter applied per hub.
- **fire_interval** (`float`, 0.1–2.0, default `0.45`) — seconds between ball launches. Lower = faster cadence.
- **ball_speed** (`float`, 400.0–1600.0, default `900.0`) — launch speed of each ball in px/s. Higher values drive harder impacts and more chain triggering.
- **ball_radius** (`float`, 6.0–18.0, default `11.0`) *(restart)* — physical and drawn radius of each ball.
- **bounce** (`float`, 0.3–1.0, default `0.8`) — physics material restitution applied to every peg and ball collision. Values near 1.0 produce long, chaotic ricochets.
- **sweep_range** (`float`, 0.0–1.2, default `0.7`) — half-width of the launch-angle oscillation in radians. 0 fires straight down; 1.2 sweeps a wide arc across the board.
- **sweep_speed** (`float`, 0.1–3.0, default `0.8`) — oscillation rate of the launch angle in cycles per second (scaled by TAU/4). Higher = rapid left-right alternation.
- **chain_trigger** (`int`, 2–8, default `4`) — minimum number of recent peg hits (within the last second, within `chain_radius` of a new hit) required to detonate a chain blast.
- **chain_radius** (`float`, 60.0–400.0, default `180.0`) — radius in px used for both chain detection and the blast zone (pegs inside are destroyed; balls inside are kicked).
- **blast_impulse** (`float`, 0.0–1500.0, default `600.0`) — magnitude of the radial impulse applied to balls caught in a chain blast. 0 = no kick; 1500 = violent scatter.
- **respawn_period** (`float`, 2.0–20.0, default `8.0`) — seconds between full board respawn sweeps; dead pegs (those destroyed by chain blasts) are regenerated each cycle.
- **max_balls** (`int`, 4–80, default `28`) — cap on simultaneously active balls. New launches are skipped when the count is at the limit.
- **hot_fraction** (`float`, 0.0–1.0, default `0.25`) *(restart)* — proportion of pegs assigned the palette's accent ("hot") colour. The rest use the base peg colour.
- **glow** (`float`, 0.0–3.0, default `1.3`) — additive glow intensity on the WorldEnvironment. Higher values make impacts and explosions bloom more aggressively.
- **palette** (`enum`, default `"classic"`) *(restart)* — colour scheme. Options: `classic` (blue pegs, orange hot, white balls), `neon` (pink pegs, cyan hot, chartreuse balls), `mono` (grey pegs, white hot, light-grey balls).

## Events

Discrete moments emitted for envelope modulation:

- `spawn` — fires each time a new ball is launched from the top of the field.
- `hit` — fires each time a ball contacts a peg (debounced: suppressed if the peg was struck within the last ~0.5 s).
- `chain` — fires when a cluster of recent hits crosses the `chain_trigger` threshold, triggering a chain detonation.

## Presets

- `default` — balanced mid-range settings; mixed layout, moderate ball rate, classic palette.
- `clockwork` — slower, deliberate; emphasises spinner geometry and regular ball cadence.
- `pachinko_riot` — high ball rate, low chain threshold, large blast radius — near-continuous demolition and scatter.
- `zen_garden` — ring layout, sparse pegs, gentle bounciness; hypnotic and low-chaos.
