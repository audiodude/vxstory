extends "res://core/sim_model.gd"

const PS = preload("res://core/param_schema.gd")
const FluidSim = preload("res://fluid_sim/fluid_sim.gd")
const GRADE := preload("res://fluid_sim/grade.gdshader")

const PALETTES := {
	"classic": {"peg": Color(0.0, 0.2, 1.0), "hot": Color(1.0, 0.35, 0.0), "ball": Color(1.0, 1.0, 1.0)},
	"neon": {"peg": Color(1.0, 0.0, 0.5), "hot": Color(0.0, 1.0, 0.7), "ball": Color(0.6, 1.0, 0.0)},
	"mono": {"peg": Color(0.4, 0.4, 0.4), "hot": Color(0.9, 0.9, 0.9), "ball": Color(0.8, 0.8, 0.8)},
}

class Peg extends StaticBody2D:
	var radius := 14.0
	var color := Color.BLUE
	var lit := 0.0
	func _init(r: float, c: Color, mat: PhysicsMaterial) -> void:
		radius = r
		color = c
		physics_material_override = mat
		var shape := CollisionShape2D.new()
		var circ := CircleShape2D.new()
		circ.radius = r
		shape.shape = circ
		add_child(shape)
	func _draw() -> void:
		var c := color.lerp(Color.WHITE, lit * 0.8)
		c *= (1.0 + lit * 2.0)  # overbright when lit -> glows
		draw_circle(Vector2.ZERO, radius, c)
		draw_arc(Vector2.ZERO, radius + 2.0, 0, TAU, 32, Color(color, 0.5 + lit * 0.5), 2.0, true)
	func _process(delta: float) -> void:
		if lit > 0.0:
			lit = maxf(lit - delta * 2.0, 0.0)
			queue_redraw()

class Ball extends RigidBody2D:
	var radius := 11.0
	var color := Color.WHITE
	func _init(r: float, c: Color, mat: PhysicsMaterial) -> void:
		radius = r
		color = c
		physics_material_override = mat
		contact_monitor = true
		max_contacts_reported = 4
		var shape := CollisionShape2D.new()
		var circ := CircleShape2D.new()
		circ.radius = r
		shape.shape = circ
		add_child(shape)
	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color * 1.3)
		draw_circle(Vector2.ZERO, radius * 0.4, Color.WHITE * 1.2)

var peg_defs: Array = []      # {pos, hot, parent_idx(-1 or spinner), node(Peg|null), dead_at}
var spinners: Array = []      # {node, speed}
var balls: Array = []
var fx_pool: Array[GPUParticles2D] = []
var fx_i := 0
var boom_pool: Array[GPUParticles2D] = []
var boom_i := 0
var recent_hits: Array = []   # {pos, time}
var phys_mat: PhysicsMaterial
var pal: Dictionary
var sim_t := 0.0
var fire_acc := 0.0
var respawn_acc := 0.0
var s: RandomNumberGenerator

var fluid: Node2D
var fluid_display: TextureRect

func model_name() -> String:
	return "chromatic_cascade"

func get_schema() -> Dictionary:
	return {
		"macros": [
			PS.macro_def("complexity", 0.5), PS.macro_def("ball_rate", 0.5),
			PS.macro_def("ink", 0.5), PS.macro_def("shockwave", 0.7),
		],
		"params": [
			PS.e("layout", "mixed", PackedStringArray(["rings", "grid", "spinners", "mixed"]), {"live": false}),
			PS.i("peg_count", 110, 20, 240, {"live": false, "macro": {"name": "complexity", "lo": 40, "hi": 200}}),
			PS.f("peg_radius", 14.0, 8.0, 26.0, {"live": false}),
			PS.i("spinner_count", 2, 0, 4, {"live": false, "macro": {"name": "complexity", "lo": 0, "hi": 4}}),
			PS.f("spinner_speed", 1.0, 0.2, 3.0, {"live": false, "jitter": {"pct": 25.0}}),
			PS.f("fire_interval", 0.45, 0.1, 2.0, {"macro": {"name": "ball_rate", "lo": 1.2, "hi": 0.12}}),
			PS.f("ball_speed", 900.0, 400.0, 1600.0),
			PS.f("ball_radius", 11.0, 6.0, 18.0, {"live": false}),
			PS.f("bounce", 0.8, 0.3, 1.0, {"live": false}),
			PS.f("sweep_range", 0.7, 0.0, 1.2),
			PS.f("sweep_speed", 0.8, 0.1, 3.0),
			PS.i("chain_trigger", 4, 2, 8),
			PS.f("chain_radius", 180.0, 60.0, 400.0, {"macro": {"name": "shockwave", "lo": 100.0, "hi": 320.0}}),
			PS.f("blast_impulse", 600.0, 0.0, 1500.0, {"macro": {"name": "shockwave", "lo": 100.0, "hi": 1200.0}}),
			PS.f("respawn_period", 8.0, 2.0, 20.0),
			PS.i("max_balls", 28, 4, 80),
			PS.f("hot_fraction", 0.2, 0.0, 1.0, {"live": false}),
			PS.f("glow", 0.8, 0.0, 3.0),
			PS.e("palette", "classic", PackedStringArray(["classic", "neon", "mono"]), {"live": false}),
			PS.f("ink_radius", 70.0, 20.0, 200.0, {"macro": {"name": "ink", "lo": 25.0, "hi": 100.0}}),
			PS.f("ink_strength", 0.8, 0.1, 2.0, {"macro": {"name": "ink", "lo": 0.5, "hi": 1.5}}),
			PS.f("wake_strength", 0.0, 0.0, 0.4),
			PS.f("fluid_dissipation", 0.992, 0.9, 0.999),
			PS.f("fluid_noise", 0.8, 0.0, 2.5),
			PS.f("fluid_flow", 1.2, 0.2, 3.0),
			PS.f("shock_power", 0.6, 0.0, 2.0, {"macro": {"name": "shockwave", "lo": 0.15, "hi": 1.5}}),
		],
	}

var env: Environment

func restart() -> void:
	for c in get_children():
		if not (c is CanvasLayer):
			c.queue_free()
	peg_defs.clear()
	spinners.clear()
	balls.clear()
	fx_pool.clear()
	boom_pool.clear()
	recent_hits.clear()
	sim_t = 0.0
	fire_acc = 0.0
	respawn_acc = 0.0
	fx_i = 0
	boom_i = 0
	s = rng.stream("sim")
	pal = PALETTES[params["palette"]]
	phys_mat = PhysicsMaterial.new()
	phys_mat.bounce = params["bounce"]
	phys_mat.friction = 0.15
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = params["glow"]
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)
	fluid = FluidSim.new()
	add_child(fluid)
	fluid.setup(rng.stream("vortices"), 960, 540, {
		"dissipation": params["fluid_dissipation"], "noise_strength": params["fluid_noise"],
		"flow_speed": params["fluid_flow"], "noise_scale": 2.5,
		"vortex_count": 3, "vortex_strength": 0.5,
	})
	fluid_display = TextureRect.new()
	fluid_display.size = Vector2(1920, 1080)
	fluid_display.stretch_mode = TextureRect.STRETCH_SCALE
	var gmat := ShaderMaterial.new()
	gmat.shader = GRADE
	gmat.set_shader_parameter("saturation", 1.4)
	gmat.set_shader_parameter("contrast", 1.1)
	fluid_display.material = gmat
	add_child(fluid_display)
	_gen_layout()
	for d in peg_defs:
		_spawn_peg(d)
	for i in 16:
		fx_pool.append(_make_pop(140, 12))
	for i in 6:
		boom_pool.append(_make_pop(420, 60))

func _gen_layout() -> void:
	var kind: String = params["layout"]
	var budget: int = params["peg_count"]
	var defs: Array = []
	if kind == "rings" or kind == "mixed":
		var n_rings := 3 if kind == "rings" else 2
		for ri in n_rings:
			var rad := 160.0 + 130.0 * ri
			var cnt := int(10 + 8 * ri)
			for i in cnt:
				var ang := TAU * i / cnt + ri * 0.3
				defs.append({"pos": Vector2(960, 620) + Vector2.from_angle(ang) * rad, "parent_idx": -1})
	if kind == "grid" or kind == "mixed":
		var rows := 6 if kind == "grid" else 3
		for r in rows:
			var cols := 12
			for cidx in cols:
				var off := 60.0 if r % 2 == 1 else 0.0
				var pos := Vector2(240 + cidx * 124 + off, (340 if kind == "grid" else 220) + r * 110)
				if kind == "mixed" and pos.distance_to(Vector2(960, 620)) < 460.0:
					continue
				defs.append({"pos": pos, "parent_idx": -1})
	if kind == "spinners" or kind == "mixed":
		for si in int(params["spinner_count"]):
			var hub := Vector2(s.randf_range(360, 1560), s.randf_range(380, 880))
			var node := Node2D.new()
			node.position = hub
			add_child(node)
			spinners.append({"node": node, "speed": params["spinner_speed"] * (1.0 if si % 2 == 0 else -1.0)})
			for arm in 6:
				for k in 2:
					var local := Vector2.from_angle(TAU * arm / 6.0) * (70.0 + 70.0 * k)
					defs.append({"pos": local, "parent_idx": spinners.size() - 1})
	# top up with scatter if under budget, trim if over (seeded shuffle)
	while defs.size() < budget:
		defs.append({"pos": Vector2(s.randf_range(160, 1760), s.randf_range(300, 980)), "parent_idx": -1})
	while defs.size() > budget:
		defs.remove_at(s.randi() % defs.size())
	for d in defs:
		d["hot"] = s.randf() < params["hot_fraction"]
		d["node"] = null
		d["dead_at"] = -1.0
		peg_defs.append(d)

func _spawn_peg(d: Dictionary) -> void:
	var peg := Peg.new(params["peg_radius"], pal["hot"] if d["hot"] else pal["peg"], phys_mat)
	peg.position = d["pos"]
	peg.add_to_group("pegs")
	peg.lit = 1.0  # spawn flash
	if d["parent_idx"] >= 0:
		spinners[d["parent_idx"]]["node"].add_child(peg)
	else:
		add_child(peg)
	d["node"] = peg
	d["dead_at"] = -1.0

func _make_pop(speed: float, amount: int) -> GPUParticles2D:
	var g := GPUParticles2D.new()
	g.amount = amount
	g.one_shot = true
	g.explosiveness = 1.0
	g.emitting = false
	g.lifetime = 0.7
	if "use_fixed_seed" in g:
		g.use_fixed_seed = true
		g.seed = s.randi()
	var cmat := CanvasItemMaterial.new()
	cmat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	g.material = cmat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, 600, 0)
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.scale_min = 2.0
	pm.scale_max = 5.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 0.8) * 0.9)
	grad.set_color(1, Color(1, 0.4, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	g.process_material = pm
	add_child(g)
	return g

func _fire_fx(pool: Array[GPUParticles2D], idx_ref: String, pos: Vector2) -> void:
	var i: int = fx_i if idx_ref == "fx" else boom_i
	var g := pool[i % pool.size()]
	g.position = pos
	g.restart()
	if idx_ref == "fx":
		fx_i += 1
	else:
		boom_i += 1

func _spawn_ball() -> void:
	var ball := Ball.new(params["ball_radius"], pal["ball"], phys_mat)
	ball.position = Vector2(960, 60)
	var ang: float = PI / 2.0 + sin(sim_t * params["sweep_speed"] * TAU * 0.25) * params["sweep_range"]
	ball.linear_velocity = Vector2.from_angle(ang) * params["ball_speed"]
	ball.body_entered.connect(_on_ball_contact.bind(ball))
	add_child(ball)
	balls.append(ball)

func _on_ball_contact(other: Node, ball: Ball) -> void:
	if not is_instance_valid(ball) or not other.is_in_group("pegs"):
		return
	var peg := other as Peg
	if peg.lit > 0.6:
		return  # debounce rapid re-hits
	peg.lit = 1.0
	var gpos := peg.global_position
	_fire_fx(fx_pool, "fx", gpos)
	emit_event("hit")
	fluid.inject_dye(gpos, peg.color, params["ink_radius"], params["ink_strength"])
	recent_hits.append({"pos": gpos, "time": sim_t})
	_check_chain(gpos)

func _check_chain(at: Vector2) -> void:
	var cluster: Array = []
	for h in recent_hits:
		if sim_t - h["time"] < 1.0 and h["pos"].distance_to(at) < params["chain_radius"]:
			cluster.append(h)
	if cluster.size() < int(params["chain_trigger"]):
		return
	recent_hits.clear()
	_fire_fx(boom_pool, "boom", at)
	emit_event("shockwave")
	for d in peg_defs:
		if d["node"] != null and is_instance_valid(d["node"]):
			if (d["node"].global_position as Vector2).distance_to(at) < params["chain_radius"]:
				_fire_fx(fx_pool, "fx", d["node"].global_position)
				d["node"].queue_free()
				d["node"] = null
				d["dead_at"] = sim_t
	for b in balls:
		if is_instance_valid(b):
			var dvec: Vector2 = b.global_position - at
			var dist := maxf(dvec.length(), 40.0)
			if dist < params["chain_radius"] * 2.0:
				b.apply_central_impulse(dvec / dist * params["blast_impulse"])
	on_chain_blast(at)

func on_chain_blast(at: Vector2) -> void:
	fluid.add_impulse(at, params["shock_power"])
	fluid.inject_dye(at, Color(1.0, 0.85, 0.5), params["ink_radius"] * 1.3, params["ink_strength"] * 0.5)

func _process(delta: float) -> void:
	super._process(delta)
	if s == null:
		return
	sim_t += delta
	for sp in spinners:
		sp["node"].rotation += sp["speed"] * delta
	for bi in mini(balls.size(), 10):
		var b = balls[bi]
		if is_instance_valid(b):
			var wake_col: Color = (pal["peg"] as Color).lerp(pal["hot"] as Color, 0.5).darkened(0.3)
			fluid.inject_dye(b.position, wake_col, 24.0, params["wake_strength"])
	fluid.step(delta)
	fluid_display.texture = fluid.output_texture()
	fire_acc += delta
	balls = balls.filter(func(b): return is_instance_valid(b))
	if fire_acc >= params["fire_interval"]:
		fire_acc = 0.0
		if balls.size() < int(params["max_balls"]):
			_spawn_ball()
	for b in balls:
		if b.position.y > 1240 or b.position.x < -120 or b.position.x > 2040:
			b.queue_free()
	respawn_acc += delta
	if respawn_acc >= params["respawn_period"]:
		respawn_acc = 0.0
		for d in peg_defs:
			if d["node"] == null:
				_spawn_peg(d)
	recent_hits = recent_hits.filter(func(h): return sim_t - h["time"] < 1.5)

func apply_live(p: Dictionary) -> void:
	if env != null:
		env.glow_intensity = p["glow"]
	if phys_mat != null:
		phys_mat.bounce = p["bounce"]
	if fluid != null:
		fluid.set_opts({"dissipation": p["fluid_dissipation"], "noise_strength": p["fluid_noise"], "flow_speed": p["fluid_flow"]})
