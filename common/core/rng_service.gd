extends RefCounted
# Deterministic RNG hub. One master seed; named sub-streams are independent,
# so jitter rolls don't perturb sim spawning and vice versa.

var master_seed: int

func _init(seed_value: int) -> void:
	master_seed = seed_value

func stream(stream_name: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%s" % [master_seed, stream_name])
	return r
