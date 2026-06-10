extends RefCounted
# Drifts macro values along smooth seeded curves over time. Preset config:
#   "director": {"enabled": true, "period_sec": 90.0, "amplitude": 0.25,
#                "macros": ["accretion", "chaos"]}
# Drift = sum of two seeded sines at incommensurate periods -> smooth, bounded,
# deterministic, non-repeating over any practical render length.

var enabled := false
var period := 90.0
var amplitude := 0.25
var macro_names: PackedStringArray = PackedStringArray()
var bases := {}    # macro -> curve center (preset value; rebased on user edit)
var _phases := {}  # macro -> [phase1, phase2]
var t := 0.0

static func from_config(cfg: Dictionary, macros: Dictionary, rng_service) -> RefCounted:
	var d = new()
	d.enabled = bool(cfg.get("enabled", false))
	d.period = maxf(float(cfg.get("period_sec", 90.0)), 1.0)
	d.amplitude = clampf(float(cfg.get("amplitude", 0.25)), 0.0, 1.0)
	for n in cfg.get("macros", []):
		if macros.has(n):
			d.macro_names.append(n)
			d.bases[n] = float(macros[n])
			var r: RandomNumberGenerator = rng_service.stream("director:" + str(n))
			d._phases[n] = [r.randf_range(0.0, TAU), r.randf_range(0.0, TAU)]
	return d

func tick(delta: float) -> void:
	t += delta

func current(macro_name: String) -> float:
	var ph: Array = _phases[macro_name]
	var drift := 0.6 * sin(TAU * t / period + ph[0]) \
		+ 0.4 * sin(TAU * t / (period * 0.391) + ph[1])
	return clampf(float(bases[macro_name]) + amplitude * drift, 0.0, 1.0)

func rebase(macro_name: String, v: float) -> void:
	if bases.has(macro_name):
		bases[macro_name] = v

func apply(macros: Dictionary) -> bool:
	if not enabled:
		return false
	var changed := false
	for n in macro_names:
		var v := current(n)
		if absf(float(macros.get(n, -1.0)) - v) > 0.0005:
			macros[n] = v
			changed = true
	return changed
