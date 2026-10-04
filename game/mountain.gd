extends RefCounted

## Deterministic block mountain shared by the authority rules and the renderer.
## The natural shape never changes; worlds differ by seed (ore veins and finds)
## and by which cells have been mined.

const SIZE_X: int = 144
const SIZE_Y: int = 72
const SIZE_Z: int = 128
const CELL_COUNT: int = SIZE_X * SIZE_Y * SIZE_Z
const ORIGIN := Vector3(-72.0, 0.0, -143.0)
const SNOW_LINE: int = 40

# Cell codes. 0 is open air; everything else is a solid block.
const AIR: int = 0
const GRASS: int = 1
const SNOW: int = 2
const DIRT: int = 3
const STONE: int = 4
const GRANITE: int = 5
const BEDROCK: int = 6
# The diamond's own block; it is the only one of its kind in the mountain.
const CRYSTAL: int = 30
const CURIO: int = 31
const ORE_CODES: Dictionary = {"coal": 10, "tin": 11, "copper": 12, "iron": 13, "silver": 14, "turquoise": 15, "gold": 16, "topaz": 17, "amethyst": 18, "opal": 19, "emerald": 20, "sapphire": 21, "platinum": 22, "ruby": 23}
const ORE_NAMES: Dictionary = {"coal": "Coal", "tin": "Tin ore", "copper": "Copper ore", "iron": "Iron ore", "silver": "Silver ore", "turquoise": "Turquoise", "gold": "Gold nugget", "topaz": "Topaz", "amethyst": "Amethyst", "opal": "Opal", "emerald": "Emerald", "sapphire": "Sapphire", "platinum": "Platinum ore", "ruby": "Ruby"}
const ORE_VALUES: Dictionary = {"coal": 2, "tin": 3, "copper": 4, "iron": 6, "silver": 11, "turquoise": 15, "gold": 20, "topaz": 24, "amethyst": 28, "opal": 33, "emerald": 38, "sapphire": 45, "platinum": 50, "ruby": 55}
const ORE_ORDER: Array[String] = ["coal", "tin", "copper", "iron", "silver", "turquoise", "gold", "topaz", "amethyst", "opal", "emerald", "sapphire", "platinum", "ruby"]
const BLOCK_NAMES: Dictionary = {1: "Turf", 2: "Snowpack", 3: "Soil", 4: "Stone", 5: "Granite", 6: "Bedrock", 30: "Glittering kimberlite", 31: "Fossil seam"}
# Ore kinds by depth below the natural surface: richer kinds sit deeper.
const ORE_TIERS: Array = [
	[4, [["coal", 0.36], ["tin", 0.24], ["copper", 0.26], ["iron", 0.14]]],
	[12, [["coal", 0.12], ["tin", 0.12], ["copper", 0.2], ["iron", 0.24], ["silver", 0.16], ["turquoise", 0.1], ["gold", 0.06]]],
	[22, [["iron", 0.12], ["silver", 0.18], ["turquoise", 0.14], ["gold", 0.2], ["topaz", 0.14], ["amethyst", 0.12], ["opal", 0.1]]],
	[32, [["gold", 0.14], ["topaz", 0.14], ["amethyst", 0.16], ["opal", 0.16], ["emerald", 0.16], ["sapphire", 0.12], ["platinum", 0.12]]],
	[999, [["amethyst", 0.08], ["opal", 0.12], ["emerald", 0.18], ["sapphire", 0.2], ["platinum", 0.2], ["ruby", 0.22]]]
]

const DOWNHILL_STEPS: Array[Vector3] = [Vector3(-1, 0, 1.0), Vector3(0, -1, 1.0), Vector3(-1, -1, 1.35), Vector3(1, -1, 1.35)]
const UPHILL_STEPS: Array[Vector3] = [Vector3(1, 0, 1.0), Vector3(0, 1, 1.0), Vector3(1, 1, 1.35), Vector3(-1, 1, 1.35)]

var heights := PackedByteArray()
var smooth := PackedFloat32Array()
# ORE_TIERS as parallel arrays of depth limits, cell codes and cumulative weights.
var _tier_depths := PackedInt32Array()
var _tier_codes: Array[PackedByteArray] = []
var _tier_weights: Array[PackedFloat32Array] = []


func _init() -> void:
	_generate_heights()
	for tier: Array in ORE_TIERS:
		var codes := PackedByteArray()
		var weights := PackedFloat32Array()
		var total: float = 0.0
		for entry: Array in tier[1]:
			total += float(entry[1])
			codes.append(int(ORE_CODES[str(entry[0])]))
			weights.append(total)
		_tier_depths.append(int(tier[0]))
		_tier_codes.append(codes)
		_tier_weights.append(weights)


func _generate_heights() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 7151
	noise.frequency = 0.032
	noise.fractal_octaves = 5
	var ridges := FastNoiseLite.new()
	ridges.seed = 2209
	ridges.frequency = 0.024
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 3
	# One main summit with three shoulders, roughened by crags and ridgelines.
	var peaks: Array = [[Vector2(72.0, 62.0), Vector2(60.0, 54.0), 62.0], [Vector2(32.0, 46.0), Vector2(30.0, 30.0), 38.0], [Vector2(114.0, 82.0), Vector2(28.0, 32.0), 40.0], [Vector2(88.0, 24.0), Vector2(38.0, 22.0), 46.0]]
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
					h = maxf(h, float(peak[2]) * pow(1.0 - d, 1.2))
			# Fade texture out at the rim so the mountain still meets the valley floor;
			# ridgelines and crags grow stronger towards the summit.
			var rim: float = clampf(h / 9.0, 0.0, 1.0)
			if h > 0.0:
				h += (noise.get_noise_2d(float(x), float(z)) * 8.0 + 1.5) * rim + ridges.get_noise_2d(float(x), float(z)) * (4.5 + h * 0.22) * rim
			# Taper to the valley floor before the grid ends so no edge is cut off.
			var border: float = float(mini(mini(x, SIZE_X - 1 - x), mini(z, SIZE_Z - 1 - z)))
			h *= clampf((border - 1.0) / 8.0, 0.0, 1.0)
			raw[x + z * SIZE_X] = clampf(h, 0.0, float(SIZE_Y - 2))
	# Limit slopes so the lower mountain stays walkable, while the upper slopes may
	# steepen into rocky cliffs. Then soften everything into a natural form.
	for _pass: int in range(2):
		for z: int in range(SIZE_Z):
			for x: int in range(SIZE_X):
				var best: float = raw[x + z * SIZE_X]
				for step: Vector3 in DOWNHILL_STEPS:
					var below: float = _column(raw, x + int(step.x), z + int(step.y))
					best = minf(best, below + step.z * _slope_limit(below))
				raw[x + z * SIZE_X] = best
		for z: int in range(SIZE_Z - 1, -1, -1):
			for x: int in range(SIZE_X - 1, -1, -1):
				var best: float = raw[x + z * SIZE_X]
				for step: Vector3 in UPHILL_STEPS:
					var below: float = _column(raw, x + int(step.x), z + int(step.y))
					best = minf(best, below + step.z * _slope_limit(below))
				raw[x + z * SIZE_X] = best
	smooth.resize(SIZE_X * SIZE_Z)
	heights.resize(SIZE_X * SIZE_Z)
	for z: int in range(SIZE_Z):
		for x: int in range(SIZE_X):
			var total: float = 0.0
			var weight: float = 0.0
			for dz: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var w: float = 2.0 if dx == 0 and dz == 0 else (1.0 if dx == 0 or dz == 0 else 0.6)
					total += _column(raw, x + dx, z + dz) * w
					weight += w
			var h: float = total / weight
			smooth[x + z * SIZE_X] = h
			heights[x + z * SIZE_X] = clampi(roundi(h), 0, SIZE_Y - 2)


func _column(values: Array[float], x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= SIZE_X or z >= SIZE_Z:
		return 0.0
	return values[x + z * SIZE_X]


## Rise per metre allowed above a given height: gentle foothills, steep summit.
func _slope_limit(height_below: float) -> float:
	return 0.85 + clampf((height_below - 12.0) / 14.0, 0.0, 1.0) * 1.7


## The continuous ground height of a column, used to draw a natural surface.
func smooth_height(x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= SIZE_X or z >= SIZE_Z:
		return 0.0
	return smooth[x + z * SIZE_X]


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
	return layer_code(height(x, z), y)


## The natural rock at height y in a column whose ground is at top.
static func layer_code(top: int, y: int) -> int:
	var d: int = top - y
	# Bedrock floors the thick interior; thin edges are ordinary rock down to the ground.
	if y == 0 and top >= 6:
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
	return ore_for_code(_vein(x, y, z, depth(x, y, z), world_seed))


## The ore code of a natural cell d blocks below the surface, or 0 for plain rock.
func _vein(x: int, y: int, z: int, d: int, world_seed: int) -> int:
	var region: int = (x / 3) * 73856093 ^ (y / 3) * 19349663 ^ (z / 3) * 83492791 ^ (world_seed * 2654435761)
	if _unit(region) > 0.38:
		return 0
	if _unit(index(x, y, z) * 2246822519 ^ world_seed * 3266489917 + 7) > 0.5:
		return 0
	var pick: float = _unit(region * 31 + 17)
	var tier: int = _tier_depths.size() - 1
	for n: int in range(_tier_depths.size()):
		if d <= _tier_depths[n]:
			tier = n
			break
	var weights: PackedFloat32Array = _tier_weights[tier]
	var codes: PackedByteArray = _tier_codes[tier]
	for n: int in range(weights.size()):
		if pick < weights[n]:
			return codes[n]
	return codes[codes.size() - 1]


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
	var layer: int = SIZE_X * SIZE_Z
	var mined_bytes: int = mined.size()
	for z: int in range(SIZE_Z):
		for x: int in range(SIZE_X):
			var column: int = x + z * SIZE_X
			var top: int = heights[column]
			for y: int in range(top):
				var cell: int = column + y * layer
				if (cell >> 3) < mined_bytes and (mined[cell >> 3] & (1 << (cell & 7))) != 0:
					continue
				var code: int = layer_code(top, y)
				if specials.has(cell):
					code = int(specials[cell])
				elif code != BEDROCK:
					var ore: int = _vein(x, y, z, top - y, world_seed)
					if ore != 0:
						code = ore
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
