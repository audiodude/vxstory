# Designer 2d — IPC playhead sync — design

**Date:** 2026-07-01

## Goal

Sync the **transport** (playhead time + play/pause) between the two running
processes — the **Designer** (`--designer`) and the **Phase-1 preview** — over a
localhost socket, **bidirectionally**. Scrub or play/pause in either window and
the other follows, so while tuning you can scrub the Designer to a moment and see
the *actual sim* at that moment in the preview. Today the two share only
`scene.json`; 2d adds a **transport bus** alongside it.

## Current transports (from survey)

- **Designer** (`common/core/designer/designer.gd`): its own clock `_t` + bool
  `_playing`, an `HSlider` scrub, a `▶` toggle; the clock drives knob animation +
  the source-card preview playheads. No sim of its own.
- **Preview** (`common/core/timeline.gd` + `sim_model.gd`): playhead time is
  `model.mod_stack.t`; dragging the timeline calls `model.scrub_to(t)` — a
  **heavy** op (restart + replay to character-at-`t`). There is **no play/pause**
  (the sim always advances) and **no loop markers** anywhere.

## Locked decisions

- Channel: **localhost socket** (UDP). Direction: **bidirectional**. Sync set:
  **playhead `t` + play/pause**.
- **Loop markers are out of scope** — they don't exist yet; add loop-marker sync
  when the loop-marker feature is built.
- Play/pause sync **requires adding pause to the preview** (new; it was a deferred
  Phase-1 "video-playback" feature) — included here.

## Components

### 1. `common/core/transport_link.gd` (new)
A small `Node` (`process_mode = PROCESS_MODE_ALWAYS`, so it keeps polling when the
sim is paused via `time_scale`). Uses `PacketPeerUDP`.

- **Role-based fixed port pair.** A base port `P` (a constant, e.g. 47615). The
  **designer** binds `P` and sends to `P+1`; the **preview** binds `P+1` and sends
  to `P`. Role is known from the launch mode (`--designer` → designer, else
  preview). Bind failure (port taken / a second pair) → link disabled, log once,
  no crash (transport just isn't synced; everything else works).
- **API:** `setup(role: String)`; `signal remote(t: float, playing: bool)`;
  `send(t: float, playing: bool)`. Poll incoming in `_process`; on a packet emit
  `remote(...)`. Packet = a small JSON dict `{"t": float, "playing": bool}`.
- **Pure helpers (unit-tested):** `encode(t, playing) -> PackedByteArray` /
  `decode(bytes) -> {t, playing}` (round-trip); `ports_for(role) -> {listen, send}`
  (the role→port-pair mapping).

### 2. Sync semantics (event-driven — no per-frame restarts)
- **Local scrub (jump)** → `send(t, playing)`. On **remote scrub received**:
  Designer sets `_t` + `_scrub.set_value_no_signal`; preview calls `scrub_to(t)`.
- **Local play/pause toggle** → `send`. On **remote received**: Designer sets
  `_playing` (+ button state); preview pauses/unpauses.
- **On play-start**, send once so both seek to the shared `t`. While both play,
  each advances real-time on its own clock (**no per-frame `scrub_to`** — that
  would restart the sim every frame). A coarse **~2 s periodic resync**: the
  driver sends `t`; the receiver adopts only if `|Δt|` exceeds a threshold
  (~0.5 s) — so long playback can't drift, but normal playback never hitches.
- **No echo:** applying a received value must NOT re-`send` (guard with a
  "applying remote" flag).

### 3. Preview play/pause (new)
- **Space** toggles `Engine.time_scale` between `1.0` (play) and `0.0` (pause).
  `time_scale = 0` freezes the sim + the modulation clock, but `_process` still
  fires (delta 0), so the transport link keeps receiving. The timeline shows a
  small paused indicator.
- The preview owns a `transport_link` (role "preview"): sends on scrub / space;
  applies remote via `scrub_to` (jump) + `time_scale` (pause). `scrub_to` already
  exists; only pause + the link are new.

### 4. Designer integration
The Designer owns a `transport_link` (role "designer"): its existing `▶`
toggle and `_scrub` `value_changed` also `send(...)`; a `remote(...)` handler sets
`_t` / `_playing` + the slider, guarded so it doesn't re-send.

## Attachment / isolation
- The link attaches **only** in designer mode and preview mode. **Movie/render
  mode does not attach it** (renders are a separate `--write-movie` process with
  no transport) — batch renders are unaffected. Confirm in `sim_model` that the
  preview link is created on the same path as `_attach_scene_tools` (non-movie),
  and the designer link inside `_attach_designer`.

## Verification
- Unit tests: `transport_link` `encode`/`decode` round-trip; `ports_for` role
  mapping; the drift-adopt threshold helper.
- Headless smoke: designer and preview each launch, bind the link (or degrade
  cleanly if the port is taken), no errors; movie mode does NOT bind the link.
- Two-process integration (user): launch Designer + preview on the same scene;
  scrub one → the other follows; space in the preview pauses both; play in the
  Designer runs both. Look/feel is the user's review.

## Out of scope
- Loop markers (don't exist yet) and loop-region sync.
- Designer 2b (compose) / 2c (drag handles + MIDI).
- Multiple simultaneous designer/preview *pairs* (one pair shares the fixed port
  pair; a second pair would collide — acceptable for now, logged).
