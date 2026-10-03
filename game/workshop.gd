extends Node3D
class_name RoughWorkshop

var stations: Dictionary = {}
var pile_centers: Array[Vector3] = []
var _machines: Dictionary = {}
var _materials: Dictionary = {}
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
	name = "TheRidiculousWorkshop"
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
	return Vector3(x, _pile_height(x, z) + 0.34, z)

func update_upgrades(upgrades: Array) -> void:
	for key: String in _machines:
		var entry: Dictionary = _machines[key]
		var active: bool = key in upgrades
		if key == "conveyor":
			_belt_enabled = active
			var belt: Node3D = entry["node"]
			belt.visible = active
			var belt_collision: CollisionShape3D = entry["collision"]
			belt_collision.disabled = not active
		else:
			var machine: Node3D = entry["node"]
			machine.visible = active
			var machine_collision: CollisionShape3D = entry["collision"]
			machine_collision.disabled = not active
			var notice: Label3D = entry["notice"]
			notice.visible = not active
			var status: Label3D = entry["status"]
			status.text = "READY TO WORK" if active else "UPGRADE AVAILABLE"
			status.modulate = Color("a1ffe0") if active else Color("f0b868")
	# Shelves fill with ludicrously bright supplies as the workshop expands.
	if has_node("ExpansionSupplies"):
		get_node("ExpansionSupplies").visible = upgrades.size() >= 3

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
	_materials = {
		"wall": _material(Color("163a41")),
		"wall_light": _material(Color("24535a")),
		"floor": _material(Color("27464a"), 0.12, 0.78),
		"floor_alt": _material(Color("2c4e50"), 0.12, 0.78),
		"wood": _material(Color("ad7446"), 0.0, 0.68),
		"wood_dark": _material(Color("694931")),
		"brass": _material(Color("e3ad52"), 0.7, 0.27),
		"steel": _material(Color("517277"), 0.65, 0.34),
		"dark": _material(Color("102a31"), 0.25, 0.57),
		"mint": _material(Color("9dffd8"), 0.25, 0.3, 0.32),
		"pink": _material(Color("f681bb"), 0.32, 0.3, 0.18),
		"orange": _material(Color("f0a64f"), 0.22, 0.42),
		"white": _material(Color("f5efdb"), 0.0, 0.55),
		"window": _material(Color("8dc2cd"), 0.16, 0.32, 0.33),
		"light": _material(Color("fff2bf"), 0.0, 0.2, 2.0),
		"rubber": _material(Color("1b282c"), 0.1, 0.84)
	}

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("163642")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bce2e1")
	environment.ambient_light_energy = 0.52
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("446c72")
	environment.fog_density = 0.006
	environment.glow_enabled = true
	environment.glow_intensity = 0.24
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sunlight := DirectionalLight3D.new()
	sunlight.light_color = Color("ffe1ac")
	sunlight.light_energy = 1.05
	sunlight.rotation_degrees = Vector3(-56, -34, 0)
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 40.0
	add_child(sunlight)
	_omni(Vector3(0, 4.6, -2.0), Color("caeaff"), 2.0, 13.0)
	_omni(Vector3(-7, 3.8, 2.5), Color("ffe1a3"), 1.15, 8.0)
	_omni(Vector3(7, 3.8, 2.5), Color("bfffe0"), 1.05, 8.0)
	_omni(Vector3(0, 3.5, -8.8), Color("ffb8dd"), 0.9, 6.0)

func _omni(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	add_child(light)

func _build_room() -> void:
	_box(self, Vector3(0, -0.16, 0), Vector3(24.0, 0.32, 22.0), "floor", true)
	# Broad floorboards and subtle seams give the floor a hand-built workshop feel.
	for x: int in range(-11, 12):
		_box(self, Vector3(float(x), 0.005, 0), Vector3(0.018, 0.008, 22.0), "dark")
	for z: int in range(-10, 11, 4):
		_box(self, Vector3(0, 0.009, float(z)), Vector3(24, 0.008, 0.017), "dark")
	_box(self, Vector3(-12, 2.7, 0), Vector3(0.34, 5.4, 22), "wall", true)
	_box(self, Vector3(12, 2.7, 0), Vector3(0.34, 5.4, 22), "wall", true)
	_box(self, Vector3(0, 2.7, -11), Vector3(24, 5.4, 0.34), "wall", true)
	_box(self, Vector3(0, 2.7, 11), Vector3(24, 5.4, 0.34), "wall", true)
	for side: int in [-1, 1]:
		_box(self, Vector3(side * 11.77, 0.55, 0), Vector3(0.15, 1.1, 21.7), "wood_dark")
		_box(self, Vector3(side * 11.65, 1.16, 0), Vector3(0.19, 0.10, 21.7), "brass")
		for z: int in [-9, -3, 3, 9]:
			_box(self, Vector3(side * 11.64, 2.6, z), Vector3(0.24, 5.2, 0.26), "wood_dark")
		for z: int in [-7, 0, 7]:
			_window(Vector3(side * 11.70, 3.45, z), side)
	_box(self, Vector3(0, 0.55, -10.78), Vector3(23.7, 1.1, 0.15), "wood_dark")
	for x: int in [-10, -6, 6, 10]:
		_box(self, Vector3(x, 2.65, -10.7), Vector3(0.26, 5.3, 0.26), "wood_dark")
	for z: int in [-7, 1, 8]:
		_box(self, Vector3(0, 5.3, z), Vector3(24, 0.36, 0.28), "wood_dark")
		for x: int in [-6, 0, 6]:
			if x == 0 and z == -7:
				continue
			_lamp(Vector3(x, 4.35, z))
	# Loading door, boot mat, and a warehouse notice anchor the player spawn.
	_box(self, Vector3(0, 2.0, 10.76), Vector3(4.2, 4.0, 0.18), "steel")
	for y: int in range(1, 8):
		_box(self, Vector3(0, float(y) * 0.45, 10.62), Vector3(4.15, 0.025, 0.06), "dark")
	_box(self, Vector3(0, 0.012, 8.95), Vector3(3.6, 0.025, 1.3), "rubber")
	_label(self, "EXPECT THE UNEXPECTED", Vector3(0, 4.3, 10.56), 30, Color("ffe1ae"), Vector3(0, PI, 0))
	_label(self, "EMPLOYEE OF THE MONTH:\nPROBABLY THE BUCKET", Vector3(-9.8, 2.75, 10.57), 29, Color("d7e7da"), Vector3(0, PI, 0))
	# Back wall title is the room's focal point.
	_label(self, "DIAMOND", Vector3(0, 4.75, -10.6), 125, Color("aaffdf"))
	_label(self, "IN THE ROUGH", Vector3(0, 3.95, -10.6), 42, Color("ffd88d"))
	_label(self, "ONE REAL DIAMOND. A LOT OF BAD DECISIONS.", Vector3(0, 3.47, -10.6), 23, Color("d0e4dc"))
	for x: float in [-5.25, 5.25]:
		var jewel: Node3D = make_gem("suspect")
		jewel.position = Vector3(x, 4.25, -10.5)
		jewel.scale = Vector3.ONE * 0.46
		jewel.rotation.z = -0.17 if x < 0 else 0.17
		add_child(jewel)

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
	var rim: float = maxf(pow(x / 6.25, 2.0), pow((z + 2.0) / 4.05, 2.0))
	return 0.42 + 1.14 * maxf(0.05, 1.0 - rim)

func _build_pile() -> void:
	_box(self, Vector3(0, 0.1, -2.0), Vector3(12.8, 0.20, 8.1), "wood_dark")
	for x: float in [-6.45, 6.45]:
		_box(self, Vector3(x, 0.19, -2.0), Vector3(0.12, 0.34, 8.2), "brass")
	for z: float in [-6.1, 2.1]:
		_box(self, Vector3(0, 0.19, z), Vector3(13.0, 0.34, 0.12), "brass")
	var colors: Array[Color] = [Color("83d8d1"), Color("a9e2f3"), Color("ed81b4"), Color("907fd0"), Color("dfb168"), Color("61acae"), Color("8be5bc"), Color("d6e9ea")]
	for color_index: int in range(colors.size()):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = gem_mesh()
		mm.instance_count = 560
		var material: StandardMaterial3D = _material(colors[color_index], 0.38, 0.19)
		var gems := MultiMeshInstance3D.new()
		gems.name = "DecorativeGems_%s" % color_index
		gems.multimesh = mm
		gems.material_override = material
		gems.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gems)
		for n: int in range(mm.instance_count):
			var x: float = _rng.randf_range(-6.15, 6.15)
			var z: float = _rng.randf_range(-5.88, 1.88)
			var top: float = _pile_height(x, z)
			var y: float = top + _rng.randf_range(-0.18, 0.08)
			if n % 4 == 0:
				y = _rng.randf_range(0.24, top)
			var size: float = _rng.randf_range(0.14, 0.25)
			var basis: Basis = Basis.from_euler(Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-PI, PI), _rng.randf_range(-1.5, 1.5)))
			basis = basis.scaled(Vector3(size, size * _rng.randf_range(0.8, 1.25), size))
			mm.set_instance_transform(n, Transform3D(basis, Vector3(x, y, z)))
	for row: int in range(3):
		for col: int in range(4):
			var center := Vector3(-4.5 + float(col) * 3.0, 0, -4.4 + float(row) * 2.4)
			pile_centers.append(center)
			var sector_id: int = row * 4 + col
			var body := StaticBody3D.new()
			body.name = "PileSector_%s" % sector_id
			body.set_meta("pile", sector_id)
			body.add_to_group("pile_sectors")
			var top: float = _pile_height(center.x, center.z) - 0.12
			body.position = center + Vector3(0, top * 0.5, 0)
			var shape := BoxShape3D.new()
			shape.size = Vector3(2.96, top, 2.38)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			body.add_child(collision)
			add_child(body)
	for row: int in range(3):
		_label(self, char(65 + row), Vector3(-6.6, 0.025, -4.4 + row * 2.4), 28, Color("ffd797"), Vector3(-PI / 2.0, 0, 0))
	_label(self, "THE ROUGH", Vector3(-5.1, 0.26, 2.5), 32, Color("ffca7d"), Vector3(-PI * 0.36, 0, 0))
	_label(self, "SCOOP  •  SORT  •  INSPECT", Vector3(1.9, 0.24, 2.5), 22, Color("afe8d6"), Vector3(-PI * 0.36, 0, 0))
	# Dashed perimeter makes the search zone legible without extra HUD.
	for x: int in range(-6, 7):
		_box(self, Vector3(x, 0.016, 2.65), Vector3(0.50, 0.02, 0.09), "orange")

func _build_stations() -> void:
	_station("sell", Vector3(-8, 1, 4), "THE SCRAP EXCHANGE", "TURN TRASH INTO TOMORROW", "mint")
	_station("shop", Vector3(8, 1, 4), "UPGRADE EMPORIUM", "YOUR NEXT BRILLIANT IDEA", "orange")
	_station("tray", Vector3(-8, 1, 0), "INSPECTION TRAY", "GOOD GEMS DESERVE A SECOND LOOK", "mint")
	_station("wash", Vector3(-8, 1, -4), "THE SPARKLE SPA", "A FRESH START FOR DIRTY ROCKS", "window")
	_station("sorter", Vector3(8, 1, -4), "THE SORT-O-MATIC", "SUSPICIOUS OBJECTS GO TO THE TRAY", "orange")
	_station("certify", Vector3(0, 1, -8), "CERTIFICATION BENCH", "REAL PROOF. REAL DIAMOND.", "brass")
	_station("scanner", Vector3(8, 1, 0), "CANDIDATE SCANNER", "SCIENCE, WITH A REASONABLE DOUBT", "pink")
	_station("recover", Vector3(-5, 1, 8), "LOST & FOUND", "NO GEM LEFT BEHIND", "orange")
	_station("collection", Vector3(5, 1, 8), "THE HALL OF FAKES", "IMPOSTORS WE HAVE LOVED", "pink")
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

func _station(id: String, at: Vector3, title: String, subtitle: String, accent: String) -> void:
	stations[id] = at
	var body := StaticBody3D.new()
	body.name = "Station_%s" % id
	body.position = Vector3(at.x, 0, at.z)
	body.set_meta("station", id)
	body.add_to_group("stations")
	add_child(body)
	_box(body, Vector3(0, 0.49, 0), Vector3(2.7, 0.96, 1.65), "dark")
	_box(body, Vector3(0, 0.99, 0), Vector3(2.90, 0.12, 1.85), "wood")
	_box(body, Vector3(0, 0.67, 0.84), Vector3(2.45, 0.095, 0.06), accent)
	for x: float in [-1.1, 1.1]:
		_box(body, Vector3(x, 0.27, 0.01), Vector3(0.10, 0.5, 1.42), "steel")
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.9, 1.05, 1.85)
	var collision := CollisionShape3D.new()
	collision.position.y = 0.525
	collision.shape = shape
	body.add_child(collision)
	# Signs always face the player so tables are readable from either aisle.
	var sign: Label3D = _label(body, title, Vector3(0, 2.5, 0), 34, Color("f4e3bf"))
	sign.pixel_size=0.0055
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var small: Label3D = _label(body, subtitle, Vector3(0, 2.17, 0), 18, Color("a7d2cd"))
	small.pixel_size=0.0055
	small.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var status: Label3D = _label(body, "", Vector3(0, 1.89, 0), 19, Color("a1ffe0"))
	status.name = "Status"
	status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_box(body, Vector3(-1.24, 1.70, 0.65), Vector3(0.045, 1.45, 0.045), "brass")
	_box(body, Vector3(1.24, 1.70, 0.65), Vector3(0.045, 1.45, 0.045), "brass")

func _station_node(id: String) -> Node3D:
	return get_node("Station_%s" % id) as Node3D

func _build_sell() -> void:
	var node: Node3D = _station_node("sell")
	_box(node, Vector3(-0.4, 1.21, 0), Vector3(1.45, 0.32, 1.3), "steel")
	_box(node, Vector3(-0.4, 1.40, 0), Vector3(1.16, 0.10, 1.03), "dark")
	_box(node, Vector3(0.87, 1.3, 0), Vector3(0.68, 0.58, 0.60), "mint")
	_box(node, Vector3(0.87, 1.45, 0.315), Vector3(0.5, 0.22, 0.02), "dark")
	_label(node, "$", Vector3(0.87, 1.46, 0.336), 44, Color("b5ffe0"))
	_label(node, "PLEASE DO NOT SELL THE INTERN", Vector3(0, 0.43, 0.84), 14, Color("e3cca4"))
	for n: int in range(5):
		_cylinder(node, Vector3(0.8 + float(n % 2) * 0.16, 1.62 + n * 0.034, 0.1), 0.10, 0.10, 0.024, "brass", 12)

func _build_shop() -> void:
	var node: Node3D = _station_node("shop")
	_box(node, Vector3(0, 1.49, -0.44), Vector3(2.65, 0.90, 0.10), "wall_light")
	for n: int in range(4):
		var x: float = -0.98 + n * 0.65
		_cylinder(node, Vector3(x, 1.40, -0.29), 0.037, 0.037, 0.49, "wood_dark", 8)
		var scoop: MeshInstance3D = _box(node, Vector3(x, 1.13, -0.1), Vector3(0.39, 0.10, 0.39), "brass")
		scoop.rotation.x = 0.4
	_box(node, Vector3(0, 1.1, 0.52), Vector3(1.72, 0.08, 0.44), "dark")
	_label(node, "BIG TOOLS / SMALL REGRETS", Vector3(0, 1.56, -0.36), 15, Color("ffe5b6"))
	_label(node, "GUARANTEED TO BE AN UPGRADE", Vector3(0, 0.40, 0.84), 14, Color("e3cca4"))

func _build_tray() -> void:
	var node: Node3D = _station_node("tray")
	for x: float in [-0.73, 0.0, 0.73]:
		for z: float in [-0.36, 0.36]:
			_box(node, Vector3(x, 1.12, z), Vector3(0.62, 0.09, 0.54), "steel")
			_box(node, Vector3(x, 1.17, z), Vector3(0.53, 0.025, 0.44), "rubber")
	_cylinder(node, Vector3(-1.2, 1.4, -0.56), 0.036, 0.036, 0.7, "brass", 8)
	_box(node, Vector3(-0.92, 1.73, -0.56), Vector3(0.65, 0.065, 0.065), "brass")
	_cylinder(node, Vector3(-0.6, 1.69, -0.56), 0.19, 0.10, 0.13, "light", 10)
	_label(node, "MAYBE", Vector3(-0.7, 0.48, 0.84), 20, Color("b7f2e0"))
	_label(node, "ALSO MAYBE", Vector3(0.68, 0.48, 0.84), 20, Color("f4bfe0"))

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
	var notice: Label3D = _label(station, "WORKSHOP SPACE RESERVED\nFOR SOMETHING RIDICULOUS", Vector3(0, 1.35, 0), 19, Color("dbb881"))
	notice.billboard = BaseMaterial3D.BILLBOARD_ENABLED
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
	_label(node, "SHAKE IT TILL YOU MAKE IT", Vector3(-0.13, 1.65, 0.505), 11, Color("173c40"))
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
	_label(node, "HMM...", Vector3(0, 1.9, 0.556), 22, Color("302741"))
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
	_label(node, "OFFICIAL-ISH", Vector3(-0.91, 1.36, 0.15), 10, Color("213c42"), Vector3(-PI / 2.0, 0, 0))
	_label(node, "THIS ONE REALLY MATTERS", Vector3(0, 0.4, 0.84), 18, Color("ffd685"))
	_omni(stations["certify"] + Vector3(0, 1.3, 0), Color("fff2c8"), 0.8, 3.5)

func _build_recovery() -> void:
	var node: Node3D = _station_node("recover")
	_box(node, Vector3(0, 1.36, -0.10), Vector3(1.5, 0.6, 1.10), "orange")
	_box(node, Vector3(0, 1.69, -0.10), Vector3(1.63, 0.08, 1.20), "brass")
	_box(node, Vector3(0, 1.53, 0.475), Vector3(0.97, 0.11, 0.03), "dark")
	_label(node, "IF IT FITS, IT GETS RECOVERED", Vector3(0, 1.25, 0.476), 11, Color("253a3a"))
	_label(node, "INCLUDING YOUR DIGNITY*", Vector3(0, 0.42, 0.84), 16, Color("e3cca4"))

func _build_collection() -> void:
	var node: Node3D = _station_node("collection")
	_box(node, Vector3(0, 1.37, -0.52), Vector3(2.58, 0.6, 0.12), "wall_light")
	for x: float in [-0.87, 0.0, 0.87]:
		_cylinder(node, Vector3(x, 1.15, 0.1), 0.30, 0.33, 0.18, "brass", 12)
		_cylinder(node, Vector3(x, 1.27, 0.1), 0.27, 0.27, 0.08, "dark", 12)
		_label(node, "YOUR FAKE HERE", Vector3(x, 1.17, 0.431), 9, Color("f5e4bd"))
	_label(node, "RARE DOES NOT ALWAYS MEAN REAL", Vector3(0, 0.42, 0.84), 14, Color("e3cca4"))

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
	# Back corner shelves, crates, books, emergency buckets and comfortable clutter.
	for side: int in [-1, 1]:
		var x: float = float(side) * 8.25
		for h: float in [0.7, 1.6, 2.5]:
			_box(self, Vector3(x, h, -9.25), Vector3(3.3, 0.14, 1.00), "wood")
		for dx: float in [-1.48, 1.48]:
			_box(self, Vector3(x + dx, 1.4, -9.25), Vector3(0.12, 2.8, 0.93), "steel")
		for n: int in range(5):
			var crate_x: float = x - 1.20 + float(n) * 0.59
			_box(self, Vector3(crate_x, 0.97, -9.2), Vector3(0.48, 0.48, 0.65), "wood_dark")
			_box(self, Vector3(crate_x, 1.0, -8.86), Vector3(0.055, 0.42, 0.035), "brass")
		for n: int in range(4):
			_cylinder(self, Vector3(x - 1.10 + n * 0.7, 1.98, -9.24), 0.23, 0.19, 0.55, "steel", 10)
		_label(self, "BUCKETS / EMERGENCY HATS", Vector3(x, 2.81, -8.74), 22, Color("ffdd9c"))
	var expansion := Node3D.new()
	expansion.name = "ExpansionSupplies"
	add_child(expansion)
	for n: int in range(12):
		var x: float = -9.45 + float(n % 6) * 0.46
		var z: float = -9.25
		if n >= 6:
			x += 16.5
		var bottle: MeshInstance3D = _cylinder(expansion, Vector3(x, 2.78, z), 0.14, 0.11, 0.45, "mint" if n % 2 == 0 else "pink", 8)
		bottle.rotation.z = -0.08 + float(n % 3) * 0.07
	# A hand-painted flow diagram by the start area.
	_box(self, Vector3(-8.6, 2.7, 10.58), Vector3(0.01, 0.01, 0.01), "wood")
	_label(self, "WORKSHOP RULES", Vector3(8.6, 3.15, 10.58), 34, Color("ffd792"), Vector3(0, PI, 0))
	_label(self, "1. EVERYTHING IS SUSPICIOUS.\n2. THE DIAMOND IS VERY SUSPICIOUS.\n3. CLEAN UP AFTER YOUR FRIENDS.", Vector3(8.6, 2.4, 10.58), 21, Color("c5dcd4"), Vector3(0, PI, 0))
	# Floor direction arrows establish the loop in the physical space.
	for x: float in [-8.0, 8.0]:
		for z: float in [2.0, 6.0]:
			var arrow: Label3D = _label(self, "▲", Vector3(x, 0.025, z), 42, Color("e9be72"), Vector3(-PI / 2.0, 0, 0))
			arrow.pixel_size = 0.013
	for side: int in [-1, 1]:
		for n: int in range(3):
			var at := Vector3(side * 10.25, 0.45 + n * 0.40, 6.75)
			_box(self, at, Vector3(1.15, 0.7, 0.92), "wood_dark")
			_box(self, at + Vector3(0, 0, 0.477), Vector3(1.03, 0.065, 0.025), "wood")
			_box(self, at + Vector3(0, 0.18, 0.477), Vector3(0.065, 0.55, 0.025), "wood")

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
	label.text = text
	label.position = at
	label.rotation = rotation
	label.font_size = font_size
	label.pixel_size = 0.009
	label.modulate = color
	label.outline_modulate = Color("0d242b")
	label.outline_size = 5
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
