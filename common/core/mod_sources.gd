extends RefCounted
# Pure modulation source signals — deterministic functions of time.

const MM = preload("res://core/macro_mapper.gd")

# LFO: free-running periodic, bipolar output in [-1, 1].
static func lfo(t: float, rate_sec: float, shape: String, phase := 0.0) -> float:
	if rate_sec <= 0.0:
		return 0.0
	var ph := TAU * t / rate_sec + phase
	match shape:
		"triangle":
			return 2.0 / PI * asin(sin(ph))
		"drift":  # two incommensurate sines -> organic, non-repeating
			return 0.6 * sin(ph) + 0.4 * sin(TAU * t / (rate_sec * 0.391) + phase)
		_:  # "sine"
			return sin(ph)

# Tween: one-shot curve from->to over secs; holds at `to` afterward.
static func tween(t: float, secs: float, curve: String, from_v: float, to_v: float) -> float:
	if secs <= 0.0:
		return to_v
	var x := clampf(t / secs, 0.0, 1.0)
	return lerpf(from_v, to_v, MM.curve_apply(x, curve))

# Envelope (one instance): age since trigger -> [0, peak]; 0 before trigger and
# after attack+decay. Linear attack, then linear decay.
static func envelope(age: float, attack: float, decay: float, peak: float) -> float:
	if age < 0.0:
		return 0.0
	if age < attack:
		return peak * (age / maxf(attack, 0.0001))
	var d := age - attack
	if d < decay:
		return peak * (1.0 - d / maxf(decay, 0.0001))
	return 0.0
