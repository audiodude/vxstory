# matter_cycle

Rigid wireframe polygons rain down, collide, and shatter into swarms of glowing particles on
impact. The particles drift through a slow curl-noise flow field, and whenever enough of them
cluster in one cell they spontaneously condense back into a new polygon — launching upward and
repeating the cycle. The result is a continuous, self-sustaining loop: matter rains, shatters,
swirls, and re-coalesces, forever.

## Superparameters

The 0..1 macro dials — each shifts many low-level params at once.

- **matter** — controls how much solid matter exists at once. At 0, polygons spawn slowly
  (every ~2.2 s) and the cap sits at 8 bodies; at 1, they rain in fast (every ~0.45 s) with
  up to 44 bodies on screen simultaneously.
- **fragility** — sets the collision speed needed to shatter a polygon. At 0, bodies are nearly
  indestructible (threshold ~950 px/s); at 1, they shatter on the lightest tap (~260 px/s),
  keeping the particle count high and the cycle frantic.
- **turbulence** — strength of the curl-noise flow field that steers particles. At 0, particles
  drift weakly (40 px/s force) and fall in near-straight paths; at 1, the field is vigorous
  (480 px/s) and swirls particles across the whole canvas.
- **cycle_speed** — controls how quickly dense particle clouds re-condense into polygons. At 0,
  condensation requires a very large cluster (~280 particles); at 1, small clusters (~70) trigger
  it, so the cycle turns over much faster.

## Parameters

Low-level knobs (pin exact values via a preset's `overrides`).

- **spawn_interval** (`float`, 0.3–3.0, default `1.0`) — seconds between polygon spawns.
- **max_bodies** (`int`, 4–60, default `22`) — maximum live physics bodies before spawning pauses.
- **poly_size** (`float`, 30.0–160.0, default `80.0`) — base radius of spawned polygons in pixels;
  each spawn is jittered ±10% and additionally scaled by a random 0.6–1.4 factor in the code.
- **bounce** (`float`, 0.0–0.9, default `0.3`) — restitution coefficient of polygon physics
  bodies; requires restart to take effect.
- **shatter_speed** (`float`, 150.0–1200.0, default `520.0`) — relative collision speed (px/s)
  above which a polygon shatters into particles.
- **min_poly_age** (`float`, 0.0–2.0, default `0.5`) — minimum seconds a polygon must be alive
  before it can shatter; prevents instant fragmentation on spawn.
- **frag_per_100px2** (`float`, 0.5–8.0, default `2.5`) — particle count per 100 px² of polygon
  area when it shatters; larger or higher-density polygons produce proportionally more particles.
- **swarm_cap** (`int`, 1000–12000, default `6000`) — hard ceiling on live particles; requires
  restart to take effect.
- **flow_strength** (`float`, 0.0–600.0, default `220.0`) — force (px/s²) the curl-noise field
  applies to particles each frame.
- **flow_scale** (`float`, 0.5–4.0, default `1.6`) — spatial scale of the noise field; higher
  values zoom out, producing broader, more gradual swirls.
- **updraft** (`float`, -300.0–300.0, default `-120.0`) — constant vertical force on particles;
  negative is upward. Default creates a gentle upward drift opposing gravity.
- **particle_drag** (`float`, 0.0–3.0, default `0.6`) — velocity damping applied to particles
  each frame; higher values slow particles more quickly.
- **condense_count** (`int`, 40–400, default `150`) — minimum particles in a 120×120 px cell
  needed to trigger condensation into a new polygon.
- **condense_radius** (`float`, 60.0–300.0, default `140.0`) — radius (px) around the
  condensation center from which particles are consumed.
- **condense_cooldown** (`float`, 0.2–4.0, default `1.0`) — minimum seconds between condensation
  events; prevents rapid-fire condensation during dense particle accumulations.
- **particle_max_age** (`float`, 3.0–30.0, default `14.0`) — lifetime in seconds before a
  particle is removed regardless of position.
- **purge_delay** (`float`, 0.0–30.0, default `5.0`) — seconds a *saturated* pile (body count
  at `max_bodies`) may sit completely at rest before every polygon detonates at once. This is the
  deadlock escape hatch: polygons only ever leave the field by shattering, and shattering needs a
  fast impact, so a pile deep enough that new rain lands softly is an absorbing state — no
  fragments, no condensation, and no `shatter` events to spike a fragility envelope. The purge
  dumps the whole pile back into the swarm, which re-condenses and restarts the cycle. Set to
  `0.0` to disable (the pile is then allowed to stall forever).
- **glow** (`float`, 0.0–3.0, default `1.1`) — additive glow intensity applied to the whole
  scene via Godot's environment bloom.
- **palette** (`enum`, default `spectrum`) — color scheme for polygons (and the particles they
  shed). Options: `spectrum` (each polygon gets a random hue from the full wheel), `ember`
  (orange/amber/red tones), `mono` (grays and white). Requires restart to take effect.

## Events

Discrete moments emitted for envelope modulation:

- `spawn` — fires each time a new polygon is created (either from the rain or from condensation).
- `shatter` — fires when a polygon breaks apart into particles on a hard collision.
- `condense` — fires when a dense particle cluster collapses back into a new polygon.

## Presets

- `slow_genesis` — long stretches of near-empty black; lone white wireframe polygons drift down,
  quietly pile, and only rarely shatter. Minimalist and patient — it earns its moments.
- `grinder` — multicolor wireframes shattering on contact into white-hot particle spray;
  condensation rings fire constantly; matter churns through the full cycle in seconds.
- `tides` — 5-minute long-form modulation: a tween builds matter density and cycle speed over
  275 s; a 90 s LFO undulates turbulence; each `shatter` event spikes a fragility envelope.
