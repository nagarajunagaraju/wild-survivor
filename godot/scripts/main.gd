extends Node3D
## Wild Survivor 3D (Godot).
## Endless forest trail: Rocky runs toward -Z with a tiger behind him.
## Swipe to switch lanes / jump / slide. Grab diamonds, dodge rocks, logs, rolling boulders and log traps,
## ride launch ramps and the glider, survive tiger attacks, keep the combo multiplier alive.

const LANES := [-2.2, 0.0, 2.2]
const CHUNK := 40.0
const NCHUNK := 6
const TRAIL_W := 8.6
const GLIDE_Y := 4.6

var rng := RandomNumberGenerator.new()

# ---------- run state ----------
var phase := "menu"          # menu, play, dead
var lane := 1
var px := 0.0
var py := 0.0
var pz := 0.0
var vy := 0.0
var slide_t := 0.0
var speed := 15.0
var t := 0.0
var gems := 0
var score := 0.0
var gap := 70.0
var hp := 100.0
var inv := 0.0
var hit_t := 0.0
var shake := 0.0
var spawn_z := -45.0
var best := 0
var gem_lane := 1
var lane_t := -9.0
var combo := 0
var boost := 1
var pw := {"glide": 0.0, "magnet": 0.0, "shield": 0.0, "double": 0.0}
var glide_timer := 22.0
var surge := {}               # active tiger attack: {left, need, got}
var surge_t := 32.0
var slowmo := 0.0
var dead_t := 0.0
var was_air := false
var launch_t := 0.0

# ---------- nodes ----------
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var player: Node3D
var rocky: Node3D
var rocky_anim: AnimationPlayer
var glider: Node3D
var shield_fx: MeshInstance3D
var backpack: Node3D
var backpack_att: BoneAttachment3D
var tiger: Node3D
var tiger_anim: AnimationPlayer
var chunks: Array = []
var obstacles: Array = []
var items: Array = []
var hud := {}
var touch_start := Vector2.ZERO
var touch_used := false
var cur_anim := ""
var dust: CPUParticles3D
var sparkle: CPUParticles3D

# ---------- shared resources ----------
var flora_species: Array = []
var rock_variants: Array = []
var gem_mesh: ArrayMesh
var bark_mat: StandardMaterial3D
var wood_mat: StandardMaterial3D
var trail_mat: StandardMaterial3D
var ground_mat: StandardMaterial3D
var grass_mesh: ArrayMesh
var warn_mat: StandardMaterial3D
var snd := {}
var music: AudioStreamPlayer

# ---------- adaptive quality ----------
var q_scale := 0.75
var fps_acc := 0.0
var fps_frames := 0

const POWERS := {
	"glide": {"name": "GLIDER", "col": Color(0.45, 0.85, 1.0), "dur": 6.5},
	"magnet": {"name": "MAGNET", "col": Color(1.0, 0.82, 0.25), "dur": 10.0},
	"shield": {"name": "SHIELD", "col": Color(0.55, 1.0, 0.6), "dur": 12.0},
	"double": {"name": "2X DIAMONDS", "col": Color(1.0, 0.45, 0.9), "dur": 10.0},
}

func _ready() -> void:
	rng.randomize()
	_load_best()
	get_viewport().scaling_3d_scale = q_scale
	_setup_env()
	_setup_materials()
	_load_flora()
	_build_chunks()
	_setup_player()
	_setup_tiger()
	_setup_camera()
	_setup_fx()
	_setup_audio()
	_setup_hud()
	_show_menu()
	if "--shot" in OS.get_cmdline_user_args():
		_autotest()

## Debug: auto-run and save screenshots (used for headless checks).
func _autotest() -> void:
	await get_tree().create_timer(1.0).timeout
	await _shot("menu")
	_start()
	inv = 9999.0
	for i in 6:
		await get_tree().create_timer(2.2).timeout
		hp = 100; gap = maxf(gap, 30)
		if i == 2:
			surge_t = 0.01; pz = minf(pz, -210.0)
		if i == 3:
			_power("glide")
		await _shot("run%d" % i)
	print("AUTOTEST dist=", int(-pz), " gems=", gems, " combo=", combo, " obs=", obstacles.size(), " items=", items.size())
	get_tree().quit()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shot_%s.png" % n)
	print("SHOT ", n)

# =====================================================================
# Environment
# =====================================================================
func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://hdri/mossy_forest_1k.exr")
	pm.energy_multiplier = 1.15
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(200), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.12
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.52, 0.45)
	env.fog_density = 0.004
	env.fog_aerial_perspective = 0.12
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.07
	env.adjustment_saturation = 1.15
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 34.0
	sun.rotation = Vector3(deg_to_rad(-26), deg_to_rad(155), 0)
	add_child(sun)

# =====================================================================
# Materials & procedural meshes
# =====================================================================
func _tex(p: String) -> Texture2D:
	return load(p) as Texture2D

func _setup_materials() -> void:
	trail_mat = StandardMaterial3D.new()
	trail_mat.albedo_texture = _tex("res://textures/trail.png")
	trail_mat.normal_enabled = true
	trail_mat.normal_texture = _tex("res://textures/trail_n.jpg")
	trail_mat.normal_scale = 1.3
	trail_mat.roughness = 0.95
	trail_mat.uv1_triplanar = true
	trail_mat.uv1_world_triplanar = true
	trail_mat.uv1_scale = Vector3(0.16, 0.16, 0.16)
	trail_mat.albedo_color = Color(1.05, 1.0, 0.95)

	ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_texture = _tex("res://textures/grass.jpg")
	ground_mat.roughness = 1.0
	ground_mat.uv1_triplanar = true
	ground_mat.uv1_world_triplanar = true
	ground_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	ground_mat.albedo_color = Color(0.85, 1.0, 0.72)

	bark_mat = StandardMaterial3D.new()
	bark_mat.albedo_texture = _tex("res://textures/bark.jpg")
	bark_mat.roughness = 0.9
	bark_mat.uv1_scale = Vector3(2, 3, 1)

	wood_mat = StandardMaterial3D.new()
	wood_mat.albedo_texture = _tex("res://textures/bark.jpg")
	wood_mat.albedo_color = Color(1.25, 1.05, 0.85)
	wood_mat.roughness = 0.8
	wood_mat.uv1_scale = Vector3(1, 4, 1)

	warn_mat = StandardMaterial3D.new()
	warn_mat.albedo_color = Color(1, 0.25, 0.15)
	warn_mat.emission_enabled = true
	warn_mat.emission = Color(1, 0.2, 0.1)
	warn_mat.emission_energy_multiplier = 2.5
	warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	gem_mesh = _make_gem()
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.93, 1.0)
	gm.metallic = 0.35
	gm.roughness = 0.05
	gm.emission_enabled = true
	gm.emission = Color(0.1, 0.65, 0.95)
	gm.emission_energy_multiplier = 0.9
	gm.rim_enabled = true
	gm.rim = 0.6
	gem_mesh.surface_set_material(0, gm)

	grass_mesh = _make_grass_card()

func _make_gem() -> ArrayMesh:
	var prof := [Vector2(0, -0.42), Vector2(0.38, 0.02), Vector2(0.38, 0.07), Vector2(0.25, 0.18), Vector2(0, 0.18)]
	var seg := 8
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for j in prof.size() - 1:
			var p0: Vector2 = prof[j]
			var p1: Vector2 = prof[j + 1]
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v11)
			st.add_vertex(v00); st.add_vertex(v11); st.add_vertex(v01)
	st.generate_normals()
	return st.commit()

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 tint = vec3(0.85, 1.0, 0.7);
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 2.1 + w.x * 0.6 + w.z * 0.35) * 0.12 * VERTEX.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
}
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb * tint * (0.75 + 0.35 * (1.0 - UV.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.3, 0.4, 0.12);
}
"""

func _make_grass_card() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := PI * 0.5 * k + 0.3
		var dx := Vector3(cos(a), 0, sin(a)) * 0.55
		var up := Vector3(0, 0.9, 0)
		var q := [-dx, dx, dx + up, -dx + up]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP); st.set_uv(uv[idx]); st.add_vertex(q[idx])
	var m := st.commit()
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", _tex("res://textures/grasscard.png"))
	m.surface_set_material(0, mat)
	return m

# =====================================================================
# Photo-scanned flora (Poly Haven, CC0)
# =====================================================================
const FLORA_DEFS := [
	{"file": "island_tree", "n": 2, "s": [3.6, 4.8], "x": [8.0, 30.0], "vis": 170.0},
	{"file": "tree_small", "n": 2, "s": [3.2, 4.2], "x": [7.5, 30.0], "vis": 170.0},
	{"file": "tree", "n": 3, "s": [0.7, 1.0], "x": [9.0, 34.0], "vis": 190.0},
	{"file": "searsia", "n": 2, "s": [1.2, 1.8], "x": [6.0, 16.0], "vis": 80.0},
	{"file": "rock_moss", "n": 1, "s": [0.45, 1.0], "x": [6.0, 18.0], "rock": true, "vis": 90.0},
	{"file": "boulder_01", "n": 1, "s": [0.8, 1.5], "x": [6.5, 22.0], "rock": true, "vis": 90.0},
	{"file": "boulder_02", "n": 1, "s": [0.7, 1.2], "x": [7.0, 24.0], "rock": true, "vis": 90.0},
	{"file": "shrub_01", "n": 2, "s": [2.4, 3.8], "x": [4.7, 9.0], "vis": 45.0},
	{"file": "periwinkle", "n": 2, "s": [2.4, 3.4], "x": [4.6, 8.0], "vis": 40.0},
	{"file": "celandine", "n": 1, "s": [2.8, 3.8], "x": [4.6, 7.5], "vis": 40.0},
	{"file": "dandelion", "n": 1, "s": [2.8, 3.8], "x": [4.6, 7.5], "vis": 40.0},
]

func _fix_material(m: Material) -> void:
	var sm := m as BaseMaterial3D
	if sm == null:
		return
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		sm.alpha_scissor_threshold = 0.5
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.backlight_enabled = true
		sm.backlight = Color(0.42, 0.5, 0.18)
		sm.albedo_color = sm.albedo_color * Color(1.12, 1.15, 1.0)

func _load_flora() -> void:
	for def in FLORA_DEFS:
		var ps := load("res://models/%s.glb" % def.file) as PackedScene
		if ps == null:
			continue
		var root := ps.instantiate()
		var tops: Array = []
		for c in root.get_children():
			tops.append(c)
		if tops.size() <= 1:
			tops = [root]
		for top in tops:
			var meshes: Array = []
			_collect_meshes(top, Transform3D.IDENTITY, meshes, top == root)
			if meshes.is_empty():
				continue
			var merged := ArrayMesh.new()
			var aabb := AABB()
			var first := true
			for e in meshes:
				var mesh: Mesh = e.mesh
				var xf: Transform3D = e.xform
				for si in mesh.get_surface_count():
					var arr := mesh.surface_get_arrays(si)
					var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var norms = arr[Mesh.ARRAY_NORMAL]
					for vi in verts.size():
						verts[vi] = xf * verts[vi]
						if first:
							aabb = AABB(verts[vi], Vector3.ZERO); first = false
						else:
							aabb = aabb.expand(verts[vi])
					arr[Mesh.ARRAY_VERTEX] = verts
					var nb := xf.basis.orthonormalized()
					if norms is PackedVector3Array:
						for vi in norms.size():
							norms[vi] = nb * norms[vi]
						arr[Mesh.ARRAY_NORMAL] = norms
					var tans = arr[Mesh.ARRAY_TANGENT]
					if tans is PackedFloat32Array and tans.size() == verts.size() * 4:
						for vi in verts.size():
							var tv: Vector3 = nb * Vector3(tans[vi * 4], tans[vi * 4 + 1], tans[vi * 4 + 2])
							tans[vi * 4] = tv.x; tans[vi * 4 + 1] = tv.y; tans[vi * 4 + 2] = tv.z
						arr[Mesh.ARRAY_TANGENT] = tans
					merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
					var mat := mesh.surface_get_material(si)
					if e.override != null:
						mat = e.override
					if mat:
						_fix_material(mat)
						merged.surface_set_material(merged.get_surface_count() - 1, mat)
			var rock: bool = def.get("rock", false)
			var off := Vector3(-(aabb.position.x + aabb.size.x * 0.5), -aabb.position.y - aabb.size.y * (0.06 if rock else 0.01), -(aabb.position.z + aabb.size.z * 0.5))
			var sp := {"mesh": merged, "off": off, "n": def.n, "s": def.s, "x": def.x, "rock": rock, "size": aabb.size, "vis": def.vis}
			flora_species.append(sp)
			if def.file == "rock_moss":
				rock_variants.append(sp)
		root.queue_free()

func _collect_meshes(n: Node, parent_xf: Transform3D, out: Array, skip_self: bool) -> void:
	var xf := parent_xf
	if n is Node3D and not skip_self:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append({"mesh": (n as MeshInstance3D).mesh, "xform": xf, "override": (n as MeshInstance3D).material_override})
	for c in n.get_children():
		_collect_meshes(c, xf, out, false)

# =====================================================================
# World chunks
# =====================================================================
func _build_chunks() -> void:
	for i in NCHUNK:
		var c := Node3D.new()
		add_child(c)
		var trail := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(TRAIL_W, CHUNK)
		trail.mesh = pm; trail.material_override = trail_mat
		trail.position = Vector3(0, 0.02, -CHUNK * 0.5)
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.add_child(trail)
		var ground := MeshInstance3D.new()
		var gm := PlaneMesh.new(); gm.size = Vector2(140, CHUNK)
		ground.mesh = gm; ground.material_override = ground_mat
		ground.position = Vector3(0, 0, -CHUNK * 0.5)
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.add_child(ground)
		var gmm := MultiMesh.new(); gmm.transform_format = MultiMesh.TRANSFORM_3D; gmm.mesh = grass_mesh; gmm.instance_count = 200
		var gmi := MultiMeshInstance3D.new(); gmi.multimesh = gmm; gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gmi.visibility_range_end = 70.0
		c.add_child(gmi)
		var fl: Array = []
		for sp in flora_species:
			var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = sp.mesh; mm.instance_count = sp.n
			var mi := MultiMeshInstance3D.new(); mi.multimesh = mm
			mi.visibility_range_end = sp.vis
			if not sp.rock and sp.size.y < 1.0:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.add_child(mi)
			fl.append({"mm": mm, "sp": sp, "mi": mi})
		c.set_meta("grass", gmm)
		c.set_meta("flora", fl)
		c.position.z = -i * CHUNK + CHUNK * 0.5
		_scatter_chunk(c)
		chunks.append(c)

func _scatter_chunk(c: Node3D) -> void:
	var gmm: MultiMesh = c.get_meta("grass")
	for k in gmm.instance_count:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * (TRAIL_W * 0.5 - 0.25 + pow(rng.randf(), 1.8) * 12.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.6))
		gmm.set_instance_transform(k, Transform3D(b, Vector3(x, 0, -rng.randf() * CHUNK)))
	for e in c.get_meta("flora"):
		var mm: MultiMesh = e.mm
		var sp: Dictionary = e.sp
		for k in mm.instance_count:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var x: float = side * (sp.x[0] + pow(rng.randf(), 1.4) * (sp.x[1] - sp.x[0]))
			var s := rng.randf_range(sp.s[0], sp.s[1])
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			mm.set_instance_transform(k, Transform3D(b, Vector3(x, 0, -rng.randf() * CHUNK) + b * sp.off))

# =====================================================================
# Player
# =====================================================================
func _setup_player() -> void:
	player = Node3D.new()
	add_child(player)
	var ps := load("res://models/rocky.glb") as PackedScene
	rocky = ps.instantiate()
	player.add_child(rocky)
	var ab := _aabb_of(rocky)
	rocky.scale = Vector3.ONE * (1.8 / maxf(ab.size.y, 0.01))
	rocky.rotation.y = PI
	rocky_anim = rocky.find_child("AnimationPlayer", true, false)
	if rocky_anim:
		for an in rocky_anim.get_animation_list():
			var a := rocky_anim.get_animation(an)
			_pin_root_motion(a)
			if an == "run" or an == "idle":
				a.loop_mode = Animation.LOOP_LINEAR
	for m in rocky.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_add_backpack()
	# glider wing (shown while flying)
	glider = Node3D.new()
	var wing := MeshInstance3D.new()
	var wm := PrismMesh.new(); wm.size = Vector3(3.4, 0.35, 1.3); wm.left_to_right = 0.5
	wing.mesh = wm
	var wmat := StandardMaterial3D.new(); wmat.albedo_color = Color(1.0, 0.45, 0.08); wmat.roughness = 0.6; wmat.cull_mode = BaseMaterial3D.CULL_DISABLED; wmat.emission_enabled = true; wmat.emission = Color(1.0, 0.4, 0.05); wmat.emission_energy_multiplier = 0.35
	wing.material_override = wmat
	wing.position = Vector3(0, 2.45, 0.05)
	glider.add_child(wing)
	for sx in [-0.55, 0.55]:
		var rod := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.015; cm.bottom_radius = 0.015; cm.height = 0.9
		rod.mesh = cm; rod.position = Vector3(sx, 1.95, 0); rod.rotation.z = -sx * 0.5
		var rm := StandardMaterial3D.new(); rm.albedo_color = Color(0.1, 0.1, 0.1); rod.material_override = rm
		glider.add_child(rod)
	glider.visible = false
	player.add_child(glider)
	# shield bubble
	shield_fx = MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 1.15; sm.height = 2.3
	shield_fx.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.5, 1.0, 0.6, 0.18)
	smat.emission_enabled = true; smat.emission = Color(0.3, 1.0, 0.5); smat.emission_energy_multiplier = 0.6
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_fx.material_override = smat
	shield_fx.position.y = 0.95
	shield_fx.visible = false
	shield_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.add_child(shield_fx)

## Trekking backpack with a rolled sleeping mat, attached to the spine bone so it moves with the run.
func _add_backpack() -> void:
	var skel := rocky.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var bi := skel.find_bone("mixamorig_Spine2")
	if bi < 0:
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).ends_with("Spine2"):
				bi = i
	if bi < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = bi
	skel.add_child(att)
	var pack := Node3D.new()
	player.add_child(pack)
	backpack = pack; backpack_att = att
	var canvas := StandardMaterial3D.new(); canvas.albedo_color = Color(0.36, 0.25, 0.14); canvas.roughness = 0.85
	var strap := StandardMaterial3D.new(); strap.albedo_color = Color(0.12, 0.1, 0.08)
	var mat_roll := StandardMaterial3D.new(); mat_roll.albedo_color = Color(0.85, 0.42, 0.1); mat_roll.roughness = 0.7
	var body := MeshInstance3D.new(); var bm := CapsuleMesh.new(); bm.radius = 0.2; bm.height = 0.62
	body.mesh = bm; body.material_override = canvas; body.scale = Vector3(1.05, 1.0, 0.62)
	pack.add_child(body)
	var pocket := MeshInstance3D.new(); var pkm := BoxMesh.new(); pkm.size = Vector3(0.26, 0.2, 0.08)
	pocket.mesh = pkm; pocket.material_override = canvas; pocket.position = Vector3(0, -0.1, -0.13)
	pack.add_child(pocket)
	var roll := MeshInstance3D.new(); var rcm := CylinderMesh.new(); rcm.top_radius = 0.08; rcm.bottom_radius = 0.08; rcm.height = 0.5
	roll.mesh = rcm; roll.material_override = mat_roll; roll.rotation.z = PI / 2; roll.position = Vector3(0, 0.33, 0.0)
	pack.add_child(roll)
	for sx in [-0.11, 0.11]:
		var st := MeshInstance3D.new(); var sbm := BoxMesh.new(); sbm.size = Vector3(0.045, 0.5, 0.03)
		st.mesh = sbm; st.material_override = strap; st.position = Vector3(sx, 0.0, -0.17)
		pack.add_child(st)

func _pin_root_motion(a: Animation) -> void:
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D and String(a.track_get_path(i)).ends_with("Hips"):
			if a.track_get_key_count(i) == 0:
				continue
			var v0: Vector3 = a.track_get_key_value(i, 0)
			for k in a.track_get_key_count(i):
				var v: Vector3 = a.track_get_key_value(i, k)
				a.track_set_key_value(i, k, Vector3(v0.x, v.y, v0.z))

func _aabb_of(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var bb := mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.get_aabb()
		if first:
			out = bb; first = false
		else:
			out = out.merge(bb)
	return out

func _setup_tiger() -> void:
	tiger = Node3D.new()
	add_child(tiger)
	var ps := load("res://models/tiger.glb") as PackedScene
	var m := ps.instantiate() as Node3D
	m.rotation.y = PI
	m.scale = Vector3.ONE * 1.05
	tiger.add_child(m)
	tiger_anim = m.find_child("AnimationPlayer", true, false)
	if tiger_anim and tiger_anim.get_animation_list().size() > 0:
		var an: String = tiger_anim.get_animation_list()[0]
		tiger_anim.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		tiger_anim.play(an)
	tiger.position = Vector3(0, 0, 14)

func _play(an: String, blend := 0.15, spd := 1.0) -> void:
	if rocky_anim == null or cur_anim == an or not rocky_anim.has_animation(an):
		return
	cur_anim = an
	rocky_anim.play(an, blend, spd)

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.1
	cam.far = 240.0
	add_child(cam)
	cam.position = Vector3(0, 2.8, 4.2)
	cam.look_at(Vector3(0, 1.2, -7))

func _soft_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64; gt.height = 64
	return gt

func _setup_fx() -> void:
	var soft := _soft_tex()
	dust = CPUParticles3D.new()
	dust.emitting = false
	dust.amount = 16
	dust.lifetime = 0.6
	dust.one_shot = false
	dust.explosiveness = 0.0
	dust.direction = Vector3(0, 1, 1)
	dust.spread = 35.0
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 2.4
	dust.gravity = Vector3(0, -1.5, 0)
	dust.scale_amount_min = 0.25
	dust.scale_amount_max = 0.5
	var dm := QuadMesh.new(); dm.size = Vector2(0.5, 0.5)
	var dmat := StandardMaterial3D.new()
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.vertex_color_use_as_albedo = true
	dmat.albedo_texture = soft
	dm.material = dmat
	dust.mesh = dm
	var grad := Gradient.new(); grad.set_color(0, Color(0.75, 0.62, 0.45, 0.22)); grad.set_color(1, Color(0.75, 0.62, 0.45, 0.0))
	dust.color_ramp = grad
	add_child(dust)

	sparkle = CPUParticles3D.new()
	sparkle.emitting = false
	sparkle.one_shot = true
	sparkle.amount = 10
	sparkle.lifetime = 0.45
	sparkle.explosiveness = 1.0
	sparkle.spread = 180.0
	sparkle.initial_velocity_min = 2.0
	sparkle.initial_velocity_max = 4.0
	sparkle.gravity = Vector3.ZERO
	sparkle.scale_amount_min = 0.15
	sparkle.scale_amount_max = 0.3
	var sq := QuadMesh.new(); sq.size = Vector2(0.4, 0.4)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = soft
	sq.material = smat
	sparkle.mesh = sq
	var g2 := Gradient.new(); g2.set_color(0, Color(0.7, 0.98, 1.0, 1.0)); g2.set_color(1, Color(0.3, 0.8, 1.0, 0.0))
	sparkle.color_ramp = g2
	add_child(sparkle)

# =====================================================================
# Audio
# =====================================================================
func _setup_audio() -> void:
	for n in ["coin", "roar", "run", "forest", "heart"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://sounds/%s.mp3" % n)
		add_child(p)
		snd[n] = p
	(snd.forest.stream as AudioStreamMP3).loop = true
	snd.forest.volume_db = -8
	snd.forest.play()
	(snd.run.stream as AudioStreamMP3).loop = true
	snd.run.volume_db = -10
	(snd.heart.stream as AudioStreamMP3).loop = true
	snd.heart.volume_db = -40
	music = AudioStreamPlayer.new()
	music.stream = load("res://sounds/music.mp3")
	(music.stream as AudioStreamMP3).loop = true
	music.volume_db = -12
	add_child(music)

func _sfx(n: String, pitch := 1.0) -> void:
	if snd.has(n):
		snd[n].pitch_scale = pitch
		snd[n].play()

func _buzz(ms: int) -> void:
	Input.vibrate_handheld(ms)

# =====================================================================
# HUD (small, out of the way: no big boxes during the run)
# =====================================================================
func _label(size: int, col := Color.WHITE, font_path := "res://fonts/bebas-neue-400.woff2") -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = load(font_path)
	ls.font_size = size
	ls.font_color = col
	ls.shadow_color = Color(0, 0, 0, 0.55)
	ls.shadow_size = 6
	ls.shadow_offset = Vector2(0, 2)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _bar(pos: Vector2, size: Vector2, col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.position = pos; b.size = size
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.45); bg.set_corner_radius_all(int(size.y / 2))
	var fg := StyleBoxFlat.new(); fg.bg_color = col; fg.set_corner_radius_all(int(size.y / 2))
	b.add_theme_stylebox_override("background", bg); b.add_theme_stylebox_override("fill", fg)
	return b

func _right_label(size: int, col: Color, y: float, h: float) -> Label:
	var l := _label(size, col)
	l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.position = Vector2(-430, y); l.size = Vector2(400, h)
	return l

func _setup_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(root)
	hud.root = root
	hud.score = _right_label(64, Color.WHITE, 40, 70); root.add_child(hud.score)
	hud.mult = _label(46, Color(1, 0.85, 0.25))
	hud.mult.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud.mult.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.mult.position = Vector2(-430, 112); hud.mult.size = Vector2(400, 50)
	root.add_child(hud.mult)
	var combo := _bar(Vector2(0, 0), Vector2(170, 8), Color(1, 0.7, 0.15))
	combo.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	combo.position = Vector2(-200, 164)
	root.add_child(combo); hud.combo = combo
	hud.gem = _right_label(48, Color(0.6, 0.95, 1.0), 178, 56); root.add_child(hud.gem)
	hud.dist = _right_label(32, Color(1, 1, 1, 0.8), 232, 40); root.add_child(hud.dist)
	hud.tiger = _bar(Vector2(30, 60), Vector2(250, 16), Color(1, 0.45, 0.1)); root.add_child(hud.tiger)
	var tl := _label(26, Color(1, 0.6, 0.25)); tl.text = "TIGER"; tl.position = Vector2(30, 24); root.add_child(tl)
	hud.hp = _bar(Vector2(30, 98), Vector2(250, 12), Color(0.95, 0.25, 0.3)); root.add_child(hud.hp)
	hud.powers = _label(30, Color(0.7, 0.95, 1.0)); hud.powers.position = Vector2(30, 120); hud.powers.size = Vector2(320, 120)
	root.add_child(hud.powers)
	hud.msg = _label(96)
	hud.msg.set_anchors_preset(Control.PRESET_CENTER)
	hud.msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.msg.position = Vector2(-340, -420); hud.msg.size = Vector2(680, 300)
	hud.msg.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hud.msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hud.msg)
	hud.sub = _label(38, Color(1, 1, 1, 0.92), "res://fonts/barlow-700.woff2")
	hud.sub.set_anchors_preset(Control.PRESET_CENTER)
	hud.sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.sub.position = Vector2(-340, -100); hud.sub.size = Vector2(680, 400)
	hud.sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hud.sub)
	hud.pop = _label(58, Color(1, 0.85, 0.3))
	hud.pop.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud.pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.pop.position = Vector2(-320, 300); hud.pop.size = Vector2(640, 70)
	hud.pop.modulate.a = 0
	root.add_child(hud.pop)
	hud.flash = ColorRect.new()
	hud.flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.flash.color = Color(1, 0.2, 0.1, 0)
	hud.flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud.flash)

var pop_tween: Tween
func _popup(text: String, col := Color(1, 0.85, 0.3)) -> void:
	var p: Label = hud.pop
	p.text = text
	p.label_settings.font_color = col
	p.modulate.a = 1.0
	p.pivot_offset = p.size * 0.5
	p.scale = Vector2.ONE * 1.3
	if pop_tween: pop_tween.kill()
	pop_tween = create_tween()
	pop_tween.set_ignore_time_scale(true)
	pop_tween.tween_property(p, "scale", Vector2.ONE, 0.15)
	pop_tween.tween_interval(0.55)
	pop_tween.tween_property(p, "modulate:a", 0.0, 0.25)

func _bump(c: Control) -> void:
	c.pivot_offset = c.size * Vector2(1.0, 0.5)
	c.scale = Vector2.ONE * 1.3
	var tw := create_tween(); tw.set_ignore_time_scale(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)

func _flash(col: Color) -> void:
	hud.flash.color = col
	var tw := create_tween(); tw.set_ignore_time_scale(true)
	tw.tween_property(hud.flash, "color:a", 0.0, 0.35)

func _show_menu() -> void:
	phase = "menu"
	hud.msg.text = "WILD SURVIVOR"
	hud.sub.text = "Tap to run\n\nSwipe ← →  change lane\nSwipe ↑  jump · ↓  slide\n\nBEST  %d" % best
	_play("idle", 0.0, 1.0)
	_update_hud()

func _update_hud() -> void:
	hud.score.text = str(int(score))
	hud.mult.text = "x%d" % _mult()
	hud.combo.value = 100.0 if boost >= 6 else float(combo % 30) / 30.0 * 100.0
	hud.gem.text = "◆ %d" % gems
	hud.dist.text = "%d M" % int(-pz)
	hud.tiger.value = 100.0 - gap
	hud.hp.value = hp
	var s := ""
	for k in pw:
		if pw[k] > 0.0:
			s += "%s  %ds\n" % [POWERS[k].name, ceili(pw[k])]
	if not surge.is_empty():
		s += "DODGE  %d/%d\n" % [surge.got, surge.need]
	hud.powers.text = s

func _mult() -> int:
	return boost

# =====================================================================
# Run control
# =====================================================================
func _start() -> void:
	for o in obstacles: o.node.queue_free()
	for it in items: it.node.queue_free()
	obstacles.clear(); items.clear()
	lane = 1; px = 0; py = 0; pz = 0; vy = 0; slide_t = 0; speed = 15.0; t = 0
	gems = 0; score = 0; gap = 70.0; hp = 100.0; inv = 0; hit_t = 0; spawn_z = -40.0; gem_lane = 1
	combo = 0; boost = 1; surge = {}; surge_t = 32.0; glide_timer = 22.0; slowmo = 0.0; launch_t = 0.0
	for k in pw: pw[k] = 0.0
	Engine.time_scale = 1.0
	for i in chunks.size():
		chunks[i].position.z = -i * CHUNK + CHUNK * 0.5
		_scatter_chunk(chunks[i])
	hud.msg.text = ""; hud.sub.text = ""
	phase = "play"
	cur_anim = ""
	_play("run", 0.1, 1.0)
	snd.run.play()
	snd.heart.play()
	music.play()
	# Temple-Run start: the tiger bursts out right behind and roars, then drops back
	tiger.position = Vector3(-5.0, 0, 3.0)
	_sfx("roar"); shake = 0.5; _buzz(120)
	_popup("RUN!", Color(1, 0.9, 0.5))

func _die() -> void:
	phase = "dead"
	dead_t = 0.0
	Engine.time_scale = 1.0
	cur_anim = ""
	_play("death", 0.1)
	snd.run.stop()
	_sfx("roar", 0.9)
	_buzz(400)
	var s := int(score)
	var nb := s > best
	if nb:
		best = s
		_save_best()
	hud.msg.text = "THE TIGER GOT YOU"
	hud.sub.text = "%s\nScore  %d\n◆ %d   ·   %d m\nBest  %d\n\nTap to run again" % ["NEW BEST!" if nb else "", s, gems, int(-pz), best]

func _load_best() -> void:
	var f := FileAccess.open("user://best.txt", FileAccess.READ)
	if f:
		best = int(f.get_as_text())

func _save_best() -> void:
	var f := FileAccess.open("user://best.txt", FileAccess.WRITE)
	if f:
		f.store_string(str(best))

# =====================================================================
# Input
# =====================================================================
func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touch_start = e.position; touch_used = false
			if phase != "play" and _can_restart():
				_start()
		return
	if e is InputEventScreenDrag and phase == "play" and not touch_used:
		var d: Vector2 = e.position - touch_start
		if d.length() > 40:
			touch_used = true
			if absf(d.x) > absf(d.y):
				_steer(1 if d.x > 0 else -1)
			elif d.y < 0:
				_jump()
			else:
				_slide()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if phase != "play":
			if _can_restart(): _start()
			return
		match e.keycode:
			KEY_LEFT, KEY_A: _steer(-1)
			KEY_RIGHT, KEY_D: _steer(1)
			KEY_UP, KEY_W, KEY_SPACE: _jump()
			KEY_DOWN, KEY_S: _slide()

func _can_restart() -> bool:
	return phase == "menu" or (phase == "dead" and dead_t > 1.2)

func _steer(d: int) -> void:
	var nl := clampi(lane + d, 0, 2)
	if nl != lane:
		lane = nl
		lane_t = t

func _jump() -> void:
	if pw.glide > 0.0: return
	if py <= 0.01:
		vy = 10.5; slide_t = 0
		cur_anim = ""
		_play("jump", 0.08, 1.25)

func _slide() -> void:
	if pw.glide > 0.0: return
	if py > 0.01:
		vy = -20.0
	slide_t = 0.75

# =====================================================================
# Spawning
# =====================================================================
func _obs_node(l: int, z: float) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(0.0 if l < 0 else LANES[l], 0, z)
	add_child(n)
	return n

func _rock_mesh(width: float, max_h: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if rock_variants.size() > 0:
		var sp: Dictionary = rock_variants[rng.randi() % rock_variants.size()]
		mi.mesh = sp.mesh
		var k: float = width / maxf(sp.size.x, 0.1)
		mi.scale = Vector3(k, minf(k * 1.1, max_h / sp.size.y), minf(k, 2.3 / sp.size.z))
		mi.position = Vector3(sp.off.x * mi.scale.x, sp.off.y * mi.scale.y, sp.off.z * mi.scale.z)
	else:
		var sm := SphereMesh.new(); sm.radius = width * 0.5; sm.height = max_h; mi.mesh = sm; mi.position.y = max_h * 0.5
	return mi

func _add_obstacle(type: String, l: int, z: float) -> void:
	var n := _obs_node(l, z)
	var o := {"node": n, "type": type, "lane": l, "z": z, "need": "avoid", "done": false}
	match type:
		"boulder":
			n.add_child(_rock_mesh(2.0, 1.9))
		"log":
			o.need = "jump"
			var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.38; cm.bottom_radius = 0.42; cm.height = 7.8
			mi.mesh = cm; mi.material_override = bark_mat; mi.rotation.z = PI / 2; mi.position.y = 0.38
			n.add_child(mi)
		"stump":
			o.need = "jump"
			var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.45; cm.bottom_radius = 0.58; cm.height = 0.75
			mi.mesh = cm; mi.material_override = bark_mat; mi.position.y = 0.37
			n.add_child(mi)
		"branch":
			o.need = "slide"
			var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.18; cm.bottom_radius = 0.26; cm.height = 9.5
			mi.mesh = cm; mi.material_override = bark_mat; mi.rotation.z = PI / 2 + 0.05; mi.position.y = 1.55
			n.add_child(mi)
			for sx in [-4.6, 4.6]:
				var post := MeshInstance3D.new(); var pc := CylinderMesh.new(); pc.top_radius = 0.22; pc.bottom_radius = 0.3; pc.height = 2.0
				post.mesh = pc; post.material_override = bark_mat; post.position = Vector3(sx, 1.0, 0)
				n.add_child(post)
		"roller":
			var holder := Node3D.new(); holder.position.y = 1.0
			n.add_child(holder)
			var rk := _rock_mesh(1.9, 1.9)
			rk.position -= Vector3(0, 0.95, 0)
			holder.add_child(rk)
			o.spin = holder
			var w := MeshInstance3D.new(); var wm := SphereMesh.new(); wm.radius = 0.22; wm.height = 0.44
			w.mesh = wm; w.material_override = warn_mat; w.position.y = 2.7; w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(w); o.warn = w
			o.rolling = false
		"swinger":
			o.need = "swing"
			var beam := MeshInstance3D.new(); var bcm := CylinderMesh.new(); bcm.top_radius = 0.24; bcm.bottom_radius = 0.28; bcm.height = 14.0
			beam.mesh = bcm; beam.material_override = bark_mat; beam.rotation.z = PI / 2; beam.position.y = 7.6
			n.add_child(beam)
			for sx in [-6.6, 6.6]:
				var post := MeshInstance3D.new(); var pc := CylinderMesh.new(); pc.top_radius = 0.26; pc.bottom_radius = 0.34; pc.height = 7.8
				post.mesh = pc; post.material_override = bark_mat; post.position = Vector3(sx, 3.9, 0)
				n.add_child(post)
			var piv := Node3D.new(); piv.position.y = 7.5
			n.add_child(piv)
			for dz in [-0.6, 0.6]:
				var rope := MeshInstance3D.new(); var rcm := CylinderMesh.new(); rcm.top_radius = 0.03; rcm.bottom_radius = 0.03; rcm.height = 6.0
				var rmat := StandardMaterial3D.new(); rmat.albedo_color = Color(0.75, 0.65, 0.45)
				rope.mesh = rcm; rope.material_override = rmat; rope.position = Vector3(0, -3.0, dz)
				piv.add_child(rope)
			var ram := MeshInstance3D.new(); var ram_m := CylinderMesh.new(); ram_m.top_radius = 0.45; ram_m.bottom_radius = 0.45; ram_m.height = 2.6
			ram.mesh = ram_m; ram.material_override = bark_mat; ram.rotation.x = PI / 2; ram.position.y = -6.2
			piv.add_child(ram)
			o.piv = piv; o.ph = rng.randf() * TAU; o.sx = 0.0
		"ramp":
			o.need = "ramp"
			var deck := MeshInstance3D.new(); var dm := BoxMesh.new(); dm.size = Vector3(1.9, 0.12, 3.4)
			deck.mesh = dm; deck.material_override = wood_mat
			deck.rotation.x = deg_to_rad(17); deck.position = Vector3(0, 0.5, 0.0)
			n.add_child(deck)
			for sx in [-0.8, 0.8]:
				var leg := MeshInstance3D.new(); var lm := BoxMesh.new(); lm.size = Vector3(0.12, 1.0, 0.12)
				leg.mesh = lm; leg.material_override = wood_mat; leg.position = Vector3(sx, 0.5, -1.5)
				n.add_child(leg)
			var arrow := MeshInstance3D.new(); var am := PrismMesh.new(); am.size = Vector3(0.7, 0.5, 0.06)
			var amat := StandardMaterial3D.new(); amat.albedo_color = Color(1, 0.85, 0.2); amat.emission_enabled = true; amat.emission = Color(1, 0.7, 0.1); amat.emission_energy_multiplier = 1.5
			arrow.mesh = am; arrow.material_override = amat; arrow.position = Vector3(0, 1.6, -1.6)
			n.add_child(arrow)
	obstacles.append(o)

func _add_gem(l: int, z: float, y := 1.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = gem_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(LANES[l], y, z)
	add_child(mi)
	items.append({"node": mi, "lane": l, "x": LANES[l], "z": z, "y": y, "done": false, "kind": "gem"})

func _add_power(kind: String, l: int, z: float, y := 1.2) -> void:
	var n := Node3D.new()
	var col: Color = POWERS[kind].col
	var orb := MeshInstance3D.new(); var om := SphereMesh.new(); om.radius = 0.42; om.height = 0.84
	var mat := StandardMaterial3D.new(); mat.albedo_color = col; mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color.a = 0.85
	orb.mesh = om; orb.material_override = mat; orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(orb)
	var beam := MeshInstance3D.new(); var bm := CylinderMesh.new(); bm.top_radius = 0.06; bm.bottom_radius = 0.35; bm.height = 6.0
	var bmat := StandardMaterial3D.new(); bmat.albedo_color = Color(col.r, col.g, col.b, 0.22); bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.mesh = bm; beam.material_override = bmat; beam.position.y = 2.8; beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(beam)
	n.position = Vector3(LANES[l], y, z)
	add_child(n)
	items.append({"node": n, "lane": l, "x": LANES[l], "z": z, "y": y, "done": false, "kind": kind})

func _spawn_segment(z: float, seg: float) -> void:
	var L := rng.randi() % 3
	var r := rng.randf()
	var dist := -pz
	if dist < 140.0:
		if r < 0.45: _add_obstacle("boulder", L, z)
		elif r < 0.8: _add_obstacle("stump", L, z)
		else: _add_obstacle("log", -1, z)
	elif r < 0.12: _add_obstacle("boulder", L, z)
	elif r < 0.22:
		for i in 3:
			if i != L: _add_obstacle("boulder", i, z)
	elif r < 0.31: _add_obstacle("log", -1, z)
	elif r < 0.39: _add_obstacle("branch", -1, z)
	elif r < 0.46: _add_obstacle("stump", L, z); _add_obstacle("stump", (L + 1) % 3, z - 8)
	elif r < 0.55: _add_obstacle("roller", L, z - 4)
	elif r < 0.63: _add_obstacle("swinger", -1, z)
	elif r < 0.72:
		_add_obstacle("boulder", L, z); _add_obstacle("boulder", (L + 1 + rng.randi() % 2) % 3, z - 9)
	elif r < 0.8: _add_obstacle("log", -1, z); _add_obstacle("branch", -1, z - 13)
	elif r < 0.88:
		var J := rng.randi() % 3
		for i in 3: _add_obstacle("stump" if i == J else "boulder", i, z)
	else:
		# launch ramp with a diamond arc in the air
		_add_obstacle("ramp", L, z)
		for i in 9:
			var zz := z - 3.0 - i * 2.2
			var ph := float(i) / 8.0
			_add_gem(L, zz, 1.2 + sin(ph * PI) * 4.2)
		if seg > 26.0: _fill_gems(z - 22.0, seg - 22.0)
		return
	_fill_gems(z, seg)
	if dist > 60.0 and rng.randf() < 0.13:
		var kinds := ["magnet", "shield", "double"]
		_add_power(kinds[rng.randi() % kinds.size()], rng.randi() % 3, z - seg * 0.6)

func _lane_blocked(l: int, z0: float, z1: float) -> bool:
	for o in obstacles:
		if o.done: continue
		if o.z <= z0 + 1 and o.z >= z1 - 1 and o.lane == l and o.need == "avoid":
			return true
		if o.type == "roller" and o.lane == l and o.z > z1 - 18:
			return true
	return false

func _fill_gems(z: float, seg: float) -> void:
	var z0 := z + 1.5
	var z1 := z - seg + 2.5
	if z0 - z1 < 4.0: return
	var free: Array = []
	for l in 3:
		if not _lane_blocked(l, z0, z1): free.append(l)
	if free.is_empty(): return
	var l1: int = gem_lane if free.has(gem_lane) and rng.randf() < 0.7 else free[rng.randi() % free.size()]
	var mid := (z0 + z1) * 0.5
	var others: Array = free.filter(func(x): return x != l1)
	if others.size() > 0 and rng.randf() < 0.5:
		var adj: Array = others.filter(func(x): return absi(x - l1) == 1)
		var l2: int = adj[rng.randi() % adj.size()] if adj.size() > 0 else others[0]
		_gem_line(l1, z0, mid + 1.2); _gem_line(l2, mid - 1.4, z1); gem_lane = l2
	else:
		_gem_line(l1, z0, z1); gem_lane = l1

func _gem_line(l: int, from: float, to: float) -> void:
	var n := int((from - to) / 2.1)
	for i in n:
		var zi := from - i * 2.1
		var y := 1.0
		for o in obstacles:
			if o.done or (o.lane != l and o.lane >= 0): continue
			var d: float = absf(zi - o.z)
			if o.need == "jump" and d < 2.6: y = 1.0 + 1.5 * (1.0 - (d / 2.6) * (d / 2.6))
			elif o.need == "slide" and d < 1.8: y = 0.45
		_add_gem(l, zi, y)

func _sky_gems() -> void:
	var n := int(speed * POWERS.glide.dur / 2.4)
	for i in n:
		var ln := clampi(int(round(1.0 + sin(i * 0.3) * 1.05)), 0, 2)
		_add_gem(ln, pz - 10.0 - i * 2.4, GLIDE_Y + 1.0)

# =====================================================================
# Combo, powers, tiger attack
# =====================================================================
func _add_combo(n: int) -> void:
	combo += n
	var b := 1 + mini(5, int(combo / 30.0))
	if b > boost:
		boost = b
		_bump(hud.mult)
		_popup("x%d MULTIPLIER" % boost, Color(1, 0.85, 0.25))
		_buzz(40)
	elif b < boost:
		boost = b

func _dodged(n: int) -> void:
	_add_combo(n)
	if not surge.is_empty():
		surge.got += 1
		if surge.got >= surge.need:
			_escape_surge()

func _power(kind: String) -> void:
	pw[kind] = POWERS[kind].dur
	_popup(POWERS[kind].name, POWERS[kind].col)
	_buzz(50)
	_sfx("coin", 0.7)
	if kind == "glide":
		_sky_gems()
		surge = {}

func _start_surge() -> void:
	surge = {"left": 9.0, "need": 3, "got": 0}
	_sfx("roar", 1.05); shake = 0.6; _buzz(250)
	_popup("TIGER ATTACK!", Color(1, 0.4, 0.25))
	_flash(Color(1, 0.3, 0.1, 0.25))

func _escape_surge() -> void:
	surge = {}
	surge_t = 30.0 + rng.randf() * 14.0
	gap = minf(100.0, gap + 35.0)
	gems += 15
	score += 1000 * _mult()
	_add_combo(15)
	slowmo = 0.5
	_popup("ESCAPED! +15 ◆", Color(0.5, 1.0, 0.55))
	_buzz(60)

# =====================================================================
# Main loop
# =====================================================================
func _process(dt_scaled: float) -> void:
	var real_dt := minf(dt_scaled / maxf(Engine.time_scale, 0.01), 0.05)
	var dt := minf(dt_scaled, 0.05)
	_adapt_quality(real_dt)
	if slowmo > 0.0:
		slowmo -= real_dt
		Engine.time_scale = lerpf(Engine.time_scale, 0.4, minf(1.0, real_dt * 14.0))
	else:
		Engine.time_scale = lerpf(Engine.time_scale, 1.0, minf(1.0, real_dt * 6.0))
	if phase == "play":
		_step(dt)
	elif phase == "dead":
		dead_t += real_dt
	_update_visuals(dt)

## Keep the frame rate up on slower phones by lowering the 3D render resolution and shadow range.
func _adapt_quality(real_dt: float) -> void:
	fps_acc += real_dt
	fps_frames += 1
	if fps_acc < 2.5:
		return
	var fps := fps_frames / fps_acc
	fps_acc = 0.0; fps_frames = 0
	if fps < 27.0 and q_scale > 0.5:
		q_scale = maxf(0.5, q_scale - 0.1)
		get_viewport().scaling_3d_scale = q_scale
		if q_scale <= 0.6:
			sun.directional_shadow_max_distance = 22.0
			env.glow_enabled = false
	elif fps > 52.0 and q_scale < 0.85:
		q_scale = minf(0.85, q_scale + 0.05)
		get_viewport().scaling_3d_scale = q_scale

func _step(dt: float) -> void:
	t += dt
	speed = minf(30.0, 15.0 + t * 0.12)
	var v := speed * (1.0 if pw.glide <= 0.0 else 1.15)
	pz -= v * dt
	score += v * dt * _mult()
	px = move_toward(px, LANES[lane], dt * 15.0)
	for k in pw:
		pw[k] = maxf(0.0, pw[k] - dt)
	launch_t = maxf(0.0, launch_t - dt)

	# vertical motion: glider holds altitude, otherwise gravity
	if pw.glide > 0.0:
		py = lerpf(py, GLIDE_Y, minf(1.0, dt * 2.6))
		vy = 0.0
		slide_t = 0.0
	else:
		vy -= (24.0 if launch_t > 0.0 else 30.0) * dt
		py = maxf(0.0, py + vy * dt)
		if py == 0.0:
			if was_air and vy < -12.0:
				shake = maxf(shake, 0.18); dust.restart(); _buzz(25)
			vy = 0.0
	was_air = py > 0.05
	slide_t = maxf(0.0, slide_t - dt)
	inv = maxf(0.0, inv - dt)
	hit_t = maxf(0.0, hit_t - dt)

	# tiger: drifts back while you run clean; an attack drains the gap fast
	if not surge.is_empty():
		surge.left -= dt
		gap -= 6.5 * dt
		if surge.left <= 0.0:
			surge = {}
			surge_t = 24.0 + rng.randf() * 12.0
	else:
		gap = minf(100.0, gap + dt * 1.6)
		if -pz > 220.0 and pw.glide <= 0.0:
			surge_t -= dt
			if surge_t <= 0.0:
				_start_surge()
	# guaranteed glider every so often (flying is the most fun)
	if -pz > 150.0:
		glide_timer -= dt
		if glide_timer <= 0.0:
			glide_timer = 26.0 + rng.randf() * 10.0
			_add_power("glide", rng.randi() % 3, spawn_z + 6.0)

	# spawn ahead
	while spawn_z > pz - 130.0:
		var seg := 10.5 + rng.randf() * 6.0 + speed * 0.32
		if -pz < 140: seg += 7
		_spawn_segment(spawn_z, seg)
		spawn_z -= seg

	_update_obstacles(dt)
	_update_items(dt)

	# cleanup behind
	var keep: Array = []
	for o in obstacles:
		if o.z > pz + 12: o.node.queue_free()
		else: keep.append(o)
	obstacles = keep
	var keep2: Array = []
	for it in items:
		if it.done: continue
		if it.z > pz + 12: it.node.queue_free()
		else: keep2.append(it)
	items = keep2

	for c in chunks:
		if c.position.z - CHUNK > pz + 15:
			c.position.z -= NCHUNK * CHUNK
			_scatter_chunk(c)

	# audio: heartbeat as the tiger closes in
	snd.heart.volume_db = lerpf(-40.0, -4.0, clampf((45.0 - gap) / 45.0, 0.0, 1.0))
	snd.run.pitch_scale = 0.9 + speed / 60.0

	if gap <= 0.0 or hp <= 0.0:
		_die()
		return

	# animation
	if hit_t > 0.0:
		pass
	elif pw.glide > 0.0 and py > 1.0:
		if cur_anim != "glide_pose":
			cur_anim = "glide_pose"
			rocky_anim.play("jump", 0.15, 1.0)
			rocky_anim.seek(0.4, true)
			rocky_anim.pause()
	elif py > 0.05:
		pass
	else:
		_play("run", 0.15, 0.8 + speed / 40.0)
	dust.emitting = py < 0.05 and phase == "play"
	_update_hud()

func _update_obstacles(dt: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	for o in obstacles:
		if o.done: continue
		if o.type == "roller" and o.z - pz > -60.0:
			if not o.rolling:
				o.rolling = true
			o.z += 9.0 * dt
			o.node.position.z = o.z
			o.spin.rotation.x += dt * 9.0 / 1.0
			o.warn.visible = sin(time * 14.0) > -0.3
		if o.type == "swinger":
			var th := 0.6 * sin(time * 1.9 + o.ph)
			o.piv.rotation.z = th
			o.sx = sin(th) * 6.2
		if pz <= o.z + 0.35:
			o.done = true
			if py > 3.0:
				continue
			if o.need == "ramp":
				if o.lane == lane and py < 0.5:
					vy = 15.5; launch_t = 1.2; slide_t = 0.0
					cur_anim = ""; _play("jump", 0.05, 0.9)
					_popup("WOOHOO!", Color(1, 0.9, 0.4)); _buzz(40)
					_add_combo(4)
				continue
			if o.need == "swing":
				var dx := absf(o.sx - px)
				if dx < 1.25: _hit(20)
				else: _dodged(6 if dx < 2.4 else 3)
				continue
			var in_lane: bool = o.lane < 0 or o.lane == lane
			if not in_lane:
				if o.need == "avoid" and absi(o.lane - lane) == 1:
					_dodged(2)
					if t - lane_t < 0.38: _near_miss()
				continue
			var hit_before := hit_t
			if o.need == "avoid": _hit(28 if o.type == "roller" else 24)
			elif o.need == "jump" and py < 0.75: _hit(18)
			elif o.need == "slide" and slide_t <= 0.0: _hit(20)
			if hit_t == hit_before: _dodged(4)

func _near_miss() -> void:
	gems += 3
	_add_combo(5)
	slowmo = 0.3
	_popup("CLOSE ONE! +3 ◆", Color(1, 0.9, 0.4))
	_buzz(30)

func _update_items(dt: float) -> void:
	for it in items:
		if it.done: continue
		var dz: float = it.z - pz
		if pw.magnet > 0.0 and it.kind == "gem" and dz < 1.0 and dz > -12.0 and absf(it.y - (py + 1.0)) < 2.5:
			it.x = lerpf(it.x, px, minf(1.0, dt * 10.0))
			it.z = lerpf(it.z, pz, minf(1.0, dt * 5.0))
			it.node.position.x = it.x
			it.node.position.z = it.z
			dz = it.z - pz
		if absf(dz) < 1.0 and absf(it.x - px) < 1.15 and absf(py + 1.0 - it.y) < 1.35:
			it.done = true
			if it.kind == "gem":
				var g := 2 if pw.double > 0.0 else 1
				gems += g
				score += 10 * _mult() * g
				_add_combo(1)
				_sfx("coin", 1.0 + (combo % 8) * 0.03)
				sparkle.global_position = it.node.global_position
				sparkle.restart()
				if gems % 10 == 0: _bump(hud.gem)
			else:
				_power(it.kind)
			it.node.queue_free()

func _hit(dmg: float) -> void:
	if inv > 0: return
	if pw.shield > 0.0:
		pw.shield = 0.0
		inv = 1.0
		shake = 0.3
		_popup("SHIELD SAVED YOU", Color(0.55, 1.0, 0.6))
		_buzz(60)
		return
	hp -= dmg
	gap -= 30.0
	inv = 1.3
	hit_t = 0.55
	shake = 0.5
	combo = 0
	boost = 1
	cur_anim = ""
	_play("hit", 0.05, 1.5)
	_flash(Color(1, 0.15, 0.1, 0.35))
	_sfx("roar", 1.15)
	_buzz(180)

func _update_visuals(dt: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	player.position = Vector3(px, py, pz)
	var lean := 0.0
	if slide_t > 0.0: lean = -1.1
	elif pw.glide > 0.0 and py > 1.0: lean = 0.5
	rocky.rotation.x = lerpf(rocky.rotation.x, lean, minf(1.0, dt * 12.0))
	rocky.position.y = lerpf(rocky.position.y, 0.25 if slide_t > 0.0 else 0.0, minf(1.0, dt * 14.0))
	rocky.rotation.z = lerpf(rocky.rotation.z, (px - LANES[lane]) * 0.12, minf(1.0, dt * 10.0))
	rocky.visible = inv <= 0.0 or inv > 100.0 or int(time * 14.0) % 2 == 0 or phase != "play"
	glider.visible = pw.glide > 0.0 and py > 0.8
	shield_fx.visible = pw.shield > 0.0
	dust.global_position = Vector3(px, 0.1, pz + 0.3)
	if backpack and backpack_att:
		# behind the shoulder blades (runner faces -Z, so his back is +Z), tilting with leans
		var bp := backpack_att.global_position
		backpack.global_transform = Transform3D(Basis.from_euler(Vector3(-rocky.rotation.x * 0.8, 0, rocky.rotation.z)), bp + Vector3(0, -0.02, 0.16))
		backpack.visible = rocky.visible

	# tiger: right behind during attacks, otherwise drops back with the gap
	var tz := pz + 2.3 + gap * 0.16
	if not surge.is_empty(): tz = pz + 2.4 + gap * 0.04
	if phase == "dead": tz = pz + 1.2
	if phase == "menu": tz = pz + 9.0
	var tx := px * 0.85
	tiger.position = tiger.position.lerp(Vector3(tx, 0, tz), minf(1.0, dt * (5.0 if phase == "play" and t < 1.0 else 3.0)))
	if tiger_anim:
		tiger_anim.speed_scale = (speed / 14.0) if phase == "play" else 0.5

	for it in items:
		it.node.rotation.y += dt * 3.5
		it.node.position.y = it.y + sin(time * 3.0 + it.z) * 0.1

	# camera: chase cam that pulls back to show the tiger during attacks
	var attack := 0.0 if surge.is_empty() else 1.0
	var goal := Vector3(px * 0.7, 2.75 + py * 0.55 + attack * 0.6, pz + 4.3 + attack * 1.8)
	var look := Vector3(px * 0.55, 1.2 + py * 0.6, pz - 7.0)
	if phase == "menu":
		var a := time * 0.22
		goal = Vector3(sin(a) * 3.2, 1.7, pz + cos(a) * 3.6)
		look = Vector3(0, 1.1, pz)
	elif phase == "dead":
		goal = Vector3(px + 3.2, 1.8, pz + 2.6)
		look = Vector3(px, 0.8, pz + 0.8)
	cam.position = cam.position.lerp(goal, minf(1.0, dt * 6.0))
	if shake > 0.0:
		shake = maxf(0.0, shake - dt)
		cam.position += Vector3(rng.randf() - 0.5, rng.randf() - 0.5, 0) * shake * 0.6
	cam.look_at(look)
	var fov_goal := 66.0 + (speed - 15.0) * 0.55 + (8.0 if pw.glide > 0.0 else 0.0) + (5.0 if launch_t > 0.0 else 0.0)
	cam.fov = lerpf(cam.fov, fov_goal, minf(1.0, dt * 2.5))
