extends Node3D
# Tower cranes over active constructions. Masts track the build line; jibs
# rotate closed-form from the sim clock (scrub-exact). One instance slot per
# building slot — only slots the tracker flags `crane` are visible.

const CRANE_COL := Color(0.55, 0.22, 0.08)

var masts: MultiMesh
var jibs: MultiMesh
var cjibs: MultiMesh
var _active := {}  # slot i -> {x, z, top_y, jib_len, phase, rate}
var _zero := Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -60, 0))

func setup(slot_count: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CRANE_COL
	mat.roughness = 0.7
	mat.metallic_specular = 0.15
	masts = _pool(mat, slot_count)
	jibs = _pool(mat, slot_count)
	cjibs = _pool(mat, slot_count)

func _pool(mat: Material, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.material = mat
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, _zero)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mm

func sync(tracker, changed: Array) -> void:
	for i in changed:
		var s: Dictionary = tracker.slot(i)
		if s["crane"]:
			var rect: Rect2 = s["rect"]
			var corner_pick := int(float(s["lit_seed"]) * 4.0) % 4
			var cx: float = rect.position.x - 2.5 if corner_pick % 2 == 0 else rect.end.x + 2.5
			var cz: float = rect.position.y - 2.5 if corner_pick < 2 else rect.end.y + 2.5
			var top_y: float = float(s["y0"]) + float(s["h"]) * float(s["progress"]) + 9.0
			_active[i] = {
				"x": cx, "z": cz, "top_y": top_y,
				"jib_len": clampf(maxf(rect.size.x, rect.size.y) * 0.8, 14.0, 26.0),
				"phase": float(s["accent"]) * TAU,
				"rate": 0.09 + float(s["lit_seed"]) * 0.08,
			}
			masts.set_instance_transform(i, Transform3D(
					Basis().scaled(Vector3(1.5, top_y, 1.5)), Vector3(cx, top_y * 0.5, cz)))
		elif _active.has(i):
			_active.erase(i)
			masts.set_instance_transform(i, _zero)
			jibs.set_instance_transform(i, _zero)
			cjibs.set_instance_transform(i, _zero)

func tick(sim_t: float) -> void:
	for i in _active:
		var a: Dictionary = _active[i]
		var ang: float = a["phase"] + sim_t * a["rate"]
		var basis := Basis(Vector3.UP, ang)
		var top := Vector3(a["x"], a["top_y"], a["z"])
		jibs.set_instance_transform(i, Transform3D(
				basis * Basis().scaled(Vector3(a["jib_len"], 1.1, 1.1)),
				top + basis.x * (float(a["jib_len"]) * 0.5 - 2.0)))
		cjibs.set_instance_transform(i, Transform3D(
				basis * Basis().scaled(Vector3(7.0, 1.4, 1.4)),
				top - basis.x * 4.5))
