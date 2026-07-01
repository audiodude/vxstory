# Designer 2d — IPC playhead sync — Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Sync playhead + play/pause between the Designer and the preview process over a bidirectional localhost UDP link. Spec: `docs/superpowers/specs/2026-07-01-designer-2d-playhead-sync-design.md`.

**Tech:** Godot 4.6 / GDScript. `PacketPeerUDP`. Test runner: `godot --headless --path radial_burst --script res://core/tests/run_tests.gd` (baseline **61**).

## Global Constraints
- **Event-driven sync only** — send on a scrub jump or a play/pause toggle (and once on play-start). NO per-frame sends and NO per-frame `scrub_to` (that restarts the sim). While both play, each runs its own real-time clock (drift over minutes is acceptable; no periodic resync this pass).
- **No echo:** applying a received value must not re-send (guard with an "applying remote" flag).
- **Isolation:** the link attaches ONLY in designer mode and preview (non-movie) mode. **Movie/render mode never binds it** — batch renders unaffected.
- **Degrade cleanly:** if the UDP bind fails (port taken), log once and disable sync; everything else still works.
- Suite stays green (use the live printed total).
- Loop markers are out of scope (don't exist).

---

### Task 1 — `transport_link.gd` (the pipe)

**Files:** Create `common/core/transport_link.gd`; Test: `common/core/tests/run_tests.gd`.

**Produces:** a `Node` with `signal remote(t: float, playing: bool)`, `setup(role: String)`, `send(t: float, playing: bool)`; statics `ports_for(role) -> {listen, send}`, `encode(t, playing) -> PackedByteArray`, `decode(bytes) -> Dictionary|null`.

- [ ] **Step 1 — failing tests** in `run_tests.gd`:
```gdscript
# ---------------- transport link ----------------

const TransportLink = preload("res://core/transport_link.gd")

func test_transport_encode_decode_roundtrip() -> void:
	var d = TransportLink.decode(TransportLink.encode(137.5, true))
	check(d != null, "decodes")
	check_eq(d["t"], 137.5, "t roundtrips")
	check_eq(d["playing"], true, "playing roundtrips")
	check_eq(TransportLink.decode("garbage".to_utf8_buffer()), null, "bad bytes -> null")

func test_transport_ports_for_roles_are_mirrored() -> void:
	var d = TransportLink.ports_for("designer")
	var p = TransportLink.ports_for("preview")
	check_eq(d["listen"], p["send"], "designer listens where preview sends")
	check_eq(d["send"], p["listen"], "designer sends where preview listens")
```

- [ ] **Step 2 — run RED.**

- [ ] **Step 3 — implement `common/core/transport_link.gd`:**
```gdscript
extends Node
# Bidirectional localhost UDP transport bus between the Designer and the preview.
# Role-based fixed port pair. Sends {t, playing} on transport events; emits
# `remote(t, playing)` on receive. process_mode ALWAYS so it keeps polling even
# when the sim is paused via Engine.time_scale.

signal remote(t: float, playing: bool)

const BASE_PORT := 47615

var _udp := PacketPeerUDP.new()
var _ok := false

func setup(role: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ports := ports_for(role)
	var err := _udp.bind(int(ports["listen"]), "127.0.0.1")
	if err != OK:
		push_warning("transport_link: bind %d failed (role %s); sync disabled" % [ports["listen"], role])
		return
	_udp.set_dest_address("127.0.0.1", int(ports["send"]))
	_ok = true

static func ports_for(role: String) -> Dictionary:
	if role == "designer":
		return {"listen": BASE_PORT, "send": BASE_PORT + 1}
	return {"listen": BASE_PORT + 1, "send": BASE_PORT}

static func encode(t: float, playing: bool) -> PackedByteArray:
	return JSON.stringify({"t": t, "playing": playing}).to_utf8_buffer()

static func decode(bytes: PackedByteArray):
	var d = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY or not d.has("t"):
		return null
	return {"t": float(d["t"]), "playing": bool(d.get("playing", false))}

func send(t: float, playing: bool) -> void:
	if _ok:
		_udp.put_packet(encode(t, playing))

func _process(_delta: float) -> void:
	if not _ok:
		return
	while _udp.get_available_packet_count() > 0:
		var d = decode(_udp.get_packet())
		if d != null:
			remote.emit(d["t"], d["playing"])
```

- [ ] **Step 4 — run GREEN** (expect 63); **smoke** the link binds headless (a throwaway `--quit-after` run of any preview that will attach it in Task 2, or trust the unit tests for now). **Step 5 — README test count; commit** `core: transport_link.gd — bidirectional localhost UDP transport bus`.

---

### Task 2 — Preview integration (pause + link)

**Files:** `common/core/sim_model.gd`, `common/core/timeline.gd`.

- [ ] **Read** `sim_model.gd` `_attach_scene_tools()` + `_process` + `scrub_to()`, and `timeline.gd` `_scrub_at()`. The preview playhead is `model.mod_stack.t`; `scrub_to(t)` jumps it.

- [ ] **Add preview play/pause** in `sim_model.gd` (preview/non-movie only). A space-bar handler toggles `Engine.time_scale` between `1.0` and `0.0` (`0.0` = paused: freezes sim + modulation; `_process` still fires at delta 0 so the link keeps receiving). Track a `_paused: bool`. Use `_unhandled_key_input` (or `_input`) gated to non-movie mode. On toggle, also `send` (below).

- [ ] **Attach the link** in the same non-movie path that calls `_attach_scene_tools()`:
```gdscript
	_link = load("res://core/transport_link.gd").new()
	add_child(_link)
	_link.setup("preview")
	_link.remote.connect(_on_remote_transport)
```
  Add `var _link` and `var _applying_remote := false`.

- [ ] **Send on local transport events:** after a local scrub (`scrub_to` called from the timeline drag) and on a local space toggle, call `if not _applying_remote: _link.send(mod_stack.t, not _paused)`. (Add the send at the end of `scrub_to` and in the space handler.)

- [ ] **Apply remote:**
```gdscript
func _on_remote_transport(t: float, playing: bool) -> void:
	_applying_remote = true
	if absf(mod_stack.t - t) > 0.01:
		scrub_to(t)               # jump to the remote playhead
	_set_paused(not playing)      # match play/pause via Engine.time_scale
	_applying_remote = false
```
  (`_set_paused(p)` sets `_paused = p` and `Engine.time_scale = 0.0 if p else 1.0`.) The `_applying_remote` guard prevents `scrub_to`'s send from echoing.

- [ ] **timeline.gd:** draw a small "❚❚ paused" indicator when `Engine.time_scale == 0.0` (read it in `_draw_strip`). Cheap; no transport logic in the timeline.

- [ ] **Verify:** suite still green; smoke `godot --headless --path radial_burst --quit-after 60 -- --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo CLEAN` → CLEAN (link binds, space handler + pause don't error headless). Commit `preview: space-bar pause + transport link (playhead sync)`.

---

### Task 3 — Designer integration

**Files:** `common/core/designer/designer.gd`.

- [ ] **Read** the current `designer.gd` (its `▶` toggle, `_scrub`, `_t`, `_playing`, `_process`).

- [ ] **Attach the link** in `setup()` (after `_build()`):
```gdscript
	_link = load("res://core/transport_link.gd").new()
	add_child(_link)
	_link.setup("designer")
	_link.remote.connect(_on_remote_transport)
```
  Add `var _link`, `var _applying_remote := false`, and promote the play `Button` to a member `_play` (so remote can reflect its pressed state).

- [ ] **Send on local transport events:** in the `▶` `toggled` handler and the `_scrub` `value_changed` handler, after updating `_playing`/`_t`, add `if not _applying_remote: _link.send(_t, _playing)`.

- [ ] **Apply remote:**
```gdscript
func _on_remote_transport(t: float, playing: bool) -> void:
	_applying_remote = true
	_t = t
	_scrub.set_value_no_signal(t / maxf(model.duration_sec, 0.0001))
	_playing = playing
	if _play != null:
		_play.set_pressed_no_signal(playing)
	_applying_remote = false
```

- [ ] **Verify:** suite green; smoke `godot --headless --path radial_burst --quit-after 60 -- --designer --preset presets/pulsar.json 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo CLEAN` → CLEAN. Commit `designer: transport link (bidirectional playhead + play/pause sync)`.

- [ ] **USER HANDOFF (controller):** launch Designer + preview on the same scene; scrub one → the other follows; space in the preview pauses both; play in the Designer runs both. (Two-process live sync is the user's review; automated coverage is the pipe unit tests + per-side smokes.)

---

## Self-review
- Spec coverage: socket pipe (Task 1), bidirectional (both integrations send+apply), playhead+play/pause sync (Tasks 2–3), preview pause via time_scale (Task 2), renders untouched (link only in designer/preview paths), degrade-on-bind-fail (Task 1). ✓
- Event-driven, echo-guarded, no per-frame scrub (constraints honored in the apply/send steps). ✓
- Types: `TransportLink.setup/send/remote/ports_for/encode/decode` consistent across tasks; `_on_remote_transport(t, playing)` + `_applying_remote` guard used identically on both sides.
- Loop markers explicitly out of scope. Live two-process sync is user-verified (UDP timing makes it a poor fit for the deterministic suite; the pipe logic is unit-tested pure).
