extends RefCounted
# Pure modulation source signals — deterministic functions of time.

const MM = preload("res://core/macro_mapper.gd")

# Oscillator: one periodic waveform, bipolar output in [-1, 1]. `phase` in degrees.
static func osc(t: float, period: float, shape: String, phase := 0.0) -> float:
	if period <= 0.0:
		return 0.0
	var ph := TAU * t / period + deg_to_rad(phase)
	match shape:
		"triangle":
			return 2.0 / PI * asin(sin(ph))
		"saw":
			return fposmod(ph, TAU) / PI - 1.0  # rising ramp -1 -> +1
		"square":
			return 1.0 if sin(ph) >= 0.0 else -1.0
		_:  # "sine"
			return sin(ph)

# LFO: weighted sum of oscillators, each {period, shape, phase, amount}. The sum
# can exceed [-1,1] if amounts do; each routing amount scales it again downstream.
static func lfo_value(t: float, oscillators: Array) -> float:
	var v := 0.0
	for o in oscillators:
		v += osc(t, float(o.get("period", 30.0)), str(o.get("shape", "sine")), float(o.get("phase", 0.0))) * float(o.get("amount", 1.0))
	return v

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
