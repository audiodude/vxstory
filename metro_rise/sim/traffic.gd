extends RefCounted
# Deterministic kinematic traffic on the road graph. Cars follow seeded
# random-walk routes over active (paved-in) segments, keep spacing to the car
# ahead on their lane, and queue at fixed-cycle traffic lights. No physics.
# Transient layer: reseed(t) re-hashes the fleet for scrubs (character-at-t).

const CAR_LEN := 4.4
const MIN_GAP := 7.0
const CAP := 2000
const SPAWN_PER_TICK := 40

var _plan: Dictionary
var _seed: int
var _rng: RandomNumberGenerator
var _cars: Array = []
var _node_pos: Array = []      # node id -> Vector2
var _adj: Array = []           # node id -> [{to, seg, kind, ring_frac, len}]
var _phase: PackedFloat32Array # node id -> light phase offset

func _init(plan: Dictionary, seed_value: int) -> void:
	_plan = plan
	_seed = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = hash("%d:traffic" % seed_value)
	var nodes: Array = plan["roads"]["nodes"]
	var segs: Array = plan["roads"]["segments"]
	_node_pos.resize(nodes.size())
	_adj.resize(nodes.size())
	_phase.resize(nodes.size())
	var prng := RandomNumberGenerator.new()
	prng.seed = hash("%d:traffic:phase" % seed_value)
	for n in nodes:
		_node_pos[n["id"]] = n["pos"]
		_adj[n["id"]] = []
		_phase[n["id"]] = prng.randf()
	for s in segs:
		var entry_a := {"to": s["nb"], "seg": s["id"], "kind": s["kind"],
				"ring_frac": (float(s["ring"]) + 0.2) / 6.0,
				"len": (s["b"] as Vector2).distance_to(s["a"])}
		var entry_b := entry_a.duplicate()
		entry_b["to"] = s["na"]
		_adj[s["na"]].append(entry_a)
		_adj[s["nb"]].append(entry_b)

func car_count() -> int:
	return _cars.size()

func cars() -> Array:
	var out: Array = []
	for c in _cars:
		var a: Vector2 = _node_pos[c["route"][c["leg"]]]
		var b: Vector2 = _node_pos[c["route"][c["leg"] + 1]]
		var dir := (b - a).normalized()
		var right := Vector2(-dir.y, dir.x)
		var pos: Vector2 = a + dir * c["s"] + right * c["off"]
		out.append({"pos": pos, "ang": atan2(dir.y, dir.x),
				"stopped": c["v"] < 0.5, "hue": c["hue"]})
	return out

func reseed(t: float) -> void:
	_cars.clear()
	_rng = RandomNumberGenerator.new()
	_rng.seed = hash("%d:traffic:%d" % [_seed, int(t * 7.0)])

func tick(dt: float, t: float, P: float, live: Dictionary) -> void:
	var ring_p := 0.22 + 0.78 * clampf(P, 0.0, 1.0)
	var era_gate := clampf((P - 0.30) / 0.10, 0.0, 1.0)
	var budget := 0
	if era_gate > 0.0:
		var lane_len := 0.0
		for s in _plan["roads"]["segments"]:
			if (float(s["ring"]) + 0.2) / 6.0 + 0.04 < ring_p:
				lane_len += (s["b"] as Vector2).distance_to(s["a"]) * (2.0 if s["kind"] == "street" else 4.0)
		budget = mini(int(float(live["car_density"]) * era_gate * lane_len / 55.0), CAP)

	# Despawn finished routes; spawn toward budget.
	var alive: Array = []
	for c in _cars:
		if c["leg"] < c["route"].size() - 1:
			alive.append(c)
	_cars = alive
	var to_spawn := mini(budget - _cars.size(), SPAWN_PER_TICK)
	for i in to_spawn:
		var c := _spawn(ring_p)
		if not c.is_empty():
			_cars.append(c)
	while _cars.size() > budget:
		_cars.pop_back()

	# Lane occupancy for car-following: key -> sorted [car index, s].
	var lanes := {}
	for i in _cars.size():
		var c: Dictionary = _cars[i]
		var key := "%d:%d:%d" % [c["route"][c["leg"]], c["route"][c["leg"] + 1], c["lane"]]
		if not lanes.has(key):
			lanes[key] = []
		lanes[key].append(Vector2(c["s"], float(i)))
	for key in lanes:
		(lanes[key] as Array).sort()

	var cycle: float = maxf(float(live["light_cycle"]), 2.0)
	for i in _cars.size():
		var c: Dictionary = _cars[i]
		var a_id: int = c["route"][c["leg"]]
		var b_id: int = c["route"][c["leg"] + 1]
		var a: Vector2 = _node_pos[a_id]
		var b: Vector2 = _node_pos[b_id]
		var leg_len := a.distance_to(b)
		var target: float = c["v_max"] * float(live["car_speed"])

		# Red light: stop 8 m before the far node unless it's the route's end.
		if c["leg"] < c["route"].size() - 2 and not _green(b_id, a, b, t, cycle):
			var to_line: float = leg_len - 8.0 - c["s"]
			if to_line < 12.0 and to_line > -2.0:
				target = 0.0 if to_line < 4.0 else minf(target, to_line * 1.2)

		# Car ahead on the same lane.
		var key := "%d:%d:%d" % [a_id, b_id, c["lane"]]
		var col: Array = lanes[key]
		for k in col.size():
			if int(col[k].y) == i and k + 1 < col.size():
				var gap: float = col[k + 1].x - c["s"] - CAR_LEN
				if gap < MIN_GAP:
					var ahead: Dictionary = _cars[int(col[k + 1].y)]
					target = minf(target, float(ahead["v"]) * clampf(gap / MIN_GAP, 0.0, 1.0))
				break

		var v: float = c["v"]
		v = minf(v + 3.0 * dt, target) if v < target else maxf(v - 7.0 * dt, target)
		c["v"] = maxf(v, 0.0)
		c["s"] = c["s"] + c["v"] * dt
		if c["s"] >= leg_len:
			c["s"] -= leg_len
			c["leg"] += 1

func _green(node_id: int, a: Vector2, b: Vector2, t: float, cycle: float) -> bool:
	if _adj[node_id].size() <= 2:
		return true  # no cross traffic, no light
	var ph := fmod(t / cycle + _phase[node_id], 1.0)
	var horizontal: bool = absf(b.x - a.x) > absf(b.y - a.y)
	return (ph < 0.46) if horizontal else (ph >= 0.5 and ph < 0.96)

func _spawn(ring_p: float) -> Dictionary:
	for attempt in 4:
		var n0 := _rng.randi() % _node_pos.size()
		if _adj[n0].is_empty() or not _node_active(n0, ring_p):
			continue
		var route: Array = [n0]
		var prev := -1
		var cur := n0
		var kind := "street"
		var legs := 5 + _rng.randi() % 9
		for leg in legs:
			var options: Array = []
			for e in _adj[cur]:
				if e["to"] != prev and e["ring_frac"] + 0.04 < ring_p:
					options.append(e)
			if options.is_empty():
				break
			var pick: Dictionary = options[_rng.randi() % options.size()]
			# Straight bias: prefer continuing direction when available.
			if route.size() >= 2 and options.size() > 1 and _rng.randf() < 0.7:
				var d_prev: Vector2 = (_node_pos[cur] - _node_pos[route[route.size() - 2]]).normalized()
				var best_dot := -2.0
				for e in options:
					var d := (_node_pos[e["to"]] - _node_pos[cur]).normalized() as Vector2
					if d.dot(d_prev) > best_dot:
						best_dot = d.dot(d_prev)
						pick = e
			if route.size() == 1:
				kind = pick["kind"]
			prev = cur
			cur = pick["to"]
			route.append(cur)
		if route.size() < 3:
			continue
		var lane := (_rng.randi() % 2) if kind == "blvd" else 0
		return {
			"route": route, "leg": 0,
			"s": _rng.randf() * 20.0,
			"off": 3.0 + (5.0 * lane if kind == "blvd" else 0.0),
			"lane": lane,
			"v": 0.0, "v_max": (16.0 if kind == "blvd" else 12.0) * _rng.randf_range(0.85, 1.1),
			"hue": _rng.randf(),
		}
	return {}

func _node_active(n: int, ring_p: float) -> bool:
	for e in _adj[n]:
		if e["ring_frac"] + 0.04 < ring_p:
			return true
	return false
