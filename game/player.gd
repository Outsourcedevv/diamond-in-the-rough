extends CharacterBody3D

var camera: Camera3D
var hands: Node3D
var tool_root: Node3D
var held_root: Node3D
var game: Node
var yaw := 0.0
var pitch := -0.04
var sway := 0.0
var kick := 0.0
var inspecting := false
var enabled := false
var tool := "scoop"
var held_id := -1
var visual_angle := Vector2.ZERO
var inspect_scale := 1.0
var foam := 0.0
var hat_mode := 0
var batch_signature := ""
var batch_root: Node3D
var held_signature := ""

func build(owner_game: Node) -> void:
	game = owner_game
	collision_layer = 2
	collision_mask = 1
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.75
	col.shape = capsule
	col.position.y = 0.88
	add_child(col)
	camera = Camera3D.new()
	camera.position.y = 1.63
	camera.near = 0.035
	camera.far = 100.0
	camera.fov = 78
	add_child(camera)
	camera.current = true
	hands = Node3D.new()
	camera.add_child(hands)
	tool_root = Node3D.new()
	hands.add_child(tool_root)
	held_root = Node3D.new()
	hands.add_child(held_root)
	build_hands()
	set_tool("scoop")
	position = Vector3(0, 0.12, 7.2)
	update_view()

func mat(color: Color, metal := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = 0.4
	material.no_depth_test = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, metal := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = mat(color, metal)
	mesh.position = pos
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

func build_hands() -> void:
	var skin := Color("cb966e")
	var sleeve := Color("244e53")
	for side in [-1, 1]:
		var arm := box(hands, Vector3(0.145, 0.16, 0.48), Vector3(side * 0.28, -0.37, -0.29), sleeve)
		arm.rotation.x = -0.32
		arm.rotation.z = side * -0.22
		box(hands, Vector3(0.16, 0.11, 0.18), Vector3(side * 0.235, -0.27, -0.54), skin)
		box(hands, Vector3(0.155, 0.022, 0.14), Vector3(side * 0.235, -0.224, -0.545), Color("efc899"))
		for finger in range(4):
			box(hands, Vector3(0.03, 0.035, 0.08), Vector3(side * 0.235 + (finger-1.5)*0.034, -0.26, -0.65), skin)

func set_tool(next: String) -> void:
	tool = next
	batch_signature=""
	batch_root=null
	for child in tool_root.get_children():
		child.queue_free()
	var orange := Color("e4a65a")
	if tool == "scoop":
		box(tool_root, Vector3(0.09, 0.08, 0.37), Vector3(0.18, -0.28, -0.62), Color("795341"))
		box(tool_root, Vector3(0.42, 0.045, 0.37), Vector3(0.07, -0.3, -0.88), orange, 0.7)
		box(tool_root, Vector3(0.04, 0.18, 0.4), Vector3(-0.13, -0.23, -0.88), orange, 0.7)
		box(tool_root, Vector3(0.04, 0.18, 0.4), Vector3(0.27, -0.23, -0.88), orange, 0.7)
		box(tool_root, Vector3(0.4, 0.16, 0.04), Vector3(0.07, -0.25, -0.71), orange, 0.7)
	elif tool == "vacuum":
		box(tool_root, Vector3(0.22, 0.21, 0.45), Vector3(0.2, -0.26, -0.68), Color("e0a357"), 0.4)
		box(tool_root, Vector3(0.14, 0.11, 0.48), Vector3(0.14, -0.28, -1.02), Color("b6cfcb"), 0.8)
		box(tool_root, Vector3(0.34, 0.13, 0.09), Vector3(0.14, -0.28, -1.24), Color("31525b"))
	elif tool == "scanner":
		box(tool_root, Vector3(0.31, 0.12, 0.4), Vector3(0.12, -0.26, -0.69), Color("ebc283"), 0.4)
		box(tool_root, Vector3(0.23, 0.016, 0.23), Vector3(0.12, -0.193, -0.69), Color("76f8c7"))
		box(tool_root, Vector3(0.04, 0.12, 0.04), Vector3(0.12, -0.23, -0.93), Color("76f8c7"))
	kick = 0.25

func show_batch(ids: Array,gems:Dictionary) -> void:
	var signature: String=tool+str(ids)
	if signature==batch_signature: return
	batch_signature=signature
	if is_instance_valid(batch_root): batch_root.queue_free()
	batch_root=Node3D.new()
	tool_root.add_child(batch_root)
	if tool!="scoop": return
	for i in range(mini(ids.size(),7)):
		var gem: Dictionary=gems[int(ids[i])]
		var visual: Node3D=game.workshop.make_gem(str(gem.kind))
		visual.scale=Vector3.ONE*0.11
		visual.position=Vector3(-0.055+(i%3)*0.085,-0.255+int(i/3)*0.045,-0.83-(i%2)*0.055)
		visual.rotation.y=i*1.43
		batch_root.add_child(visual)

func show_held(gem: Dictionary) -> void:
	var next_id: int = int(gem.get("id", -1))
	var signature: String=str(next_id)+str(gem.get("tag",false))+str(gem.get("clean",false))
	if held_id == next_id and held_signature==signature:
		return
	held_id = next_id
	held_signature=signature
	for child in held_root.get_children():
		child.queue_free()
	if held_id < 0:
		return
	var visual: Node3D = game.workshop.make_gem(str(gem.get("kind", "glass")))
	visual.scale = Vector3.ONE * 0.65
	visual.name = "HeldCandidate"
	for mesh in visual.get_children():
		if mesh is MeshInstance3D and mesh.material_override is StandardMaterial3D:
			mesh.material_override.no_depth_test=true
			mesh.material_override.render_priority=100
	held_root.add_child(visual)
	if gem.get("tag",false):
		var label:=Label3D.new()
		label.text="CERTIFIED DIAMOND*"
		label.font_size=24
		label.pixel_size=0.0025
		label.position=Vector3(0,0.11,0.41)
		label.modulate=Color("ffc975")
		label.no_depth_test=true
		visual.add_child(label)
	visual_angle = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if not enabled or game.ui.menu_visible:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if inspecting:
			visual_angle += event.relative * 0.009
		else:
			yaw -= event.relative.x * float(game.settings.sensitivity)
			pitch = clampf(pitch - event.relative.y * float(game.settings.sensitivity), -1.35, 1.35)
			update_view()

func update_view() -> void:
	rotation.y = yaw
	camera.rotation.x = pitch

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var moving := Vector2.ZERO
	if not game.ui.menu_visible and not inspecting:
		moving = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var direction := (transform.basis * Vector3(moving.x, 0, moving.y)).normalized()
	var speed := 4.7 if Input.is_physical_key_pressed(KEY_SHIFT) else 3.3
	velocity.x = move_toward(velocity.x, direction.x * speed, 22 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 22 * delta)
	if not is_on_floor():
		velocity.y -= 20 * delta
	elif Input.is_physical_key_pressed(KEY_SPACE) and not game.ui.menu_visible:
		velocity.y = 6.2
	move_and_slide()
	if position.y < -8 or absf(position.x)>13 or absf(position.z)>12:
		game.unstuck()

func _process(delta: float) -> void:
	if not enabled: return
	var moving: bool=Vector2(velocity.x,velocity.z).length()>0.3
	sway += delta * (9.0 if moving else 1.8)
	kick = move_toward(kick, 0, delta * 2.0)
	hands.position = Vector3(sin(sway)*0.008, sin(sway*2)*0.007 - kick * 0.14, kick * 0.12)
	hands.rotation.z = sin(sway) * 0.008
	held_root.position = Vector3(-0.19, -0.02, -0.85) if inspecting else Vector3(-0.2, -0.15, -0.67)
	held_root.rotation = Vector3(visual_angle.y, visual_angle.x, 0)
	held_root.scale = Vector3.ONE * (inspect_scale * 0.72 if inspecting else 0.36)
	tool_root.visible = not inspecting
	foam = move_toward(foam, 0, delta * 0.12)
	camera.rotation.z = sin(Time.get_ticks_msec()*0.018)*foam*0.04

func target() -> Dictionary:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 4.0, 5)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)
