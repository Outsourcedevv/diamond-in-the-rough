extends Node3D

const StateScript = preload("res://game/state.gd")
const WorldScript = preload("res://game/workshop.gd")
const PlayerScript = preload("res://game/player.gd")
const InterfaceScript = preload("res://game/interface.gd")
const SoundScript = preload("res://game/sound.gd")
const VoiceScript = preload("res://game/voice.gd")
const UpdaterScript = preload("res://game/updater.gd")

var state: Node
var workshop: Node3D
var player: CharacterBody3D
var ui: CanvasLayer
var sound: Node
var voice: Node3D
var updater: Node
var settings := {"sensitivity":0.0025,"fov":78.0,"volume":0.7,"fullscreen":false,"voice_enabled":true,"mic_muted":false,"voice_volume":0.85,"mic_gain":1.0,"input_device":"Default","auto_updates":true}
var active := false
var gem_nodes := {}
var avatars := {}
var selection := 0
var last_pile := 5
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
	DisplayServer.window_set_title("DIAMOND IN THE ROUGH · Native prototype")
	load_settings()
	state = StateScript.new()
	add_child(state)
	workshop = WorldScript.new()
	add_child(workshop)
	workshop.build(self)
	state.station_positions = workshop.stations.duplicate()
	for i in range(workshop.pile_centers.size()):
		state.pile_positions[i] = workshop.pile_centers[i]
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
	active = true
	player.enabled = true
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
	refresh()
	ui.update_network(session_mode + (" · UDP %s" % port if mode == "host" else ""))
	ui.toast("Welcome to the shed. Scoop a batch, inspect a stone, then visit Scrap & Cash.")

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
	player.enabled = false
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
		var badge: Label3D=avatars[peer].get_node_or_null("VoiceBadge")
		if badge:
			badge.visible=voice.is_speaking(int(peer))
	action_cooldown = maxf(0, action_cooldown-delta)
	if not active: return
	pose_timer += delta
	if pose_timer >= 0.05:
		pose_timer = 0
		state.send_pose(player.position, player.yaw, player.pitch)
	selected_target = player.target()
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
	player.show_batch(held,state.gems)
	var tool_text: String = str({"scoop":"BRASS SCOOP", "hands":"BARE HANDS", "vacuum":"SHOP VAC", "scanner":"CANDIDATE SCANNER"}.get(player.tool,"SCOOP"))
	ui.update_hud(state, str(tool_text), state.capacity(), prompt, objective())
	if ui.menu_visible: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for n in particle_root.get_children():
		n.position += n.get_meta("velocity",Vector3.UP) * delta
		n.rotation += Vector3(2,1,3)*delta
		var life: float = n.get_meta("life",1.0)-delta
		n.set_meta("life",life)
		if life<0: n.queue_free()
	if state.upgrades.has("conveyor"):
		var direction := 1
		for entry in state.players.values():
			if entry.get("prank","")=="reverse" and float(entry.get("prank_until",0))>Time.get_unix_time_from_system(): direction=-1
		workshop.set_conveyor_direction(direction)
		var on_belt: bool=absf(player.position.x-workshop.conveyor_center.x)<0.6 and absf(player.position.z-workshop.conveyor_center.z)<2.3 and player.position.y>0.65 and player.position.y<1.2
		if on_belt and not ui.menu_visible: player.position.z+=delta*direction*0.8

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
			KEY_1: equip("scoop")
			KEY_2: equip("hands")
			KEY_3:
				if state.upgrades.has("vacuum"): equip("vacuum")
				else: ui.toast("Shop vac is on the upgrade board: $440.")
			KEY_4:
				if state.upgrades.has("scanner"): equip("scanner")
				else: ui.toast("The scanner shortlists one local batch. Buy it at the shop.")
			KEY_F: prank("label")
			KEY_M:
				set_setting("mic_muted",not bool(settings.mic_muted))
				ui.toast("Microphone muted." if settings.mic_muted else "Microphone unmuted · hold V to talk.")
			KEY_G: prank("foam")
			KEY_C:
				var collectible := current_gem()
				if not collectible.is_empty(): state.action("collect",{"id":int(collectible.id)})
			KEY_R: prank("present")
			KEY_T: prank("reverse")
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
	sound.play("pick")

func current_gem() -> Dictionary:
	var ids: Array = state.held_ids()
	if ids.is_empty(): return {}
	return state.gems[int(ids[posmod(selection,ids.size())])]

func toggle_inspection() -> void:
	var gem := current_gem()
	if gem.is_empty():
		ui.toast("Pick up a stone first. Right-click to inspect it closely.")
		return
	player.inspecting = not player.inspecting
	if player.inspecting:
		ui.show_inspection(gem,state.upgrades.has("loupe"))
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

func interaction_prompt() -> String:
	if player.inspecting: return "Mouse · rotate     Wheel · next stone     Ctrl + wheel · zoom     RMB · put down"
	var gid: int = int(target_meta("gem_id",-1))
	if gid >= 0:
		var g: Dictionary = state.gems.get(gid,{})
		if g.get("stage","")=="tray" and state.held_ids().is_empty():
			return "[E] Pick up %s · [Wheel] storage tray %s/%s" % [g.get("name","candidate"),tray_page+1,maxi(1,ceili(float(tray_count())/48))]
		return "[E] Pick up %s   ·   [RMB] Inspect held stone" % g.get("name","a glinting candidate")
	var pile: int = int(target_meta("pile",-1))
	if pile >= 0:
		var remaining := 0
		for g in state.gems.values():
			if int(g.pile)==pile and g.stage=="pile": remaining += 1
		return "[LMB] Scoop sector %s · %s searchable pieces remain" % [sector_name(pile),remaining]
	var station := str(target_meta("station",""))
	match station:
		"sell": return "[E] Sell batch · promising stones go safely to the tray"
		"shop": return "[E] Upgrade your operation"
		"tray": return "[E] Pour batch / next empty-hand tray · [Wheel] storage %s/%s" % [tray_page+1,maxi(1,ceili(float(tray_count())/48))]
		"wash": return "[E] Wash held/tray finds" if state.upgrades.has("wash") else "[E] Washing station · unlock at the shop ($180)"
		"sorter": return "[E] Process sector %s · recycle bulk & save promising candidates" % sector_name(last_pile)
		"scanner": return "[E] Scan a batch from sector %s" % sector_name(last_pile)
		"certify":
			var candidate:=current_gem()
			var step: int=state.certification_step if int(candidate.get("id",-1))==state.certification_id else 0
			return "[E] Certification · %s" % ["optical inspection","facet response test","blue-light test · reveal"][clampi(step,0,2)]
		"recover": return "[E] Recover lost items & reset equipment"
		"collection": return "[E] Collection ledger & workshop milestones"
	var peer: int = int(target_meta("peer_id",-1))
	if peer >= 0: return "[F] Label   [G] Foam   [R] Wrapped present   [T] Reverse belt   [LMB] Pour / vacuum"
	return "E · interact     LMB · use tool     RMB · inspect     Tab · ledger"

func sector_name(index: int) -> String:
	return "%s%s" % ["ABC"[clampi(index/4,0,2)], index%4+1]

func objective() -> String:
	if state.certified: return "CERTIFIED! Keep collecting, improve the shed, or invite a friend."
	if state.searched == 0: return "01 / Scoop a batch from the pile. Try E on any individual stone."
	if not state.upgrades.has("scoop"): return "Next: larger scoop $70 · sell batches at Scrap & Cash. Inspect promising stones."
	if not state.upgrades.has("loupe"): return "Next: loupe + lamp $145 · learn the diamond's clues at the inspection tray."
	if not state.upgrades.has("sorter"): return "Next: batch sorter $330 · build a collection of 6 oddities."
	if not state.upgrades.has("scanner"): return "Next: scanner $850 · certify a stone with sharp facets, no bubbles and fast-clearing fog."
	return "Find the real diamond · shortlist nearby batches, inspect the candidates, certify at the back bench."

func use_tool() -> void:
	if action_cooldown>0 or player.inspecting: return
	var peer: int = int(target_meta("peer_id",-1))
	if peer>=0:
		prank("vacuum" if player.tool=="vacuum" else "scoop")
		return
	var gid: int = int(target_meta("gem_id",-1))
	var pile: int = int(target_meta("pile",-1))
	if gid>=0:
		pile = int(state.gems[gid].pile)
		if player.tool=="hands" or state.gems[gid].stage!="pile":
			state.action("pick",{"id":gid})
			sound.play("pick")
			player.kick = 0.28
			return
	if pile<0:
		ui.toast("Aim at the gem pile or a loose object. E uses equipment.")
		return
	last_pile = pile
	if player.tool=="scanner":
		state.action("scan",{"pile":pile,"portable":true})
		sound.play("scan")
	else:
		state.action("scoop",{"pile":pile,"tool":player.tool})
		sound.play("scoop")
	player.kick = 0.65
	action_cooldown = 0.32

func interact() -> void:
	if action_cooldown>0: return
	var gid: int = int(target_meta("gem_id",-1))
	if gid>=0:
		var g: Dictionary = state.gems[gid]
		if g.stage=="pile": last_pile=int(g.pile)
		state.action("pick",{"id":gid})
		sound.play("pick")
		player.kick=0.2
		return
	var station := str(target_meta("station",""))
	match station:
		"shop":
			player.inspecting=false
			ui.hide_inspection()
			ui.show_shop(state)
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		"collection":
			await collect_held_batch()
			player.inspecting=false
			ui.hide_inspection()
			ui.show_collection(state)
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		"sell": state.action("sell")
		"tray":
			if not state.held_ids().is_empty(): state.action("tray")
			else:
				var pages: int=maxi(1,ceili(float(tray_count())/48))
				tray_page=posmod(tray_page+1,pages)
				refresh()
				ui.toast("Storage tray %s/%s · point at a stone and press E. Wheel changes trays." % [tray_page+1,pages])
		"wash":
			state.action("wash")
			if state.upgrades.has("wash"): workshop.animate_machine("wash")
			sound.play("wash")
			burst(workshop.stations.wash,Color("c1f4ed"),16)
		"sorter":
			state.action("process",{"pile":last_pile})
			if state.upgrades.has("sorter"): workshop.animate_machine("sorter")
			sound.play("sort")
			burst(workshop.stations.sorter,Color("edbc72"),14)
		"scanner":
			state.action("scan",{"pile":last_pile})
			if state.upgrades.has("scanner"): workshop.animate_machine("scanner")
			sound.play("scan")
		"certify":
			var gem := current_gem()
			if gem.is_empty(): ui.toast("Hold your chosen candidate, then run the three certification tests.")
			else:
				var step: int=state.certification_step if state.certification_id==int(gem.id) else 0
				state.action("certify",{"id":int(gem.id),"test":step})
				sound.play("test")
		"recover":
			state.action("recover")
			state.action("machine_reset")
		_:
			if int(target_meta("pile",-1))>=0: use_tool()
	action_cooldown=0.35

func drop_selected() -> void:
	var gem := current_gem()
	if gem.is_empty(): return
	var pos: Vector3 = player.camera.global_position - player.camera.global_basis.z * 1.0
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
		ui.toast("Invite a friend to share the work — and the polishing foam.")
		return
	state.action("prank",{"target":target,"mode":mode})
	sound.play("prank")
	if avatars.has(target):
		burst(avatars[target].position+Vector3.UP*1.5, Color("f0f8e9"),14)

func refresh() -> void:
	if not is_instance_valid(workshop): return
	workshop.update_upgrades(state.upgrades)
	if is_instance_valid(player): player.tool_root.scale=Vector3.ONE*(1.16 if state.upgrades.has("scoop") and player.tool=="scoop" else 1.0)
	var desired := {}
	var counts := {}
	var tray_index := 0
	var collection_index := 0
	tray_page=clampi(tray_page,0,maxi(0,ceili(float(tray_count())/48)-1))
	for key in state.gems:
		var gem: Dictionary = state.gems[key]
		var stage := str(gem.stage)
		var p := Vector3.ZERO
		if stage=="pile":
			var sector: int = int(gem.pile)
			var count: int = counts.get(sector,0)
			if count>=7: continue
			counts[sector]=count+1
			p=workshop.pile_position(sector,count)
		elif stage=="tray":
			var slot: int=tray_index-tray_page*48
			tray_index+=1
			if slot<0 or slot>=48: continue
			p=Vector3(-8+(slot%8-3.5)*0.28,1.31,-0.6+int(slot/8)*0.23)
		elif stage=="loose":
			var a: Array=gem.get("pos",[0,1,5])
			p=Vector3(float(a[0]),float(a[1]),float(a[2]))
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
			if stage!="loose": gem_nodes[id].position=p
			continue
		if gem_nodes.has(id) and is_instance_valid(gem_nodes[id]):
			gem_nodes[id].queue_free()
		var body: PhysicsBody3D
		if stage=="loose":
			body=RigidBody3D.new()
			body.mass=0.12
			body.linear_damp=1.2
			body.angular_damp=2
			body.physics_material_override=PhysicsMaterial.new()
			body.physics_material_override.bounce=0.3
			body.collision_mask=1
		else: body=StaticBody3D.new()
		body.collision_layer=4
		body.set_meta("gem_id",id)
		body.set_meta("stage",stage)
		body.set_meta("visual",visual_signature)
		var visual: Node3D=workshop.make_gem(str(gem.kind))
		visual.scale=Vector3.ONE*(0.29 if stage=="pile" else (0.35 if stage=="certified" else (0.26 if stage=="collection" else 0.18)))
		body.add_child(visual)
		var collision:=CollisionShape3D.new()
		var shape:=SphereShape3D.new()
		shape.radius=0.20 if stage=="pile" else 0.12
		collision.shape=shape
		body.add_child(collision)
		body.position=p
		body.rotation=Vector3(0.0,float(id)*2.31,0.06)
		add_child(body)
		gem_nodes[id]=body
		if gem.get("flagged",false) or gem.get("tag",false):
			var label:=Label3D.new()
			label.text="?" if gem.get("flagged",false) else "CERTIFIED*"
			label.position.y=0.32
			label.font_size=32
			label.pixel_size=0.004
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate=Color("ffd184")
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
	if is_instance_valid(workshop):
		if message.begins_with("Sorter processed"): workshop.animate_machine("sorter")
		if message.begins_with("Scanned "): workshop.animate_machine("scanner")
		if message.begins_with("Washed "): workshop.animate_machine("wash")

func on_network(message: String) -> void:
	ui.update_network(message)
	if message.to_lower().contains("failed") or message.to_lower().contains("closed") or message.to_lower().contains("disconnected"):
		voice.stop_session()
		active=false
		player.enabled=false
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
	var label:=Label3D.new()
	label.text="SORTER %s" % (avatars.size()+2)
	label.position.y=2.15
	label.font_size=26
	label.pixel_size=0.006
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	avatar.add_child(label)
	var voice_badge:=Label3D.new()
	voice_badge.name="VoiceBadge"
	voice_badge.text="◖  TALKING  ◗"
	voice_badge.position.y=2.47
	voice_badge.font_size=22
	voice_badge.pixel_size=0.005
	voice_badge.modulate=Color("b9e9ca")
	voice_badge.billboard=BaseMaterial3D.BILLBOARD_ENABLED
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

func burst(pos: Vector3,color: Color,count:int) -> void:
	for i in range(count):
		var m:=MeshInstance3D.new()
		var mesh:=BoxMesh.new()
		mesh.size=Vector3(0.055,0.03,0.07)
		m.mesh=mesh
		var material:=StandardMaterial3D.new()
		material.albedo_color=color
		material.emission_enabled=true
		material.emission=color*0.3
		m.material_override=material
		m.position=pos
		m.set_meta("velocity",Vector3(randf_range(-1.6,1.6),randf_range(0.3,2.4),randf_range(-1.6,1.6)))
		m.set_meta("life",randf_range(0.5,1.5))
		particle_root.add_child(m)

func save_now() -> void:
	if state.is_authority():
		state.save_game()
		ui.toast("Workshop saved. Your diamond stays exactly where it is.")
	else: ui.toast("The host saves your shared workshop automatically.")

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
