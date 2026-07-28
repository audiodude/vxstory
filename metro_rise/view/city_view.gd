extends Node3D
# CityView: owns every MultiMesh pool and keeps them in sync with a
# StateTracker via sparse diffs. Static geometry (roads, sidewalks, trees,
# lamps, ground) is written once in setup(); dynamic pools (buildings, roof
# clutter, dirt patches) are written only for changed slots. Cars/cranes live
# in their own modules.

const FacadeShader := preload("res://view/facade.gdshader")
const RoadShader := preload("res://view/road.gdshader")
const GroundShader := preload("res://view/ground.gdshader")
const TreeShader := preload("res://view/tree.gdshader")
const LampShader := preload("res://view/lamp.gdshader")
const CarShader := preload("res://view/car.gdshader")

const CAR_CAP := 2048

var buildings: MultiMesh
var roofs: MultiMesh
var dirt: MultiMesh
var roads_mm: MultiMesh
var trees_mm: MultiMesh
var lamps_mm: MultiMesh
var cars_mm: MultiMesh
var facade_mat: ShaderMaterial
var road_mat: ShaderMaterial
var tree_mat: ShaderMaterial
var lamp_mat: ShaderMaterial
var car_mat: ShaderMaterial
var _last_car_count := 0

var _plan: Dictionary
var _params: Dictionary
var _zero := Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -50, 0))

func setup(plan: Dictionary, params: Dictionary, slot_count: int) -> void:
	_plan = plan
	_params = params

	facade_mat = ShaderMaterial.new()
	facade_mat.shader = FacadeShader
	facade_mat.set_shader_parameter("floor_h", params["floor_h"])
	buildings = _pool(BoxMesh.new(), facade_mat, slot_count, true, true)

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.3, 0.29, 0.27)
	roof_mat.roughness = 0.9
	roof_mat.metallic_specular = 0.05
	roofs = _pool(BoxMesh.new(), roof_mat, slot_count * 2, false, false)

	var dirt_mat := StandardMaterial3D.new()
	dirt_mat.albedo_color = Color(0.22, 0.17, 0.12)
	dirt_mat.roughness = 1.0
	dirt_mat.metallic_specular = 0.03
	dirt = _pool(BoxMesh.new(), dirt_mat, slot_count, false, false)

	road_mat = ShaderMaterial.new()
	road_mat.shader = RoadShader
	var segs: Array = plan["roads"]["segments"]
	roads_mm = _pool(BoxMesh.new(), road_mat, segs.size() * 3 + plan["roads"]["nodes"].size(), false, true)
	_write_roads(segs)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	ground.mesh = pm
	var gmat := ShaderMaterial.new()
	gmat.shader = GroundShader
	ground.material_override = gmat
	ground.position.y = -0.02
	add_child(ground)

	tree_mat = ShaderMaterial.new()
	tree_mat.shader = TreeShader
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 7
	trees_mm = _pool(cone, tree_mat, plan["trees"].size(), false, true)
	_write_trees(plan["trees"])

	lamp_mat = ShaderMaterial.new()
	lamp_mat.shader = LampShader
	var pole := CylinderMesh.new()
	pole.top_radius = 0.34
	pole.bottom_radius = 0.16
	pole.height = 1.0
	pole.radial_segments = 5
	lamps_mm = _pool(pole, lamp_mat, plan["lamps"].size(), false, true)
	_write_lamps(plan["lamps"])

	car_mat = ShaderMaterial.new()
	car_mat.shader = CarShader
	cars_mm = _pool(BoxMesh.new(), car_mat, CAR_CAP, true, true)

	_setup_dust()

func _pool(mesh: Mesh, mat: Material, count: int, colors: bool, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = count
	if mesh is PrimitiveMesh:
		mesh.material = mat
	for i in count:
		mm.set_instance_transform(i, _zero)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mm

func _write_roads(segs: Array) -> void:
	# One square pad per intersection; road boxes butt INTO the pads instead of
	# extending across the node. Collinear neighbors used to overlap co-planar
	# in the node square and z-fight (visible as flicker at every intersection,
	# paved or dirt). Pads sit above road tops, roads tuck 1 m under their rim.
	var ring_div := 6.0
	var nodes: Array = _plan["roads"]["nodes"]
	var pad_w := PackedFloat32Array()
	pad_w.resize(nodes.size())
	for n in nodes:
		var w := 0.0
		for sid in n["segs"]:
			w = maxf(w, float(segs[sid]["width"]))
		pad_w[n["id"]] = w + 2.0
	var pad_base := segs.size() * 3
	for n in nodes:
		var pw: float = pad_w[n["id"]]
		var nring: float = (float(n["ring"]) + 0.2) / ring_div
		roads_mm.set_instance_transform(pad_base + n["id"], Transform3D(
				Basis().scaled(Vector3(pw, 0.06, pw)),
				Vector3(n["pos"].x, 0.07, n["pos"].y)))
		roads_mm.set_instance_custom_data(pad_base + n["id"], Color(3.0, nring, pw, 0.0))
	for i in segs.size():
		var s: Dictionary = segs[i]
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var dir := (b - a).normalized()
		var seg_len := a.distance_to(b)
		var ang := (b - a).angle()
		var kind := 1.0 if s["kind"] == "blvd" else 0.0
		var ring_frac: float = (float(s["ring"]) + 0.2) / ring_div
		var basis := Basis(Vector3.UP, -ang)
		var start: float = pad_w[s["na"]] * 0.5 - 1.0
		var endd: float = seg_len - pad_w[s["nb"]] * 0.5 + 1.0
		var box_len := maxf(endd - start, 2.0)
		var mid: Vector2 = a + dir * ((start + endd) * 0.5)
		# Orientation height stagger (crossing diagonals vs grid roads).
		var road_y := 0.036
		if s["diag"]:
			road_y = 0.052
		elif absf(b.x - a.x) > absf(b.y - a.y):
			road_y = 0.044
		roads_mm.set_instance_transform(i * 3, Transform3D(
				basis * Basis().scaled(Vector3(box_len, 0.07, float(s["width"]))),
				Vector3(mid.x, road_y, mid.y)))
		roads_mm.set_instance_custom_data(i * 3, Color(kind, ring_frac, box_len, 0.0))
		if not s["diag"]:
			var wmid := (a + b) * 0.5
			var side := Vector2(-sin(ang), cos(ang))
			var walk_y := 0.028 if absf(b.x - a.x) > absf(b.y - a.y) else 0.024
			for k in 2:
				var flip := 1.0 if k == 0 else -1.0
				var off := side * (float(s["width"]) * 0.5 + 1.5) * flip
				roads_mm.set_instance_transform(i * 3 + 1 + k, Transform3D(
						basis * Basis().scaled(Vector3(seg_len, 0.05, 3.0)),
						Vector3(wmid.x + off.x, walk_y, wmid.y + off.y)))
				roads_mm.set_instance_custom_data(i * 3 + 1 + k, Color(2.0, ring_frac, seg_len, 0.0))

func _write_trees(trees: Array) -> void:
	for i in trees.size():
		var t: Dictionary = trees[i]
		var sc: float = t["scale"]
		var h := 9.0 * sc
		var ring_frac: float = (float(t["ring"]) + 0.3) / 6.0
		trees_mm.set_instance_transform(i, Transform3D(
				Basis().scaled(Vector3(3.1 * sc, h, 3.1 * sc)),
				Vector3(t["pos"].x, h * 0.5 + 0.3, t["pos"].y)))
		var hue_var := fmod(float(t["pos"].x * 12.9898 + t["pos"].y * 78.233), 1.0)
		trees_mm.set_instance_custom_data(i, Color(ring_frac, absf(hue_var), absf(fmod(hue_var * 7.13, 1.0)), 0.0))

func _write_lamps(lamps: Array) -> void:
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		var ring_frac: float = (float(l["ring"]) + 0.25) / 6.0
		lamps_mm.set_instance_transform(i, Transform3D(
				Basis().scaled(Vector3(1.0, 7.5, 1.0)),
				Vector3(l["pos"].x, 3.75, l["pos"].y)))
		lamps_mm.set_instance_custom_data(i, Color(ring_frac, fmod(absf(l["pos"].x + l["pos"].y), 1.0), 0.0, 0.0))

var _dust: Array = []
var _dust_next := 0

func _setup_dust() -> void:
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = 6.0
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 65.0
	pmat.initial_velocity_min = 5.0
	pmat.initial_velocity_max = 13.0
	pmat.gravity = Vector3(0, -4.0, 0)
	pmat.scale_min = 2.0
	pmat.scale_max = 4.5
	var grad := Gradient.new()
	grad.set_color(0, Color(0.5, 0.46, 0.4, 0.8))
	grad.set_color(1, Color(0.45, 0.42, 0.38, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pmat.color_ramp = gt
	var quad := QuadMesh.new()
	quad.size = Vector2(3.0, 3.0)
	var qmat := StandardMaterial3D.new()
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.vertex_color_use_as_albedo = true
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = qmat
	for i in 6:
		var gp := GPUParticles3D.new()
		gp.process_material = pmat
		gp.draw_pass_1 = quad
		gp.one_shot = true
		gp.emitting = false
		gp.amount = 48
		gp.lifetime = 1.6
		gp.explosiveness = 0.92
		gp.set("use_fixed_seed", true)
		add_child(gp)
		_dust.append(gp)

func on_event(e: Dictionary) -> void:
	if e["kind"] != "demolish" or _dust.is_empty():
		return
	var gp: GPUParticles3D = _dust[_dust_next]
	_dust_next = (_dust_next + 1) % _dust.size()
	var pos: Vector2 = e["pos"]
	gp.position = Vector3(pos.x, 7.0, pos.y)
	gp.set("seed", hash(str(e["lot"])))
	gp.restart()

func update_cars(car_list: Array) -> void:
	var n := mini(car_list.size(), CAR_CAP)
	for i in n:
		var c: Dictionary = car_list[i]
		var p: Vector2 = c["pos"]
		var basis := Basis(Vector3.UP, -float(c["ang"])) * Basis().scaled(Vector3(4.4, 1.5, 1.9))
		cars_mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, 0.83, p.y)))
		var body := Color.from_hsv(c["hue"], 0.55 if c["hue"] < 0.7 else 0.05, 0.35 + 0.45 * fmod(c["hue"] * 7.31, 1.0)).srgb_to_linear()
		cars_mm.set_instance_color(i, body)
		cars_mm.set_instance_custom_data(i, Color(1.0 if c["stopped"] else 0.0, 0.0, 0.0, 0.0))
	for i in range(n, _last_car_count):
		cars_mm.set_instance_transform(i, _zero)
	_last_car_count = n

func apply_slots(tracker, changed: Array) -> void:
	for i in changed:
		var s: Dictionary = tracker.slot(i)
		if not s["active"]:
			buildings.set_instance_transform(i, _zero)
			roofs.set_instance_transform(i * 2, _zero)
			roofs.set_instance_transform(i * 2 + 1, _zero)
			dirt.set_instance_transform(i, _zero)
			continue
		var rect: Rect2 = s["rect"]
		var vis_h: float = maxf(float(s["h"]) * float(s["progress"]), 0.4)
		var sink: float = float(s["demo"]) * (float(s["total_h"]) + 2.0)
		var base_y: float = float(s["y0"]) - sink
		var c := rect.get_center()
		buildings.set_instance_transform(i, Transform3D(
				Basis().scaled(Vector3(rect.size.x, vis_h, rect.size.y)),
				Vector3(c.x, base_y + vis_h * 0.5, c.y)))
		buildings.set_instance_custom_data(i, Color(float(s["style"]), s["win_w"], s["lit_seed"], s["progress"]))
		buildings.set_instance_color(i, _tint(s))
		_apply_clutter(i, s, base_y + vis_h)
		if s["bottom_tier"] and s["ep"] < 0.999 and s["demo"] == 0.0:
			var er: Rect2 = s["entry_rect"].grow(2.5)
			var ec := er.get_center()
			dirt.set_instance_transform(i, Transform3D(
					Basis().scaled(Vector3(er.size.x, 0.06, er.size.y)),
					Vector3(ec.x, 0.03, ec.y)))
		else:
			dirt.set_instance_transform(i, _zero)

func _apply_clutter(i: int, s: Dictionary, top_y: float) -> void:
	var done: bool = s["progress"] >= 0.999 and s["demo"] == 0.0
	if not done or s["h"] < 6.0:
		roofs.set_instance_transform(i * 2, _zero)
		roofs.set_instance_transform(i * 2 + 1, _zero)
		return
	var rect: Rect2 = s["rect"]
	var c := rect.get_center()
	var h1 := fmod(float(s["lit_seed"]) * 17.77, 1.0)
	var h2 := fmod(float(s["accent"]) * 23.13, 1.0)
	# AC box, always.
	var bw := clampf(rect.size.x * 0.16, 1.5, 5.0)
	roofs.set_instance_transform(i * 2, Transform3D(
			Basis().scaled(Vector3(bw, 1.6, bw * 0.8)),
			Vector3(c.x + (h1 - 0.5) * rect.size.x * 0.4, top_y + 0.8, c.y + (h2 - 0.5) * rect.size.y * 0.4)))
	# Water tower (older styles, mid-rise) or antenna (glass, tall).
	if int(s["style"]) <= 1 and int(s["floors"]) >= 5 and h1 < 0.45:
		roofs.set_instance_transform(i * 2 + 1, Transform3D(
				Basis().scaled(Vector3(2.6, 3.4, 2.6)),
				Vector3(c.x - (h2 - 0.5) * rect.size.x * 0.35, top_y + 1.7, c.y + (h1 - 0.5) * rect.size.y * 0.35)))
	elif int(s["style"]) == 2 and int(s["floors"]) >= 25 and h2 < 0.5:
		roofs.set_instance_transform(i * 2 + 1, Transform3D(
				Basis().scaled(Vector3(0.5, minf(float(s["floors"]) * 0.35, 16.0), 0.5)),
				Vector3(c.x, top_y + minf(float(s["floors"]) * 0.35, 16.0) * 0.5, c.y)))
	else:
		roofs.set_instance_transform(i * 2 + 1, _zero)

func _tint(s: Dictionary) -> Color:
	var a: float = s["accent"]
	var l: float = s["lit_seed"]
	var c: Color
	match int(s["style"]):
		0:
			c = Color.from_hsv(0.02 + 0.05 * a, 0.42 + 0.2 * l, 0.42 + 0.2 * a)
		1:
			c = Color.from_hsv(0.08 + 0.06 * a, 0.06 + 0.08 * l, 0.5 + 0.22 * a)
		_:
			c = Color.from_hsv(0.5 + 0.12 * a, 0.18 + 0.15 * l, 0.45 + 0.22 * a)
	if s["industrial"]:
		c = c.darkened(0.25)
	c = c.srgb_to_linear()   # instance colors reach the shader linearly
	c.a = a
	return c

func set_globals(sun_out: Dictionary, live: Dictionary, sim_t: float) -> void:
	var night: float = sun_out["night"]
	facade_mat.set_shader_parameter("night", night)
	facade_mat.set_shader_parameter("lit_fraction", live["lit_fraction"])
	facade_mat.set_shader_parameter("neon", live["neon_amount"])
	facade_mat.set_shader_parameter("hue_shift", live["hue_shift"])
	facade_mat.set_shader_parameter("interior_warm", sun_out["interior_warm"])
	facade_mat.set_shader_parameter("interior_cool", sun_out["interior_cool"])
	road_mat.set_shader_parameter("night", night)
	road_mat.set_shader_parameter("ring_p", live["ring_p"])
	tree_mat.set_shader_parameter("ring_p", live["ring_p"])
	tree_mat.set_shader_parameter("t", sim_t)
	lamp_mat.set_shader_parameter("ring_p", live["ring_p"])
	lamp_mat.set_shader_parameter("night", night)
	car_mat.set_shader_parameter("night", night)
