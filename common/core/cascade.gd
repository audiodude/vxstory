extends RefCounted
# Probabilistic sympathetic flood. Given point positions and an ignition origin,
# each not-yet-lit point within `radius` of a lit point catches with probability
# `coupling`, cascading outward (BFS). Deterministic given `rng`. Returns an
# Array of {idx:int, dist:float} for caught points, excluding the origin;
# `dist` is straight-line distance from the origin (for ripple timing).

static func flood(positions: Array, origin: int, coupling: float, radius: float, rng: RandomNumberGenerator) -> Array:
	var lit := {origin: true}
	var frontier := [origin]
	var caught := []
	var r2 := radius * radius
	while not frontier.is_empty():
		var n: int = frontier.pop_front()
		for m in positions.size():
			if lit.has(m):
				continue
			if (positions[m] - positions[n]).length_squared() <= r2 and rng.randf() < coupling:
				lit[m] = true
				frontier.push_back(m)
				caught.append({"idx": m, "dist": (positions[m] - positions[origin]).length()})
	return caught
