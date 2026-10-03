extends RefCounted

## Deterministic block mountain shared by the authority rules and the renderer.
## The natural shape never changes; worlds differ by seed (ore veins and finds)
## and by which cells have been mined.

const SIZE_X: int = 72
const SIZE_Y: int = 34
const SIZE_Z: int = 64
const CELL_COUNT: int = SIZE_X * SIZE_Y * SIZE_Z
const ORIGIN := Vector3(-36.0, 0.0, -79.0)
const SNOW_LINE: int = 18

# Cell codes. 0 is open air; everything else is a solid block.
const AIR: int = 0
const GRASS: int = 1
const SNOW: int = 2
const DIRT: int = 3
const STONE: int = 4
const GRANITE: int = 5
const BEDROCK: int = 6
const CRYSTAL: int = 20
const CURIO: int = 21
const ORE_CODES: Dictionary = {"coal": 10, "copper": 11, "iron": 12, "silver": 13, "gold": 14, "amethyst": 15, "emerald": 16, "sapphire": 17, "ruby": 18}
const ORE_NAMES: Dictionary = {"coal": "Coal", "copper": "Copper ore", "iron": "Iron ore", "silver": "Silver ore", "gold": "Gold nugget", "amethyst": "Amethyst", "emerald": "Emerald", "sapphire": "Sapphire", "ruby": "Ruby"}
const ORE_VALUES: Dictionary = {"coal": 2, "copper": 4, "iron": 6, "silver": 11, "gold": 20, "amethyst": 28, "emerald": 38, "sapphire": 45, "ruby": 55}
const ORE_ORDER: Array[String] = ["coal", "copper", "iron", "silver", "gold", "amethyst", "emerald", "sapphire", "ruby"]
const BLOCK_NAMES: Dictionary = {1: "Grass", 2: "Snow", 3: "Dirt", 4: "Stone", 5: "Granite", 6: "Bedrock", 20: "Crystal vein", 21: "Fossil seam"}

var heights := PackedByteArray()


func _init() -> void:
	_generate_heights()


func _generate_heights() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 7151
	noise.frequency = 0.06
	noise.fractal_octaves = 4
	var ridges := FastNoiseLite.new()
	ridges.seed = 2209
	ridges.frequency = 0.045
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 3
	# One main summit with two shoulders, roughened by crags and ridgelines.
	var peaks: Array = [[Vector2(37.0, 30.0), Vector2(31.0, 29.0), 30.0], [Vector2(17.0, 22.0), Vector2(15.0, 14.0), 17.0], [Vector2(57.0, 40.0), Vector2(14.0, 16.0), 19.0]]
	var raw: Array[float] = []
	raw.resize(SIZE_X * SIZE_Z)
	for z: int in range(SIZE_Z):
		for x: int in range(SIZE_X):
			var h: float = 0.0
			for peak: Array in peaks:
				var centre: Vector2 = peak[0]
				var radius: Vector2 = peak[1]
				var dx: float = (float(x) + 0.5 - centre.x) / radius.x
				var dz: float = (float(z) + 0.5 - centre.y) / radius.y
				var d: float = sqrt(dx * dx + dz * dz)
				if d < 1.0:
					h = maxf(h, float(peak[2]) * pow(1.0 - d, 1.05))
			# Fade texture out at the rim so the mountain still meets the valley floor.
			var rim: float = clampf(h / 6.0, 0.0, 1.0)
			if h > 0.0:
				h += (noise.get_noise_2d(float(x), float(z)) * 6.5 + ridges.get_noise_2d(float(x), float(z)) * 5.0 + 1.5) * rim
			raw[x + z * SIZE_X] = clampf(h, 0.0, float(SIZE_Y - 2))
	var h_int: Array[int] = []
	h_int.resize(raw.size())
	for i: int in range(raw.size()):
		h_int[i] = int(round(raw[i]))
	# Limit slopes so every face can be climbed one block at a time.
	for _pass: int in range(2):
		for z: int in range(SIZE_Z):
			for x: int in range(SIZE_X):
				var best: int = h_int[x + z * SIZE_X]
				for offset: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1)]:
					best = mini(best, _column(h_int, x + offset.x, z + offset.y) + 1)
				h_int[x + z * SIZE_X] = best
		for z: int in range(SIZE_Z - 1, -1, -1):
			for x: int in range(SIZE_X - 1, -1, -1):
				var best: int = h_int[x + z * SIZE_X]
				for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					best = mini(best, _column(h_int, x + offset.x, z + offset.y) + 1)
				h_int[x + z * SIZE_X] = best
	heights.resize(SIZE_X * SIZE_Z)
	for i: int in range(h_int.size()):
		heights[i] = h_int[i]


func _column(values: Array[int], x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= SIZE_X or z >= SIZE_Z:
		return 0
	return values[x + z * SIZE_X]


func height(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= SIZE_X or z >= SIZE_Z:
		return 0
	return heights[x + z * SIZE_X]


static func index(x: int, y: int, z: int) -> int:
	return x + SIZE_X * (z + SIZE_Z * y)


static func coords(cell: int) -> Vector3i:
	var x: int = cell % SIZE_X
	var z: int = (cell / SIZE_X) % SIZE_Z
	var y: int = cell / (SIZE_X * SIZE_Z)
	return Vector3i(x, y, z)


static func in_grid(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < SIZE_X and y < SIZE_Y and z < SIZE_Z


static func valid_cell(cell: int) -> bool:
	return cell >= 0 and cell < CELL_COUNT


static func cell_center(cell: int) -> Vector3:
	var c: Vector3i = coords(cell)
	return ORIGIN + Vector3(float(c.x) + 0.5, float(c.y) + 0.5, float(c.z) + 0.5)


static func world_to_grid(p: Vector3) -> Vector3i:
	var local: Vector3 = p - ORIGIN
	return Vector3i(floori(local.x), floori(local.y), floori(local.z))


static func in_footprint(p: Vector3) -> bool:
	var g: Vector3i = world_to_grid(p)
	return g.x >= 0 and g.z >= 0 and g.x < SIZE_X and g.z < SIZE_Z


func natural_solid(x: int, y: int, z: int) -> bool:
	return in_grid(x, y, z) and y < height(x, z)


## Depth below the natural surface: 1 is the top block of a column.
func depth(x: int, y: int, z: int) -> int:
	return height(x, z) - y


func base_code(x: int, y: int, z: int) -> int:
	if not natural_solid(x, y, z):
		return AIR
	var d: int = depth(x, y, z)
	# Bedrock floors the thick interior; thin edges are ordinary rock down to the ground.
	if y == 0 and height(x, z) >= 6:
		return BEDROCK
	if d == 1:
		return SNOW if y >= SNOW_LINE else GRASS
	if d <= 3:
		return DIRT
	if d >= 8 or y <= 3:
		return GRANITE
	return STONE


## Hits needed with a tool that deals one damage. Ore adds a little toughness.
func hardness(x: int, y: int, z: int, code: int) -> int:
	var host: int = base_code(x, y, z)
	var value: int = 3
	match host:
		GRASS, SNOW, DIRT: value = 2
		STONE: value = 3
		GRANITE: value = 6
		BEDROCK: value = 9999
	if code >= 10:
		value += 1
	return value


func needs_steel(x: int, y: int, z: int) -> bool:
	return base_code(x, y, z) == GRANITE


static func _hash(value: int) -> int:
	var a: int = value & 0xffffffff
	a = ((a ^ (a >> 16)) * 0x45d9f3b) & 0xffffffff
	a = ((a ^ (a >> 16)) * 0x45d9f3b) & 0xffffffff
	a = a ^ (a >> 16)
	return a & 0xffffffff


static func _unit(value: int) -> float:
	return float(_hash(value)) / 4294967296.0


## Ore veins cluster in 3×3×3 regions; richer kinds sit deeper in the mountain.
func ore_at(x: int, y: int, z: int, world_seed: int) -> String:
	if not natural_solid(x, y, z) or base_code(x, y, z) == BEDROCK:
		return ""
	var region: int = (x / 3) * 73856093 ^ (y / 3) * 19349663 ^ (z / 3) * 83492791 ^ (world_seed * 2654435761)
	var vein: float = _unit(region)
	if vein > 0.32:
		return ""
	if _unit(index(x, y, z) * 2246822519 ^ world_seed * 3266489917 + 7) > 0.46:
		return ""
	var pick: float = _unit(region * 31 + 17)
	var d: int = depth(x, y, z)
	var table: Array
	if d <= 3:
		table = [["coal", 0.5], ["copper", 0.35], ["iron", 0.15]]
	elif d <= 8:
		table = [["coal", 0.2], ["copper", 0.25], ["iron", 0.3], ["silver", 0.15], ["gold", 0.1]]
	elif d <= 14:
		table = [["iron", 0.2], ["silver", 0.25], ["gold", 0.25], ["amethyst", 0.15], ["emerald", 0.15]]
	else:
		table = [["gold", 0.2], ["amethyst", 0.2], ["emerald", 0.2], ["sapphire", 0.2], ["ruby", 0.2]]
	var total: float = 0.0
	for entry: Array in table:
		total += float(entry[1])
		if pick < total:
			return str(entry[0])
	return str(table[-1][0])


static func ore_for_code(code: int) -> String:
	for kind: String in ORE_CODES:
		if int(ORE_CODES[kind]) == code:
			return kind
	return ""


static func block_name(code: int) -> String:
	var ore: String = ore_for_code(code)
	if not ore.is_empty():
		return str(ORE_NAMES[ore])
	return str(BLOCK_NAMES.get(code, "Rock"))


## Builds the live cell codes from the natural shape, the seed's ore veins,
## buried finds (cell -> CRYSTAL/CURIO) and the mined bitset.
func build_cells(world_seed: int, mined: PackedByteArray, specials: Dictionary) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(CELL_COUNT)
	for z: int in range(SIZE_Z):
		for x: int in range(SIZE_X):
			var top: int = height(x, z)
			for y: int in range(top):
				var cell: int = index(x, y, z)
				if is_mined(mined, cell):
					continue
				var code: int = base_code(x, y, z)
				if specials.has(cell):
					code = int(specials[cell])
				elif code != BEDROCK:
					var ore: String = ore_at(x, y, z, world_seed)
					if not ore.is_empty():
						code = int(ORE_CODES[ore])
				cells[cell] = code
	return cells


static func empty_mined() -> PackedByteArray:
	var bits := PackedByteArray()
	bits.resize(CELL_COUNT / 8 + 1)
	return bits


static func is_mined(mined: PackedByteArray, cell: int) -> bool:
	var byte: int = cell >> 3
	return byte < mined.size() and (mined[byte] & (1 << (cell & 7))) != 0


static func set_mined(mined: PackedByteArray, cell: int) -> void:
	var byte: int = cell >> 3
	if byte < mined.size():
		mined[byte] = mined[byte] | (1 << (cell & 7))
