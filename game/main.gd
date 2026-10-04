extends Node3D

const StateScript = preload("res://game/state.gd")
const WorldScript = preload("res://game/workshop.gd")
const PlayerScript = preload("res://game/player.gd")
const InterfaceScript = preload("res://game/interface.gd")
const SoundScript = preload("res://game/sound.gd")
const VoiceScript = preload("res://game/voice.gd")
const UpdaterScript = preload("res://game/updater.gd")
const TutorialScript = preload("res://game/tutorial.gd")
const MountainScript = preload("res://game/mountain.gd")
const MountainViewScript = preload("res://game/mountain_view.gd")

var state: Node
var workshop: Node3D
var mountain_view: Node3D
var player: CharacterBody3D
var ui: CanvasLayer
var sound: Node
var voice: Node3D
var updater: Node
var tutorial: Node
var settings := {"sensitivity":0.0025,"fov":78.0,"volume":0.7,"fullscreen":false,"voice_enabled":true,"mic_muted":false,"voice_volume":0.85,"mic_gain":1.0,"input_device":"Default","auto_updates":true}
var active := false
var gem_nodes := {}
var avatars := {}
var selection := 0
var mine_target := -1
var mine_damage := 0
var mine_warned := -1
var mine_progress := 0.0
var explosives := {}
var throw_ready_at := {}
var auto_pick_timer := 0.0
var recent_drops := {}
var pending_picks := {}
var last_ore_total := 0
var shake := 0.0
var auto_collect := true
var pose_timer := 0.0
var action_cooldown := 0.0
var selected_target := {}
var was_certified := false
var particle_root: Node3D
var screenshot_path := ""
var session_mode := "SOLO"
var test_runner: Node
var last_money := 22
var last_upgrades := 0
var tray_page := 0
var cosmetic_signature := ""

func _ready() -> void:
	DisplayServer.window_set_title("DIAMOND IN THE ROUGH")
	load_settings()
	state = StateScript.new()
	add_child(state)
	workshop = WorldScript.new()
	add_child(workshop)
	workshop.build(self)
	state.station_positions = workshop.stations.duplicate()
	state.upgrade_positions = workshop.upgrade_positions.duplicate()
	mountain_view = MountainViewScript.new()
	add_child(mountain_view)
	mountain_view.build(self)
	mountain_view.surface_settled.connect(func(): call_deferred("refresh"))
	player = PlayerScript.new()
	add_child(player)
	player.build(self)
	ui = InterfaceScript.new()
	add_child(ui)
	ui.build(self)
	ui.request_start.connect(start_session)
	ui.request_resume.connect(resume_game)
	ui.request_action.connect(ui_action)
	ui.setting_changed.connect(set_setting)
	state.changed.connect(refresh)
	state.notice.connect(on_notice)
	state.pose_received.connect(remote_pose)
	state.peer_left.connect(remove_avatar)
	state.connection_status.connect(on_network)
	state.cells_changed.connect(on_cells_changed)
	state.throw_spawned.connect(spawn_explosive)
	state.blasted.connect(on_blast)
	sound = SoundScript.new()
	add_child(sound)
	voice=VoiceScript.new()
	add_child(voice)
	for voice_arg in OS.get_cmdline_user_args():
		if voice_arg.begins_with("--verify-voice="): voice.test_mode=true
	voice.build(self)
	updater=UpdaterScript.new()
	add_child(updater)
	for update_arg in OS.get_cmdline_user_args():
		if update_arg.begins_with("--verify"): updater.test_mode=true
	updater.status_changed.connect(ui.update_updates)
	updater.build(self)
	tutorial=TutorialScript.new()
	add_child(tutorial)
	for tutorial_arg in OS.get_cmdline_user_args():
		if tutorial_arg.begins_with("--verify"): tutorial.test_mode=true
	tutorial.changed.connect(ui.set_tutorial)
	tutorial.build(self)
	particle_root = Node3D.new()
	add_child(particle_root)
	apply_settings()
	ui.show_menu(false)
	var args := OS.get_cmdline_user_args()
	var slot := "workshop"
	for arg in args:
		if arg.begins_with("--save-slot="): slot = arg.get_slice("=",1)
		if arg.begins_with("--screenshot="): screenshot_path = arg.trim_prefix("--screenshot=")
	state.configure_save(slot)
	for arg in args:
		if arg == "--solo": start_session("solo", "", 24680, false)
		if arg == "--host": start_session("host", "", port_from_args(args), false)
		if arg.begins_with("--join="): start_session("join", arg.trim_prefix("--join="), port_from_args(args), false)
	for arg in args:
		if arg=="--verify-redesign":
			test_runner=load("res://game/redesign_verification.gd").new()
			add_child(test_runner)
			test_runner.begin(self,args)
		if arg.begins_with("--verify-updater="):
			test_runner=load("res://game/updater_verification.gd").new()
			add_child(test_runner)
			test_runner.begin(self,args)
		if arg.begins_with("--verify-voice="):
			test_runner=load("res://game/voice_verification.gd").new()
			add_child(test_runner)
			test_runner.begin(self,arg.trim_prefix("--verify-voice="),args)
		if arg.begins_with("--verify="):
			test_runner = load("res://game/verification.gd").new()
			add_child(test_runner)
			test_runner.begin(self, arg.trim_prefix("--verify="), args)
	if not screenshot_path.is_empty():
		capture_later()

func port_from_args(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with("--port="): return int(arg.trim_prefix("--port="))
	return 24680

func start_session(mode: String, address: String, port: int, new_save: bool) -> void:
	if is_instance_valid(voice): voice.stop_session()
	for id in avatars.keys(): remove_avatar(int(id))
	player.inspecting=false
	ui.hide_inspection()
	state.leave()
	if mode != "join":
		state.start_solo()
		if new_save or not state.load_game(): state.new_game()
		if mode == "host":
			var err: int = state.host(port)
			if err != OK:
				ui.toast("Could not host on UDP %s. Try another port." % port)
				return
	else:
		var err: int = state.join(address, port)
		if err != OK:
			ui.toast("Could not connect. Check the host address and UDP port.")
			return
	session_mode = mode.to_upper()
	for fuse in explosives.keys(): clear_explosive(int(fuse))
	mine_target = -1
	mountain_view.hide_crack()
	# A local world is ready before play starts; a joining client builds progressively.
	if mode != "join": mountain_view.flush()
	active = true
	player.enabled = true
	player.hands.show()
	player.position = Vector3(0, 0.12, 7.2)
	player.yaw = 0
	player.pitch = -0.10
	player.update_view()
	ui.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	state.set_player(state.local_id(), player.position, player.yaw, player.pitch)
	was_certified = state.certified
	last_money = state.money
	last_upgrades = state.upgrades.size()
	last_ore_total = state.ore_total()
	player.set_tool("pickaxe")
	refresh()
	ui.update_network(session_mode + (" · UDP %s" % port if mode == "host" else ""))
	tutorial.start_session(mode)

func resume_game() -> void:
	player.inspecting = false
	ui.hide_inspection()
	ui.hide_menu()
	if active: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func return_to_menu() -> void:
	voice.stop_session()
	if active and state.is_authority(): state.save_game()
	state.leave()
	active = false
	tutorial.stop()
	player.enabled = false
	player.hands.hide()
	player.inspecting = false
	ui.hide_inspection()
	ui.show_menu(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for id in avatars.keys(): remove_avatar(id)

func ui_action(kind: String, args: Dictionary) -> void:
	match kind:
		"updates_check": updater.check_for_updates()
		"updates_download": updater.download_update()
		"updates_install": install_update()
		"updates_open_repo": updater.open_repository()
		"updates_use_cli": updater.use_github_cli()
		"updates_token": updater.set_session_token(str(args.get("token","")))
		"tutorial_restart":
			if not active: start_session("solo","",24680,false)
			tutorial.restart()
			resume_game()
		"tutorial_skip": tutorial.skip()
		"save": save_now()
		"unstuck": unstuck()
		"recover": recover_items()
		"menu": return_to_menu()
		"close_modal": resume_game()
		_: state.action(kind, args)
	if ui.menu_visible: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func install_update() -> void:
	if updater.status.phase!="ready": return
	if active and state.is_authority() and not state.save_game():
		ui.toast("The workshop could not be saved. Update installation stopped.")
		return
	if updater.prepare_install()<0: return
	voice.stop_session()
	state.leave()
	get_tree().quit()

func _process(delta: float) -> void:
	for peer in avatars:
		var badge: Node3D=avatars[peer].get_node_or_null("VoiceBadge")
		if badge:
			badge.visible=voice.is_speaking(int(peer))
	action_cooldown = maxf(0, action_cooldown-delta)
	update_explosives(delta)
	if not active: return
	tutorial.tick(delta)
	pose_timer += delta
	if pose_timer >= 0.05:
		pose_timer = 0
		state.send_pose(player.position, player.yaw, player.pitch)
	selected_target = player.target()
	if player.tool=="pickaxe" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and not ui.menu_visible and not player.inspecting:
		if target_cell()>=0: mine_step()
	if mine_target>=0 and target_cell()!=mine_target:
		mine_target=-1
		mountain_view.hide_crack()
	auto_pick_timer -= delta
	if auto_pick_timer <= 0.0:
		auto_pick_timer = 0.25
		auto_pickup()
	var prompt := interaction_prompt()
	var held: Array = state.held_ids()
	if held.is_empty():
		selection = 0
		player.show_held({})
		if player.inspecting:
			player.inspecting = false
			ui.hide_inspection()
	else:
		selection = posmod(selection, held.size())
		var gem: Dictionary = state.gems[int(held[selection])]
		if player.inspecting and player.held_id!=int(gem.id): ui.show_inspection(gem,state.upgrades.has("loupe"))
		player.show_held(gem)
	ui.update_hud(state, tool_label(), state.capacity(), prompt, objective(), carry_text())
	if ui.menu_visible: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for n in particle_root.get_children():
		if not n.has_meta("velocity"): continue
		var velocity: Vector3 = n.get_meta("velocity")
		velocity.y -= 9.0*delta*float(n.get_meta("gravity",0.0))
		n.set_meta("velocity",velocity)
		n.position += velocity * delta
		n.rotation += Vector3(2,1,3)*delta
		var life: float = n.get_meta("life",1.0)-delta
		n.set_meta("life",life)
		if life<0: n.queue_free()
	shake = move_toward(shake,0.0,delta*1.6)
	player.camera.h_offset = sin(Time.get_ticks_msec()*0.09)*shake*0.12
	player.camera.v_offset = cos(Time.get_ticks_msec()*0.11)*shake*0.10

func tool_label() -> String:
	match player.tool:
		"dynamite","tnt","buster":
			var tier: String=player.tool
			var wait: float=float(throw_ready_at.get(tier,0))-Time.get_ticks_msec()/1000.0
			return str(state.upgrade_names[tier])+(" · ready" if wait<=0.0 else " · %.1f s" % wait)
	return {"pickaxe":"Old pickaxe","steel_pick":"Steel pickaxe","drill":"Power drill"}[state.mining_tool()]

func carry_text() -> String:
	return "Satchel %d / %d ore  ·  $%d\nHands %d / %d finds" % [state.ore_total(),state.ore_capacity(),state.ore_value(),state.held_ids().size(),state.capacity()]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if ui.menu_visible and active:
			resume_game()
		elif active:
			player.inspecting = false
			ui.hide_inspection()
			ui.show_menu(true)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if not active or ui.menu_visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E: interact()
			KEY_Q: drop_selected()
			KEY_TAB:
				player.inspecting = false
				ui.hide_inspection()
				ui.show_collection(state)
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_1: equip("pickaxe")
			KEY_2: equip_explosive("dynamite")
			KEY_3: equip_explosive("tnt")
			KEY_4: equip_explosive("buster")
			KEY_F: prank("label")
			KEY_M:
				set_setting("mic_muted",not bool(settings.mic_muted))
				ui.toast("Microphone muted." if settings.mic_muted else "Microphone unmuted · hold V to talk.")
			KEY_G: prank("foam")
			KEY_C:
				var collectible := current_gem()
				if not collectible.is_empty(): state.action("collect",{"id":int(collectible.id)})
			KEY_R: prank("present")
			KEY_H:
				player.hat_mode = (player.hat_mode+1)%3
				state.action("prank", {"target":state.local_id(),"mode":"hat"})
				ui.toast(["Bucket hat off.", "Bucket hat equipped. A very practical crown.", "Gem hat equipped. Taste is optional."][player.hat_mode])
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: use_tool()
			MOUSE_BUTTON_RIGHT: toggle_inspection()
			MOUSE_BUTTON_WHEEL_UP: cycle_candidate(-1)
			MOUSE_BUTTON_WHEEL_DOWN: cycle_candidate(1)

func equip(tool: String) -> void:
	player.set_tool(tool)
	player.inspecting = false
	ui.hide_inspection()
	mine_target = -1
	mountain_view.hide_crack()
	sound.play("pick")

func equip_explosive(tier: String) -> void:
	if state.upgrades.has(tier):
		equip(tier)
		ui.toast("%s ready · left click to throw." % state.upgrade_names[tier])
	else:
		ui.toast("%s · $%d at the camp outfitter." % [state.upgrade_names[tier],int(state.prices[tier])])

func current_gem() -> Dictionary:
	var ids: Array = state.held_ids()
	if ids.is_empty(): return {}
	return state.gems[int(ids[posmod(selection,ids.size())])]

func toggle_inspection() -> void:
	var gem := current_gem()
	if gem.is_empty():
		ui.toast("Pick up a crystal or fossil first. Right-click to inspect it closely.")
		return
	player.inspecting = not player.inspecting
	if player.inspecting:
		ui.show_inspection(gem,state.upgrades.has("loupe"))
		tutorial.on_action("inspect")
	else:
		ui.hide_inspection()

func cycle_candidate(direction: int) -> void:
	if player.inspecting and Input.is_physical_key_pressed(KEY_CTRL):
		player.inspect_scale = clampf(player.inspect_scale-direction*0.1,0.7,1.6)
		return
	var target_id: int=int(target_meta("gem_id",-1))
	var targets_tray: bool=str(target_meta("station",""))=="tray" or (target_id>=0 and state.gems.get(target_id,{}).get("stage","")=="tray")
	if not player.inspecting and state.held_ids().is_empty() and targets_tray:
		var pages: int=maxi(1,ceili(float(tray_count())/48))
		tray_page=posmod(tray_page+direction,pages)
		refresh()
		ui.toast("Inspection storage · tray %s of %s" % [tray_page+1,pages])
		return
	selection += direction
	var ids: Array = state.held_ids()
	if not ids.is_empty():
		selection = posmod(selection,ids.size())
		if player.inspecting: ui.show_inspection(current_gem(),state.upgrades.has("loupe"))

func target_meta(key: String, fallback: Variant=null) -> Variant:
	if selected_target.is_empty(): return fallback
	var body: Object = selected_target.get("collider")
	return body.get_meta(key,fallback) if is_instance_valid(body) else fallback

## The mountain block under the crosshair, if any.
func target_cell() -> int:
	if not bool(target_meta("mountain",false)): return -1
	return mountain_view.cell_from_hit(selected_target.position,selected_target.normal)

func interaction_prompt() -> String:
	if player.inspecting: return "Mouse: rotate   ·   Wheel: next   ·   Ctrl + wheel: zoom   ·   Right-click: finish"
	var upgrade: String=str(target_meta("upgrade",""))
	if state.prices.has(upgrade):
		var equipment: String=str(state.upgrade_names[upgrade])
		if upgrade in state.upgrades: return equipment+" · owned"
		var price: int=int(state.prices[upgrade])
		var purchase: String="E: buy" if state.money>=price else "Need $%d more" % (price-state.money)
		return "%s · $%d\n%s · %s" % [equipment,price,purchase,state.benefits[upgrade]]
	var gid: int = int(target_meta("gem_id",-1))
	if gid >= 0:
		var g: Dictionary = state.gems.get(gid,{})
		if g.get("stage","")=="tray" and state.held_ids().is_empty():
			return "[E] Pick up %s · [Wheel] storage tray %s/%s" % [g.get("name","candidate"),tray_page+1,maxi(1,ceili(float(tray_count())/48))]
		return "[E] Pick up %s   ·   [RMB] Inspect held stone" % str(g.get("name","a find")).to_lower()
	if player.tool in ["dynamite","tnt","buster"]:
		return "Left click: throw %s · 1: back to the pickaxe" % str(state.upgrade_names[player.tool]).to_lower()
	var cell: int = target_cell()
	if cell >= 0:
		var code: int = state.cell_code(cell)
		var block: String = MountainScript.block_name(code)
		if code == MountainScript.BEDROCK: return "Bedrock · unbreakable"
		var c: Vector3i = MountainScript.coords(cell)
		if state.mining_tool()=="pickaxe" and state.mountain.needs_steel(c.x,c.y,c.z):
			return "%s · too hard for the old pickaxe\nBuy a steel pickaxe or blast it" % block
		var ore: String = MountainScript.ore_for_code(code)
		if not ore.is_empty():
			if state.ore_total()>=state.ore_capacity(): return "%s · satchel full · sell at the exchange" % block
			return "%s · $%d · hold left click to mine%s" % [block,int(MountainScript.ORE_VALUES[ore]),progress_text(cell)]
		if code == MountainScript.CRYSTAL: return "Crystal vein · something clear glints inside%s" % progress_text(cell)
		if code == MountainScript.CURIO: return "Fossil seam · something is buried here%s" % progress_text(cell)
		return "%s · hold left click to mine%s" % [block,progress_text(cell)]
	var station := str(target_meta("station",""))
	match station:
		"sell": return "[E] Sell ore and finds · clear crystals go safely to the tray"
		"shop": return "Point at a tool to see its price. E: buy"
		"tray": return "[E] Store finds / next empty-hand tray · [Wheel] storage %s/%s" % [tray_page+1,maxi(1,ceili(float(tray_count())/48))]
		"certify":
			var candidate:=current_gem()
			var step: int=state.certification_step if int(candidate.get("id",-1))==state.certification_id else 0
			return "[E] Certification · %s" % ["optical inspection","facet response test","blue-light test · reveal"][clampi(step,0,2)]
		"recover": return "[E] Recover lost finds"
		"collection": return "[E] Journal & specimen collection"
	var peer: int = int(target_meta("peer_id",-1))
	if peer >= 0: return "[F] Label   [G] Foam   [R] Wrapped present   [LMB] Dump your finds on them"
	return ""

func progress_text(cell: int) -> String:
	if cell != mine_target or mine_progress <= 0.0: return ""
	return "  ·  %d%%" % roundi(mine_progress*100.0)

func rock_tint(code: int) -> Color:
	match code:
		MountainScript.GRASS, MountainScript.DIRT: return Color("6e5a44")
		MountainScript.SNOW: return Color("e6ebee")
		MountainScript.GRANITE: return Color("5c5d5f")
	return Color("85837c")

func objective() -> String:
	if state.certified: return "Diamond certified. Keep blasting for treasure or fill your collection."
	if not state.upgrades.has("steel_pick"):
		if state.money < 10 and state.ore_total() == 0: return "Walk to the mountain and hold left click to mine ore."
		return "Sell ore at the exchange. A steel pickaxe costs $60."
	if not state.upgrades.has("dynamite"): return "Save $180 for dynamite and blast your way in."
	if not state.upgrades.has("loupe"): return "Keep clear crystals. The loupe ($150) reveals their clues."
	if not state.upgrades.has("tnt"): return "TNT ($750) clears big craters. Dig towards the mountain's core."
	return "The diamond lies deep in the core. Test clear crystals at the bench."

func use_tool() -> void:
	if action_cooldown>0 or player.inspecting: return
	var peer: int = int(target_meta("peer_id",-1))
	if peer>=0:
		prank("scoop")
		return
	if player.tool in ["dynamite","tnt","buster"]:
		throw_explosive(player.tool)
		return
	var gid: int = int(target_meta("gem_id",-1))
	if gid>=0:
		pick(gid)
		return
	if target_cell()>=0:
		mine_step()
		return
	ui.toast("Aim at the mountain to mine. E uses stations and picks up finds.")

func mine_step() -> void:
	if action_cooldown>0: return
	var cell: int = target_cell()
	if cell<0: return
	var code: int = state.cell_code(cell)
	var c: Vector3i = MountainScript.coords(cell)
	var tool: String = state.mining_tool()
	action_cooldown = 0.11 if tool=="drill" else 0.3
	player.kick = 0.55 if tool!="drill" else 0.2
	var blocked := ""
	if code == MountainScript.BEDROCK: blocked = "Bedrock. Nothing gets through this."
	elif tool=="pickaxe" and state.mountain.needs_steel(c.x,c.y,c.z): blocked = "Granite is too hard for the old pickaxe. Buy a steel pickaxe or blast it."
	elif not MountainScript.ore_for_code(code).is_empty() and state.ore_total()>=state.ore_capacity(): blocked = "Your satchel is full. Sell your ore at the exchange."
	if not blocked.is_empty():
		sound.play("clank")
		if mine_warned != cell:
			mine_warned = cell
			ui.toast(blocked)
		return
	if cell != mine_target:
		mine_target = cell
		mine_damage = 0
	mine_damage += 1 if tool=="pickaxe" else 2
	mine_progress = clampf(float(mine_damage)/float(state.mountain.hardness(c.x,c.y,c.z,code)),0.0,1.0)
	if not selected_target.is_empty():
		burst(selected_target.position,rock_tint(code),3,true,1.1)
	state.action("mine",{"cell":cell})
	sound.play("drill" if tool=="drill" else "mine")
	tutorial.on_action("mine")

func on_cells_changed(list: PackedInt32Array) -> void:
	var near := 0
	for cell in list:
		if cell == mine_target:
			mine_target = -1
			mountain_view.hide_crack()
		if list.size() <= 3 and near < 3:
			var at: Vector3 = MountainScript.cell_center(cell)
			if at.distance_to(player.position) < 9.0:
				near += 1
				burst(at,Color("8d8a80"),10,true)
	if near > 0: sound.play("break")
	var total: int = state.ore_total()
	if total > last_ore_total and list.size() <= 3:
		ui.toast("+%d ore · satchel %d / %d" % [total-last_ore_total,total,state.ore_capacity()])
	last_ore_total = total

func pick(gid: int) -> void:
	var g: Dictionary = state.gems.get(gid,{})
	if g.is_empty(): return
	pending_picks[gid] = Time.get_ticks_msec()
	state.action("pick",{"id":gid})
	tutorial.on_action("pick",{"id":gid,"fresh":not bool(g.get("searched",false))})
	sound.play("pick")
	player.kick = 0.28

## Finds that fall out of the rock are collected by walking over them.
func auto_pickup() -> void:
	if not auto_collect or player.inspecting or state.held_ids().size() >= state.capacity(): return
	var now: int = Time.get_ticks_msec()
	var magnet: bool = state.upgrades.has("magnet")
	var nearest := -1
	var best := 1.9
	var in_magnet_range := false
	for g in state.gems.values():
		if g.stage != "loose": continue
		var id: int = int(g.id)
		if now - int(recent_drops.get(id,-100000)) < 4000 or now - int(pending_picks.get(id,-100000)) < 700: continue
		var a: Array = g.pos
		var d: float = player.position.distance_to(Vector3(float(a[0]),float(a[1]),float(a[2])))
		if d < 7.0: in_magnet_range = true
		if d < best:
			best = d
			nearest = id
	if magnet and in_magnet_range:
		state.action("vacuum")
		sound.play("pick")
	elif nearest >= 0:
		pick(nearest)

func throw_explosive(tier: String) -> void:
	if not state.upgrades.has(tier):
		equip_explosive(tier)
		return
	var now: float = Time.get_ticks_msec()/1000.0
	if now < float(throw_ready_at.get(tier,0.0)) and not state.test_mode:
		ui.toast("%s is being prepared · %.1f s" % [state.upgrade_names[tier],float(throw_ready_at[tier])-now])
		return
	throw_ready_at[tier] = now + float(state.EXPLOSIVES[tier].cooldown)
	var forward: Vector3 = -player.camera.global_basis.z
	var origin: Vector3 = player.camera.global_position + forward*0.6 - Vector3(0,0.15,0)
	var velocity: Vector3 = forward*11.0 + Vector3.UP*2.6 + player.velocity*0.5
	state.action("throw",{"tier":tier,"pos":[origin.x,origin.y,origin.z],"vel":[velocity.x,velocity.y,velocity.z]})
	player.kick = 0.8
	action_cooldown = 0.45

func spawn_explosive(peer: int, tier: String, origin: Vector3, velocity: Vector3, fuse: int) -> void:
	var body := RigidBody3D.new()
	body.name = "Fuse_%d" % fuse
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.6
	body.continuous_cd = true
	body.angular_damp = 1.5
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.bounce = 0.05
	body.physics_material_override.friction = 1.0
	# Charges stick where they first land instead of rolling back down the steps.
	body.contact_monitor = true
	body.max_contacts_reported = 1
	body.body_entered.connect(func(_other: Node): body.set_deferred("freeze",true))
	var visual: Node3D = workshop.make_explosive(tier)
	visual.scale = Vector3.ONE*1.5
	body.add_child(visual)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.24 if tier=="buster" else 0.13
	col.shape = shape
	body.add_child(col)
	body.position = origin
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(randf_range(-6,6),randf_range(-3,3),randf_range(-6,6))
	add_child(body)
	explosives[fuse] = {"node":body,"left":float(state.EXPLOSIVES[tier].fuse),"owner":peer,"tier":tier,"sent":false}
	if origin.distance_to(player.position) < 30.0: sound.play("fuse")

func update_explosives(delta: float) -> void:
	for fuse in explosives.keys():
		var entry: Dictionary = explosives[fuse]
		var body: RigidBody3D = entry.node
		if not is_instance_valid(body):
			explosives.erase(fuse)
			continue
		entry.left = float(entry.left) - delta
		var spark: Node3D = body.get_node_or_null("Explosive/Spark")
		if spark: spark.visible = fmod(float(entry.left),0.24) > 0.1 or float(entry.left) < 0.6
		var due: bool = float(entry.left) <= 0.0 or body.position.y < -20.0
		if due and int(entry.owner)==state.local_id() and not bool(entry.sent):
			entry.sent = true
			var at: Vector3 = body.position
			state.action("blast",{"fuse":int(fuse),"pos":[at.x,at.y,at.z]})
		elif float(entry.left) < -6.0:
			clear_explosive(int(fuse))

func clear_explosive(fuse: int) -> void:
	if explosives.has(fuse):
		var body: Node = explosives[fuse].node
		if is_instance_valid(body): body.queue_free()
		explosives.erase(fuse)

func on_blast(fuse: int, at: Vector3, tier: String) -> void:
	clear_explosive(fuse)
	var radius: float = float(state.EXPLOSIVES[tier].radius)
	var distance: float = player.position.distance_to(at)
	var flash := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	flash.mesh = ball
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(1.0,0.62,0.24,0.95)
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash.material_override = glow
	flash.position = at
	flash.scale = Vector3.ONE*0.3
	add_child(flash)
	var core := MeshInstance3D.new()
	core.mesh = ball
	var heat := glow.duplicate()
	heat.albedo_color = Color(1.0,0.95,0.7,1.0)
	core.material_override = heat
	core.position = at
	core.scale = Vector3.ONE*0.2
	add_child(core)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb35c")
	light.light_energy = 6.0
	light.omni_range = radius*4.0
	light.position = at
	add_child(light)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash,"scale",Vector3.ONE*radius*1.15,0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(glow,"albedo_color:a",0.0,0.55)
	tween.tween_property(core,"scale",Vector3.ONE*radius*0.6,0.16)
	tween.tween_property(heat,"albedo_color:a",0.0,0.3)
	tween.tween_property(light,"light_energy",0.0,0.7)
	tween.chain().tween_callback(flash.queue_free)
	tween.tween_callback(core.queue_free)
	tween.tween_callback(light.queue_free)
	var debris: int = clampi(int(radius*12.0),20,80)
	burst(at,Color("8a8780"),debris,true,radius*2.2)
	burst(at,Color("ffcf7a"),debris/3,false,radius*1.5)
	# A slow grey plume hangs over the crater after the flash.
	for puff in range(clampi(int(radius*4.0),8,26)):
		var smoke := MeshInstance3D.new()
		var cloud := SphereMesh.new()
		cloud.radius = randf_range(0.4,0.9)*clampf(radius/2.4,1.0,2.2)
		cloud.height = cloud.radius*2.0
		cloud.radial_segments = 8
		cloud.rings = 4
		smoke.mesh = cloud
		var haze := StandardMaterial3D.new()
		haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		haze.albedo_color = Color(0.55,0.53,0.5,0.55)
		haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke.material_override = haze
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke.position = at + Vector3(randf_range(-1,1),randf_range(-0.3,0.6),randf_range(-1,1))*radius*0.5
		add_child(smoke)
		var drift := create_tween().set_parallel(true)
		drift.tween_property(smoke,"position",smoke.position+Vector3(randf_range(-0.6,0.6),randf_range(1.2,2.6)+radius*0.3,randf_range(-0.6,0.6)),2.4)
		drift.tween_property(smoke,"scale",Vector3.ONE*1.8,2.4)
		drift.tween_property(haze,"albedo_color:a",0.0,2.4).set_ease(Tween.EASE_IN)
		drift.chain().tween_callback(smoke.queue_free)
	sound.play("boom",clampf(-4.0-distance*0.35,-30.0,-2.0))
	if distance < radius*5.0:
		shake = maxf(shake,clampf(1.2-distance/(radius*4.0),0.15,1.0))
	if distance < radius+2.0 and is_instance_valid(player):
		var push: Vector3 = (player.position-at)
		push.y = 0.0
		player.velocity += push.normalized()*(4.0+radius) + Vector3.UP*(3.0+radius*0.6)

func interact() -> void:
	if action_cooldown>0: return
	var upgrade: String=str(target_meta("upgrade",""))
	if state.prices.has(upgrade):
		state.action("buy",{"upgrade":upgrade})
		tutorial.on_action("buy",{"upgrade":upgrade})
		action_cooldown=0.35
		return
	var gid: int = int(target_meta("gem_id",-1))
	if gid>=0:
		pick(gid)
		return
	var station := str(target_meta("station",""))
	match station:
		"shop":
			ui.toast("Point at a tool on its display and press E to buy it.")
		"collection":
			await collect_held_batch()
			player.inspecting=false
			ui.hide_inspection()
			ui.show_collection(state)
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		"sell":
			state.action("sell")
			tutorial.on_action("sell")
		"tray":
			if not state.held_ids().is_empty():
				state.action("tray")
				tutorial.on_action("tray")
			else:
				var pages: int=maxi(1,ceili(float(tray_count())/48))
				tray_page=posmod(tray_page+1,pages)
				refresh()
				ui.toast("Storage tray %s/%s · point at a stone and press E. Wheel changes trays." % [tray_page+1,pages])
		"certify":
			var gem := current_gem()
			if gem.is_empty(): ui.toast("Hold your chosen crystal, then run the three certification tests.")
			else:
				var step: int=state.certification_step if state.certification_id==int(gem.id) else 0
				state.action("certify",{"id":int(gem.id),"test":step})
				sound.play("test")
		"recover":
			state.action("recover")
		_:
			if target_cell()>=0: use_tool()
	action_cooldown=0.35

func drop_selected() -> void:
	var gem := current_gem()
	if gem.is_empty(): return
	var pos: Vector3 = player.camera.global_position - player.camera.global_basis.z * 1.0
	recent_drops[int(gem.id)] = Time.get_ticks_msec()
	state.action("drop",{"id":int(gem.id),"pos":[pos.x,pos.y,pos.z]})
	sound.play("drop")
	player.inspecting = false
	ui.hide_inspection()

func prank(mode: String) -> void:
	var target: int = int(target_meta("peer_id",-1))
	if mode=="label" and target<0:
		var g := current_gem()
		if not g.is_empty():
			state.action("prank",{"mode":"label","target":state.local_id(),"id":int(g.id)})
			ui.toast("CERTIFIED DIAMOND label applied. The bench remains unimpressed.")
			sound.play("prank")
		return
	if target<0:
		ui.toast("Invite a friend to share the mountain — and the polishing foam.")
		return
	state.action("prank",{"target":target,"mode":mode})
	sound.play("prank")
	if avatars.has(target):
		burst(avatars[target].position+Vector3.UP*1.5, Color("f0f8e9"),14)

func refresh() -> void:
	if not is_instance_valid(workshop): return
	workshop.update_upgrades(state.upgrades)
	if is_instance_valid(player) and player.tool=="pickaxe" and player.mining_look!=state.mining_tool(): player.set_tool("pickaxe")
	var desired := {}
	var tray_index := 0
	var collection_index := 0
	tray_page=clampi(tray_page,0,maxi(0,ceili(float(tray_count())/48)-1))
	for key in state.gems:
		var gem: Dictionary = state.gems[key]
		var stage := str(gem.stage)
		var p := Vector3.ZERO
		if stage=="tray":
			var slot: int=tray_index-tray_page*48
			tray_index+=1
			if slot<0 or slot>=48: continue
			p=Vector3(-8+(slot%8-3.5)*0.28,1.31,-0.6+int(slot/8)*0.23)
		elif stage=="loose":
			var a: Array=gem.get("pos",[0,1,5])
			p=ground_point(Vector3(float(a[0]),float(a[1]),float(a[2])))
		elif stage=="collection":
			p=Vector3(4.2+(collection_index%6)*0.32,1.5+int(collection_index/6)*0.4,8.1)
			collection_index+=1
		elif stage=="certified":
			p=Vector3(0,1.65,-8)
		else: continue
		var id: int=int(key)
		desired[id]=true
		var visual_signature: String=str(gem.get("flagged",false))+str(gem.get("tag",false))+str(gem.get("clean",false))
		if gem_nodes.has(id) and is_instance_valid(gem_nodes[id]) and gem_nodes[id].get_meta("stage")==stage and gem_nodes[id].get_meta("visual","")==visual_signature:
			if stage=="loose" and gem_nodes[id].get_meta("rest",p)!=p:
				# Finds settle further when the rock beneath them is mined away.
				gem_nodes[id].set_meta("rest",p)
				create_tween().tween_property(gem_nodes[id],"position",p,0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			elif stage!="loose": gem_nodes[id].position=p
			continue
		var previous: Vector3 = p
		if gem_nodes.has(id) and is_instance_valid(gem_nodes[id]):
			previous = gem_nodes[id].position
			gem_nodes[id].queue_free()
		var body: PhysicsBody3D=StaticBody3D.new()
		body.collision_layer=4
		body.set_meta("gem_id",id)
		body.set_meta("stage",stage)
		body.set_meta("visual",visual_signature)
		var visual: Node3D=workshop.make_gem(str(gem.kind))
		visual.scale=Vector3.ONE*(0.3 if stage=="loose" else (0.35 if stage=="certified" else (0.26 if stage=="collection" else 0.18)))
		body.add_child(visual)
		var collision:=CollisionShape3D.new()
		var shape:=SphereShape3D.new()
		shape.radius=0.26 if stage=="loose" else 0.12
		collision.shape=shape
		body.add_child(collision)
		body.position=p
		body.rotation=Vector3(0.0,float(id)*2.31,0.06)
		add_child(body)
		if stage=="loose":
			# Fresh finds pop out of the rock and drop onto their resting place.
			body.set_meta("rest",p)
			var start: Vector3=previous if previous!=p else p+Vector3(0,0.6,0)
			body.position=start
			create_tween().tween_property(body,"position",p,0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			if str(gem.kind) in ["suspect","diamond"]:
				var glint:=OmniLight3D.new()
				glint.light_color=Color("bff6ff")
				glint.light_energy=0.6
				glint.omni_range=1.6
				glint.position.y=0.35
				body.add_child(glint)
		gem_nodes[id]=body
		if gem.get("flagged",false):
			avatar_box(body,Vector3(0.035,0.19,0.035),Vector3(0,0.22,0),Color("38372f"))
			avatar_box(body,Vector3(0.15,0.10,0.025),Vector3(0.055,0.28,0),Color("e1b04d"))
		if gem.get("tag",false):
			avatar_box(body,Vector3(0.27,0.07,0.015),Vector3(0,0.1,0.15),Color("ede3cd"))
			var label:=Label3D.new()
			label.text="CERTIFIED*"
			label.position=Vector3(0,0.1,0.161)
			label.font_size=18
			label.pixel_size=0.0015
			label.outline_size=0
			label.modulate=Color("332c21")
			body.add_child(label)
	for id in gem_nodes.keys():
		if not desired.has(id):
			if is_instance_valid(gem_nodes[id]): gem_nodes[id].queue_free()
			gem_nodes.erase(id)
	if active:
		if state.money>last_money: sound.play("sell")
		if state.upgrades.size()>last_upgrades:
			sound.play("buy")
			burst(player.position+Vector3.UP*2,Color("ffd183"),28)
		last_money=state.money
		last_upgrades=state.upgrades.size()
		if state.certified and not was_certified:
			was_certified=true
			sound.play("win")
			burst(Vector3(0,2,-8),Color("a6ffe0"),80)
			ui.show_ending()
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for peer in state.players:
		if int(peer)==state.local_id():
			var me: Dictionary=state.players[peer]
			if float(me.get("foam_until",0.0))>Time.get_unix_time_from_system(): player.foam=0.7
		elif avatars.has(int(peer)):
			update_avatar_props(int(peer))

func on_notice(message: String) -> void:
	if is_instance_valid(ui): ui.toast(message)
	if message.begins_with("Something broke loose"): sound.play("scan")

func on_network(message: String) -> void:
	ui.update_network(message)
	if message.to_lower().contains("failed") or message.to_lower().contains("closed") or message.to_lower().contains("disconnected"):
		voice.stop_session()
		tutorial.stop()
		active=false
		player.enabled=false
		player.hands.hide()
		ui.show_menu(false)
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		ui.toast(message)
		for id in avatars.keys(): remove_avatar(int(id))

func remote_pose(peer: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if peer==state.local_id(): return
	if not avatars.has(peer): create_avatar(peer)
	var avatar: Node3D=avatars[peer]
	avatar.position=pos
	avatar.rotation.y=yaw
	var head: Node3D=avatar.get_node("Head")
	head.rotation.x=pitch*0.4
	update_avatar_props(peer)

func create_avatar(peer: int) -> void:
	var avatar:=Node3D.new()
	avatar.name="Sorter_%s" % peer
	var colors: Array=[Color("45818a"),Color("ba6077"),Color("dda457"),Color("7687b5")]
	var color: Color=colors[posmod(peer,4)]
	avatar_box(avatar,Vector3(0.52,0.68,0.3),Vector3(0,1.04,0),color)
	for x in [-0.15,0.15]:
		avatar_box(avatar,Vector3(0.2,0.58,0.24),Vector3(x,0.4,0),Color("243a40"))
		avatar_box(avatar,Vector3(0.18,0.56,0.2),Vector3(x*2.2,1.08,-0.07),color)
	var head:=Node3D.new()
	head.name="Head"
	head.position=Vector3(0,1.58,0)
	avatar.add_child(head)
	avatar_box(head,Vector3(0.35,0.37,0.34),Vector3.ZERO,Color("d4a477"))
	avatar_box(head,Vector3(0.38,0.18,0.38),Vector3(0,0.18,0),Color("ebbb66"))
	for x in [-0.08,0.08]: avatar_box(head,Vector3(0.04,0.055,0.02),Vector3(x,0.045,-0.18),Color("173539"))
	var voice_badge:=Node3D.new()
	voice_badge.name="VoiceBadge"
	voice_badge.position.y=2.05
	for bar in range(5):
		var height: float=0.045+0.022*float(2-absi(bar-2))
		avatar_box(voice_badge,Vector3(0.025,height,0.025),Vector3((bar-2)*0.045,0,0),Color("edc86e"))
	voice_badge.visible=false
	avatar.add_child(voice_badge)
	var collision:=StaticBody3D.new()
	collision.collision_layer=4
	collision.collision_mask=0
	collision.set_meta("peer_id",peer)
	var col:=CollisionShape3D.new()
	var shape:=CapsuleShape3D.new()
	shape.height=1.8
	shape.radius=0.32
	col.shape=shape
	col.position.y=0.9
	collision.add_child(col)
	avatar.add_child(collision)
	var held:=Node3D.new()
	held.name="SharedHeld"
	held.position=Vector3(0.28,1.15,-0.4)
	avatar.add_child(held)
	add_child(avatar)
	avatars[peer]=avatar

func avatar_box(parent: Node3D,size:Vector3,pos:Vector3,color:Color) -> void:
	var mesh:=MeshInstance3D.new()
	var shape:=BoxMesh.new()
	shape.size=size
	mesh.mesh=shape
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=0.65
	mesh.material_override=material
	mesh.position=pos
	parent.add_child(mesh)

func update_avatar_props(peer: int) -> void:
	if not avatars.has(peer): return
	var avatar: Node3D=avatars[peer]
	var held: Node3D=avatar.get_node("SharedHeld")
	var ids: Array=state.held_ids(peer)
	var next: int=int(ids[0]) if not ids.is_empty() else -1
	if held.get_meta("id",-2)!=next:
		held.set_meta("id",next)
		for child in held.get_children(): child.queue_free()
		if next>=0:
			var mesh: Node3D=workshop.make_gem(str(state.gems[next].kind))
			mesh.scale=Vector3.ONE*0.6
			held.add_child(mesh)
	var info: Dictionary=state.players.get(peer,{})
	var foam: float=maxf(float(info.get("foam_until",0))-Time.get_unix_time_from_system(),0)
	avatar.get_node("Head").rotation.z=sin(Time.get_ticks_msec()*0.015)*minf(foam,1)*0.3
	var head: Node3D=avatar.get_node("Head")
	var hat: String=str(info.get("hat",""))
	if str(head.get_meta("hat","unset"))!=hat:
		head.set_meta("hat",hat)
		if head.has_node("Cosmetic"):
			head.get_node("Cosmetic").queue_free()
		var cosmetic:=Node3D.new()
		cosmetic.name="Cosmetic"
		head.add_child(cosmetic)
		if hat=="Bucket hat":
			avatar_box(cosmetic,Vector3(0.46,0.34,0.46),Vector3(0,0.25,0),Color("a9c7c0"))
			avatar_box(cosmetic,Vector3(0.57,0.04,0.57),Vector3(0,0.09,0),Color("7faba7"))
		elif hat=="Gem crown":
			avatar_box(cosmetic,Vector3(0.42,0.14,0.42),Vector3(0,0.23,0),Color("dfb260"))
			var gem: Node3D=workshop.make_gem("collectible")
			gem.scale=Vector3.ONE*0.3
			gem.position.y=0.4
			cosmetic.add_child(gem)

func remove_avatar(peer: int) -> void:
	if avatars.has(peer):
		avatars[peer].queue_free()
		avatars.erase(peer)

func burst(pos: Vector3,color: Color,count:int,heavy: bool=false,speed: float=1.6) -> void:
	for i in range(count):
		var m:=MeshInstance3D.new()
		var size: float=randf_range(0.07,0.16) if heavy else 0.06
		if heavy:
			var chip:=SphereMesh.new()
			chip.radius=size*0.6
			chip.height=size*0.9
			chip.radial_segments=5
			chip.rings=2
			m.mesh=chip
		else:
			var mesh:=BoxMesh.new()
			mesh.size=Vector3(size,size*0.7,size*1.2)
			m.mesh=mesh
		var material:=StandardMaterial3D.new()
		material.albedo_color=color*randf_range(0.8,1.15)
		material.albedo_color.a=1.0
		if not heavy:
			material.emission_enabled=true
			material.emission=color*0.3
		m.material_override=material
		m.position=pos
		m.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.set_meta("velocity",Vector3(randf_range(-speed,speed),randf_range(0.3,speed*1.5),randf_range(-speed,speed)))
		m.set_meta("gravity",1.0 if heavy else 0.0)
		m.set_meta("life",randf_range(0.5,1.5))
		particle_root.add_child(m)

func save_now() -> void:
	if state.is_authority():
		state.save_game()
		ui.toast("Claim saved. Your diamond stays exactly where it is.")
	else: ui.toast("The host saves your shared claim automatically.")

func unstuck() -> void:
	player.position=Vector3(0,0.2,7.2)
	player.velocity=Vector3.ZERO
	state.send_pose(player.position,player.yaw,player.pitch)
	ui.toast("Back on solid ground. All held items are safe.")

func recover_items() -> void:
	player.position=Vector3(-4,0.2,7.2)
	player.velocity=Vector3.ZERO
	state.send_pose(player.position,player.yaw,player.pitch)
	await get_tree().create_timer(0.18).timeout
	state.action("recover")

## Finds rest on whole blocks in the rules; draw them on the smooth surface instead.
func ground_point(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at+Vector3(0,1.4,0),at-Vector3(0,1.6,0),1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return at
	return Vector3(at.x,float(hit.position.y)+0.14,at.z)

func tray_count() -> int:
	var count:=0
	for g in state.gems.values():
		if g.stage=="tray": count+=1
	return count

func collect_held_batch() -> void:
	for id in state.held_ids().duplicate():
		if state.gems[int(id)].kind in ["collectible","oddity"]:
			state.action("collect",{"id":int(id)})
			await get_tree().create_timer(0.12).timeout

func load_settings() -> void:
	if FileAccess.file_exists("user://settings.json"):
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
		if parsed is Dictionary:
			for key in settings:
				if parsed.has(key): settings[key]=parsed[key]

func set_setting(key: String,value:Variant) -> void:
	if not settings.has(key): return
	settings[key]=value
	apply_settings()
	var f:=FileAccess.open("user://settings.json",FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(settings))

func apply_settings() -> void:
	if is_instance_valid(voice): voice.apply_settings(settings)
	if is_instance_valid(player): player.camera.fov=clampf(float(settings.fov),60,110)
	AudioServer.set_bus_volume_db(0,linear_to_db(clampf(float(settings.volume),0.001,1)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)

func capture_later() -> void:
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("SCREENSHOT_SAVED ",screenshot_path)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if active and is_instance_valid(state) and state.is_authority(): state.save_game()
		get_tree().quit()
