# supernova_orbit

A gravitational accretion simulator. Particles spiral inward from evenly spaced stream arms, are absorbed by one or more glowing cores, and push each core toward critical mass. At threshold the core either fissions into two orbiting bodies or detonates — blasting infalling matter outward, spawning tumbling debris, and starting the cycle fresh. Two cores that drift close enough merge back into one. A fluid haze layer beneath the swarm absorbs the shockwave and slowly disperses.

## Superparameters

The 0..1 macro dials — each shifts many low-level params at once.

- **accretion** — controls how aggressively the disk feeds the core. At 0: a thin trickle of particles under mild gravity. At 1: a dense particle storm with strong inward pull. Scales both spawn rate and gravitational strength.
- **critical_mass** — how much mass a core must absorb before it explodes. At 0: a hair-trigger (≈300 particles) producing rapid, small detonations. At 1: a slow build to a massive single event (≈1730 particles). This is the biggest dial for controlling cycle tempo.
- **detonation** — blast strength at the moment of explosion. At 0: particles and debris drift outward lazily. At 1: violent high-velocity ejection that clears the disk in a flash.
- **chaos** — orbit quality and trail length. At 0: particles trace tight near-circular orbits and leave very long-lived trails. At 1: highly eccentric, scattered infall with faster-fading trails. Also adjusts per-particle velocity variance.
- **duality** — fission tendency and binary-core spread. At 0: the core never fissions, stays near center, and always detonates solo. At 1: at critical mass it almost always splits into two, kicks the pair far apart, and lets them drift widely before re-merging.

## Parameters

Low-level knobs (pin exact values via a preset's `overrides`).

- **stream_count** (`int`, 1–8, default `3`) — number of infall arms. Particles spawn along edges evenly spaced by this count. Not live; requires restart.
- **spawn_rate** (`float`, 10–400, default `120.0`) — particles created per second. Driven by the `accretion` macro (30–300).
- **max_particles** (`int`, 2000–24000, default `16000`) — swarm pool capacity. Not live; requires restart.
- **g_strength** (`float`, 10000000–250000000, default `60000000`) — gravitational constant pulling particles toward the core(s). Driven by the `accretion` macro (25 M–90 M).
- **core_radius** (`float`, 20–150, default `100.0`) — absorption radius in pixels. Particles within this distance are swallowed and add to core mass.
- **critical** (`int`, 100–6000, default `1500`) — absorbed-particle mass that triggers fission or detonation. Driven by the `critical_mass` macro (300–1730).
- **orbit_factor** (`float`, 0.35–1.3, default `0.6`) — multiplier on the calculated circular orbital velocity. Below 1: elliptical plunging orbits. Above 1: particles tend to escape. Driven by the `chaos` macro (0.85 at chaos=0 → 0.42 at chaos=1).
- **chaos_spread** (`float`, 0–1, default `0.35`) — per-particle velocity jitter range (±spread). Driven by the `chaos` macro (0.05–0.8).
- **detonation_speed** (`float`, 200–3000, default `1200.0`) — outward blast velocity for particles and debris at detonation or fission. Driven by the `detonation` macro (400–2500).
- **debris_count** (`int`, 0–60, default `18`) — number of tumbling rock fragments spawned per detonation.
- **debris_radius** (`float`, 6–40, default `16.0`) — base radius of debris polygon fragments. Has 20% jitter by default.
- **trail_persist** (`float`, 0.01–0.5, default `0.025`) — per-frame fade amount applied to the trail viewport (lower = longer-lasting trails). Driven by the `chaos` macro (0.012–0.05). Live.
- **fluid_reactivity** (`float`, 0–1, default `0.5`) — how strongly detonations disturb the fluid haze: 0 = no effect, 1 = full dye injection and impulse.
- **glow** (`float`, 0–3, default `0.3`) — Godot additive glow intensity over the whole scene. Live.
- **palette** (`enum`, default `"solar"`) — color palette for the core, particle streams, and debris. Options: `solar` (amber/orange/yellow), `void` (purple/pink/blue), `emerald` (green). Not live; requires restart.
- **split_chance** (`float`, 0–0.85, default `0.35`) — probability a solo core at critical mass fissions instead of detonating. Driven by the `duality` macro (0.0–0.85).
- **core_drift** (`float`, 0–260, default `120.0`) — radius in pixels of the sinusoidal wander for a lone core around screen center. Driven by the `duality` macro (40–240).
- **split_kick** (`float`, 80–500, default `260.0`) — separation velocity applied to each half at fission. Driven by the `duality` macro (150–420).
- **merge_radius** (`float`, 60–300, default `130.0`) — distance at which two orbiting cores merge back into one via momentum-averaged velocity.
- **core_gravity** (`float`, 0–3000000, default `900000`) — gravitational attraction between two cores when in binary mode. Higher values pull them together faster.
- **debris_cap** (`int`, 10–200, default `80`) — maximum simultaneous debris fragments. Oldest pieces are culled when the cap is exceeded.
- **hue_drift** (`float`, 0–90, default `0.0`) — hue rotation in degrees per minute applied to all palette colors over the run. Creates slow color evolution across a single scene.
- **pulse_depth** (`float`, 0–0.25, default `0.08`) — amplitude of the core glow pulsation shader effect.
- **pulse_rate** (`float`, 0–2, default `1.0`) — frequency of the core glow pulsation.

## Events

Discrete moments emitted for envelope modulation:

- `fission` — fires when a solo core at critical mass splits into two. Produces a half-strength blast ring and kicks both halves apart.
- `detonation` — fires on a full supernova detonation. Clears all infalling particles, spawns debris, and triggers the fluid shockwave.
- `merge` — fires when two orbiting cores close within `merge_radius` and collapse back into one.

## Presets

- `default` — balanced starting point: high accretion, moderate critical threshold, strong detonation, balanced chaos. Good for exploring from scratch.
- `slow_burn` — three violet-and-teal spiral arms feed a purple core through one long, ominous charge toward a single massive detonation (void palette).
- `strobe_core` — emerald accretion at maximum inflow with a hair-trigger core: detonation rings every few seconds, each clearing the disk to start again.
- `odyssey` — 5-minute modulation-driven journey: two gravitationally interacting cores fission, orbit, and merge while a debris belt accumulates at blast sites; solar palette hue drifts 70° across the run so early amber warmth cools through teal by the end.
- `odyssey_slow_pulse` — long-form (5-minute) variant with slow pulse rate and extended trails; three incommensurate LFOs continuously drift accretion, chaos, and duality so no two minutes look alike; each detonation briefly spikes chaos via an envelope.
