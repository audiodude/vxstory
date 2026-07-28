extends RefCounted
# Per-lot building timelines in P-space (P = the `development` dial, 0..1).
# Each lot gets a chain of entries: construct -> stand -> (maybe) demolish ->
# successor in a later architectural era. Parcels (merged core lots) demolish
# together and yield a single era-3 tower. Pure logic.
#
# Entry: {p0, p1, p_demo (INF = never), style (0 brick, 1 concrete, 2 glass),
#         floors, industrial, parcel_id (-1), rect: Rect2,
#         tiers: [{rect: Rect2, floors}], win_w, accent, lit_seed}

const FLOOR_RANGES := {
	0: {"core": [4, 8], "commercial": [3, 7], "residential": [2, 5], "industrial": [1, 3]},
	1: {"core": [10, 24], "commercial": [8, 18], "residential": [6, 12], "industrial": [2, 4]},
	2: {"core": [24, 60], "commercial": [16, 40], "residential": [12, 24], "industrial": [3, 5]},
}
const WIN_W := {0: 1.6, 1: 1.9, 2: 1.5}
const LINGER := 0.06      # min standing time before demolition
const GAP := 0.015        # dust gap between demolition and groundbreaking
const DEMO_SPREAD := 0.25 # teardowns trickle through the era, not at its edge
const LAST_TOPOUT := 0.995

static func timelines(rng: RandomNumberGenerator, lots_dict: Dictionary, params: Dictionary) -> Dictionary:
	var out := {}
	var parcel_info := {}  # parcel_id -> {"p": demo P, "tower_lot": lowest member lot id}
	for pc in lots_dict["parcels"]:
		var e2: float = params["era2_end"]
		var lo: Array = pc["lots"].duplicate()
		lo.sort()
		parcel_info[pc["id"]] = {
			"p": clampf(e2 + 0.05 + rng.randf() * (0.85 - e2 - 0.05), 0.0, 0.9),
			"tower_lot": lo[0], "rect": pc["rect"],
		}

	for l in lots_dict["lots"]:
		var chain := _lot_chain(rng, l, params, parcel_info)
		if not chain.is_empty():
			out[l["id"]] = chain
	return out

static func _lot_chain(rng: RandomNumberGenerator, l: Dictionary, params: Dictionary, parcel_info: Dictionary) -> Array:
	var d_frac: float = maxf(absf(l["rect"].get_center().x), absf(l["rect"].get_center().y)) / float(params["city_radius"])
	var p_open := clampf((d_frac - 0.22) / 0.78, 0.0, 1.0)
	var p := p_open + rng.randf() * 0.08
	var in_parcel: bool = l["parcel"] != -1
	var parcel_p: float = parcel_info[l["parcel"]]["p"] if in_parcel else INF
	var entries: Array = []

	while p < 0.93:
		if in_parcel and p > parcel_p - 0.05:
			break  # don't start what the parcel demolition would immediately kill
		var style := _style_at(p, rng, params)
		if l["district"] == "industrial":
			style = mini(style, 1)
		if in_parcel:
			style = mini(style, 1)  # members never go glass; the parcel tower does
		var e := _make_entry(rng, l["rect"], l["district"], style, p, params, false)
		if e["p1"] > LAST_TOPOUT:
			break
		entries.append(e)
		# Parcel members: forced demolition at the parcel's shared P.
		if in_parcel and parcel_p > e["p1"] - 0.02:
			e["p_demo"] = maxf(parcel_p, e["p1"])
			break
		# Seeded replacement: only if the successor would be a later era.
		var demo_prob := _demo_prob(l["district"], params)
		if rng.randf() > demo_prob:
			break
		var p_demo: float = maxf(e["p1"] + LINGER, _next_band_start(style, params) + rng.randf() * DEMO_SPREAD)
		var p_next := p_demo + GAP
		if p_next >= 0.93 or _style_at_nominal(p_next, params) <= style:
			break
		e["p_demo"] = p_demo
		p = p_next

	# A demolition whose successor never got built (end-of-run cutoff) is cancelled:
	# the building simply stands. Parcel members keep their forced demolition.
	if not in_parcel and not entries.is_empty() and entries.back()["p_demo"] != INF:
		entries.back()["p_demo"] = INF

	# The parcel tower rises on the lowest member lot after the shared demolition.
	if in_parcel and parcel_info[l["parcel"]]["tower_lot"] == l["id"]:
		var info: Dictionary = parcel_info[l["parcel"]]
		var t := _make_entry(rng, info["rect"], "core", 2, info["p"] + GAP, params, true)
		if t["p1"] <= LAST_TOPOUT:
			t["parcel_id"] = l["parcel"]
			entries.append(t)
	return entries

static func _make_entry(rng: RandomNumberGenerator, lot_rect: Rect2, district: String, style: int, p0: float, params: Dictionary, is_tower: bool) -> Dictionary:
	var setback := rng.randf_range(4.0, 7.0) if is_tower else rng.randf_range(1.0, 3.0)
	if district == "industrial":
		setback = 1.0
	var rect := lot_rect.grow(-setback)
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		rect = lot_rect.grow(-maxf((minf(lot_rect.size.x, lot_rect.size.y) - 8.0) * 0.5, 0.0))
	var floors := _roll_floors(rng, district, style, rect, params, is_tower)
	var dur: float = (0.010 + 0.0016 * float(floors)) / float(params["construct_speed"])
	var e := {
		"p0": p0, "p1": p0 + dur, "p_demo": INF, "style": style, "floors": floors,
		"industrial": district == "industrial", "parcel_id": -1, "rect": rect,
		"tiers": _make_tiers(rng, rect, floors, style),
		"win_w": WIN_W[style] * float(params["win_scale"]) * rng.randf_range(0.9, 1.1),
		"accent": rng.randf(), "lit_seed": rng.randf(),
	}
	return e

static func _roll_floors(rng: RandomNumberGenerator, district: String, style: int, rect: Rect2, params: Dictionary, is_tower: bool) -> int:
	var rr: Array = FLOOR_RANGES[style][district]
	var f := rng.randf_range(float(rr[0]), float(rr[1]))
	if is_tower:
		f = rng.randf_range(40.0, 60.0)
	f *= float(params["height_scale"])
	var aspect := 7.0 if style == 2 else 4.0
	var min_dim := minf(rect.size.x, rect.size.y)
	var cap := maxf(min_dim * aspect / float(params["floor_h"]), 2.0)
	return maxi(roundi(minf(f, cap)), 1)

static func _make_tiers(rng: RandomNumberGenerator, rect: Rect2, floors: int, style: int) -> Array:
	if floors < 14 or style == 0 or rng.randf() < 0.4:
		return [{"rect": rect, "floors": floors}]
	var n := 3 if (floors >= 30 and rng.randf() < 0.6) else 2
	var tiers: Array = []
	var remaining := floors
	var r := rect
	for i in n:
		var take := remaining
		if i < n - 1:
			take = maxi(roundi(float(remaining) * rng.randf_range(0.45, 0.65)), 1)
		tiers.append({"rect": r, "floors": take})
		remaining -= take
		if remaining <= 0:
			break
		r = r.grow(-minf(r.size.x, r.size.y) * rng.randf_range(0.1, 0.18))
	if remaining > 0:
		tiers[tiers.size() - 1]["floors"] = int(tiers[tiers.size() - 1]["floors"]) + remaining
	return tiers

static func _style_at(p: float, rng: RandomNumberGenerator, params: Dictionary) -> int:
	var e1: float = params["era1_end"]
	var e2: float = params["era2_end"]
	var ov: float = params["era_overlap"]
	if p < e1 - ov:
		return 0
	if p <= e1 + ov:
		return 1 if rng.randf() < (p - (e1 - ov)) / (2.0 * ov) else 0
	if p < e2 - ov:
		return 1
	if p <= e2 + ov:
		return 2 if rng.randf() < (p - (e2 - ov)) / (2.0 * ov) else 1
	return 2

static func _style_at_nominal(p: float, params: Dictionary) -> int:
	if p < float(params["era1_end"]):
		return 0
	if p < float(params["era2_end"]):
		return 1
	return 2

static func _next_band_start(style: int, params: Dictionary) -> float:
	return float(params["era1_end"]) if style == 0 else float(params["era2_end"])

static func _demo_prob(district: String, params: Dictionary) -> float:
	match district:
		"core", "commercial":
			return float(params["demolish_core"])
		"residential":
			return lerpf(float(params["demolish_edge"]), float(params["demolish_core"]), 0.5)
	return float(params["demolish_edge"])
