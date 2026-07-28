extends RefCounted
# Pure day-cycle curves: day_phase (0..1, dawn->night) to sun/moon/sky/fog
# state. One sun arc per run — dawn at ~0.04, dusk at ~0.86, night after.
# Palettes grade sun color, sky and interior warmth (applied by the caller).

const DAWN := 0.04
const DUSK := 0.86
const PEAK_ELEV := 62.0

const PALETTES := {
	"daybreak": {
		"sun_low": Color(1.0, 0.62, 0.32), "sun_high": Color(1.0, 0.96, 0.9),
		"day_top": Color(0.22, 0.45, 0.82), "day_hor": Color(0.72, 0.82, 0.92),
		"warm_hor": Color(1.0, 0.55, 0.3),
		"night_top": Color(0.012, 0.018, 0.045), "night_hor": Color(0.05, 0.07, 0.13),
		"interior_warm": Color(1.0, 0.82, 0.55), "interior_cool": Color(0.75, 0.85, 1.0),
	},
	"sodium": {
		"sun_low": Color(1.0, 0.52, 0.18), "sun_high": Color(1.0, 0.9, 0.78),
		"day_top": Color(0.3, 0.42, 0.62), "day_hor": Color(0.82, 0.78, 0.7),
		"warm_hor": Color(1.0, 0.5, 0.2),
		"night_top": Color(0.02, 0.015, 0.04), "night_hor": Color(0.12, 0.08, 0.06),
		"interior_warm": Color(1.0, 0.72, 0.35), "interior_cool": Color(1.0, 0.85, 0.6),
	},
	"overcast": {
		"sun_low": Color(0.85, 0.72, 0.62), "sun_high": Color(0.85, 0.88, 0.92),
		"day_top": Color(0.45, 0.52, 0.6), "day_hor": Color(0.7, 0.74, 0.78),
		"warm_hor": Color(0.85, 0.68, 0.55),
		"night_top": Color(0.015, 0.02, 0.035), "night_hor": Color(0.06, 0.07, 0.1),
		"interior_warm": Color(0.95, 0.85, 0.65), "interior_cool": Color(0.7, 0.82, 0.95),
	},
}

static func eval(day: float, palette: String, params: Dictionary) -> Dictionary:
	day = clampf(day, 0.0, 1.0)
	var pal: Dictionary = PALETTES.get(palette, PALETTES["daybreak"])

	var elev := 0.0
	if day >= DAWN and day <= DUSK:
		elev = sin(PI * (day - DAWN) / (DUSK - DAWN)) * PEAK_ELEV
	else:
		var span := 1.0 - DUSK + DAWN
		var u := (day - DUSK) / span if day > DUSK else (day + 1.0 - DUSK) / span
		elev = -sin(PI * u) * 14.0
	var azim := lerpf(60.0, 285.0, day)

	var night := 1.0 - smoothstep(-8.0, 6.0, elev)
	var hump := exp(-pow(elev - 8.0, 2.0) / 120.0) * (1.0 - night)

	var er := deg_to_rad(elev)
	var ar := deg_to_rad(azim)
	var sun_pos := Vector3(cos(er) * cos(ar), sin(er), cos(er) * sin(ar))

	var sun_energy := smoothstep(-2.0, 10.0, elev) * (0.7 + 0.9 * clampf(elev / PEAK_ELEV, 0.0, 1.0))
	var sun_color: Color = pal["sun_low"].lerp(pal["sun_high"], clampf(elev / 35.0, 0.0, 1.0))

	var fog: float = float(params.get("fog_amount", 0.35)) \
			* (0.0008 + 0.0012 * hump + 0.0004 * night)

	return {
		"sun_dir": -sun_pos,               # direction light travels (scene-ward)
		"elev_deg": elev, "azim_deg": azim,
		"sun_energy": sun_energy, "sun_color": sun_color,
		"moon_energy": 0.2 * night * night,
		"night": night,
		"ambient_energy": lerpf(1.0, 0.32, night),
		"fog_density": fog,
		"star_alpha": clampf((night - 0.6) / 0.4, 0.0, 1.0),
		"sky_top": (pal["day_top"] as Color).lerp(pal["night_top"], night),
		"sky_horizon": ((pal["day_hor"] as Color).lerp(pal["warm_hor"], hump)).lerp(pal["night_hor"], night),
		"interior_warm": pal["interior_warm"], "interior_cool": pal["interior_cool"],
	}
