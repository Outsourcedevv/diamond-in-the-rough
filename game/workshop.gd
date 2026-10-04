extends Node3D
class_name RoughWorkshop

const SHOP_ORDER: Array[String] = ["steel_pick", "satchel", "loupe", "dynamite", "magnet", "drill", "tnt", "sonar", "buster"]

var stations: Dictionary = {}
var upgrade_positions: Dictionary = {}
var _product_cards: Dictionary = {}
var _materials: Dictionary = {}
var _sign_font: SystemFont
var _game: Node
var _rng := RandomNumberGenerator.new()
static var _shared_gem_mesh: ArrayMesh

func build(game: Node) -> void:
	_game = game
	name = "MountainQuarry"
	_rng.seed = 408916
	_make_materials()
	_build_environment()
	_build_room()
	_build_stations()
	_build_props()
	update_upgrades([])

func update_upgrades(upgrades: Array) -> void:
	for id: String in _product_cards:
		var card: Label3D = _product_cards[id]
		card.text = "OWNED" if id in upgrades else "$%d" % int(_game.state.prices.get(id, 0))
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
	sunlight.shadow_bias = 0.08
	sunlight.shadow_normal_bias = 2.2
	sunlight.directional_shadow_max_distance = 110.0
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
	_box(self, Vector3(0, -0.32, -90), Vector3(1400.0, 0.6, 1400.0), "floor_alt", true)
	# Distant peaks frame the mineable mountain without touching its blocks.
	_mountain(Vector3(-150, -1.0, -112), 42.0, 52.0, 41, true)
	_mountain(Vector3(152, -1.0, -124), 46.0, 58.0, 42, true)
	_mountain(Vector3(-10, -1.0, -252), 72.0, 84.0, 21, true)
	_mountain(Vector3(-104, -1.0, -12), 22.0, 18.0, 29, false)
	_mountain(Vector3(106, -1.0, -18), 23.0, 20.0, 32, false)
	for side: int in [-1, 1]:
		for n: int in range(12):
			_pine(Vector3(side * _rng.randf_range(80.0, 94.0), -0.25, -150.0 + float(n) * 12.0), _rng.randf_range(4.0, 8.0))
		for n: int in range(8):
			_pine(Vector3(side * _rng.randf_range(15.0, 24.0), -0.25, -9.0 + float(n) * 2.6), _rng.randf_range(3.6, 6.0))
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
	_canopy(Vector3(-8.15, 0, 1.9), Vector2(4.1, 7.2), 3.75)
	_canopy(Vector3(8.0, 0, 3.6), Vector2(6.0, 7.2), 3.9)
	_canopy(Vector3(0, 0, -8.5), Vector2(4.3, 3.5), 3.7)
	_box(self, Vector3(-8.2, 0.02, 1.9), Vector3(4.2, 0.045, 7.4), "wood_dark")
	_box(self, Vector3(8.0, 0.02, 3.6), Vector3(5.9, 0.05, 7.1), "wood_dark")
	# Hand-built trailhead board, with text attached to the board rather than the camera.
	var trailhead := Node3D.new()
	trailhead.position = Vector3(-2.35, 0, 9.9)
	trailhead.rotation.y = PI
	add_child(trailhead)
	for x: float in [-0.9, 0.9]:
		_box(trailhead, Vector3(x, 1.08, 0), Vector3(0.14, 2.2, 0.16), "wood_dark")
	_box(trailhead, Vector3(0, 1.75, 0), Vector3(2.18, 0.89, 0.13), "sign")
	_label(trailhead, "DIAMOND IN THE ROUGH", Vector3(0, 1.96, 0.071), 27, Color("e9dfc8")).pixel_size = 0.0029
	_label(trailhead, "ALPINE MINING CLAIM", Vector3(0, 1.67, 0.071), 18, Color("c6baa1")).pixel_size = 0.0036
	_label(trailhead, "Break the mountain. Find the diamond.", Vector3(0, 1.44, 0.071), 16, Color("c6baa1")).pixel_size = 0.0031
	# Angular gravel makes the terrace belong to the landscape.
	for n: int in range(90):
		var x: float = _rng.randf_range(-11.4, 11.4)
		var z: float = _rng.randf_range(-10.4, 10.0)
		if absf(x) < 3.0 and z > 4.0:
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
		# Faces are listed counter-clockwise from outside; Godot draws clockwise
		# front faces, so emit them reversed to keep the outside visible from above.
		for point: Vector3 in [a, c, b]:
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

func _build_stations() -> void:
	_station("sell", Vector3(-8, 1, 4), "SCRAP EXCHANGE", "", "orange")
	_station("shop", Vector3(8, 1, 4), "CAMP OUTFITTER", "", "orange")
	_station("tray", Vector3(-8, 1, 0), "INSPECTION TRAY", "", "mint")
	_station("certify", Vector3(0, 1, -8), "CERTIFICATION BENCH", "", "brass")
	_station("recover", Vector3(-5, 1, 8), "LOST & FOUND", "", "orange")
	_station("collection", Vector3(5, 1, 8), "SPECIMEN COLLECTION", "", "pink")
	_build_sell()
	_build_shop()
	_build_tray()
	_build_certify()
	_build_recovery()
	_build_collection()
	_build_mountain_signs()

func _build_mountain_signs() -> void:
	var board := Node3D.new()
	board.name = "BlastingSign"
	board.position = Vector3(4.6, 0, -10.6)
	add_child(board)
	_box(board, Vector3(0, 0.75, 0), Vector3(0.1, 1.5, 0.1), "wood_dark")
	_box(board, Vector3(0, 1.45, 0), Vector3(1.9, 0.62, 0.08), "orange")
	_label(board, "BLASTING ZONE", Vector3(0, 1.55, 0.045), 26, Color("2d2418")).pixel_size = 0.0032
	_label(board, "Light it, throw it, step back.", Vector3(0, 1.33, 0.045), 16, Color("2d2418")).pixel_size = 0.0034

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
		# The outfitter is a hall of physical displays; it has no counter of its own.
		return
	else:
		for x: float in [-1.22, 1.22]:
			_box(body, Vector3(x, 0.48, 0), Vector3(0.14, 0.96, 1.56), "wood_dark")
		_box(body, Vector3(0, 0.42, -0.6), Vector3(2.55, 0.15, 0.12), "wood_dark")
		_box(body, Vector3(0, 0.99, 0), Vector3(2.82, 0.12, 1.7), "wood")
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.82, 1.05, 1.7)
	var collision := CollisionShape3D.new()
	collision.position = Vector3(0, 0.525, 0)
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
	for index: int in range(SHOP_ORDER.size()):
		var id: String = SHOP_ORDER[index]
		var x: float = 6.4 + float(index % 3) * 1.6
		var z: float = 6.0 - float(index / 3) * 2.4
		var pedestal := StaticBody3D.new()
		pedestal.name = "Product_%s" % id
		pedestal.position = Vector3(x, 0, z)
		pedestal.set_meta("upgrade", id)
		pedestal.add_to_group("upgrade_displays")
		add_child(pedestal)
		upgrade_positions[id] = Vector3(x, 0.9, z)
		var base_height: float = 0.98
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
	var board := Node3D.new()
	board.position = Vector3(8.0, 0, 7.25)
	add_child(board)
	_box(board, Vector3(0, 3.25, 0), Vector3(3.2, 0.55, 0.09), "sign")
	_label(board, "CAMP OUTFITTER", Vector3(0, 3.27, 0.05), 30, Color("e8ddc2")).pixel_size = 0.0034

func _product_model(model: Node3D, id: String) -> void:
	match id:
		"steel_pick":
			var handle: MeshInstance3D = _cylinder(model, Vector3(0, 0.3, 0), 0.035, 0.035, 0.62, "wood", 8)
			handle.rotation.z = 0.5
			var head: MeshInstance3D = _box(model, Vector3(-0.14, 0.55, 0), Vector3(0.62, 0.07, 0.07), "steel")
			head.rotation.z = 0.5 - PI / 2.0 + 0.25
		"satchel":
			_box(model, Vector3(0, 0.2, 0), Vector3(0.62, 0.4, 0.3), "wood")
			_box(model, Vector3(0, 0.34, 0.12), Vector3(0.64, 0.16, 0.1), "wood_dark")
			_box(model, Vector3(0, 0.36, 0.18), Vector3(0.08, 0.08, 0.02), "brass")
			var strap: MeshInstance3D = _cylinder(model, Vector3(0, 0.46, 0), 0.25, 0.25, 0.03, "wood_dark", 14)
			strap.rotation.x = PI / 2.0
		"loupe":
			_cylinder(model, Vector3(-0.25, 0.25, -0.12), 0.035, 0.035, 0.52, "brass", 8)
			_box(model, Vector3(-0.07, 0.49, -0.12), Vector3(0.41, 0.04, 0.04), "brass")
			_cylinder(model, Vector3(0.1, 0.44, -0.12), 0.19, 0.11, 0.12, "light", 10)
			var lens: MeshInstance3D = _cylinder(model, Vector3(0.22, 0.11, 0.17), 0.16, 0.16, 0.085, "steel", 12)
			lens.rotation.x = 0.35
			_cylinder(model, Vector3(0.22, 0.16, 0.17), 0.12, 0.12, 0.018, "window", 12)
		"dynamite":
			_box(model, Vector3(0, 0.08, 0), Vector3(0.7, 0.16, 0.5), "wood")
			for n: int in range(4):
				var stick: Node3D = make_explosive("dynamite")
				stick.position = Vector3(-0.22 + n * 0.15, 0.22, 0)
				stick.rotation.z = 0.12 * (n - 1.5)
				model.add_child(stick)
		"magnet":
			for side: float in [-0.16, 0.16]:
				_box(model, Vector3(side, 0.3, 0), Vector3(0.12, 0.44, 0.14), "pink")
				_box(model, Vector3(side, 0.56, 0), Vector3(0.12, 0.1, 0.14), "steel")
			_box(model, Vector3(0, 0.1, 0), Vector3(0.44, 0.12, 0.14), "pink")
		"drill":
			_box(model, Vector3(0, 0.3, 0), Vector3(0.22, 0.24, 0.52), "orange")
			_box(model, Vector3(0, 0.12, 0.12), Vector3(0.14, 0.3, 0.14), "dark")
			var bit: MeshInstance3D = _cylinder(model, Vector3(0, 0.3, -0.42), 0.0, 0.07, 0.34, "steel", 8)
			bit.rotation.x = -PI / 2.0
		"tnt":
			var crate: MeshInstance3D = _box(model, Vector3(0, 0.22, 0), Vector3(0.62, 0.44, 0.48), "wood")
			crate.name = "Crate"
			_label(model, "TNT", Vector3(0, 0.24, 0.245), 52, Color("b8322a")).pixel_size = 0.004
			var bundle: Node3D = make_explosive("tnt")
			bundle.position = Vector3(0, 0.52, 0)
			model.add_child(bundle)
		"sonar":
			_box(model, Vector3(0, 0.16, 0), Vector3(0.44, 0.3, 0.3), "steel")
			_box(model, Vector3(0, 0.2, 0.152), Vector3(0.3, 0.16, 0.01), "mint")
			var dish: MeshInstance3D = _cylinder(model, Vector3(0, 0.48, 0), 0.26, 0.04, 0.14, "brass", 14)
			dish.rotation.x = -0.5
		"buster":
			var bomb: Node3D = make_explosive("buster")
			bomb.position = Vector3(0, 0.3, 0)
			bomb.scale = Vector3.ONE * 1.25
			model.add_child(bomb)

func _build_tray() -> void:
	var node: Node3D = _station_node("tray")
	for x: float in [-0.73, 0.0, 0.73]:
		for z: float in [-0.36, 0.36]:
			_box(node, Vector3(x, 1.12, z), Vector3(0.62, 0.09, 0.54), "steel")
			_box(node, Vector3(x, 1.17, z), Vector3(0.53, 0.025, 0.44), "rubber")
	_cylinder(node, Vector3(-1.2, 1.4, -0.56), 0.036, 0.036, 0.7, "brass", 8)
	_box(node, Vector3(-0.92, 1.73, -0.56), Vector3(0.65, 0.065, 0.065), "brass")
	_cylinder(node, Vector3(-0.6, 1.69, -0.56), 0.19, 0.10, 0.13, "light", 10)

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
		# A spiral fossil: stacked shell rings shrinking towards the centre.
		var shell := TorusMesh.new()
		shell.inner_radius = 0.30
		shell.outer_radius = 0.62
		shell.rings = 16
		shell.ring_segments = 8
		mesh = shell
		material = _material(Color("d9c08f"), 0.05, 0.72)
		var inner := MeshInstance3D.new()
		var inner_mesh := TorusMesh.new()
		inner_mesh.inner_radius = 0.10
		inner_mesh.outer_radius = 0.30
		inner_mesh.rings = 12
		inner_mesh.ring_segments = 6
		inner.mesh = inner_mesh
		inner.material_override = _material(Color("b89a68"), 0.05, 0.75)
		inner.position.y = 0.05
		visual.add_child(inner)
	elif kind == "diamond":
		mesh = gem_mesh()
		material = _material(Color("c1eee6"), 0.43, 0.13)
	else:
		mesh = gem_mesh()
		material = _material(Color("82c6dc"), 0.3, 0.22)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	visual.add_child(instance)
	return visual

static func make_explosive(tier: String) -> Node3D:
	var visual := Node3D.new()
	visual.name = "Explosive"
	var red: StandardMaterial3D = _material(Color("c8322b"), 0.05, 0.6)
	var fuse_material: StandardMaterial3D = _material(Color("e9d9a6"), 0.0, 0.9)
	var spark: StandardMaterial3D = _material(Color("ffb347"), 0.0, 0.3, 2.0)
	var sticks: Array[Vector3] = []
	if tier == "dynamite":
		sticks = [Vector3.ZERO]
	elif tier == "tnt":
		sticks = [Vector3(-0.055, 0, 0), Vector3(0.055, 0, 0), Vector3(0, 0, 0.09)]
	if tier == "buster":
		var ball := MeshInstance3D.new()
		var ball_mesh := SphereMesh.new()
		ball_mesh.radius = 0.2
		ball_mesh.height = 0.4
		ball_mesh.radial_segments = 14
		ball_mesh.rings = 7
		ball.mesh = ball_mesh
		ball.material_override = _material(Color("23262a"), 0.5, 0.35)
		visual.add_child(ball)
		var band := MeshInstance3D.new()
		var band_mesh := TorusMesh.new()
		band_mesh.inner_radius = 0.19
		band_mesh.outer_radius = 0.215
		band.mesh = band_mesh
		band.material_override = _material(Color("e58a2d"), 0.2, 0.4)
		visual.add_child(band)
	for at: Vector3 in sticks:
		var stick := MeshInstance3D.new()
		var stick_mesh := CylinderMesh.new()
		stick_mesh.top_radius = 0.045
		stick_mesh.bottom_radius = 0.045
		stick_mesh.height = 0.32
		stick_mesh.radial_segments = 10
		stick.mesh = stick_mesh
		stick.material_override = red
		stick.position = at
		visual.add_child(stick)
	if tier == "tnt":
		var tape := MeshInstance3D.new()
		var tape_mesh := BoxMesh.new()
		tape_mesh.size = Vector3(0.22, 0.05, 0.2)
		tape.mesh = tape_mesh
		tape.material_override = _material(Color("3b3a36"), 0.0, 0.8)
		tape.position = Vector3(0, 0, 0.03)
		visual.add_child(tape)
	var top: float = 0.2 if tier == "buster" else 0.16
	var fuse := MeshInstance3D.new()
	var fuse_mesh := CylinderMesh.new()
	fuse_mesh.top_radius = 0.008
	fuse_mesh.bottom_radius = 0.008
	fuse_mesh.height = 0.12
	fuse.mesh = fuse_mesh
	fuse.material_override = fuse_material
	fuse.position.y = top + 0.06
	visual.add_child(fuse)
	var glow := MeshInstance3D.new()
	glow.name = "Spark"
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.025
	glow_mesh.height = 0.05
	glow.mesh = glow_mesh
	glow.material_override = spark
	glow.position.y = top + 0.12
	glow.visible = false
	visual.add_child(glow)
	return visual
