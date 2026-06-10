# TODO

Deferred ideas for long-form interest (from the 2026-06-09 long-form design discussion).
Context: the v1.0 models are statistically stationary and reset state, so they hold
attention ~20-30s. Milestone 1 (binary cores, persistent consequences, director layer —
in supernova_orbit) is being built. These are the next candidates:

## Epochs — turn the loop into a life story (supernova_orbit)

Replace detonate-and-reset with a progression of visually distinct regimes:
diffuse nebula coalescing → protostar + accretion disk (current hero look) →
supernova → remnant path chosen seeded (pulsar: strobing beams sweeping leftover
dust / black hole: infall in inverted colors, trails visibly bending) → remnant
seeds the next nebula from its own wreckage. ~5 epochs × ~60s = a full non-looping
arc. Highest impact, most work: each epoch is a mini-model sharing the swarm/trail/
fluid machinery. Builds naturally on top of milestone 1's core-state machine.

## Heavy-tailed rare events (all models, start with supernova_orbit)

Seeded low-probability spectacles so rarity creates anticipation: a rogue mass
flying through and slingshotting the disk; overlapping double detonations; in
peg models, a one-in-N "golden ball" that detonates everything it touches.
Implementation sketch: a seeded event scheduler with per-event probability per
cycle, hooked into the same director/RNG streams so renders stay reproducible.

## Camera breathing (framework-level, benefits all models)

Slow drift/zoom during calm phases, punch-in on climax events, pull-back to
reveal accumulated scale (debris belt, painted canvas). Implementation sketch:
a Camera2D driven by the director layer with per-model "interest points" the
model publishes (e.g. core position, latest detonation). Costs little; makes
unchanged dynamics feel directed.
