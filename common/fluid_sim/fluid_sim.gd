extends Node2D
# Reusable ping-pong dye-advection sim (see spec: common/fluid_sim).
# Owner calls setup() once, step(delta) every frame, then displays
# output_texture() however it likes. inject_dye/add_impulse queue effects.

const MAX_SPLATS := 16
const MAX_IMPULSES := 8
const MAX_VORTICES := 8
const SHADER := preload("res://fluid_sim/advect.gdshader")

var vps: Array[SubViewport] = []
var mats: Array[ShaderMaterial] = []
var cur := 0  # index of vp holding the LATEST frame
var sim_size := Vector2i(960, 540)
var screen_size := Vector2(1920, 1080)
var t := 0.0
var opts := {}
var _splats: Array = []
var _impulses: Array = []   # {uv: Vector2, power: float, age: float}
var _vortices: Array = []   # {base: Vector2, amp: Vector2, spd: Vector2, ph: Vector2, strength, radius}

func setup(vrng: RandomNumberGenerator, w: int, h: int, p_opts: Dictionary) -> void:
	sim_size = Vector2i(w, h)
	screen_size = p_opts.get("screen_size", Vector2(1920, 1080))
	opts = p_opts
	# Black 1x1 placeholder so prev_tex is never uninitialized (avoids gray from default white sampler)
	var black_img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	black_img.fill(Color.BLACK)
	var black_tex := ImageTexture.create_from_image(black_img)
	for i in 2:
		var vp := SubViewport.new()
		vp.size = sim_size
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE  # render once to init (dissipation=0 → pure black)
		var rect := ColorRect.new()
		rect.size = Vector2(sim_size)
		rect.color = Color.BLACK
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("prev_tex", black_tex)
		mat.set_shader_parameter("dissipation", 0.0)  # on init frame output pure black
		rect.material = mat
		vp.add_child(rect)
		add_child(vp)
		vps.append(vp)
		mats.append(mat)
	var n: int = mini(int(p_opts.get("vortex_count", 5)), MAX_VORTICES)
	var aspect := Vector2(float(sim_size.x) / float(sim_size.y), 1.0)
	for mat in mats:
		mat.set_shader_parameter("aspect", aspect)
	for i in n:
		_vortices.append({
			"base": Vector2(vrng.randf_range(0.2, 0.8), vrng.randf_range(0.2, 0.8)),
			"amp": Vector2(vrng.randf_range(0.05, 0.25), vrng.randf_range(0.05, 0.25)),
			"spd": Vector2(vrng.randf_range(0.05, 0.3), vrng.randf_range(0.05, 0.3)),
			"ph": Vector2(vrng.randf_range(0.0, TAU), vrng.randf_range(0.0, TAU)),
			"strength": vrng.randf_range(0.3, 1.0) * (1.0 if vrng.randf() < 0.5 else -1.0),
			"radius": vrng.randf_range(0.1, 0.3),
		})

func set_opts(p_opts: Dictionary) -> void:
	opts.merge(p_opts, true)

func inject_dye(pos_px: Vector2, color: Color, radius_px: float, strength: float) -> void:
	if _splats.size() < MAX_SPLATS:
		_splats.append({"uv": pos_px / screen_size, "r": radius_px / screen_size.x, "color": color, "s": strength})

func add_impulse(pos_px: Vector2, power: float) -> void:
	if _impulses.size() < MAX_IMPULSES:
		_impulses.append({"uv": pos_px / screen_size, "power": power, "age": 0.0})

func output_texture() -> Texture2D:
	return vps[cur].get_texture()

func step(delta: float) -> void:
	t += delta
	var nxt := 1 - cur
	var mat := mats[nxt]
	mat.set_shader_parameter("prev_tex", vps[cur].get_texture())
	mat.set_shader_parameter("dt", delta)
	mat.set_shader_parameter("t", t)
	mat.set_shader_parameter("dissipation", opts.get("dissipation", 0.985))
	mat.set_shader_parameter("flow_speed", opts.get("flow_speed", 1.5))
	mat.set_shader_parameter("noise_scale", opts.get("noise_scale", 3.0))
	mat.set_shader_parameter("noise_strength", opts.get("noise_strength", 1.2))
	var vort := PackedVector4Array()
	for v in _vortices:
		var p: Vector2 = v["base"] + Vector2(sin(t * v["spd"].x + v["ph"].x) * v["amp"].x, cos(t * v["spd"].y + v["ph"].y) * v["amp"].y)
		vort.append(Vector4(p.x, p.y, v["strength"] * opts.get("vortex_strength", 0.8) * 0.1, v["radius"]))
	mat.set_shader_parameter("vortex_count", vort.size())
	mat.set_shader_parameter("vortices", _pad4(vort, MAX_VORTICES))
	var spos := PackedVector4Array()
	var scol := PackedVector4Array()
	for sp in _splats:
		spos.append(Vector4(sp["uv"].x, sp["uv"].y, sp["r"], sp["s"]))
		scol.append(Vector4(sp["color"].r, sp["color"].g, sp["color"].b, 1.0))
	mat.set_shader_parameter("splat_count", spos.size())
	mat.set_shader_parameter("splat_pos_r", _pad4(spos, MAX_SPLATS))
	mat.set_shader_parameter("splat_color", _pad4(scol, MAX_SPLATS))
	var imp := PackedVector4Array()
	for im in _impulses:
		im["age"] += delta
		imp.append(Vector4(im["uv"].x, im["uv"].y, im["power"], im["age"]))
	mat.set_shader_parameter("impulse_count", imp.size())
	mat.set_shader_parameter("impulses", _pad4(imp, MAX_IMPULSES))
	_impulses = _impulses.filter(func(im): return im["age"] < 2.0)
	_splats.clear()
	vps[nxt].render_target_update_mode = SubViewport.UPDATE_ONCE
	cur = nxt

func _pad4(arr: PackedVector4Array, n: int) -> PackedVector4Array:
	var out := arr.duplicate()
	while out.size() < n:
		out.append(Vector4.ZERO)
	return out
