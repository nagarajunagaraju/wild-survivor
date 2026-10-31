extends Node3D
## Wild Survivor 3D: Godot test level.
## Endless forest trail: Rocky runs (-Z), the tiger chases, swipe to switch lanes / jump / slide,
## collect diamonds, avoid rocks, logs and low branches.

const LANES := [-2.2, 0.0, 2.2]
const CHUNK := 40.0
const NCHUNK := 7
const TRAIL_W := 8.6

var rng := RandomNumberGenerator.new()

# ---------- run state ----------
var phase := "menu"          # menu, play, dead
var lane := 1
var px := 0.0
var py := 0.0
var pz := 0.0
var vy := 0.0
var slide_t := 0.0
var speed := 14.0
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

# ---------- nodes ----------
var cam: Camera3D
var sun: DirectionalLight3D
var player: Node3D
var rocky: Node3D
var rocky_anim: AnimationPlayer
var tiger: Node3D
var tiger_anim: AnimationPlayer
var chunks: Array = []
var obstacles: Array = []
var items: Array = []
var hud := {}
var touch_start := Vector2.ZERO
var touch_used := false
var cur_anim := ""

# ---------- shared resources ----------
var flora_species: Array = []      # [{variants:[{mesh,xform}], n, s:[a,b], x:[a,b], rock}]
var rock_variants: Array = []
var gem_mesh: ArrayMesh
var gem_mat: StandardMaterial3D
var bark_mat: StandardMaterial3D
var trail_mat: StandardMaterial3D
var ground_mat: StandardMaterial3D
var grass_mesh: ArrayMesh
var snd := {}
var music: AudioStreamPlayer

func _ready() -> void:
	rng.randomize()
	_load_best()
	_setup_env()
	_setup_materials()
	_load_flora()
	_build_chunks()
	_setup_player()
	_setup_tiger()
	_setup_camera()
	_setup_audio()
	_setup_hud()
	_show_menu()
	if "--shot" in OS.get_cmdline_user_args():
		_autotest()

## Debug: auto-run and save screenshots (used for headless checks).
func _autotest() -> void:
	await get_tree().create_timer(1.0).timeout
	_shot("menu")
	_start()
	inv = 9999.0
	for i in 4:
		await get_tree().create_timer(2.5).timeout
		hp = 100; gap = 70
		_shot("run%d" % i)
		if i == 1: _jump()
	print("AUTOTEST dist=", int(-pz), " gems=", gems, " fps=", Engine.get_frames_per_second())
	get_tree().quit()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shot_%s.png" % n)
	print("SHOT ", ProjectSettings.globalize_path("user://shot_%s.png" % n))

# =====================================================================
# Environment: HDRI sky, sun with soft shadows, filmic tone mapping, glow, aerial fog
# =====================================================================
func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://hdri/mossy_forest_2k.exr")
	pm.energy_multiplier = 1.15
	sky.sky_material = pm
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(200), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.52, 0.45)
	env.fog_density = 0.004
	env.fog_aerial_perspective = 0.12
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	# low sun ahead and to the right of the runner: backlit leaves, long shadows toward the camera
	sun.rotation = Vector3(deg_to_rad(-24), deg_to_rad(155), 0)
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
	ground_mat.normal_enabled = true
	ground_mat.normal_texture = _tex("res://textures/grass_n.jpg")
	ground_mat.roughness = 1.0
	ground_mat.uv1_triplanar = true
	ground_mat.uv1_world_triplanar = true
	ground_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	ground_mat.albedo_color = Color(0.82, 0.95, 0.7)

	bark_mat = StandardMaterial3D.new()
	bark_mat.albedo_texture = _tex("res://textures/bark.jpg")
	bark_mat.roughness = 0.9
	bark_mat.uv1_scale = Vector3(2, 3, 1)

	gem_mesh = _make_gem()
	gem_mat = StandardMaterial3D.new()
	gem_mat.albedo_color = Color(0.55, 0.93, 1.0)
	gem_mat.metallic = 0.35
	gem_mat.roughness = 0.05
	gem_mat.emission_enabled = true
	gem_mat.emission = Color(0.1, 0.65, 0.95)
	gem_mat.emission_energy_multiplier = 0.9
	gem_mat.rim_enabled = true
	gem_mat.rim = 0.6
	gem_mesh.surface_set_material(0, gem_mat)

	grass_mesh = _make_grass_card()

## Brilliant-cut diamond: lathe profile with flat facets.
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

## Two crossed grass cards using the grass texture with alpha cut-out.
func _make_grass_card() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := PI * 0.5 * k + 0.3
		var dx := Vector3(cos(a), 0, sin(a)) * 0.55
		var up := Vector3(0, 0.9, 0)
		var n := Vector3(0, 1, 0)
		var q := [-dx, dx, dx + up, -dx + up]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n); st.set_uv(uv[idx]); st.add_vertex(q[idx])
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex("res://textures/grasscard.png")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.85, 1.0, 0.7)
	mat.roughness = 1.0
	mat.backlight_enabled = true
	mat.backlight = Color(0.35, 0.45, 0.15)
	m.surface_set_material(0, mat)
	return m

# =====================================================================
# Photo-scanned flora (Poly Haven, CC0): each variant becomes MultiMesh instances per chunk
# =====================================================================
const FLORA_DEFS := [
	{"file": "island_tree", "n": 3, "s": [3.6, 4.8], "x": [8.0, 30.0]},
	{"file": "tree_small", "n": 3, "s": [3.2, 4.2], "x": [7.5, 30.0]},
	{"file": "tree", "n": 3, "s": [0.7, 1.0], "x": [9.0, 34.0]},
	{"file": "searsia", "n": 3, "s": [1.2, 1.8], "x": [6.0, 16.0]},
	{"file": "rock_moss", "n": 1, "s": [0.45, 1.0], "x": [6.0, 18.0], "rock": true},
	{"file": "boulder_01", "n": 1, "s": [0.8, 1.5], "x": [6.5, 22.0], "rock": true},
	{"file": "boulder_02", "n": 1, "s": [0.7, 1.2], "x": [7.0, 24.0], "rock": true},
	{"file": "shrub_01", "n": 3, "s": [2.4, 3.8], "x": [4.7, 9.0]},
	{"file": "periwinkle", "n": 2, "s": [2.4, 3.4], "x": [4.6, 8.0]},
	{"file": "celandine", "n": 2, "s": [2.8, 3.8], "x": [4.6, 7.5]},
	{"file": "dandelion", "n": 2, "s": [2.8, 3.8], "x": [4.6, 7.5]},
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
			_collect_meshes(top, Transform3D.IDENTITY if top == root else Transform3D.IDENTITY, meshes, top == root)
			if meshes.is_empty():
				continue
			# merge all mesh instances of this variant into one ArrayMesh (one surface per source surface)
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
					if norms is PackedVector3Array:
						var nb := xf.basis.orthonormalized()
						for vi in norms.size():
							norms[vi] = nb * norms[vi]
						arr[Mesh.ARRAY_NORMAL] = norms
					var tans = arr[Mesh.ARRAY_TANGENT]
					if tans is PackedFloat32Array and tans.size() == verts.size() * 4:
						var tb := xf.basis.orthonormalized()
						for vi in verts.size():
							var tv: Vector3 = tb * Vector3(tans[vi * 4], tans[vi * 4 + 1], tans[vi * 4 + 2])
							tans[vi * 4] = tv.x; tans[vi * 4 + 1] = tv.y; tans[vi * 4 + 2] = tv.z
						arr[Mesh.ARRAY_TANGENT] = tans
					merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
					var mat := mesh.surface_get_material(si)
					if e.has("override") and e.override != null:
						mat = e.override
					if mat:
						_fix_material(mat)
						merged.surface_set_material(merged.get_surface_count() - 1, mat)
			# re-center on the ground: x/z center, sink slightly into the ground
			var off := Vector3(-(aabb.position.x + aabb.size.x * 0.5), -aabb.position.y - aabb.size.y * (0.06 if def.get("rock", false) else 0.01), -(aabb.position.z + aabb.size.z * 0.5))
			var sp := {"mesh": merged, "off": off, "n": def.n, "s": def.s, "x": def.x, "rock": def.get("rock", false), "size": aabb.size}
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
# World chunks: trail, ground, grass, flora; recycled ahead of the runner
# =====================================================================
func _build_chunks() -> void:
	for i in NCHUNK:
		var c := Node3D.new()
		add_child(c)
		var trail := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(TRAIL_W, CHUNK); pm.subdivide_depth = 4
		trail.mesh = pm; trail.material_override = trail_mat
		trail.position = Vector3(0, 0.02, -CHUNK * 0.5)
		c.add_child(trail)
		var ground := MeshInstance3D.new()
		var gm := PlaneMesh.new(); gm.size = Vector2(140, CHUNK)
		ground.mesh = gm; ground.material_override = ground_mat
		ground.position = Vector3(0, 0, -CHUNK * 0.5)
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.add_child(ground)
		# grass
		var gmm := MultiMesh.new(); gmm.transform_format = MultiMesh.TRANSFORM_3D; gmm.mesh = grass_mesh; gmm.instance_count = 520
		var gmi := MultiMeshInstance3D.new(); gmi.multimesh = gmm; gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.add_child(gmi)
		# flora
		var fl: Array = []
		for sp in flora_species:
			var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = sp.mesh; mm.instance_count = sp.n
			var mi := MultiMeshInstance3D.new(); mi.multimesh = mm
			if not sp.rock and sp.size.y < 1.0:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.add_child(mi)
			fl.append({"mm": mm, "sp": sp})
		c.set_meta("grass", gmm)
		c.set_meta("flora", fl)
		c.position.z = -i * CHUNK + CHUNK * 0.5
		_scatter_chunk(c)
		chunks.append(c)

func _scatter_chunk(c: Node3D) -> void:
	var gmm: MultiMesh = c.get_meta("grass")
	for k in gmm.instance_count:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * (TRAIL_W * 0.5 - 0.2 + pow(rng.randf(), 1.6) * 16.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.5))
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
# Player (Rocky, Mixamo) and tiger
# =====================================================================
func _setup_player() -> void:
	player = Node3D.new()
	add_child(player)
	var ps := load("res://models/rocky.glb") as PackedScene
	rocky = ps.instantiate()
	player.add_child(rocky)
	var ab := _aabb_of(rocky)
	var k := 1.8 / maxf(ab.size.y, 0.01)
	rocky.scale = Vector3.ONE * k
	rocky.rotation.y = PI
	rocky_anim = rocky.find_child("AnimationPlayer", true, false)
	if rocky_anim:
		for an in rocky_anim.get_animation_list():
			var a := rocky_anim.get_animation(an)
			_pin_root_motion(a)
			if an == "run":
				a.loop_mode = Animation.LOOP_LINEAR
	for m in rocky.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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

func _play(an: String, blend := 0.15, spd := 1.0) -> void:
	if rocky_anim == null or cur_anim == an or not rocky_anim.has_animation(an):
		return
	cur_anim = an
	rocky_anim.play(an, blend, spd)

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 260.0
	add_child(cam)
	cam.position = Vector3(0, 3.4, 5.2)
	cam.look_at(Vector3(0, 1.0, -8))

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
	music = AudioStreamPlayer.new()
	music.stream = load("res://sounds/music.mp3")
	(music.stream as AudioStreamMP3).loop = true
	music.volume_db = -12
	add_child(music)

func _sfx(n: String, pitch := 1.0) -> void:
	if snd.has(n):
		snd[n].pitch_scale = pitch
		snd[n].play()

# =====================================================================
# HUD
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
	return l

func _setup_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(root)
	hud.root = root
	var score := _label(64)
	score.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.position = Vector2(-420, 40); score.size = Vector2(390, 70)
	root.add_child(score); hud.score = score
	var gem := _label(48, Color(0.6, 0.95, 1.0))
	gem.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gem.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gem.position = Vector2(-420, 110); gem.size = Vector2(390, 56)
	root.add_child(gem); hud.gem = gem
	var dist := _label(34, Color(1, 1, 1, 0.8))
	dist.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dist.position = Vector2(-420, 166); dist.size = Vector2(390, 40)
	root.add_child(dist); hud.dist = dist
	# tiger proximity bar
	var tb := ProgressBar.new()
	tb.show_percentage = false
	tb.position = Vector2(30, 60); tb.size = Vector2(250, 16)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.45); bg.set_corner_radius_all(8)
	var fg := StyleBoxFlat.new(); fg.bg_color = Color(1, 0.45, 0.1); fg.set_corner_radius_all(8)
	tb.add_theme_stylebox_override("background", bg); tb.add_theme_stylebox_override("fill", fg)
	root.add_child(tb); hud.tiger = tb
	var tl := _label(26, Color(1, 0.6, 0.25)); tl.text = "TIGER"; tl.position = Vector2(30, 24)
	root.add_child(tl)
	var hb := ProgressBar.new()
	hb.show_percentage = false
	hb.position = Vector2(30, 100); hb.size = Vector2(250, 12)
	var fg2 := StyleBoxFlat.new(); fg2.bg_color = Color(0.95, 0.25, 0.3); fg2.set_corner_radius_all(6)
	hb.add_theme_stylebox_override("background", bg); hb.add_theme_stylebox_override("fill", fg2)
	root.add_child(hb); hud.hp = hb
	# center message (menu / game over)
	var msg := _label(92)
	msg.set_anchors_preset(Control.PRESET_CENTER)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.position = Vector2(-340, -330); msg.size = Vector2(680, 300)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(msg); hud.msg = msg
	var sub := _label(40, Color(1, 1, 1, 0.9), "res://fonts/barlow-700.woff2")
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(-340, -20); sub.size = Vector2(680, 200)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub); hud.sub = sub
	var pop := _label(54, Color(1, 0.85, 0.3))
	pop.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.position = Vector2(-300, 250); pop.size = Vector2(600, 70)
	pop.modulate.a = 0
	root.add_child(pop); hud.pop = pop

func _popup(text: String, col := Color(1, 0.85, 0.3)) -> void:
	var p: Label = hud.pop
	p.text = text
	p.label_settings.font_color = col
	p.modulate.a = 1.0
	p.scale = Vector2.ONE * 1.25
	p.pivot_offset = p.size * 0.5
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector2.ONE, 0.18)
	tw.tween_interval(0.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)

func _show_menu() -> void:
	phase = "menu"
	hud.msg.text = "WILD SURVIVOR"
	hud.sub.text = "Tap to run\nSwipe ← → lanes · ↑ jump · ↓ slide\nBest %d" % best
	_play("run", 0.0, 0.0)
	_update_hud()

func _update_hud() -> void:
	hud.score.text = str(int(score))
	hud.gem.text = "◆ %d" % gems
	hud.dist.text = "%d M" % int(-pz)
	hud.tiger.value = 100.0 - gap
	hud.hp.value = hp

# =====================================================================
# Run control
# =====================================================================
func _start() -> void:
	for o in obstacles: o.node.queue_free()
	for it in items: it.node.queue_free()
	obstacles.clear(); items.clear()
	lane = 1; px = 0; py = 0; pz = 0; vy = 0; slide_t = 0; speed = 14.0; t = 0
	gems = 0; score = 0; gap = 70.0; hp = 100.0; inv = 0; hit_t = 0; spawn_z = -45.0; gem_lane = 1
	for i in chunks.size():
		chunks[i].position.z = -i * CHUNK + CHUNK * 0.5
		_scatter_chunk(chunks[i])
	hud.msg.text = ""; hud.sub.text = ""
	phase = "play"
	cur_anim = ""
	_play("run", 0.1, 1.0)
	snd.run.play()
	music.play()
	_sfx("roar")
	shake = 0.4

func _die() -> void:
	phase = "dead"
	_play("death", 0.1)
	snd.run.stop()
	var s := int(score)
	if s > best:
		best = s
		_save_best()
	hud.msg.text = "THE TIGER GOT YOU"
	hud.sub.text = "Score %d · ◆ %d · %d m\nBest %d\n\nTap to run again" % [s, gems, int(-pz), best]

func _load_best() -> void:
	var f := FileAccess.open("user://best.txt", FileAccess.READ)
	if f:
		best = int(f.get_as_text())

func _save_best() -> void:
	var f := FileAccess.open("user://best.txt", FileAccess.WRITE)
	if f:
		f.store_string(str(best))

# =====================================================================
# Input: swipes on touch screens, arrow keys on desktop
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
		if d.length() > 45:
			touch_used = true
			if abs(d.x) > abs(d.y):
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

var dead_t := 0.0
func _can_restart() -> bool:
	return phase == "menu" or (phase == "dead" and dead_t > 1.2)

func _steer(d: int) -> void:
	lane = clampi(lane + d, 0, 2)

func _jump() -> void:
	if py <= 0.01:
		vy = 10.5; slide_t = 0
		cur_anim = ""
		_play("jump", 0.08, 1.25)

func _slide() -> void:
	if py > 0.01:
		vy = -18.0
	slide_t = 0.75

# =====================================================================
# Spawning: obstacle patterns + diamond lines that hop lanes
# =====================================================================
func _add_obstacle(type: String, l: int, z: float) -> void:
	var n := Node3D.new()
	var x: float = 0.0 if l < 0 else LANES[l]
	var need := "avoid"
	match type:
		"boulder":
			if rock_variants.size() > 0:
				var sp: Dictionary = rock_variants[rng.randi() % rock_variants.size()]
				var mi := MeshInstance3D.new(); mi.mesh = sp.mesh
				var k: float = 2.0 / maxf(sp.size.x, 0.1)
				mi.scale = Vector3(k, minf(k * 1.1, 1.9 / sp.size.y), minf(k, 2.3 / sp.size.z))
				mi.position = Vector3(sp.off.x * k, sp.off.y * mi.scale.y, sp.off.z * mi.scale.z)
				n.add_child(mi)
			else:
				var mi2 := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.95; sm.height = 1.6; mi2.mesh = sm; mi2.position.y = 0.75; n.add_child(mi2)
		"log":
			need = "jump"
			var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.38; cm.bottom_radius = 0.4; cm.height = 7.6
			mi.mesh = cm; mi.material_override = bark_mat; mi.rotation.z = PI / 2; mi.position.y = 0.36
			n.add_child(mi)
		"stump":
			need = "jump"
			var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.45; cm.bottom_radius = 0.58; cm.height = 0.75
			mi.mesh = cm; mi.material_override = bark_mat; mi.position.y = 0.37
			n.add_child(mi)
		"branch":
			need = "slide"
			var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.18; cm.bottom_radius = 0.26; cm.height = 9.5
			mi.mesh = cm; mi.material_override = bark_mat; mi.rotation.z = PI / 2 + 0.05; mi.position.y = 1.55
			n.add_child(mi)
			for sx in [-4.6, 4.6]:
				var post := MeshInstance3D.new(); var pc := CylinderMesh.new(); pc.top_radius = 0.22; pc.bottom_radius = 0.3; pc.height = 2.0
				post.mesh = pc; post.material_override = bark_mat; post.position = Vector3(sx, 1.0, 0)
				n.add_child(post)
	n.position = Vector3(x, 0, z)
	add_child(n)
	obstacles.append({"node": n, "type": type, "lane": l, "z": z, "need": need, "done": false})

func _add_gem(l: int, z: float, y := 1.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = gem_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(LANES[l], y, z)
	add_child(mi)
	items.append({"node": mi, "lane": l, "z": z, "y": y, "done": false})

func _spawn_segment(z: float, seg: float) -> void:
	var L := rng.randi() % 3
	var r := rng.randf()
	var early := -pz < 150.0
	if early:
		if r < 0.5: _add_obstacle("boulder", L, z)
		else: _add_obstacle("stump", L, z)
	elif r < 0.22: _add_obstacle("boulder", L, z)
	elif r < 0.38:
		for i in 3:
			if i != L: _add_obstacle("boulder", i, z)
	elif r < 0.52: _add_obstacle("log", -1, z)
	elif r < 0.66: _add_obstacle("branch", -1, z)
	elif r < 0.78: _add_obstacle("stump", L, z)
	elif r < 0.9:
		_add_obstacle("boulder", L, z); _add_obstacle("boulder", (L + 1 + rng.randi() % 2) % 3, z - 9)
	else:
		_add_obstacle("log", -1, z); _add_obstacle("branch", -1, z - 13)
	_fill_gems(z, seg)

func _lane_blocked(l: int, z0: float, z1: float) -> bool:
	for o in obstacles:
		if o.done: continue
		if o.z <= z0 + 1 and o.z >= z1 - 1 and o.lane == l and o.need == "avoid":
			return true
	return false

func _fill_gems(z: float, seg: float) -> void:
	var z0 := z + 1.5
	var z1 := z - seg + 2.5
	var free: Array = []
	for l in 3:
		if not _lane_blocked(l, z0, z1): free.append(l)
	if free.is_empty(): return
	var l1: int = gem_lane if free.has(gem_lane) and rng.randf() < 0.7 else free[rng.randi() % free.size()]
	var mid := (z0 + z1) * 0.5
	var others: Array = free.filter(func(x): return x != l1)
	if others.size() > 0 and rng.randf() < 0.45:
		var adj: Array = others.filter(func(x): return abs(x - l1) == 1)
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
			var d: float = abs(zi - o.z)
			if o.need == "jump" and d < 2.6: y = 1.0 + 1.5 * (1.0 - (d / 2.6) * (d / 2.6))
			elif o.need == "slide" and d < 1.8: y = 0.45
		_add_gem(l, zi, y)

# =====================================================================
# Main loop
# =====================================================================
func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if phase == "play":
		_step(dt)
	elif phase == "dead":
		dead_t += dt
	else:
		dead_t = 0.0
	_update_visuals(dt)

func _step(dt: float) -> void:
	t += dt
	speed = minf(28.0, 14.0 + t * 0.1)
	pz -= speed * dt
	score += speed * dt
	var tx: float = LANES[lane]
	px = move_toward(px, tx, dt * 14.0)
	vy -= 30.0 * dt
	py = maxf(0.0, py + vy * dt)
	if py == 0.0: vy = 0.0
	slide_t = maxf(0.0, slide_t - dt)
	inv = maxf(0.0, inv - dt)
	hit_t = maxf(0.0, hit_t - dt)
	gap = minf(100.0, gap + dt * 1.8)

	# spawn ahead
	while spawn_z > pz - 130.0:
		var seg := 11.0 + rng.randf() * 6.0 + speed * 0.35
		if -pz < 120: seg += 6
		_spawn_segment(spawn_z, seg)
		spawn_z -= seg

	# obstacles
	for o in obstacles:
		if o.done: continue
		if pz <= o.z + 0.35:
			o.done = true
			var in_lane: bool = o.lane < 0 or o.lane == lane
			if not in_lane: continue
			if o.need == "avoid": _hit(25)
			elif o.need == "jump" and py < 0.75: _hit(18)
			elif o.need == "slide" and slide_t <= 0.0: _hit(20)
	# items
	for it in items:
		if it.done: continue
		var dz: float = it.z - pz
		if abs(dz) < 1.0 and abs(LANES[it.lane] - px) < 1.1 and abs(py + 1.0 - it.y) < 1.3:
			it.done = true
			gems += 1
			score += 10
			_sfx("coin", 1.0 + (gems % 5) * 0.04)
			it.node.queue_free()

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

	# recycle chunks
	for c in chunks:
		if c.position.z - CHUNK > pz + 15:
			c.position.z -= NCHUNK * CHUNK
			_scatter_chunk(c)

	if gap <= 0.0 or hp <= 0.0:
		_die()

	# animation choice
	if hit_t > 0.0:
		pass
	elif py > 0.05:
		pass
	elif slide_t > 0.0:
		_play("run", 0.1, 1.0)
	else:
		_play("run", 0.15, 0.8 + speed / 40.0)
	_update_hud()

func _hit(dmg: float) -> void:
	if inv > 0: return
	hp -= dmg
	gap -= 34.0
	inv = 1.2
	hit_t = 0.55
	shake = 0.45
	cur_anim = ""
	_play("hit", 0.05, 1.4)
	_popup("OUCH!", Color(1, 0.4, 0.35))
	_sfx("roar", 1.1)

func _update_visuals(dt: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	player.position = Vector3(px, py, pz)
	# slide: lean back
	rocky.rotation.x = lerp(rocky.rotation.x, -1.1 if slide_t > 0.0 else 0.0, minf(1.0, dt * 14.0))
	rocky.position.y = lerp(rocky.position.y, 0.25 if slide_t > 0.0 else 0.0, minf(1.0, dt * 14.0))
	rocky.visible = inv <= 0.0 or inv > 100.0 or int(time * 14.0) % 2 == 0 or phase != "play"
	# tiger
	var tz := pz + 2.2 + gap * 0.16
	if phase == "dead": tz = pz + 1.0
	tiger.position = tiger.position.lerp(Vector3(px * 0.85, 0, tz), minf(1.0, dt * 4.0))
	if tiger_anim:
		tiger_anim.speed_scale = (speed / 14.0) if phase == "play" else 0.6
	# items spin
	for it in items:
		it.node.rotation.y += dt * 3.5
		it.node.position.y = it.y + sin(time * 3.0 + it.z) * 0.1
	# camera
	var goal := Vector3(px * 0.7, 3.3 + py * 0.3, pz + 5.0 + (100.0 - gap) * 0.01)
	if phase == "menu":
		var a := time * 0.25
		goal = Vector3(sin(a) * 4.0, 2.0, pz + cos(a) * 4.5 + 0.5)
	cam.position = cam.position.lerp(goal, minf(1.0, dt * 6.0))
	if shake > 0.0:
		shake = maxf(0.0, shake - dt)
		cam.position += Vector3(rng.randf() - 0.5, rng.randf() - 0.5, 0) * shake * 0.6
	var look := Vector3(px * 0.5, 1.0, pz - 8.0) if phase != "menu" else Vector3(0, 1.1, pz)
	cam.look_at(look)
	cam.fov = lerp(cam.fov, 68.0 + (speed - 14.0) * 0.6, minf(1.0, dt * 2.0))
	# keep the sun's shadow box around the runner (directional lights follow the camera automatically)
