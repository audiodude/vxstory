extends RefCounted
# The modulation stack. Parses a preset's `modulators` and composes the live
# param set each frame under one rule (see the modulation-system design spec):
#   live superparam = clamp(macro_base + Σ offsets, 0, 1)
#   param           = resolve(live superparams) + Σ offsets, clamped to [min,max]
# Sources: LFO (continuous), tween (one-shot at t=0), envelope (event-triggered,
# polyphonic). Envelope output sums over live instances.

const MS = preload("res://core/mod_sources.gd")
const MM = preload("res://core/macro_mapper.gd")

var enabled := false
var t := 0.0
var lfos: Array = []       # {shape, rate, phase, targets:[{to, amount}]}
var tweens: Array = []     # {secs, curve, from, to, targets}
var envelopes: Array = []  # {event, attack, decay, peak, targets, instances:[float]}

static func from_config(cfg: Dictionary, rng_service) -> RefCounted:
	var m = new()
	for d in cfg.get("lfo", []):
		var nm := str(d.get("name", "lfo"))
		var r: RandomNumberGenerator = rng_service.stream("mod:" + nm)
		m.lfos.append({
			"shape": str(d.get("shape", "sine")),
			"rate": maxf(float(d.get("rate_sec", 30.0)), 0.0),
			"phase": r.randf_range(0.0, TAU),
			"targets": m._targets(d),
		})
	for d in cfg.get("tween", []):
		m.tweens.append({
			"secs": maxf(float(d.get("secs", 60.0)), 0.0),
			"curve": str(d.get("curve", "linear")),
			"from": float(d.get("from", 0.0)),
			"to": float(d.get("to", 1.0)),
			"targets": m._targets(d),
		})
	for d in cfg.get("envelope", []):
		m.envelopes.append({
			"event": str(d.get("event", "")),
			"attack": maxf(float(d.get("attack", 0.01)), 0.0),
			"decay": maxf(float(d.get("decay", 0.3)), 0.0),
			"peak": float(d.get("peak", 1.0)),
			"targets": m._targets(d),
			"instances": [],
		})
	m.enabled = not (m.lfos.is_empty() and m.tweens.is_empty() and m.envelopes.is_empty())
	return m

func _targets(d: Dictionary) -> Array:
	var out := []
	for tg in d.get("targets", []):
		out.append({"to": str(tg.get("to", "")), "amount": float(tg.get("amount", 0.0))})
	return out

func tick(delta: float) -> void:
	t += delta
	for env in envelopes:
		var dur: float = env["attack"] + env["decay"]
		var live := []
		for trig in env["instances"]:
			if t - float(trig) <= dur:
				live.append(trig)
		env["instances"] = live

func emit(event_name: String) -> void:
	for env in envelopes:
		if env["event"] == event_name:
			env["instances"].append(t)

func offsets() -> Dictionary:
	var d := {}
	for lfo in lfos:
		var o := MS.lfo(t, lfo["rate"], lfo["shape"], lfo["phase"])
		for tg in lfo["targets"]:
			d[tg["to"]] = float(d.get(tg["to"], 0.0)) + o * float(tg["amount"])
	for tw in tweens:
		var o := MS.tween(t, tw["secs"], tw["curve"], tw["from"], tw["to"])
		for tg in tw["targets"]:
			d[tg["to"]] = float(d.get(tg["to"], 0.0)) + o * float(tg["amount"])
	for env in envelopes:
		var o := 0.0
		for trig in env["instances"]:
			o += MS.envelope(t - float(trig), env["attack"], env["decay"], env["peak"])
		for tg in env["targets"]:
			d[tg["to"]] = float(d.get(tg["to"], 0.0)) + o * float(tg["amount"])
	return d

func compose(schema: Dictionary, macros: Dictionary, overrides: Dictionary, jitter: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var off := offsets()
	var live := {}
	for mm in schema["macros"]:
		var base: float = float(macros.get(mm["name"], mm["default"]))
		live[mm["name"]] = clampf(base + float(off.get(mm["name"], 0.0)), 0.0, 1.0)
	var params := MM.resolve(schema, live, overrides, jitter, rng)
	for p in schema["params"]:
		var pn: String = p["name"]
		if (p["type"] == "float" or p["type"] == "int") and off.has(pn):
			var v := float(params[pn]) + float(off[pn])
			if p["type"] == "int":
				params[pn] = clampi(roundi(v), int(p["min"]), int(p["max"]))
			else:
				params[pn] = clampf(v, float(p["min"]), float(p["max"]))
	return params
