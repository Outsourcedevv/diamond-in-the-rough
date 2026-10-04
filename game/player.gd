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
var tool := "pickaxe"
var mining_look := ""
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
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.32
	floor_stop_on_slope = true
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
	camera.far = 420.0
	camera.fov = 78
	add_child(camera)
	camera.current = true
	hands = Node3D.new()
	hands.scale=Vector3.ONE*0.82
	hands.visible=false
	camera.add_child(hands)
	tool_root = Node3D.new()
	hands.add_child(tool_root)
	held_root = Node3D.new()
	hands.add_child(held_root)
	build_hands()
	set_tool("pickaxe")
	position = Vector3(0, 0.12, 7.2)
	update_view()

func mat(color: Color, metal := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = 0.4
	material.no_depth_test = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
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
	var glove := Color("967550")
	var sleeve := Color("56564b")
	for side in [-1, 1]:
		var arm := rounded_part(hands,0.07,0.48,Vector3(side*0.28,-0.37,-0.29),sleeve)
		arm.rotation=Vector3(-1.20,0,side*-0.20)
		var palm:=rounded_part(hands,0.068,0.18,Vector3(side*0.235,-0.27,-0.54),glove)
		palm.rotation.x=PI*0.5
		box(hands,Vector3(0.105,0.018,0.09),Vector3(side*0.235,-0.205,-0.54),Color("b2946c"))
		for finger in range(4):
			var digit:=rounded_part(hands,0.017,0.09,Vector3(side*0.235+(finger-1.5)*0.032,-0.26,-0.635),glove)
			digit.rotation.x=PI*0.5

func rounded_part(parent: Node3D,radius: float,height: float,at: Vector3,color: Color) -> MeshInstance3D:
	var mesh:=MeshInstance3D.new()
	var shape:=CapsuleMesh.new()
	shape.radius=radius
	shape.height=height
	shape.radial_segments=12
	shape.rings=3
	mesh.mesh=shape
	mesh.material_override=mat(color)
	mesh.material_override.roughness=0.78
	mesh.material_override.metallic_specular=0.2
	mesh.position=at
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

func set_tool(next: String) -> void:
	tool = next
	for child in tool_root.get_children():
		child.queue_free()
	if tool == "pickaxe":
		mining_look = game.state.mining_tool() if is_instance_valid(game) and game.state else "pickaxe"
		if mining_look == "drill":
			box(tool_root, Vector3(0.16, 0.17, 0.34), Vector3(0.17, -0.27, -0.66), Color("e0a24c"), 0.3)
			box(tool_root, Vector3(0.09, 0.2, 0.1), Vector3(0.17, -0.37, -0.6), Color("2f3436"))
			var bit := box(tool_root, Vector3(0.05, 0.05, 0.32), Vector3(0.17, -0.27, -0.98), Color("b8bec0"), 0.9)
			bit.name = "Bit"
		else:
			# The handle rises from the right glove; the head points forward over it.
			var head_color := Color("9aa7ad") if mining_look == "steel_pick" else Color("6f6a62")
			var pick := Node3D.new()
			pick.name = "Pick"
			pick.position = Vector3(0.24, -0.33, -0.56)
			tool_root.add_child(pick)
			box(pick, Vector3(0.045, 0.66, 0.045), Vector3(0, 0.3, 0), Color("8a5f3c"))
			box(pick, Vector3(0.06, 0.07, 0.12), Vector3(0, 0.64, 0), head_color, 0.7)
			var front := box(pick, Vector3(0.04, 0.04, 0.3), Vector3(0, 0.59, -0.19), head_color, 0.7)
			front.rotation.x = -0.42
			var back := box(pick, Vector3(0.04, 0.04, 0.26), Vector3(0, 0.6, 0.17), head_color, 0.7)
			back.rotation.x = 0.42
	elif tool in ["dynamite", "tnt", "buster"]:
		var charge: Node3D = game.workshop.make_explosive(tool)
		charge.position = Vector3(0.18, -0.25, -0.6)
		charge.scale = Vector3.ONE * (0.9 if tool != "buster" else 0.7)
		for mesh in charge.get_children():
			if mesh is MeshInstance3D and mesh.material_override is StandardMaterial3D:
				mesh.material_override = mesh.material_override.duplicate()
				mesh.material_override.no_depth_test = true
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var spark: Node3D = charge.get_node_or_null("Spark")
		if spark: spark.visible = true
		tool_root.add_child(charge)
	kick = 0.25

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
		box(visual,Vector3(0.52,0.13,0.018),Vector3(0,0.11,0.42),Color("f1e4c5"))
		var label:=Label3D.new()
		label.text="CERTIFIED*"
		label.font_size=22
		label.pixel_size=0.002
		label.position=Vector3(0,0.11,0.432)
		label.modulate=Color("342f25")
		label.outline_size=0
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
		# Enough lift to climb one block of the mountain at a time.
		velocity.y = 7.2
	move_and_slide()
	if position.y < -8 or absf(position.x) > 40 or position.z > 12 or position.z < -84:
		game.unstuck()

func _process(delta: float) -> void:
	if not enabled: return
	var moving: bool=Vector2(velocity.x,velocity.z).length()>0.3
	sway += delta * (9.0 if moving else 1.8)
	kick = move_toward(kick, 0, delta * 2.0)
	hands.position = Vector3(sin(sway)*0.006,-0.10+sin(sway*2)*0.005-kick*0.09,-0.14+kick*0.075)
	hands.rotation.z = sin(sway) * 0.008
	# Swing the pickaxe down into the rock; the drill buzzes instead.
	var pick: Node3D = tool_root.get_node_or_null("Pick")
	if pick:
		pick.rotation = Vector3(-0.42 - sin(clampf(kick, 0.0, 0.55) / 0.55 * PI) * 1.05, 0.0, 0.32)
	else:
		var bit: Node3D = tool_root.get_node_or_null("Bit")
		if bit: bit.position.x = 0.17 + sin(Time.get_ticks_msec() * 0.2) * 0.006 * kick * 4.0
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
