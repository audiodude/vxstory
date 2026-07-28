extends RefCounted
# Closed-form orbit + pull-back camera: azimuth advances with the sim clock,
# radius/height/look-target grow with development P so the skyline always
# just-fills the frame. Pure function of (t, P, params) — scrub-exact.

static func eval(t: float, P: float, params: Dictionary) -> Dictionary:
	var s := smoothstep(0.0, 1.0, clampf(P, 0.0, 1.0))
	var radius: float = float(params.get("cam_pull", 1.0)) * lerpf(250.0, 900.0, s)
	var height: float = float(params.get("cam_height", 1.0)) * lerpf(120.0, 450.0, s)
	var az := deg_to_rad(float(params.get("orbit_deg0", 20.0)) + float(params.get("orbit_rate", 1.3)) * t)
	return {
		"pos": Vector3(cos(az) * radius, height, sin(az) * radius),
		"look": Vector3(0.0, lerpf(6.0, 90.0, s), 0.0),
		"fov": float(params.get("cam_fov", 40.0)),
	}
