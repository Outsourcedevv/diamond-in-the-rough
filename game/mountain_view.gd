extends Node3D

## Renders the mountain's cells as one smooth rock surface (surface nets over a
## density field) with matching trimesh collision, in chunks. Only chunks touched
## by mining are rebuilt. The rules still work on 1 m cells underneath.

signal surface_settled

const MountainScript = preload("res://game/mountain.gd")
const CHUNK: int = 12
const BATCH_CHUNKS: int = 3

# Rock tone along a ramp: 0 soil, 0.5 stone, 0.8 granite, 1 bedrock.
const ROCK_RAMP: Dictionary = {1: 0.42, 2: 0.55, 3: 0.0, 4: 0.5, 5: 0.8, 6: 1.0}
# Ore speck styles: 1 dull, 2 metallic, 3 glinting gem.
const ORE_STYLE: Dictionary = {
	10: [1, Color("1d1d1f")], 11: [2, Color("c26d35")], 12: [2, Color("b98a6f")], 13: [2, Color("d9dde0")],
	14: [2, Color("e8b93c")], 15: [3, Color("9a55c9")], 16: [3, Color("2aa868")], 17: [3, Color("3462d4")],
	18: [3, Color("cf2a40")], 20: [3, Color("e6fbff")], 21: [1, Color("e3d3ad")]
}
const SHADER_CODE: String = """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03) * 0.28 + vnoise(p * 4.11) * 0.14 + vnoise(p * 8.3) * 0.08;
}
void fragment() {
	vec3 n = normalize(world_normal);
	vec3 p = world_pos;
	float large = fbm(p * 0.35);
	float detail = fbm(p * 2.6);
	// Rock: soil, layered stone, dark granite and bedrock along one ramp.
	float ramp = UV2.x;
	vec3 soil = vec3(0.40, 0.33, 0.25);
	vec3 stone = vec3(0.50, 0.49, 0.46);
	vec3 granite = vec3(0.36, 0.36, 0.37);
	vec3 bedrock = vec3(0.17, 0.18, 0.19);
	vec3 rock = ramp < 0.5 ? mix(soil, stone, ramp * 2.0) : (ramp < 0.8 ? mix(stone, granite, (ramp - 0.5) / 0.3) : mix(granite, bedrock, (ramp - 0.8) / 0.2));
	float strata = sin(p.y * 2.7 + large * 6.0) * 0.5 + 0.5;
	vec3 albedo = rock * (0.74 + large * 0.34 + detail * 0.14) * (0.93 + strata * 0.1);
	float rough = 0.94;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	// Ore veins show as speckled patches in the exposed rock.
	float layer = COLOR.a;
	float wobble = (fbm(p * 0.8) - 0.5) * 0.3;
	float meadow = layer > 0.25 && layer < 0.75 ? smoothstep(0.62, 0.84, n.y + wobble) * (1.0 - smoothstep(13.0, 19.0, p.y + wobble * 8.0)) : 0.0;
	if (UV.x > 0.05) {
		// Small mineral flecks: sparse where turf covers the ground, dense in bare rock.
		float grain_mask = vnoise(p * 7.5 + vec3(UV.y * 5.1));
		float cluster = fbm(p * 1.3 + vec3(UV.y * 2.7));
		// Untouched mountainside shows only the odd stain; freshly dug rock shows the vein.
		float threshold = mix(layer > 0.25 ? 0.8 : 0.62, 0.86, meadow);
		float speck = smoothstep(threshold, threshold + 0.05, grain_mask * 0.7 + cluster * 0.5) * smoothstep(0.05, 0.6, UV.x);
		vec3 ore = COLOR.rgb * (0.8 + detail * 0.4);
		albedo = mix(albedo, ore, speck);
		if (UV.y > 2.5) {
			rough = mix(rough, 0.15, speck);
			metal = speck * 0.15;
			emit = ore * speck * (0.10 + 0.07 * sin(TIME * 2.2 + dot(p, vec3(3.1, 1.7, 2.3))));
		} else if (UV.y > 1.5) {
			metal = speck * 0.5;
			rough = mix(rough, 0.45, speck);
		}
	}
	// Grass only holds on gentle, lower ground; steep faces and high slopes stay bare rock.
	if (meadow > 0.0) {
		vec3 turf = mix(vec3(0.27, 0.36, 0.18), vec3(0.42, 0.47, 0.25), fbm(p * 0.6)) * (0.8 + detail * 0.35);
		albedo = mix(albedo, turf, meadow * 0.94);
		rough = mix(rough, 1.0, meadow);
	}
	float snowy = layer > 0.75 ? 1.0 : smoothstep(20.0, 27.0, p.y + wobble * 6.0) * step(0.25, layer);
	float snow = snowy * smoothstep(0.55, 0.78, n.y + wobble * 0.6);
	// The summit keeps a proper snowcap even on its steeper faces.
	snow = max(snow, smoothstep(27.0, 32.0, p.y + wobble * 5.0) * step(0.25, layer) * smoothstep(0.2, 0.45, n.y + wobble));
	albedo = mix(albedo, vec3(0.9, 0.92, 0.95) * (0.92 + detail * 0.1), snow);
	rough = mix(rough, 0.75, snow);
	// The foot of the mountain fades into the valley floor's colour.
	albedo = mix(vec3(0.34, 0.38, 0.33), albedo, smoothstep(-0.05, 0.9, p.y + wobble));
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
"""

var game: Node
var state: Node
var material: ShaderMaterial
var _chunks: Dictionary = {}
var _dirty: Dictionary = {}
var _sonar_root: Node3D
var _sonar_timer: float = 0.0
var _host_codes := PackedByteArray()
var _slope_scale := PackedFloat32Array()
var _ground := PackedFloat32Array()
var _natural_top := PackedByteArray()
var _chunk_heights: Dictionary = {}
var _task: int = -1
var _task_keys: Array = []
var _task_results: Array = []

func build(owner_game: Node) -> void:
	game = owner_game
	state = game.state
	name = "Mountain"
	var shader := Shader.new()
	shader.code = SHADER_CODE
	material = ShaderMaterial.new()
	material.shader = shader
	_host_codes.resize(MountainScript.CELL_COUNT)
	var grid = state.mountain
	_slope_scale.resize(MountainScript.SIZE_X * MountainScript.SIZE_Z)
	_ground.resize(MountainScript.SIZE_X * MountainScript.SIZE_Z)
	_natural_top.resize(MountainScript.SIZE_X * MountainScript.SIZE_Z)
	for z: int in range(MountainScript.SIZE_Z):
		for x: int in range(MountainScript.SIZE_X):
			for y: int in range(grid.height(x, z)):
				_host_codes[MountainScript.index(x, y, z)] = grid.base_code(x, y, z)
			# Vertical distance to the ground overstates true distance on steep slopes;
			# scaling by the slope keeps the smoothed surface free of terrace bands.
			var gx: float = (grid.smooth_height(x + 1, z) - grid.smooth_height(x - 1, z)) * 0.5
			var gz: float = (grid.smooth_height(x, z + 1) - grid.smooth_height(x, z - 1)) * 0.5
			_slope_scale[x + z * MountainScript.SIZE_X] = 1.0 / sqrt(1.0 + gx * gx + gz * gz)
			# The surface sits slightly below the valley floor away from the mountain.
			_ground[x + z * MountainScript.SIZE_X] = grid.smooth_height(x, z) - 0.35
			_natural_top[x + z * MountainScript.SIZE_X] = grid.height(x, z)
	for cy: int in range(ceili(float(MountainScript.SIZE_Y) / CHUNK)):
		for cz: int in range(ceili(float(MountainScript.SIZE_Z) / CHUNK)):
			for cx: int in range(ceili(float(MountainScript.SIZE_X) / CHUNK)):
				var key := Vector3i(cx, cy, cz)
				var body := StaticBody3D.new()
				body.name = "Chunk_%d_%d_%d" % [cx, cy, cz]
				body.set_meta("mountain", true)
				body.collision_layer = 1
				var mesh := MeshInstance3D.new()
				mesh.material_override = material
				body.add_child(mesh)
				var collision := CollisionShape3D.new()
				collision.shape = ConcavePolygonShape3D.new()
				body.add_child(collision)
				add_child(body)
				_chunks[key] = {"body": body, "mesh": mesh, "collision": collision}
				# Lowest and highest ground under this chunk (with a one-cell margin),
				# so chunks that are plainly all air or all rock skip sampling.
				var low: float = 999.0
				var high: float = -999.0
				for z: int in range(cz * CHUNK - 2, mini((cz + 1) * CHUNK + 2, MountainScript.SIZE_Z + 2)):
					for x: int in range(cx * CHUNK - 2, mini((cx + 1) * CHUNK + 2, MountainScript.SIZE_X + 2)):
						var h: float = grid.smooth_height(x, z)
						low = minf(low, h)
						high = maxf(high, h)
				_chunk_heights[key] = Vector2(low, high)
	_sonar_root = Node3D.new()
	_sonar_root.name = "SonarPings"
	add_child(_sonar_root)
	state.world_reset.connect(rebuild_all)
	state.cells_changed.connect(mark_cells)

## A new or loaded world is rebuilt over several frames so a joining client never
## stalls its network loop; flush() finishes immediately when collision is needed now.
func rebuild_all() -> void:
	_finish_task()
	for key: Vector3i in _chunks:
		_dirty[key] = true

func mark_cells(list: PackedInt32Array) -> void:
	for cell: int in list:
		var c: Vector3i = MountainScript.coords(cell)
		# The surface around a cell is shared with up to seven neighbouring chunks.
		for dy: int in range(-1, 2):
			for dz: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var n := Vector3i(c.x + dx, c.y + dy, c.z + dz)
					if n.x < 0 or n.y < 0 or n.z < 0:
						continue
					var key := Vector3i(n.x / CHUNK, n.y / CHUNK, n.z / CHUNK)
					if _chunks.has(key):
						_dirty[key] = true

func flush() -> void:
	_finish_task()
	for key: Vector3i in _dirty.keys():
		_rebuild(key)
	_dirty.clear()

func _process(delta: float) -> void:
	# Surfaces are computed on a worker thread so mining, blasts and joining never
	# stall the game loop (and with it networking and voice); results apply here.
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_finish_task()
		if _dirty.is_empty():
			surface_settled.emit()
	if _task < 0 and not _dirty.is_empty():
		_task_keys.clear()
		for key: Vector3i in _dirty.keys():
			_task_keys.append(key)
			_dirty.erase(key)
			if _task_keys.size() >= BATCH_CHUNKS:
				break
		_task_results.clear()
		_task_results.resize(_task_keys.size())
		_task = WorkerThreadPool.add_task(_compute_batch.bind(_task_keys.duplicate(), state.cells.duplicate()))
	_update_sonar(delta)

func _compute_batch(keys: Array, cells: PackedByteArray) -> void:
	for i: int in range(keys.size()):
		_task_results[i] = _compute(keys[i], cells)

func _finish_task() -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	for i: int in range(_task_keys.size()):
		# A chunk changed again while it was being computed is rebuilt once more later.
		if not _dirty.has(_task_keys[i]):
			_apply(_task_keys[i], _task_results[i])
	_task_keys.clear()
	_task_results.clear()

## How solid a cell looks: mined cells are empty, the natural top follows the
## smooth ground height, and below the grid is the valley floor.
func _density(cells: PackedByteArray, x: int, y: int, z: int) -> float:
	var in_columns: bool = x >= 0 and z >= 0 and x < MountainScript.SIZE_X and z < MountainScript.SIZE_Z
	# The field continues below the valley floor, so the mountain's foot meets the
	# ground smoothly; surface that lies on or under the floor is never drawn.
	var column: int = x + z * MountainScript.SIZE_X
	var ground: float = _ground[column] if in_columns else -0.35
	var scale: float = _slope_scale[column] if in_columns else 1.0
	var top: float = 0.5 + (ground - float(y) - 0.5) * scale
	if y < 0:
		return clampf(top, 0.5, 1.0)
	if not in_columns or y >= MountainScript.SIZE_Y:
		return clampf(top, 0.0, 0.49)
	if cells[MountainScript.index(x, y, z)] != 0:
		# Thin ground-level rim cells may sink under the floor instead of bulging.
		return clampf(top, 0.0 if y == 0 else 0.5, 1.0)
	if y < _natural_top[column]:
		return 0.0
	return clampf(top, 0.0, 0.49)

func _rebuild(key: Vector3i) -> void:
	if _chunks.has(key):
		_apply(key, _compute(key, state.cells))

func _apply(key: Vector3i, result: Dictionary) -> void:
	var entry: Dictionary = _chunks[key]
	var mesh_instance: MeshInstance3D = entry.mesh
	var collision: CollisionShape3D = entry.collision
	if result.is_empty():
		mesh_instance.mesh = null
		collision.disabled = true
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result.arrays)
	mesh_instance.mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	# Diggers can end up inside a freshly opened pocket; collide on both sides.
	shape.backface_collision = true
	shape.set_faces(result.faces)
	collision.shape = shape
	collision.disabled = false

## Builds one chunk's surface arrays. Pure data, safe to run on a worker thread.
func _compute(key: Vector3i, cells: PackedByteArray) -> Dictionary:
	if cells.size() != MountainScript.CELL_COUNT:
		return {}
	var x0: int = key.x * CHUNK
	var y0: int = key.y * CHUNK
	var z0: int = key.z * CHUNK
	var x1: int = mini(x0 + CHUNK, MountainScript.SIZE_X)
	var y1: int = mini(y0 + CHUNK, MountainScript.SIZE_Y)
	var z1: int = mini(z0 + CHUNK, MountainScript.SIZE_Z)
	var span: Vector2 = _chunk_heights[key]
	if float(y0) - 2.0 > span.y:
		return {}
	if float(y1) + 2.0 < span.x - 1.0:
		var opened := false
		for y: int in range(maxi(y0 - 1, 0), mini(y1 + 1, MountainScript.SIZE_Y)):
			for z: int in range(maxi(z0 - 1, 0), mini(z1 + 1, MountainScript.SIZE_Z)):
				var row: int = MountainScript.index(maxi(x0 - 1, 0), y, z)
				for x: int in range(maxi(x0 - 1, 0), mini(x1 + 1, MountainScript.SIZE_X)):
					if cells[row + x - maxi(x0 - 1, 0)] == 0:
						opened = true
						break
				if opened: break
			if opened: break
		if not opened:
			return {}
	# Samples cover the chunk plus one cell either side (cubes start one cell early).
	var sx: int = x1 - x0 + 2
	var sy: int = y1 - y0 + 2
	var sz: int = z1 - z0 + 2
	var samples := PackedFloat32Array()
	samples.resize(sx * sy * sz)
	var solid := PackedByteArray()
	solid.resize(sx * sy * sz)
	var any_in := false
	var any_out := false
	var grid_x: int = MountainScript.SIZE_X
	var grid_y: int = MountainScript.SIZE_Y
	var grid_z: int = MountainScript.SIZE_Z
	var layer_cells: int = grid_x * grid_z
	for z: int in range(sz):
		for x: int in range(sx):
			# Same field as _density(), computed once per column for speed.
			var wx: int = x0 - 1 + x
			var wz: int = z0 - 1 + z
			var in_columns: bool = wx >= 0 and wz >= 0 and wx < grid_x and wz < grid_z
			var column: int = wx + wz * grid_x
			var ground: float = _ground[column] if in_columns else -0.35
			var scale: float = _slope_scale[column] if in_columns else 1.0
			var natural: int = _natural_top[column] if in_columns else 0
			for y: int in range(sy):
				var wy: int = y0 - 1 + y
				var d: float = 0.5 + (ground - float(wy) - 0.5) * scale
				if wy < 0:
					d = clampf(d, 0.5, 1.0)
				elif not in_columns or wy >= grid_y:
					d = clampf(d, 0.0, 0.49)
				elif cells[column + wy * layer_cells] != 0:
					d = clampf(d, 0.0 if wy == 0 else 0.5, 1.0)
				elif wy < natural:
					d = 0.0
				else:
					d = clampf(d, 0.0, 0.49)
				var at: int = x + sx * (z + sz * y)
				samples[at] = d
				if d >= 0.5:
					solid[at] = 1
					any_in = true
				else:
					any_out = true
	if not (any_in and any_out):
		return {}
	var layer_stride: int = sx * sz
	var origin: Vector3 = MountainScript.ORIGIN + Vector3(0.5, 0.5, 0.5)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cube_vertex: Dictionary = {}
	# One vertex per dual cube that the surface passes through.
	for cy: int in range(sy - 1):
		for cz: int in range(sz - 1):
			for cx: int in range(sx - 1):
				# Most cubes are wholly rock or wholly air; reject them before any float work.
				var base: int = cx + sx * (cz + sz * cy)
				var inside: int = solid[base] + solid[base + 1] + solid[base + sx] + solid[base + sx + 1] + solid[base + layer_stride] + solid[base + layer_stride + 1] + solid[base + layer_stride + sx] + solid[base + layer_stride + sx + 1]
				if inside == 0 or inside == 8:
					continue
				var corner: Array[float] = [samples[base], samples[base + 1], samples[base + layer_stride], samples[base + layer_stride + 1], samples[base + sx], samples[base + sx + 1], samples[base + layer_stride + sx], samples[base + layer_stride + sx + 1]]
				var sum := Vector3.ZERO
				var crossings: int = 0
				for edge: Array in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
					var a: float = corner[edge[0]]
					var b: float = corner[edge[1]]
					if (a >= 0.5) == (b >= 0.5):
						continue
					var t: float = clampf((0.5 - a) / (b - a), 0.0, 1.0)
					var pa := Vector3(edge[0] & 1, (edge[0] >> 1) & 1, (edge[0] >> 2) & 1)
					var pb := Vector3(edge[1] & 1, (edge[1] >> 1) & 1, (edge[1] >> 2) & 1)
					sum += pa.lerp(pb, t)
					crossings += 1
				var local: Vector3 = sum / float(crossings)
				var gx: float = (corner[1] + corner[3] + corner[5] + corner[7]) - (corner[0] + corner[2] + corner[4] + corner[6])
				var gy: float = (corner[2] + corner[3] + corner[6] + corner[7]) - (corner[0] + corner[1] + corner[4] + corner[5])
				var gz: float = (corner[4] + corner[5] + corner[6] + corner[7]) - (corner[0] + corner[1] + corner[2] + corner[3])
				var normal := -Vector3(gx, gy, gz)
				normal = normal.normalized() if normal.length() > 0.0001 else Vector3.UP
				cube_vertex[Vector3i(cx, cy, cz)] = verts.size()
				verts.append(origin + Vector3(x0 - 1 + cx, y0 - 1 + cy, z0 - 1 + cz) + local)
				normals.append(normal)
				_surface_look(cells, x0 - 1 + cx, y0 - 1 + cy, z0 - 1 + cz, colors, uv, uv2)
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	# A quad joins the four cubes around every sample edge the surface crosses.
	for y: int in range(1, sy - 1):
		for z: int in range(1, sz - 1):
			for x: int in range(1, sx - 1):
				var here: bool = samples[x + sx * (z + sz * y)] >= 0.5
				for axis: int in range(3):
					var nx: int = x + int(axis == 0)
					var ny: int = y + int(axis == 1)
					var nz: int = z + int(axis == 2)
					if (samples[nx + sx * (nz + sz * ny)] >= 0.5) == here:
						continue
					var ring: Array[Vector3i]
					if axis == 0:
						ring = [Vector3i(x, y - 1, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x, y - 1, z)]
					elif axis == 1:
						ring = [Vector3i(x - 1, y, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x - 1, y, z)]
					else:
						ring = [Vector3i(x - 1, y - 1, z), Vector3i(x, y - 1, z), Vector3i(x, y, z), Vector3i(x - 1, y, z)]
					var ids: Array[int] = []
					for cube: Vector3i in ring:
						if not cube_vertex.has(cube):
							break
						ids.append(int(cube_vertex[cube]))
					if ids.size() != 4:
						continue
					var a: Vector3 = verts[ids[0]]
					var b: Vector3 = verts[ids[1]]
					var c: Vector3 = verts[ids[2]]
					var d: Vector3 = verts[ids[3]]
					if a.y < -0.1 and b.y < -0.1 and c.y < -0.1 and d.y < -0.1:
						continue
					var outward := Vector3.ZERO
					outward[axis] = 1.0 if here else -1.0
					# Godot treats clockwise triangles as front faces: order them so
					# (second - first) × (third - first) points into the rock.
					if (b - a).cross(c - a).dot(outward) > 0.0:
						indices.append_array([ids[0], ids[2], ids[1], ids[0], ids[3], ids[2]])
						faces.append_array([a, c, b, a, d, c])
					else:
						indices.append_array([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]])
						faces.append_array([a, b, c, a, c, d])
	if indices.is_empty():
		return {}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"arrays": arrays, "faces": faces}

## Picks how a surface vertex looks from the solid cells around it: ore shows
## through when any neighbour is ore, and grass/snow only on the natural top.
func _surface_look(cells: PackedByteArray, bx: int, by: int, bz: int, colors: PackedColorArray, uv: PackedVector2Array, uv2: PackedVector2Array) -> void:
	var ore_code: int = 0
	var rock: float = -1.0
	var layer: float = 0.0
	for k: int in range(8):
		var x: int = bx + (k & 1)
		var y: int = by + ((k >> 1) & 1)
		var z: int = bz + ((k >> 2) & 1)
		if not MountainScript.in_grid(x, y, z):
			continue
		var i: int = MountainScript.index(x, y, z)
		var code: int = cells[i]
		if code == 0:
			continue
		var host: int = code
		if ORE_STYLE.has(code):
			ore_code = code
			host = _host_codes[i]
		rock = maxf(rock, float(ROCK_RAMP.get(host, 0.5)))
		if host == 1:
			layer = maxf(layer, 0.5)
		elif host == 2:
			layer = 1.0
	if rock < 0.0:
		rock = 0.5
	if ore_code != 0:
		var style: Array = ORE_STYLE[ore_code]
		var tint: Color = style[1]
		colors.append(Color(tint.r, tint.g, tint.b, layer))
		uv.append(Vector2(1.0, float(style[0])))
	else:
		colors.append(Color(0.5, 0.5, 0.5, layer))
		uv.append(Vector2(0.0, 0.0))
	uv2.append(Vector2(rock, 0.0))

## The solid, exposed cell behind a ray hit on the mountain surface, or -1.
func cell_from_hit(position: Vector3, normal: Vector3) -> int:
	var probe: Vector3 = position - normal * 0.45
	var g: Vector3i = MountainScript.world_to_grid(probe)
	var best: int = -1
	var distance: float = INF
	for dy: int in range(-1, 2):
		for dz: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var x: int = g.x + dx
				var y: int = g.y + dy
				var z: int = g.z + dz
				if not MountainScript.in_grid(x, y, z):
					continue
				var cell: int = MountainScript.index(x, y, z)
				if not state.is_solid(cell) or not state.exposed(cell):
					continue
				var squared: float = MountainScript.cell_center(cell).distance_squared_to(probe)
				if squared < distance:
					distance = squared
					best = cell
	return best

## Kept for callers; mining progress shows as chips and in the prompt instead.
func show_crack(_cell: int, _fraction: float) -> void:
	pass

func hide_crack() -> void:
	pass

func _update_sonar(delta: float) -> void:
	_sonar_timer -= delta
	var t: float = Time.get_ticks_msec() * 0.004
	for ping: Node3D in _sonar_root.get_children():
		ping.scale = Vector3.ONE * (0.46 + sin(t + ping.position.x) * 0.1)
	if _sonar_timer > 0.0:
		return
	_sonar_timer = 1.0
	for child: Node in _sonar_root.get_children():
		child.queue_free()
	if not is_instance_valid(game) or not game.active or not "sonar" in state.upgrades:
		return
	var here: Vector3 = game.player.position
	var shown: int = 0
	for gem: Dictionary in state.gems.values():
		if str(gem.get("stage", "")) != "buried" or not str(gem.get("kind", "")) in ["suspect", "diamond"]:
			continue
		var at: Vector3 = MountainScript.cell_center(int(gem.get("cell", 0)))
		if at.distance_to(here) > 12.0:
			continue
		var ping: Node3D = game.workshop.make_gem("suspect")
		ping.position = at
		ping.scale = Vector3.ONE * 0.46
		for mesh: Node in ping.get_children():
			if mesh is MeshInstance3D and mesh.material_override is StandardMaterial3D:
				var glow: StandardMaterial3D = mesh.material_override.duplicate()
				glow.no_depth_test = true
				glow.emission_enabled = true
				glow.emission = Color("8ff3ff")
				glow.emission_energy_multiplier = 1.4
				glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				glow.albedo_color = Color(0.6, 0.95, 1.0, 0.85)
				glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh.material_override = glow
		_sonar_root.add_child(ping)
		shown += 1
		if shown >= 24:
			break
