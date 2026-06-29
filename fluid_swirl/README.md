# fluid_swirl

Psychedelic marbled dye advection. Colored injectors trace Lissajous-like paths across a ping-pong fluid simulation, depositing dye that is advected, sheared, and diffused each frame by a noise field and a set of seeded vortices. The output is graded through saturation and contrast shaders before display.

## Superparameters

The 0..1 macro dials — each shifts many low-level params at once.

- **turbulence** — raises both the noise field strength and vortex strength together, turning gentle swirling folds (0) into chaotic, shredding turbulence with strong spinning cores (1).
- **viscosity** — controls how long dye lingers. At 0, dye dissipates quickly and colours fade out fast; at 1, dissipation is near-perfect and shapes persist indefinitely, building up thick, saturated masses.
- **flow** — sets the overall advection speed. At 0 the field creeps; at 1 it sweeps rapidly across the canvas.
- **vibrance** — drives post-process saturation. At 0, colours are muted and close to pastel; at 1, they are vivid and fully saturated.

## Parameters

Low-level knobs (pin exact values via a preset's `overrides`). Params marked *(restart)* require a sim restart to take effect — they cannot be changed live.

- **sim_height** (`int`, 270–1080, default `540`) *(restart)* — vertical resolution of the fluid simulation. Width is locked to 16:9 (e.g. 960×540). Higher values cost more GPU per step.
- **noise_strength** (`float`, 0.0–3.0, default `2.0`) — amplitude of the curl-noise velocity field applied each step. Drives the *turbulence* macro (lo 0.5 → hi 3.0).
- **noise_scale** (`float`, 1.0–8.0, default `3.0`) — spatial frequency of the noise field. Larger values produce coarser, slower-varying swirls; smaller values give fine, rapid texture.
- **dissipation** (`float`, 0.9–1.0, default `0.995`) — per-step dye retention factor. 1.0 = no fade; 0.9 = fast decay. Drives the *viscosity* macro (lo 0.98 → hi 1.0).
- **flow_speed** (`float`, 0.2–4.5, default `3.0`) — scalar multiplier on the advection velocity applied to the dye field each step. Drives the *flow* macro (lo 1.2 → hi 4.5).
- **vortex_count** (`int`, 0–8, default `6`) *(restart)* — number of seeded vortex centres placed at sim start. More vortices create more orbital spin structures competing with the noise field.
- **vortex_strength** (`float`, 0.0–2.4, default `1.6`) — rotational velocity magnitude at each vortex core. Drives the *turbulence* macro (lo 0.4 → hi 2.4).
- **injector_count** (`int`, 1–8, default `8`) *(restart)* — number of dye injectors. Each gets a unique Lissajous phase/frequency pair and cycles through the active palette.
- **inject_radius** (`float`, 20.0–200.0, default `140.0`) — radius in pixels of each dye injection blob per frame. Larger blobs spread dye faster and produce broader colour masses.
- **inject_strength** (`float`, 0.05–1.0, default `0.6`) — intensity of each dye injection. Higher values saturate the sim quickly; lower values produce translucent washes.
- **injector_speed** (`float`, 0.05–1.0, default `0.5`) — playback speed of the Lissajous paths the injectors trace. Slower paths leave long streaks; faster paths scatter dye broadly.
- **palette** (`enum`, default `"psychedelic"`) *(restart)* — colour set assigned round-robin to the injectors. Options: `psychedelic` (blue/red/green/gold/violet), `magma` (deep reds and incandescent yellows), `ocean` (blues and teals), `neon` (hot pink/cyan/lime/violet/orange).
- **saturation** (`float`, 0.5–2.0, default `1.25`) — post-process saturation applied to the final output via shader. Drives the *vibrance* macro (lo 0.8 → hi 1.8).
- **contrast** (`float`, 0.8–1.6, default `1.1`) — post-process contrast applied to the final output via shader. Values above 1.0 crush blacks and lift whites.

## Events

Emits no events (continuous injectors — drive it with tweens/LFOs).

## Presets

- `default` — schema defaults at mid-range turbulence/viscosity/flow/vibrance with ±20% jitter on noise_scale; a general-purpose starting point.
- `lava_lamp` — thick, slow magma: deep reds and incandescent yellows rising and folding like flame in oil, high viscosity so shapes linger and ooze. Three injectors, magma palette.
- `maelstrom` — saturated cyan/magenta/yellow turbulence at 8 vortices and high flow; the whole canvas shreds and recombines continuously, edge-to-edge colour with no rest. Neon palette.
- `aurora` — 5-minute long-form modulation: a 275s ease-in tween builds turbulence (+0.45) and flow (+0.4) from calm to active; a slow 75s sine LFO breathes vibrance for continuous colour pulsing. No envelope (fluid emits no discrete events).
