extends Node3D

## Renders the block mountain as chunked meshes with matching trimesh collision.
## Only exposed faces are built, and only chunks touched by mining are rebuilt.

const MountainScript = preload("res://game/mountain.gd")
const CHUNK: int = 12
const REBUILDS_PER_FRAME: int = 6

const ROCK_COLORS: Dictionary = {
	1: Color("7b5f43"), 2: Color("c9d3d6"), 3: Color("7b5f43"), 4: Color("8a8a83"),
	5: Color("666868"), 6: Color("2f3133")
}
const TOP_COLORS: Dictionary = {1: Color("6c8a4a"), 2: Color("eef3f4")}
# Speck styles: 1 dull, 2 metallic, 3 glinting gem.
const ORE_STYLE: Dictionary = {
	10: [1, Color("1d1d1f")], 11: [2, Color("d07a3c")], 12: [2, Color("c99c82")], 13: [2, Color("e2e6ea")],
	14: [2, Color("f4c542")], 15: [3, Color("a35ad6")], 16: [3, Color("2fbf74")], 17: [3, Color("3768e0")],
	18: [3, Color("db2f45")], 20: [3, Color("eafcff")], 21: [1, Color("efe1bf")]
}
const SHADER_CODE: String = """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
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
void fragment() {
	vec3 p = world_pos - world_normal * 0.01;
	float grain = vnoise(p * 6.0) * 0.6 + vnoise(p * 15.0) * 0.4;
	vec3 albedo = COLOR.rgb * (0.84 + grain * 0.28);
	float rough = 0.93;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (UV.x < -0.5) {
		// Grass and snow spill over the top edge of a block's sides.
		float lip = fract(world_pos.y) + (vnoise(p * 9.0) - 0.5) * 0.18;
		albedo = mix(albedo, vec3(UV.y, UV2.x, UV2.y) * (0.86 + grain * 0.28), smoothstep(0.6, 0.66, lip));
	} else if (UV.x > 0.5) {
		vec3 ore = vec3(UV.y, UV2.x, UV2.y);
		float blob = vnoise(p * 4.6 + vec3(UV.x * 3.1));
		float speck = smoothstep(0.55, 0.61, blob);
		albedo = mix(albedo, ore * (0.86 + grain * 0.26), speck);
		if (UV.x > 2.5) {
			rough = mix(rough, 0.16, speck);
			metal = speck * 0.2;
			emit = ore * speck * (0.14 + 0.08 * sin(TIME * 2.2 + dot(p, vec3(3.1, 1.7, 2.3))));
		} else if (UV.x > 1.5) {
			metal = speck * 0.55;
			rough = mix(rough, 0.42, speck);
		}
	}
	// Darkened block edges keep every cube readable from a distance.
	vec3 f = fract(world_pos);
	vec3 n = abs(world_normal);
	vec2 face = n.x > 0.5 ? f.yz : (n.y > 0.5 ? f.xz : f.xy);
	float edge = min(min(face.x, 1.0 - face.x), min(face.y, 1.0 - face.y));
	albedo *= mix(0.7, 1.0, smoothstep(0.0, 0.07, edge));
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
var _crack: MeshInstance3D
var _crack_material: StandardMaterial3D
var _sonar_root: Node3D
var _sonar_timer: float = 0.0
var _host_codes := PackedByteArray()

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
	for z: int in range(MountainScript.SIZE_Z):
		for x: int in range(MountainScript.SIZE_X):
			for y: int in range(grid.height(x, z)):
				_host_codes[MountainScript.index(x, y, z)] = grid.base_code(x, y, z)
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
	_crack = MeshInstance3D.new()
	var crack_box := BoxMesh.new()
	crack_box.size = Vector3.ONE * 1.012
	_crack.mesh = crack_box
	_crack_material = StandardMaterial3D.new()
	_crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_material.albedo_color = Color(0.06, 0.05, 0.04, 0.0)
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack.material_override = _crack_material
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crack.visible = false
	add_child(_crack)
	_sonar_root = Node3D.new()
	_sonar_root.name = "SonarPings"
	add_child(_sonar_root)
	state.world_reset.connect(rebuild_all)
	state.cells_changed.connect(mark_cells)

## A new or loaded world is rebuilt over several frames so a joining client never
## stalls its network loop; flush() finishes immediately when collision is needed now.
func rebuild_all() -> void:
	for key: Vector3i in _chunks:
		_dirty[key] = true
	hide_crack()

func mark_cells(list: PackedInt32Array) -> void:
	for cell: int in list:
		var c: Vector3i = MountainScript.coords(cell)
		_dirty[Vector3i(c.x / CHUNK, c.y / CHUNK, c.z / CHUNK)] = true
		# Neighbouring chunks expose a new face when a boundary block disappears.
		for offset: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = c + offset
			if MountainScript.in_grid(n.x, n.y, n.z):
				_dirty[Vector3i(n.x / CHUNK, n.y / CHUNK, n.z / CHUNK)] = true

func flush() -> void:
	for key: Vector3i in _dirty.keys():
		_rebuild(key)
	_dirty.clear()

func _process(delta: float) -> void:
	var budget: int = REBUILDS_PER_FRAME
	for key: Vector3i in _dirty.keys():
		if budget <= 0:
			break
		_dirty.erase(key)
		_rebuild(key)
		budget -= 1
	_update_sonar(delta)

func _rebuild(key: Vector3i) -> void:
	if not _chunks.has(key):
		return
	var cells: PackedByteArray = state.cells
	var entry: Dictionary = _chunks[key]
	var mesh_instance: MeshInstance3D = entry.mesh
	var collision: CollisionShape3D = entry.collision
	if cells.size() != MountainScript.CELL_COUNT:
		mesh_instance.mesh = null
		collision.disabled = true
		return
	var sx: int = MountainScript.SIZE_X
	var sy: int = MountainScript.SIZE_Y
	var sz: int = MountainScript.SIZE_Z
	var layer: int = sx * sz
	var origin: Vector3 = MountainScript.ORIGIN
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	var x0: int = key.x * CHUNK
	var y0: int = key.y * CHUNK
	var z0: int = key.z * CHUNK
	for y: int in range(y0, mini(y0 + CHUNK, sy)):
		for z: int in range(z0, mini(z0 + CHUNK, sz)):
			for x: int in range(x0, mini(x0 + CHUNK, sx)):
				var i: int = x + sx * (z + sz * y)
				var code: int = cells[i]
				if code == 0:
					continue
				var open_px: bool = x + 1 >= sx or cells[i + 1] == 0
				var open_nx: bool = x == 0 or cells[i - 1] == 0
				var open_py: bool = y + 1 >= sy or cells[i + layer] == 0
				var open_ny: bool = y > 0 and cells[i - layer] == 0
				var open_pz: bool = z + 1 >= sz or cells[i + sx] == 0
				var open_nz: bool = z == 0 or cells[i - sx] == 0
				if not (open_px or open_nx or open_py or open_ny or open_pz or open_nz):
					continue
				var host: int = code
				var style: int = 0
				var ore_color := Color.BLACK
				if ORE_STYLE.has(code):
					host = _host_codes[i]
					if host == 1 or host == 2:
						host = 3
					style = int(ORE_STYLE[code][0])
					ore_color = ORE_STYLE[code][1]
				var jitter: float = 0.94 + float((i * 2654435761) & 255) / 255.0 * 0.12
				var side: Color = ROCK_COLORS.get(host, Color("8a8a83")) * jitter
				var top: Color = TOP_COLORS.get(host, side) * jitter if style == 0 else side
				# Grass and snow blocks show their cap colour along the top of each side.
				var cap_style: int = style
				var cap_color: Color = ore_color
				if style == 0 and (host == 1 or host == 2) and TOP_COLORS.has(host):
					cap_style = -1
					cap_color = TOP_COLORS[host] * jitter
				var o := Vector3(origin.x + x, origin.y + y, origin.z + z)
				if open_py:
					_quad(verts, normals, colors, uv, uv2, indices, faces, o + Vector3(0, 1, 0), o + Vector3(0, 1, 1), o + Vector3(1, 1, 1), o + Vector3(1, 1, 0), Vector3.UP, top, style, ore_color)
				if open_ny:
					_quad(verts, normals, colors, uv, uv2, indices, faces, o, o + Vector3(1, 0, 0), o + Vector3(1, 0, 1), o + Vector3(0, 0, 1), Vector3.DOWN, side, style, ore_color)
				if open_px:
					_quad(verts, normals, colors, uv, uv2, indices, faces, o + Vector3(1, 0, 0), o + Vector3(1, 1, 0), o + Vector3(1, 1, 1), o + Vector3(1, 0, 1), Vector3.RIGHT, side, cap_style, cap_color)
				if open_nx:
					_quad(verts, normals, colors, uv, uv2, indices, faces, o, o + Vector3(0, 0, 1), o + Vector3(0, 1, 1), o + Vector3(0, 1, 0), Vector3.LEFT, side, cap_style, cap_color)
				if open_pz:
					_quad(verts, normals, colors, uv, uv2, indices, faces, o + Vector3(0, 0, 1), o + Vector3(1, 0, 1), o + Vector3(1, 1, 1), o + Vector3(0, 1, 1), Vector3.BACK, side, cap_style, cap_color)
				if open_nz:
					_quad(verts, normals, colors, uv, uv2, indices, faces, o, o + Vector3(0, 1, 0), o + Vector3(1, 1, 0), o + Vector3(1, 0, 0), Vector3.FORWARD, side, cap_style, cap_color)
	if verts.is_empty():
		mesh_instance.mesh = null
		collision.disabled = true
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	# Diggers can end up inside a freshly opened pocket; collide on both sides.
	shape.backface_collision = true
	shape.set_faces(faces)
	collision.shape = shape
	collision.disabled = false

func _quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv: PackedVector2Array, uv2: PackedVector2Array, indices: PackedInt32Array, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color, style: int, ore: Color) -> void:
	# Corners are listed so (b - a) × (c - a) points out of the block; Godot treats
	# the opposite (clockwise) order as front-facing, so triangles use a, c, b.
	var base: int = verts.size()
	var shade: Color = color
	if normal.y < -0.5:
		shade = color * 0.62
	elif normal.y < 0.5:
		shade = color * (0.86 if absf(normal.x) > 0.5 else 0.8)
	shade.a = 1.0
	if style < 0:
		ore = ore * (shade.r / maxf(color.r, 0.001))
	for p: Vector3 in [a, b, c, d]:
		verts.append(p)
		normals.append(normal)
		colors.append(shade)
		uv.append(Vector2(float(style), ore.r))
		uv2.append(Vector2(ore.g, ore.b))
	indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	faces.append_array([a, c, b, a, d, c])

## The solid cell behind a ray hit on the mountain, or -1.
func cell_from_hit(position: Vector3, normal: Vector3) -> int:
	var g: Vector3i = MountainScript.world_to_grid(position - normal * 0.5)
	if not MountainScript.in_grid(g.x, g.y, g.z):
		return -1
	var cell: int = MountainScript.index(g.x, g.y, g.z)
	return cell if state.is_solid(cell) else -1

func show_crack(cell: int, fraction: float) -> void:
	if cell < 0 or fraction <= 0.0:
		hide_crack()
		return
	_crack.position = MountainScript.cell_center(cell)
	_crack_material.albedo_color.a = clampf(0.12 + fraction * 0.55, 0.0, 0.7)
	_crack.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.05) * 0.004 * fraction)
	_crack.visible = true

func hide_crack() -> void:
	if is_instance_valid(_crack):
		_crack.visible = false

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
