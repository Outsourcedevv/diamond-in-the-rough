extends Node3D
class_name RoughWorkshop

var stations: Dictionary = {}
var pile_centers: Array[Vector3] = []
var upgrade_positions: Dictionary = {}
var _product_cards: Dictionary = {}
var _machines: Dictionary = {}
var _materials: Dictionary = {}
var _sign_font: SystemFont
var _game: Node
var _rng := RandomNumberGenerator.new()
var conveyor_center := Vector3(6.65, 0.9, -2.0)
var conveyor_direction: int = 1
var _belt_enabled: bool = false
var _belt_slats: Array[MeshInstance3D] = []
var _animation_timers: Dictionary = {}
var _moving_parts: Dictionary = {}
static var _shared_gem_mesh: ArrayMesh

func build(game: Node) -> void:
	_game = game
	name = "MountainQuarry"
	_rng.seed = 408916
	_make_materials()
	_build_environment()
	_build_room()
	_build_pile()
	_build_stations()
	_build_props()
	update_upgrades([])

func animate_machine(id: String, duration: float = 1.25) -> void:
	_animation_timers[id] = maxf(float(_animation_timers.get(id, 0.0)), duration)

func reverse_conveyor() -> void:
	conveyor_direction *= -1

func set_conveyor_direction(direction: int) -> void:
	conveyor_direction = 1 if direction >= 0 else -1

func _process(delta: float) -> void:
	if _belt_enabled:
		for slat: MeshInstance3D in _belt_slats:
			slat.position.z = wrapf(slat.position.z + delta * 0.85 * conveyor_direction, -2.25, 2.25)
	for id: String in _animation_timers.keys():
		var remaining: float = maxf(0.0, float(_animation_timers[id]) - delta)
		_animation_timers[id] = remaining
		if remaining <= 0.0 or not _moving_parts.has(id):
			continue
		var parts: Array = _moving_parts[id]
		for index: int in range(parts.size()):
			var part: Node3D = parts[index]
			if id == "scanner":
				part.position.z = sin(remaining * 12.0) * 0.27
			elif id == "wash":
				part.position.y = 1.4 + sin(remaining * 14.0 + float(index)) * 0.045
			else:
				part.rotate_object_local(Vector3.UP, delta * 11.0)

func pile_position(sector: int, slot: int) -> Vector3:
	var c: Vector3 = pile_centers[clampi(sector, 0, pile_centers.size() - 1)]
	var angle: float = float(slot) * 2.399963 + float(sector) * 0.43
	var radius: float = 0.26 + float(slot % 4) * 0.22
	var x: float = c.x + cos(angle) * radius
	var z: float = c.z + sin(angle) * radius * 0.72
	return Vector3(x, _pile_height(x, z) + 0.17, z)

func update_upgrades(upgrades: Array) -> void:
	for key: String in _machines:
		var entry: Dictionary = _machines[key]
		var active: bool = key in upgrades
		if key == "conveyor":
			_belt_enabled = active
			entry["node"].visible = active
			entry["collision"].disabled = not active
		else:
			entry["node"].visible = active
			entry["collision"].disabled = not active
			entry["notice"].visible = not active
			var status: Label3D = entry["status"]
			status.text = "READY" if active else "EQUIPMENT NOT INSTALLED"
			status.modulate = Color("f0e3c7") if active else Color("bcaa8b")
	for id: String in _product_cards:
		var card: Label3D = _product_cards[id]
		card.text = "INSTALLED" if id in upgrades else "$%d" % int(_game.state.prices.get(id, 0))
		card.modulate = Color("9dac86") if id in upgrades else Color("e9b866")
	if has_node("ExpansionSupplies"):
		get_node("ExpansionSupplies").visible = upgrades.size() >= 3

func get_upgrade_name(id: String) -> String:
	return str(_game.state.upgrade_names.get(id,id.capitalize()))

static func _material(color: Color, metal: float = 0.0, roughness: float = 0.65, glow: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = roughness
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat

func _make_materials() -> void:
	_sign_font=SystemFont.new()
	_sign_font.font_names=PackedStringArray(["Segoe UI","Arial","sans-serif"])
	_sign_font.font_weight=600
	_sign_font.font_italic=false
	_materials = {
		"wall": _material(Color("677164")),
		"wall_light": _material(Color("72796b")),
		"floor": _material(Color("64675c"), 0.0, 0.95),
		"floor_alt": _material(Color("566055"), 0.0, 0.95),
		"wood": _material(Color("a2845c"), 0.0, 0.88),
		"wood_dark": _material(Color("524336"), 0.0, 0.92),
		"brass": _material(Color("bda063"), 0.45, 0.48),
		"steel": _material(Color("808783"), 0.52, 0.56),
		"dark": _material(Color("333a39"), 0.15, 0.72),
		"mint": _material(Color("8caa91"), 0.25, 0.5),
		"pink": _material(Color("80665a"), 0.32, 0.5),
		"orange": _material(Color("bd814a"), 0.2, 0.58),
		"white": _material(Color("e5e0cf"), 0.0, 0.78),
		"window": _material(Color("a1bcc3"), 0.12, 0.34),
		"light": _material(Color("ffe9b1"), 0.0, 0.3, 0.9),
		"rubber": _material(Color("282d2d"), 0.0, 0.96),
		"rock": _material(Color("5f6b66"), 0.0, 0.94),
		"rock_light": _material(Color("828b7d"), 0.0, 0.97),
		"rock_dark": _material(Color("465651"), 0.0, 0.97),
		"snow": _material(Color("ccd9d1"), 0.0, 0.93),
		"canvas": _material(Color("bcac84"), 0.0, 0.97),
		"pine": _material(Color("435d4d"), 0.0, 0.92),
		"pine_dark": _material(Color("31483d"), 0.0, 0.95),
		"sign": _material(Color("2e3531"), 0.0, 0.98),
		"gravel": _material(Color("747668"), 0.0, 1.0)
	}

func _build_environment() -> void:
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6b91aa")
	sky_material.sky_horizon_color = Color("d7dfd7")
	sky_material.ground_bottom_color = Color("667365")
	sky_material.ground_horizon_color = Color("b7c3b8")
	sky_material.sky_energy_multiplier = 0.55
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.30
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("c1d1d4")
	environment.fog_density = 0.0018
	environment.glow_enabled = false
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sunlight := DirectionalLight3D.new()
	sunlight.light_color = Color("fffaf1")
	sunlight.light_energy = 0.72
	sunlight.rotation_degrees = Vector3(-48, -38, 0)
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 70.0
	add_child(sunlight)

func _omni(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	add_child(light)

func _build_room() -> void:
	# The sorting camp sits on a gravel terrace cut into an alpine mountainside.
	_box(self, Vector3(0, -0.22, 0), Vector3(26.0, 0.44, 23.0), "floor", true)
	_box(self, Vector3(0, -0.55, -16), Vector3(112.0, 0.55, 108.0), "floor_alt")
	_mountain(Vector3(0, -0.5, -34), 23.0, 24.0, 21, true)
	_mountain(Vector3(-23, -1.0, -31), 18.0, 17.0, 29, false)
	_mountain(Vector3(24, -1.0, -35), 20.0, 20.0, 32, true)
	_mountain(Vector3(-43, -1.0, -50), 24.0, 30.0, 41, true)
	_mountain(Vector3(43, -1.0, -55), 27.0, 34.0, 42, true)
	# Rough quarry face and a timber retaining edge behind the working terrace.
	for n: int in range(17):
		var x: float = -16.0 + float(n) * 2.0
		_rock(Vector3(x, 0.85, -12.3 + _rng.randf_range(-0.6, 0.6)), Vector3(1.8, _rng.randf_range(1.3, 3.6), 1.55), n % 3)
	for side: int in [-1, 1]:
		for n: int in range(8):
			_pine(Vector3(side * _rng.randf_range(16.0, 24.0), -0.25, -11.0 + float(n) * 5.0), _rng.randf_range(3.6, 7.0))
		for z: int in range(-10, 12, 3):
			_box(self, Vector3(side * 12.1, 0.78, float(z)), Vector3(0.17, 1.55, 0.17), "wood_dark")
		for h: float in [0.65, 1.14]:
			_box(self, Vector3(side * 12.1, h, 0.7), Vector3(0.08, 0.095, 22.0), "wood")
	for x: float in [-10.5, -7.5, -3.8, 3.8, 7.5, 10.5]:
		_box(self, Vector3(x, 0.77, 10.75), Vector3(0.16, 1.54, 0.16), "wood_dark")
	for side: int in [-1, 1]:
		for h: float in [0.65, 1.14]:
			_box(self, Vector3(side * 7.1, h, 10.75), Vector3(7.4, 0.10, 0.09), "wood")
	# Open-sided canvas work bays leave the mountain view unobstructed.
	_canopy(Vector3(-8.15, 0, -0.1), Vector2(4.1, 11.2), 3.75)
	_canopy(Vector3(8.15, 0, -2.4), Vector2(4.1, 7.8), 3.75)
	_canopy(Vector3(8.0, 0, 4.55), Vector2(6.6, 4.2), 3.9)
	_canopy(Vector3(0, 0, -8.5), Vector2(4.3, 3.5), 3.7)
	for side: int in [-1, 1]:
		_box(self, Vector3(side * 8.2, 0.02, -0.1), Vector3(4.2, 0.045, 11.4), "wood_dark")
	_box(self, Vector3(8.0, 0.02, 4.55), Vector3(6.55, 0.05, 4.15), "wood_dark")
	# Hand-built trailhead board, with text attached to the board rather than the camera.
	var trailhead := Node3D.new()
	trailhead.position = Vector3(-2.35, 0, 9.9)
	trailhead.rotation.y = PI
	add_child(trailhead)
	for x: float in [-0.9, 0.9]:
		_box(trailhead, Vector3(x, 1.08, 0), Vector3(0.14, 2.2, 0.16), "wood_dark")
	_box(trailhead, Vector3(0, 1.75, 0), Vector3(2.18, 0.89, 0.13), "sign")
	_label(trailhead, "DIAMOND IN THE ROUGH", Vector3(0, 1.96, 0.071), 27, Color("e9dfc8")).pixel_size = 0.0029
	_label(trailhead, "ALPINE SORTING CAMP", Vector3(0, 1.67, 0.071), 18, Color("c6baa1")).pixel_size = 0.0036
	_label(trailhead, "Search the scree. Keep what matters.", Vector3(0, 1.44, 0.071), 16, Color("c6baa1")).pixel_size = 0.0031
	# Angular gravel makes the terrace belong to the landscape.
	for n: int in range(90):
		var x: float = _rng.randf_range(-11.4, 11.4)
		var z: float = _rng.randf_range(-10.4, 10.0)
		if absf(x) < 6.3 and z > -6.0 and z < 2.3:
			continue
		_rock(Vector3(x, 0.025, z), Vector3(_rng.randf_range(0.05, 0.17), 0.06, _rng.randf_range(0.07, 0.20)), n % 3)

func _canopy(at: Vector3, footprint: Vector2, height: float) -> void:
	var canopy := Node3D.new()
	canopy.position = at
	add_child(canopy)
	for x: float in [-footprint.x * 0.48, footprint.x * 0.48]:
		for z: float in [-footprint.y * 0.46, footprint.y * 0.46]:
			_box(canopy, Vector3(x, height * 0.5, z), Vector3(0.14, height, 0.14), "wood_dark")
	for z: float in [-footprint.y * 0.47, footprint.y * 0.47]:
		_box(canopy, Vector3(0, height - 0.14, z), Vector3(footprint.x, 0.13, 0.13), "wood_dark")
	for side: int in [-1, 1]:
		var roof: MeshInstance3D = _box(canopy, Vector3(side * footprint.x * 0.25, height + 0.15, 0), Vector3(footprint.x * 0.54, 0.065, footprint.y), "canvas")
		roof.rotation.z = -side * 0.16

func _mountain(at: Vector3, radius: float, height: float, seed_number: int, snowy: bool) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = seed_number
	var rings: Array = []
	var levels: Array[float] = [0.0, 0.18, 0.40, 0.62, 0.81, 0.96]
	for ring: int in range(levels.size()):
		var points: Array[Vector3] = []
		for n: int in range(14):
			var angle: float = float(n) / 14.0 * TAU
			var taper: float = pow(1.0 - levels[ring], 0.80)
			var extent: float = radius * taper * random.randf_range(0.83, 1.15)
			var y: float = height * levels[ring] + random.randf_range(-0.5, 0.5) * float(ring > 0)
			points.append(Vector3(cos(angle) * extent + levels[ring] * radius * 0.10, y, sin(angle) * extent * 0.80))
		rings.append(points)
	var meshes: Array = [[], [], [], []]
	for ring: int in range(rings.size() - 1):
		for n: int in range(14):
			var next: int = (n + 1) % 14
			var color_index: int = random.randi_range(0, 2)
			if snowy and ring >= 3:
				color_index = 3 if ring >= 4 or n % 4 == 0 else random.randi_range(0, 2)
			meshes[color_index].append([rings[ring][n], rings[ring + 1][n], rings[ring + 1][next]])
			meshes[color_index].append([rings[ring][n], rings[ring + 1][next], rings[ring][next]])
	for n: int in range(14):
		meshes[3 if snowy else 1].append([rings[-1][n], Vector3(radius * 0.1, height * 1.035, 0), rings[-1][(n + 1) % 14]])
	for material_index: int in range(meshes.size()):
		var mountain := MeshInstance3D.new()
		mountain.mesh = _face_mesh(meshes[material_index])
		mountain.material_override = _materials[["rock", "rock_light", "rock_dark", "snow"][material_index]]
		mountain.position = at
		mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mountain)

func _face_mesh(faces: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for face: Array in faces:
		var a: Vector3 = face[0]
		var b: Vector3 = face[1]
		var c: Vector3 = face[2]
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		for point: Vector3 in [a, b, c]:
			vertices.append(point)
			normals.append(normal)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _rock(at: Vector3, size: Vector3, shade: int = 0) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.3
	sphere.radial_segments = 5
	sphere.rings = 2
	mesh.mesh = sphere
	mesh.material_override = _materials[["rock", "rock_light", "rock_dark"][shade % 3]]
	mesh.position = at
	mesh.scale = size
	mesh.rotation = Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-PI, PI), _rng.randf_range(-0.15, 0.15))
	add_child(mesh)

func _pine(at: Vector3, height: float) -> void:
	_cylinder(self, at + Vector3(0, height * 0.35, 0), 0.07, 0.14, height * 0.7, "wood_dark", 6)
	for tier: int in range(3):
		_cylinder(self, at + Vector3(0, height * (0.39 + tier * 0.17), 0), 0.0, height * (0.20 - tier * 0.034), height * 0.49, "pine" if tier % 2 == 0 else "pine_dark", 7)

func _window(at: Vector3, side: int) -> void:
	_box(self, at, Vector3(0.055, 1.62, 3.1), "window")
	_box(self, at + Vector3(-side * 0.055, 0, 0), Vector3(0.07, 1.72, 0.1), "wood_dark")
	for dz: float in [-1.59, 1.59]:
		_box(self, at + Vector3(-side * 0.05, 0, dz), Vector3(0.1, 1.78, 0.11), "wood_dark")
	for dy: float in [-0.87, 0.0, 0.87]:
		_box(self, at + Vector3(-side * 0.05, dy, 0), Vector3(0.1, 0.10, 3.25), "wood_dark")

func _lamp(at: Vector3) -> void:
	_cylinder(self, at + Vector3(0, 0.45, 0), 0.03, 0.03, 0.9, "dark", 6)
	_cylinder(self, at, 0.48, 0.24, 0.3, "brass", 10)
	_cylinder(self, at + Vector3(0, -0.16, 0), 0.38, 0.38, 0.025, "light", 10)

func _pile_height(x: float, z: float) -> float:
	# Gentle continuous ramps, with a peak towards the quarry face. Every sector is walkable.
	var x_profile: float = maxf(0.0, 1.0 - pow(absf(x) / 6.4, 2.0))
	var z_profile: float = maxf(0.0, 1.0 - pow((z + 2.7) / 4.8, 2.0))
	return 0.03 + 2.65 * x_profile * z_profile

func _build_pile() -> void:
	for row: int in range(3):
		for col: int in range(4):
			var center := Vector3(-4.5 + float(col) * 3.0, 0, -4.4 + float(row) * 2.4)
			center.y = _pile_height(center.x, center.z)
			pile_centers.append(center)
			var sector_id: int = row * 4 + col
			var body := StaticBody3D.new()
			body.name = "PileSector_%s" % sector_id
			body.set_meta("pile", sector_id)
			body.add_to_group("pile_sectors")
			add_child(body)
			var faces: Array = []
			var span_x: float = 3.0
			var span_z: float = 2.4
			for sx: int in range(6):
				for sz: int in range(5):
					var x0: float = center.x - span_x * 0.5 + float(sx) * span_x / 6.0
					var x1: float = x0 + span_x / 6.0
					var z0: float = center.z - span_z * 0.5 + float(sz) * span_z / 5.0
					var z1: float = z0 + span_z / 5.0
					var a := Vector3(x0, _pile_height(x0, z0), z0)
					var b := Vector3(x1, _pile_height(x1, z0), z0)
					var c := Vector3(x1, _pile_height(x1, z1), z1)
					var d := Vector3(x0, _pile_height(x0, z1), z1)
					faces.append([a, c, b])
					faces.append([a, d, c])
			var mesh: ArrayMesh = _face_mesh(faces)
			var surface := MeshInstance3D.new()
			surface.mesh = mesh
			surface.material_override = _materials["gravel" if sector_id % 3 == 0 else "rock_light"]
			body.add_child(surface)
			var collider := CollisionShape3D.new()
			collider.shape = mesh.create_trimesh_shape()
			collider.shape.backface_collision = true
			body.add_child(collider)
	# Feather the hill into the camp floor so its edges are climbable instead of steps.
	var rim_faces: Array = []
	for side: int in [-1, 1]:
		for n: int in range(18):
			var z0: float = -5.6 + n * 0.4
			var z1: float = z0 + 0.4
			var inner_x: float = side * 6.0
			var outer_x: float = side * 6.5
			rim_faces.append([Vector3(inner_x, _pile_height(inner_x, z0), z0), Vector3(inner_x, _pile_height(inner_x, z1), z1), Vector3(outer_x, 0.025, z0)])
			rim_faces.append([Vector3(inner_x, _pile_height(inner_x, z1), z1), Vector3(outer_x, 0.025, z1), Vector3(outer_x, 0.025, z0)])
	for edge: float in [-5.6, 1.6]:
		var outer_z: float = -7.0 if edge < 0 else 2.4
		for n: int in range(24):
			var x0: float = -6.0 + n * 0.5
			var x1: float = x0 + 0.5
			rim_faces.append([Vector3(x0, _pile_height(x0, edge), edge), Vector3(x1, _pile_height(x1, edge), edge), Vector3(x0, 0.025, outer_z)])
			rim_faces.append([Vector3(x1, _pile_height(x1, edge), edge), Vector3(x1, 0.025, outer_z), Vector3(x0, 0.025, outer_z)])
	for face: Array in rim_faces:
		if (face[1] - face[0]).cross(face[2] - face[0]).y < 0.0:
			var swap: Vector3 = face[1]
			face[1] = face[2]
			face[2] = swap
	var rim_sectors: Dictionary = {}
	for face: Array in rim_faces:
		var center: Vector3 = (face[0] + face[1] + face[2]) / 3.0
		var col: int = clampi(roundi((center.x + 4.5) / 3.0), 0, 3)
		var row: int = clampi(roundi((center.z + 4.4) / 2.4), 0, 2)
		var sector: int = row * 4 + col
		if not rim_sectors.has(sector):
			rim_sectors[sector] = []
		rim_sectors[sector].append(face)
	for sector: int in rim_sectors:
		var rim_mesh: ArrayMesh = _face_mesh(rim_sectors[sector])
		var rim := MeshInstance3D.new()
		rim.mesh = rim_mesh
		rim.material_override = _materials["gravel"]
		var rim_body := StaticBody3D.new()
		rim_body.name = "ScreeEdge_%d" % sector
		rim_body.set_meta("pile", sector)
		rim_body.add_child(rim)
		var rim_collision := CollisionShape3D.new()
		rim_collision.shape = rim_mesh.create_trimesh_shape()
		rim_collision.shape.backface_collision = true
		rim_body.add_child(rim_collision)
		add_child(rim_body)
	# Hundreds of dull stones and occasional glass glints are embedded in the scree.
	var colors: Array[Color] = [Color("85877b"), Color("a6aca1"), Color("788781"), Color("8a8177"), Color("b2b6a7"), Color("87999c")]
	for color_index: int in range(colors.size()):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = gem_mesh()
		mm.instance_count = 215
		var stones := MultiMeshInstance3D.new()
		stones.name = "ScreeStones_%s" % color_index
		stones.multimesh = mm
		stones.material_override = _material(colors[color_index], 0.16 if color_index == 5 else 0.0, 0.50 if color_index == 5 else 0.93)
		stones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(stones)
		for n: int in range(mm.instance_count):
			var x: float = _rng.randf_range(-6.13, 6.13)
			var z: float = _rng.randf_range(-5.6, 1.6)
			var size: float = _rng.randf_range(0.13, 0.31)
			var basis: Basis = Basis.from_euler(Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-PI, PI), _rng.randf_range(-1.5, 1.5)))
			basis = basis.scaled(Vector3(size, size * _rng.randf_range(0.5, 0.8), size))
			mm.set_instance_transform(n, Transform3D(basis, Vector3(x, _pile_height(x, z) + 0.035, z)))
	var marker := Node3D.new()
	marker.position = Vector3(-4.5, 0, 2.8)
	add_child(marker)
	_box(marker, Vector3(0, 0.6, 0), Vector3(0.08, 1.25, 0.09), "wood_dark")
	_box(marker, Vector3(0, 0.98, 0), Vector3(1.35, 0.35, 0.09), "sign")
	_label(marker, "GEM SCREE", Vector3(0, 0.98, 0.05), 26, Color("e8ddc2")).pixel_size = 0.0035

func _build_stations() -> void:
	_station("sell", Vector3(-8, 1, 4), "SCRAP EXCHANGE", "", "orange")
	_station("shop", Vector3(8, 1, 4), "CAMP OUTFITTER", "", "orange")
	_station("tray", Vector3(-8, 1, 0), "INSPECTION TRAY", "GOOD GEMS DESERVE A SECOND LOOK", "mint")
	_station("wash", Vector3(-8, 1, -4), "WASHING STATION", "", "window")
	_station("sorter", Vector3(8, 1, -4), "BATCH SORTER", "", "orange")
	_station("certify", Vector3(0, 1, -8), "CERTIFICATION BENCH", "REAL PROOF. REAL DIAMOND.", "brass")
	_station("scanner", Vector3(8, 1, 0), "CANDIDATE SCANNER", "", "pink")
	_station("recover", Vector3(-5, 1, 8), "LOST & FOUND", "NO GEM LEFT BEHIND", "orange")
	_station("collection", Vector3(5, 1, 8), "SPECIMEN COLLECTION", "", "pink")
	_build_sell()
	_build_shop()
	_build_tray()
	_build_wash()
	_build_sorter()
	_build_scanner()
	_build_certify()
	_build_recovery()
	_build_collection()
	_build_conveyor()

func _station(id: String, at: Vector3, title: String, _subtitle: String, _accent: String) -> void:
	stations[id] = at
	var body := StaticBody3D.new()
	body.name = "Station_%s" % id
	body.position = Vector3(at.x, 0, at.z)
	body.set_meta("station", id)
	body.add_to_group("stations")
	if id != "shop":
		if at.x < -6.0:
			body.rotation.y = PI / 2.0
		elif at.x > 6.0:
			body.rotation.y = -PI / 2.0
		elif at.z > 5.0:
			body.rotation.y = PI
	add_child(body)
	if id == "shop":
		_box(body, Vector3(0, 0.38, -0.58), Vector3(2.0, 0.74, 0.45), "wood_dark")
	else:
		for x: float in [-1.22, 1.22]:
			_box(body, Vector3(x, 0.48, 0), Vector3(0.14, 0.96, 1.56), "wood_dark")
		_box(body, Vector3(0, 0.42, -0.6), Vector3(2.55, 0.15, 0.12), "wood_dark")
		_box(body, Vector3(0, 0.99, 0), Vector3(2.82, 0.12, 1.7), "wood")
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.82, 1.05, 1.7) if id != "shop" else Vector3(2.0, 0.74, 0.45)
	var collision := CollisionShape3D.new()
	collision.position = Vector3(0, 0.525, 0) if id != "shop" else Vector3(0, 0.37, -0.58)
	collision.shape = shape
	body.add_child(collision)
	# Fixed boards mounted to timber uprights above the bench.
	for x: float in [-1.1, 1.1]:
		_box(body, Vector3(x, 1.68, -0.82), Vector3(0.085, 1.37, 0.085), "wood_dark")
	_box(body, Vector3(0, 2.1, -0.82), Vector3(2.62, 0.55, 0.085), "sign")
	var sign: Label3D = _label(body, title, Vector3(0, 2.19, -0.772), 27, Color("e8ddc2"))
	sign.pixel_size = 0.0034
	var status: Label3D = _label(body, "", Vector3(0, 1.98, -0.772), 17, Color("c6baa1"))
	status.pixel_size = 0.0035
	status.name = "Status"

func _station_node(id: String) -> Node3D:
	return get_node("Station_%s" % id) as Node3D

func _build_sell() -> void:
	var node: Node3D = _station_node("sell")
	_box(node, Vector3(-0.4, 1.21, 0), Vector3(1.45, 0.32, 1.3), "steel")
	_box(node, Vector3(-0.4, 1.40, 0), Vector3(1.16, 0.10, 1.03), "dark")
	_box(node, Vector3(0.87, 1.3, 0), Vector3(0.68, 0.58, 0.60), "mint")
	_box(node, Vector3(0.87, 1.45, 0.315), Vector3(0.5, 0.22, 0.02), "dark")
	_label(node, "$", Vector3(0.87, 1.46, 0.336), 44, Color("b5ffe0"))
	for n: int in range(5):
		_cylinder(node, Vector3(0.8 + float(n % 2) * 0.16, 1.62 + n * 0.034, 0.1), 0.10, 0.10, 0.024, "brass", 12)

func _build_shop() -> void:
	# Each item is a physical purchase target. Cards belong to its plinth.
	var ids: Array[String] = ["scoop", "trays", "loupe", "wash", "sorter", "vacuum", "conveyor", "scanner"]
	for index: int in range(ids.size()):
		var id: String = ids[index]
		var x: float = 5.95 + float(index % 4) * 1.40
		var z: float = 5.62 if index < 4 else 3.57
		var pedestal := StaticBody3D.new()
		pedestal.name = "Product_%s" % id
		pedestal.position = Vector3(x, 0, z)
		pedestal.set_meta("upgrade", id)
		pedestal.add_to_group("upgrade_displays")
		add_child(pedestal)
		upgrade_positions[id] = Vector3(x, 0.9, z)
		var base_height: float = 0.98 if index < 4 else 1.38
		for side: float in [-0.49, 0.49]:
			_box(pedestal, Vector3(side, base_height * 0.5, 0), Vector3(0.11, base_height, 0.90), "wood_dark")
		_box(pedestal, Vector3(0, base_height, 0), Vector3(1.26, 0.10, 1.04), "wood")
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.24, base_height + 0.80, 1.02)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = shape.size.y * 0.5
		pedestal.add_child(collision)
		_box(pedestal, Vector3(0, base_height - 0.25, 0.525), Vector3(1.22, 0.40, 0.045), "sign")
		var name_card: Label3D = _label(pedestal, get_upgrade_name(id), Vector3(0, base_height - 0.16, 0.552), 24, Color("eee5ce"))
		name_card.pixel_size = 0.0031
		var price: Label3D = _label(pedestal, "$%d" % int(_game.state.prices.get(id, 0)), Vector3(0, base_height - 0.33, 0.552), 22, Color("e9b866"))
		price.pixel_size = 0.0034
		_product_cards[id] = price
		var model := Node3D.new()
		model.position.y = base_height + 0.08
		pedestal.add_child(model)
		_product_model(model, id)

func _product_model(model: Node3D, id: String) -> void:
	match id:
		"scoop":
			var handle: MeshInstance3D = _cylinder(model, Vector3(0.12, 0.36, -0.12), 0.055, 0.055, 0.64, "wood_dark", 8)
			handle.rotation.x = -0.48
			_box(model, Vector3(0.02, 0.08, 0.15), Vector3(0.69, 0.08, 0.48), "brass")
			for side: float in [-0.32, 0.32]:
				_box(model, Vector3(side + 0.02, 0.17, 0.15), Vector3(0.07, 0.2, 0.48), "brass")
			_box(model, Vector3(0.02, 0.15, -0.08), Vector3(0.68, 0.22, 0.055), "brass")
		"trays":
			for n: int in range(3):
				_box(model, Vector3(-0.13 + n * 0.11, 0.06 + n * 0.13, 0), Vector3(0.83, 0.075, 0.62), "steel")
				for side: float in [-0.41, 0.41]:
					_box(model, Vector3(side - 0.13 + n * 0.11, 0.11 + n * 0.13, 0), Vector3(0.04, 0.12, 0.62), "steel")
		"loupe":
			_cylinder(model, Vector3(-0.25, 0.25, -0.12), 0.035, 0.035, 0.52, "brass", 8)
			_box(model, Vector3(-0.07, 0.49, -0.12), Vector3(0.41, 0.04, 0.04), "brass")
			_cylinder(model, Vector3(0.1, 0.44, -0.12), 0.19, 0.11, 0.12, "light", 10)
			var lens: MeshInstance3D = _cylinder(model, Vector3(0.22, 0.11, 0.17), 0.16, 0.16, 0.085, "steel", 12)
			lens.rotation.x = 0.35
			_cylinder(model, Vector3(0.22, 0.16, 0.17), 0.12, 0.12, 0.018, "window", 12)
		"wash":
			_cylinder(model, Vector3(0, 0.15, 0), 0.42, 0.35, 0.28, "steel", 14)
			_cylinder(model, Vector3(0, 0.30, 0), 0.35, 0.35, 0.025, "window", 14)
			_cylinder(model, Vector3(0.29, 0.42, -0.27), 0.035, 0.035, 0.39, "brass", 8)
			var tap: MeshInstance3D = _cylinder(model, Vector3(0.10, 0.61, -0.27), 0.035, 0.035, 0.39, "brass", 8)
			tap.rotation.z = PI / 2.0
		"sorter":
			_box(model, Vector3(0, 0.25, 0), Vector3(0.85, 0.45, 0.64), "orange")
			_box(model, Vector3(0, 0.50, 0), Vector3(0.87, 0.05, 0.68), "dark")
			for n: int in range(5):
				_box(model, Vector3(-0.34 + n * 0.17, 0.535, 0), Vector3(0.045, 0.025, 0.62), "steel")
			for side: float in [-0.24, 0.24]:
				_box(model, Vector3(side, 0.10, 0.4), Vector3(0.33, 0.13, 0.25), "steel")
		"vacuum":
			_cylinder(model, Vector3(0, 0.27, -0.07), 0.29, 0.29, 0.47, "orange", 12)
			_cylinder(model, Vector3(0, 0.52, -0.07), 0.31, 0.31, 0.09, "dark", 12)
			for side: float in [-0.23, 0.23]:
				_sphere(model, Vector3(side, 0.05, -0.07), 0.09, "rubber")
			var hose: MeshInstance3D = _cylinder(model, Vector3(0.23, 0.27, 0.25), 0.055, 0.055, 0.50, "rubber", 8)
			hose.rotation.x = -0.8
			_box(model, Vector3(0.23, 0.09, 0.47), Vector3(0.37, 0.09, 0.13), "steel")
		"conveyor":
			_box(model, Vector3(0, 0.28, 0), Vector3(0.87, 0.14, 0.62), "steel")
			_box(model, Vector3(0, 0.37, 0), Vector3(0.81, 0.045, 0.49), "rubber")
			for n: int in range(6):
				_box(model, Vector3(-0.35 + n * 0.14, 0.40, 0), Vector3(0.035, 0.025, 0.46), "orange")
			for side: float in [-0.33, 0.33]:
				_box(model, Vector3(side, 0.11, 0), Vector3(0.055, 0.28, 0.48), "steel")
		"scanner":
			for side: float in [-0.33, 0.33]:
				_box(model, Vector3(side, 0.27, 0), Vector3(0.12, 0.51, 0.58), "steel")
			_box(model, Vector3(0, 0.56, 0), Vector3(0.80, 0.14, 0.58), "steel")
			_box(model, Vector3(0, 0.06, 0), Vector3(0.79, 0.07, 0.56), "rubber")
			_box(model, Vector3(0, 0.49, 0), Vector3(0.52, 0.027, 0.09), "light")
			_box(model, Vector3(0.20, 0.56, 0.3), Vector3(0.22, 0.08, 0.015), "dark")

func _build_tray() -> void:
	var node: Node3D = _station_node("tray")
	for x: float in [-0.73, 0.0, 0.73]:
		for z: float in [-0.36, 0.36]:
			_box(node, Vector3(x, 1.12, z), Vector3(0.62, 0.09, 0.54), "steel")
			_box(node, Vector3(x, 1.17, z), Vector3(0.53, 0.025, 0.44), "rubber")
	_cylinder(node, Vector3(-1.2, 1.4, -0.56), 0.036, 0.036, 0.7, "brass", 8)
	_box(node, Vector3(-0.92, 1.73, -0.56), Vector3(0.65, 0.065, 0.065), "brass")
	_cylinder(node, Vector3(-0.6, 1.69, -0.56), 0.19, 0.10, 0.13, "light", 10)

func _machine_setup(id: String) -> Node3D:
	var station: Node3D = _station_node(id)
	var machine := Node3D.new()
	machine.name = "Machine"
	station.add_child(machine)
	var machine_body := StaticBody3D.new()
	machine_body.set_meta("station", id)
	var machine_shape := BoxShape3D.new()
	machine_shape.size = Vector3(1.70, 0.76, 0.10)
	var machine_collision := CollisionShape3D.new()
	machine_collision.shape = machine_shape
	machine_collision.position = Vector3(0, 1.43, -0.65)
	machine_body.add_child(machine_collision)
	machine.add_child(machine_body)
	_box(machine, Vector3(0, 1.43, -0.65), Vector3(1.70, 0.76, 0.10), "steel")
	var notice: Label3D = _label(station, "EQUIPMENT BAY", Vector3(0, 1.01, 0.22), 18, Color("c8b58f"), Vector3(-PI / 2.0, 0, 0))
	notice.pixel_size = 0.0032
	_machines[id] = {"node": machine, "notice": notice, "status": station.get_node("Status"), "collision": machine_collision}
	return machine

func _build_wash() -> void:
	var node: Node3D = _machine_setup("wash")
	var bubbles: Array = []
	_cylinder(node, Vector3(0, 1.2, 0), 0.70, 0.64, 0.3, "steel", 20)
	_cylinder(node, Vector3(0, 1.37, 0), 0.59, 0.59, 0.035, "window", 20)
	_cylinder(node, Vector3(0.94, 1.41, -0.44), 0.046, 0.046, 0.74, "brass", 8)
	var faucet: MeshInstance3D = _cylinder(node, Vector3(0.70, 1.78, -0.44), 0.046, 0.046, 0.50, "brass", 8)
	faucet.rotation.z = PI / 2.0
	_cylinder(node, Vector3(0.45, 1.72, -0.44), 0.058, 0.058, 0.14, "brass", 8)
	for n: int in range(7):
		bubbles.append(_sphere(node, Vector3(_rng.randf_range(-0.4, 0.4), 1.40, _rng.randf_range(-0.38, 0.38)), _rng.randf_range(0.07, 0.13), "white"))
	_moving_parts["wash"] = bubbles
	_box(node, Vector3(-1.04, 1.28, -0.2), Vector3(0.25, 0.44, 0.27), "pink")
	_label(node, "FOAM", Vector3(-1.04, 1.27, -0.058), 10, Color("fff5d8"))

func _build_sorter() -> void:
	var node: Node3D = _machine_setup("sorter")
	var gears: Array = []
	_box(node, Vector3(0, 1.43, -0.1), Vector3(1.82, 0.74, 1.19), "orange")
	_box(node, Vector3(0, 1.82, -0.1), Vector3(1.59, 0.05, 0.97), "dark")
	for n: int in range(7):
		_box(node, Vector3(-0.66 + n * 0.22, 1.86, -0.1), Vector3(0.045, 0.025, 0.95), "steel")
	for x: float in [-0.66, 0.66]:
		_box(node, Vector3(x, 1.2, 0.73), Vector3(0.58, 0.23, 0.40), "steel")
		_box(node, Vector3(x, 1.33, 0.73), Vector3(0.48, 0.02, 0.32), "dark")
	_box(node, Vector3(0.6, 1.48, 0.518), Vector3(0.12, 0.12, 0.04), "mint")
	_box(node, Vector3(0.38, 1.48, 0.518), Vector3(0.12, 0.12, 0.04), "pink")
	for x: float in [-0.60, 0.60]:
		var gear := Node3D.new()
		gear.position = Vector3(x, 1.50, 0.555)
		gear.rotation.x = PI / 2.0
		node.add_child(gear)
		_cylinder(gear, Vector3.ZERO, 0.20, 0.20, 0.08, "dark", 12)
		for tooth: int in range(5):
			var spoke: MeshInstance3D = _box(gear, Vector3.ZERO, Vector3(0.52, 0.085, 0.055), "brass")
			spoke.rotation.y = tooth * PI / 5.0
		_cylinder(gear, Vector3(0, 0.052, 0), 0.07, 0.07, 0.05, "mint", 8)
		gears.append(gear)
	_moving_parts["sorter"] = gears

func _build_scanner() -> void:
	var node: Node3D = _machine_setup("scanner")
	for x: float in [-0.85, 0.85]:
		_box(node, Vector3(x, 1.48, 0), Vector3(0.25, 0.79, 1.08), "pink")
	_box(node, Vector3(0, 1.9, 0), Vector3(1.96, 0.23, 1.08), "pink")
	_box(node, Vector3(0, 1.14, 0), Vector3(1.68, 0.12, 1.02), "rubber")
	var scanner_beam: MeshInstance3D = _box(node, Vector3(0, 1.75, -0.04), Vector3(1.3, 0.05, 0.16), "mint")
	_moving_parts["scanner"] = [scanner_beam]
	_box(node, Vector3(1.15, 1.25, 0.28), Vector3(0.34, 0.38, 0.43), "dark")
	_box(node, Vector3(1.15, 1.34, 0.507), Vector3(0.24, 0.20, 0.025), "mint")

func _build_certify() -> void:
	var node: Node3D = _station_node("certify")
	_box(node, Vector3(0, 1.1, 0), Vector3(1.44, 0.12, 1.2), "rubber")
	_box(node, Vector3(0, 1.16, 0), Vector3(0.7, 0.028, 0.7), "brass")
	_box(node, Vector3(0, 1.19, 0), Vector3(0.59, 0.018, 0.59), "dark")
	_cylinder(node, Vector3(0.93, 1.42, -0.40), 0.06, 0.06, 0.76, "brass", 10)
	var arm: MeshInstance3D = _cylinder(node, Vector3(0.61, 1.8, -0.40), 0.06, 0.06, 0.68, "brass", 10)
	arm.rotation.z = PI / 2.0
	_cylinder(node, Vector3(0.24, 1.73, -0.4), 0.26, 0.16, 0.18, "light", 12)
	_box(node, Vector3(-0.91, 1.2, 0.2), Vector3(0.46, 0.28, 0.63), "white")
	_omni(stations["certify"] + Vector3(0, 1.3, 0), Color("fff2c8"), 0.8, 3.5)

func _build_recovery() -> void:
	var node: Node3D = _station_node("recover")
	_box(node, Vector3(0, 1.36, -0.10), Vector3(1.5, 0.6, 1.10), "orange")
	_box(node, Vector3(0, 1.69, -0.10), Vector3(1.63, 0.08, 1.20), "brass")
	_box(node, Vector3(0, 1.53, 0.475), Vector3(0.97, 0.11, 0.03), "dark")

func _build_collection() -> void:
	var node: Node3D = _station_node("collection")
	_box(node, Vector3(0, 1.37, -0.52), Vector3(2.58, 0.6, 0.12), "wall_light")
	for x: float in [-0.87, 0.0, 0.87]:
		_cylinder(node, Vector3(x, 1.15, 0.1), 0.30, 0.33, 0.18, "brass", 12)
		_cylinder(node, Vector3(x, 1.27, 0.1), 0.27, 0.27, 0.08, "dark", 12)

func _build_conveyor() -> void:
	var node := Node3D.new()
	node.name = "ConveyorUpgrade"
	add_child(node)
	node.position = Vector3(6.65, 0, -2.0)
	var body := StaticBody3D.new()
	body.set_meta("station", "sorter")
	body.set_meta("conveyor", true)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.98, 0.93, 4.6)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.465
	body.add_child(collision)
	node.add_child(body)
	_box(node, Vector3(0, 0.8, 0), Vector3(0.98, 0.14, 4.6), "steel")
	_box(node, Vector3(0, 0.895, 0), Vector3(0.80, 0.06, 4.55), "rubber")
	for n: int in range(13):
		_belt_slats.append(_box(node, Vector3(0, 0.938, -2.10 + n * 0.35), Vector3(0.78, 0.035, 0.05), "orange"))
	for x: float in [-0.53, 0.53]:
		_box(node, Vector3(x, 1.00, 0), Vector3(0.06, 0.19, 4.66), "brass")
		for z: float in [-1.8, 1.8]:
			_box(node, Vector3(x, 0.43, z), Vector3(0.09, 0.72, 0.10), "steel")
	_machines["conveyor"] = {"node": node, "collision": collision}

func _build_props() -> void:
	# Practical camp supplies: a few timber crates, sacks and a water barrel.
	for side: int in [-1, 1]:
		for n: int in range(3):
			var at := Vector3(side * 10.7, 0.3 + (n % 2) * 0.58, -8.2 + int(n / 2) * 0.8)
			_box(self, at, Vector3(0.9, 0.58, 0.72), "wood")
			for y: float in [-0.15, 0.15]:
				_box(self, at + Vector3(0, y, 0.37), Vector3(0.9, 0.04, 0.025), "wood_dark")
			for x: float in [-0.35, 0.35]:
				_box(self, at + Vector3(x, 0, 0.37), Vector3(0.05, 0.56, 0.025), "wood_dark")
	_cylinder(self, Vector3(-10.4, 0.56, 6.8), 0.47, 0.43, 1.1, "steel", 12)
	for y: float in [0.18, 0.86]:
		_cylinder(self, Vector3(-10.4, y, 6.8), 0.48, 0.48, 0.05, "dark", 12)
	var expansion := Node3D.new()
	expansion.name = "ExpansionSupplies"
	add_child(expansion)
	for n: int in range(5):
		_box(expansion, Vector3(-9.0 + n * 0.43, 0.21, -9.45), Vector3(0.35, 0.41, 0.32), "canvas")
		_cylinder(expansion, Vector3(-9.0 + n * 0.43, 0.44, -9.45), 0.055, 0.06, 0.06, "dark", 8)
	# A small loading cart beside the entrance.
	_box(self, Vector3(8.8, 0.38, 9.55), Vector3(1.8, 0.13, 0.95), "wood")
	for x: float in [8.08, 9.52]:
		for z: float in [9.24, 9.86]:
			_sphere(self, Vector3(x, 0.18, z), 0.16, "rubber")
	_box(self, Vector3(8.8, 0.67, 9.05), Vector3(1.78, 0.56, 0.07), "wood_dark")

func _box(parent: Node3D, at: Vector3, size: Vector3, material_name: String, collision: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var object := MeshInstance3D.new()
	object.mesh = mesh
	object.material_override = _materials[material_name]
	object.position = at
	parent.add_child(object)
	if collision:
		var body := StaticBody3D.new()
		body.position = at
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		parent.add_child(body)
	return object

func _cylinder(parent: Node3D, at: Vector3, top: float, bottom: float, height: float, material_name: String, sides: int = 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	var object := MeshInstance3D.new()
	object.mesh = mesh
	object.material_override = _materials[material_name]
	object.position = at
	parent.add_child(object)
	return object

func _sphere(parent: Node3D, at: Vector3, radius: float, material_name: String) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var object := MeshInstance3D.new()
	object.mesh = mesh
	object.material_override = _materials[material_name]
	object.position = at
	parent.add_child(object)
	return object

func _label(parent: Node3D, text: String, at: Vector3, font_size: int, color: Color, rotation: Vector3 = Vector3.ZERO) -> Label3D:
	var label := Label3D.new()
	label.font=_sign_font
	label.text = text
	label.position = at
	label.rotation = rotation
	label.font_size = font_size
	label.pixel_size = 0.0035
	label.modulate = color
	label.outline_modulate = Color("242925")
	label.outline_size = 0
	label.no_depth_test = false
	label.shaded = false
	parent.add_child(label)
	return label

static func gem_mesh() -> ArrayMesh:
	if _shared_gem_mesh != null:
		return _shared_gem_mesh
	var faces: Array = []
	var crown: Array[Vector3] = []
	var girdle: Array[Vector3] = []
	for n: int in range(8):
		var a: float = float(n) * TAU / 8.0
		crown.append(Vector3(cos(a) * 0.39, 0.43, sin(a) * 0.39))
		girdle.append(Vector3(cos(a) * 0.68, 0.04, sin(a) * 0.68))
	for n: int in range(8):
		var next: int = (n + 1) % 8
		faces.append([Vector3(0, 0.43, 0), crown[next], crown[n]])
		faces.append([crown[n], crown[next], girdle[next]])
		faces.append([crown[n], girdle[next], girdle[n]])
		faces.append([girdle[n], girdle[next], Vector3(0, -0.73, 0)])
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for face: Array in faces:
		var a: Vector3 = face[0]
		var b: Vector3 = face[1]
		var c: Vector3 = face[2]
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		vertices.append(a)
		vertices.append(b)
		vertices.append(c)
		normals.append(normal)
		normals.append(normal)
		normals.append(normal)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	_shared_gem_mesh = ArrayMesh.new()
	_shared_gem_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _shared_gem_mesh

static func make_gem(kind: String) -> Node3D:
	var visual := Node3D.new()
	visual.name = "GemVisual"
	var material: StandardMaterial3D
	var mesh: Mesh
	if kind in ["metal", "scrap"]:
		var scrap := PrismMesh.new()
		scrap.size = Vector3(0.76, 0.58, 0.54)
		mesh = scrap
		material = _material(Color("bcab78"), 0.82, 0.24)
	elif kind == "cash":
		var banknote := BoxMesh.new()
		banknote.size = Vector3(0.82, 0.13, 0.42)
		mesh = banknote
		material = _material(Color("8dd396"), 0.05, 0.73)
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.15, 0.14, 0.44)
		band.mesh = band_mesh
		band.material_override = _material(Color("f6ebc5"))
		visual.add_child(band)
	elif kind in ["oddity", "useless"]:
		var bolt := TorusMesh.new()
		bolt.inner_radius = 0.17
		bolt.outer_radius = 0.41
		bolt.rings = 8
		bolt.ring_segments = 6
		mesh = bolt
		material = _material(Color("dba864"), 0.67, 0.30)
	elif kind == "collectible":
		mesh = gem_mesh()
		material = _material(Color("f7a1cf"), 0.43, 0.16, 0.20)
		var halo := MeshInstance3D.new()
		var halo_mesh := TorusMesh.new()
		halo_mesh.inner_radius = 0.63
		halo_mesh.outer_radius = 0.71
		halo_mesh.rings = 14
		halo_mesh.ring_segments = 6
		halo.mesh = halo_mesh
		halo.material_override = _material(Color("ffca66"), 0.78, 0.19)
		halo.rotation.z = 0.38
		visual.add_child(halo)
	elif kind in ["diamond", "suspect"]:
		mesh = gem_mesh()
		material = _material(Color("c1eee6"), 0.43, 0.13)
	elif kind == "crystal":
		mesh = gem_mesh()
		material = _material(Color("c58dc9"), 0.35, 0.18)
	else:
		mesh = gem_mesh()
		material = _material(Color("82c6dc"), 0.3, 0.22)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	visual.add_child(instance)
	return visual
