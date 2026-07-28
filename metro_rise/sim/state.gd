extends RefCounted
# StateTracker: evaluates a CityPlan at a development value P and reports what
# changed since the last eval. Slots are (entry x tier) flattened at init with
# stable indices — the view maps slot i to MultiMesh instance i. Structural
# state is an exact pure function of P, so scrubbing is exact by construction.
# The first eval after init reports every active slot as changed and NO events
# (that swallows would-be event storms on restart/scrub).

const DEMO_DUR := 0.02      # P-width of the demolition sink
const CRANE_MIN_FLOORS := 8

var _plan: Dictionary
var _params: Dictionary
var _slots: Array = []       # static: {lot, entry, tier_rect, tier_floors, y0, h, ep_a, ep_b, top_tier}
var _state: Array = []       # dynamic: {active, progress, demo, crane}
var _entry_prog: Dictionary = {}   # "lot:entry_idx" -> ep (for event edges)
var _first := true
var _prev_p := 0.0

func _init(plan: Dictionary, params: Dictionary) -> void:
	_plan = plan
	_params = params
	var floor_h: float = params["floor_h"]
	var lot_ids: Array = plan["timelines"].keys()
	lot_ids.sort()
	for lot_id in lot_ids:
		var entries: Array = plan["timelines"][lot_id]
		for ei in entries.size():
			var e: Dictionary = entries[ei]
			var total := float(e["floors"])
			var below := 0.0
			var frac_done := 0.0
			for ti in e["tiers"].size():
				var tier: Dictionary = e["tiers"][ti]
				var tf := float(tier["floors"])
				_slots.append({
					"lot": lot_id, "entry": e, "entry_key": "%d:%d" % [lot_id, ei],
					"tier_rect": tier["rect"], "tier_floors": tier["floors"],
					"y0": below * floor_h, "h": tf * floor_h,
					"ep_a": frac_done / 1.0, "ep_b": (frac_done + tf / total),
					"top_tier": ti == e["tiers"].size() - 1,
				})
				_state.append({"active": false, "progress": 0.0, "demo": 0.0, "crane": false})
				below += tf
				frac_done += tf / total

func building_count() -> int:
	return _slots.size()

func slot(i: int) -> Dictionary:
	var s: Dictionary = _slots[i]
	var d: Dictionary = _state[i]
	var e: Dictionary = s["entry"]
	return {
		"active": d["active"], "progress": d["progress"], "demo": d["demo"],
		"crane": d["crane"], "rect": s["tier_rect"], "y0": s["y0"], "h": s["h"],
		"style": e["style"], "floors": e["floors"], "win_w": e["win_w"],
		"accent": e["accent"], "lit_seed": e["lit_seed"], "lot": s["lot"],
		"industrial": e["industrial"],
	}

func eval(P: float) -> Dictionary:
	var changed: Array = []
	var events: Array = []
	var new_entry_prog := {}
	var crane_density: float = _params.get("crane_density", 0.7)
	var topout_floors: int = int(_params.get("topout_floors", 18))

	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var e: Dictionary = s["entry"]
		var ep := clampf((P - float(e["p0"])) / maxf(float(e["p1"]) - float(e["p0"]), 0.0001), 0.0, 1.0)
		var dp := 0.0
		if e["p_demo"] != INF:
			dp = clampf((P - float(e["p_demo"])) / DEMO_DUR, 0.0, 1.0)
		var tier_prog := clampf((ep - float(s["ep_a"])) / maxf(float(s["ep_b"]) - float(s["ep_a"]), 0.0001), 0.0, 1.0)
		var active: bool = ep > 0.0001 and dp < 1.0
		var crane: bool = s["top_tier"] and active and dp == 0.0 \
				and int(e["floors"]) >= CRANE_MIN_FLOORS \
				and ep > 0.02 and ep < 0.999 \
				and float(e["lit_seed"]) < crane_density

		var st: Dictionary = _state[i]
		if _first or st["active"] != active or absf(st["progress"] - tier_prog) > 0.0005 \
				or absf(st["demo"] - dp) > 0.0005 or st["crane"] != crane:
			if _first:
				if active:
					changed.append(i)
			else:
				changed.append(i)
			st["active"] = active
			st["progress"] = tier_prog
			st["demo"] = dp
			st["crane"] = crane

		# Entry-level event edges (once per entry, via its first tier slot).
		if s["ep_a"] == 0.0:
			var key: String = s["entry_key"]
			if not new_entry_prog.has(key):
				var prev_ep: float = _entry_prog.get(key, ep if _first else 0.0)
				if not _first:
					if prev_ep < 1.0 and ep >= 1.0 and int(e["floors"]) >= topout_floors:
						events.append({"kind": "topout", "lot": s["lot"],
								"floors": e["floors"], "pos": e["rect"].get_center()})
					var prev_dp := 0.0 if e["p_demo"] == INF else clampf((_prev_p - float(e["p_demo"])) / DEMO_DUR, 0.0, 1.0)
					if prev_dp <= 0.0 and dp > 0.0:
						events.append({"kind": "demolish", "lot": s["lot"],
								"pos": e["rect"].get_center()})
				new_entry_prog[key] = ep

	if not _first:
		for edge in [float(_params["era1_end"]), float(_params["era2_end"])]:
			if _prev_p < edge and P >= edge:
				events.append({"kind": "era", "edge": edge})

	for key in new_entry_prog:
		_entry_prog[key] = new_entry_prog[key]
	_prev_p = P
	var was_first := _first
	_first = false
	return {"changed": changed, "events": [] if was_first else events,
			"ring_p": 0.22 + 0.78 * clampf(P, 0.0, 1.0)}
