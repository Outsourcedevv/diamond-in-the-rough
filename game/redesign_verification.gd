extends Node

## Exercises the actual first-person interaction path using an isolated save.
var game: Node
var report_dir := ""
var checks: Array[String] = []
var errors: Array[String] = []
var phase := "boot"
var started := 0

func begin(owner_game: Node, args: PackedStringArray) -> void:
	game = owner_game
	started = Time.get_ticks_msec()
	for arg in args:
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=")
	if report_dir.is_empty(): report_dir = OS.get_user_data_dir().path_join("redesign-verification")
	DirAccess.make_dir_recursive_absolute(report_dir)
	game.state._save_path = report_dir.path_join("redesign_save.json")
	game.tutorial.test_mode = true
	game.tutorial.preferences_path = report_dir.path_join("tutorial_preferences.json")
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if condition:
		checks.append(description)
		print("PASS ",description)
	else:
		errors.append(description)
		push_error("REDESIGN_FAIL " + description)
	write_report()

func write_report() -> void:
	var file := FileAccess.open(report_dir.path_join("redesign_report.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"phase":phase,"checks":checks,"errors":errors,"passed":checks.size(),"failed":errors.size(),"elapsed_ms":Time.get_ticks_msec()-started,"tutorial_step":game.tutorial.step,"tutorial_complete":game.tutorial.preferences.completed},"  "))

func run() -> void:
	await get_tree().create_timer(0.4).timeout
	phase = "guided first shift"
	game.start_session("solo","",24680,true)
	await probe_mountain_geometry()
	var initial_funds: int = game.state.money
	await purchase_model("scoop")
	check(game.state.money == initial_funds and not game.state.upgrades.has("scoop"),"Insufficient funds cannot purchase equipment or spend the balance")
	check(not game.ui.menu_visible,"An unaffordable model keeps the player inside the game")
	var card: Label3D = game.workshop._product_cards.scoop
	var name_card: Label3D
	for child in card.get_parent().get_children():
		if child is Label3D and child.text == game.workshop.get_upgrade_name("scoop"): name_card = child
	check(card.text == "$70" and name_card != null and card.position.y < name_card.position.y,"The scoop's physical price sits underneath its name")
	check(not card.no_depth_test and card.billboard == BaseMaterial3D.BILLBOARD_DISABLED,"Equipment text stays attached to its depth-tested placard")
	await go(Vector3(0,0.12,7.2))
	game.player.yaw = 0.0
	game.player.pitch = -0.10
	game.player.update_view()
	game.player.set_physics_process(true)
	game.tutorial.test_mode = false
	game.tutorial.preferences = {"schema":1,"completed":false,"dismissed":false}
	game.tutorial.start_session("solo")
	check(game.tutorial.running,"A first solo session starts guidance automatically")
	game.tutorial.test_mode = true
	game.tutorial.restart()
	check(game.tutorial.running and game.tutorial.step == 0,"A fresh tutorial starts inside the playable world")
	game.tutorial.tick(30.0)
	check(game.tutorial.step == 0,"Waiting alone does not complete the movement lesson")
	var before: Vector3 = game.player.position
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().create_timer(0.4).timeout
	key = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = false
	Input.parse_input_event(key)
	var walked: bool = Vector2(game.player.position.x-before.x,game.player.position.z-before.z).length() > 0.9
	check(walked,"WASD physically moves the player during the tutorial")
	check(game.tutorial.step == 0,"Movement alone does not skip the look control")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(90,-50)
	if DisplayServer.get_name() == "headless":
		# The headless display cannot capture the pointer; exercise the same player
		# handler with an explicit captured mode only in a native-window run.
		game.player.yaw -= 0.3
		game.player.pitch += 0.2
		game.player.update_view()
	else:
		Input.parse_input_event(mouse)
	await get_tree().create_timer(0.15).timeout
	check(game.tutorial.step == 1,"Moving and looking complete the first playable lesson")
	await screenshot("01_tutorial_in_world")
	var held_before: int = game.state.held_ids().size()
	game.state.action("scoop",{"pile":0})
	game.tutorial.on_action("scoop",{"pile":0})
	check(game.state.held_ids().size() == held_before and game.tutorial.step == 1,"An out-of-reach scoop cannot complete the batch lesson")
	game.state.action("pick",{"id":0})
	game.tutorial.on_action("pick",{"id":0})
	check(game.state.held_ids().size() == held_before and game.tutorial.step == 1,"An out-of-reach individual pick cannot advance the guide")
	var one_piece: Dictionary = game.state.gems[0]
	var one_position := Vector3(float(one_piece.pos[0]),float(one_piece.pos[1]),float(one_piece.pos[2]))
	await go(one_position + Vector3(0,0.1,1.7))
	# First make a held find without claiming it as the result of the next
	# command. A rejected repeat must not gain credit from this earlier success.
	game.state.action("pick",{"id":0})
	game.state.action("pick",{"id":0})
	game.tutorial.on_action("pick",{"id":0})
	check(game.state.held_ids().has(0) and game.tutorial.step == 1,"A rejected repeat cannot reuse an earlier pickup as tutorial credit")
	var next_piece: Dictionary = game.state.gems[1]
	var next_position := Vector3(float(next_piece.pos[0]),float(next_piece.pos[1]),float(next_piece.pos[2]))
	await go(next_position + Vector3(0,0.1,1.7))
	aim(next_position)
	var reached_id: int = int(game.target_meta("gem_id",-1))
	check(reached_id >= 0 and game.state.gems.get(reached_id,{}).get("stage","") == "pile","The first-person ray reaches an individual mountain find")
	game.interact()
	await get_tree().create_timer(0.08).timeout
	check(game.state.held_ids().has(reached_id) and game.tutorial.step == 2,"A successful E pickup advances the guide without requiring a larger batch")
	game.toggle_inspection()
	await get_tree().create_timer(0.12).timeout
	check(game.player.inspecting and game.tutorial.step == 2,"Opening inspection alone does not skip turning the stone")
	mouse = InputEventMouseMotion.new()
	mouse.relative = Vector2(52,24)
	if DisplayServer.get_name() == "headless":
		game.player.visual_angle += mouse.relative * 0.009
	else:
		Input.parse_input_event(mouse)
	await get_tree().create_timer(0.12).timeout
	check(game.player.visual_angle.length() > 0.25 and game.tutorial.step == 3,"Turning a held stone advances the evidence lesson")
	await screenshot("02_tutorial_inspection")
	game.toggle_inspection()
	var money_before: int = game.state.money
	await interact_station("sell")
	# A rare all-candidate first batch earns nothing. Continue the same natural
	# search-and-exchange loop instead of seeding tutorial money or identities.
	var guard := 0
	while game.tutorial.step == 3 and guard < 8:
		await scoop_from_mountain()
		await interact_station("sell")
		guard += 1
	check(game.state.money > money_before and game.tutorial.step == 4,"Actual exchange payouts complete the selling lesson")
	while game.state.money < int(game.state.prices.scoop) and guard < 35:
		await scoop_from_mountain()
		await interact_station("sell")
		guard += 1
	check(game.state.money >= int(game.state.prices.scoop),"Repeated ordinary sales naturally fund the first upgrade")
	await purchase_model("scoop")
	check(game.state.upgrades.has("scoop") and game.state.capacity() == 9,"The displayed scoop purchase changes real carrying capacity")
	check(not game.ui.menu_visible and game.tutorial.step == 5,"Buying a physical model opens no buying menu and advances the guide")
	var funds_after_purchase: int = game.state.money
	await purchase_model("scoop")
	check(game.state.money == funds_after_purchase and game.state.upgrades.count("scoop") == 1,"An installed model cannot charge for a duplicate upgrade")
	check(game.workshop._product_cards.scoop.text == "INSTALLED","The physical price plate changes to installed after purchase")
	await screenshot("03_physical_purchase")
	await scoop_from_mountain()
	var stored_ids: Array = game.state.held_ids().duplicate()
	check(stored_ids.size() > 1,"A larger scoop gathers a real batch from the mountain")
	await interact_station("tray")
	var all_safe := not stored_ids.is_empty()
	for id in stored_ids: all_safe = all_safe and game.state.gems[int(id)].stage == "tray"
	check(all_safe and game.tutorial.step == 6,"Pouring a real batch into the tray completes safe storage")
	await scoop_from_mountain()
	check(game.tutorial.preferences.completed and not game.tutorial.running,"Returning to search completes the entire guided first shift")
	check(not game.state.certified,"The tutorial preserves manual diamond discovery and certification")
	await adaptive_tutorial_cases()
	game.tutorial.test_mode = false
	game.tutorial._save_preferences()
	game.tutorial.load_preferences()
	game.tutorial.start_session("solo")
	check(not game.tutorial.running,"Completed first-session guidance stays completed after local reload")
	game.tutorial.restart()
	check(game.tutorial.running and game.tutorial.step == 0,"Help can replay the complete guide on an established save")
	game.tutorial.skip()
	game.tutorial.load_preferences()
	game.tutorial.start_session("host")
	check(not game.tutorial.running and bool(game.tutorial.preferences.dismissed),"Skipping persists locally without altering the shared world")
	game.tutorial.preferences = {"schema":1,"completed":false,"dismissed":false}
	game.tutorial.start_session("join")
	check(not game.tutorial.running,"Joining a friend's game does not auto-start first-session guidance")
	game.tutorial.test_mode = true
	phase = "responsive layouts"
	await responsive_layouts()
	phase = "complete"
	write_report()
	print("REDESIGN_RESULT ",JSON.stringify({"passed":checks.size(),"errors":errors}))
	game.state.leave()
	get_tree().quit(0 if errors.is_empty() else 1)

func go(pos: Vector3) -> void:
	game.player.set_physics_process(false)
	game.player.position = pos
	game.player.velocity = Vector3.ZERO
	game.state.send_pose(pos,game.player.yaw,game.player.pitch)
	await get_tree().create_timer(0.08).timeout

func probe_mountain_geometry() -> void:
	for sector in range(game.workshop.pile_centers.size()):
		var center: Vector3 = game.workshop.pile_centers[sector]
		var ray := PhysicsRayQueryParameters3D.create(center + Vector3(0,6,0),center - Vector3(0,6,0),1)
		var hit: Dictionary = game.player.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and int(hit.collider.get_meta("pile",-1)) == sector and absf(hit.position.y-center.y) < 0.035,"Mountain section %d has a solid surface at its authoritative height" % (sector+1))
	game.player.position = Vector3(0,0.1,3.0)
	game.player.velocity = Vector3.ZERO
	game.player.yaw = 0.0
	game.player.update_view()
	game.player.set_physics_process(true)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().create_timer(1.65).timeout
	key = InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = false
	Input.parse_input_event(key)
	await get_tree().create_timer(0.25).timeout
	check(game.player.position.z < -0.2 and game.player.position.y > 1.9 and game.player.is_on_floor(),"WASD climbs the mountain's scree while staying on its physical surface")
	await screenshot("00_walkable_mountain")

func adaptive_tutorial_cases() -> void:
	var saved_world: Dictionary = game.state.snapshot().duplicate(true)
	var saved_preferences: Dictionary = game.tutorial.preferences.duplicate(true)
	var saved_test_mode: bool = game.tutorial.test_mode
	check(game.state.held_ids().size() == game.state.capacity(),"The replay fixture starts with a naturally collected full batch")
	await go(Vector3(0,0.1,7.2))
	game.player.yaw = 0.0
	game.player.pitch = -0.1
	game.player.update_view()
	game.player.set_physics_process(true)
	game.tutorial.restart()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().create_timer(0.4).timeout
	key = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = false
	Input.parse_input_event(key)
	game.player.yaw -= 0.3
	game.player.update_view()
	await get_tree().create_timer(0.1).timeout
	var guide: Dictionary = game.tutorial.data()
	check(game.tutorial.step == 1 and guide.instruction.contains("hands are full") and guide.target_label == "Inspection tray","Replay directs full hands to safe storage before asking for another find")
	await screenshot("04_full_hands_replay")
	var carried: Array = game.state.held_ids().duplicate()
	await interact_station("tray")
	var safely_stored: bool = game.state.held_ids().is_empty()
	for id in carried: safely_stored = safely_stored and game.state.gems[int(id)].stage == "tray"
	guide = game.tutorial.data()
	check(safely_stored and game.tutorial.step == 1 and guide.target_label == "Searchable material","Pouring the replay batch safely restores the gathering instruction")
	await scoop_from_mountain()
	check(game.tutorial.step == 2,"A full-hands replay can continue after storing and gathering normally")
	game.tutorial.stop()
	# Load a complete existing search through the real save path. This fixture
	# changes only the disposable QA world, without creating funds or upgrades.
	for gem in game.state.gems.values():
		if gem.stage == "pile":
			game.state._mark_searched(gem)
			game.state._to_tray(gem)
	check(game.state.save_game() and game.state.load_game(),"An exhausted existing world reloads through the compatible save format")
	var unchanged_world: String = JSON.stringify(game.state.snapshot())
	game.tutorial.test_mode = false
	game.tutorial.preferences = {"schema":1,"completed":false,"dismissed":false}
	game.tutorial.start_session("solo")
	guide = game.tutorial.data()
	check(not game.tutorial.running and guide.visible and guide.completed and guide.instruction.contains("stored candidates"),"First guidance on an exhausted save offers stored-find help instead of an impossible scoop")
	check(JSON.stringify(game.state.snapshot()) == unchanged_world,"Adaptive guidance grants no items or money and preserves completed world progress")
	await screenshot("05_established_save_help")
	game.tutorial.restart()
	guide = game.tutorial.data()
	check(not game.tutorial.running and guide.visible and guide.title == "Search complete","Replaying an exhausted save follows the same bounded useful help path")
	game.tutorial.load_preferences()
	check(bool(game.tutorial.preferences.completed),"The exhausted-save help path persists its local completion")
	game.tutorial.test_mode = saved_test_mode
	game.tutorial.stop()
	game.state._apply_snapshot(saved_world)
	game.state.changed.emit()
	game.state.save_game()
	game.tutorial.preferences = saved_preferences

func aim(pos: Vector3) -> void:
	game.player.camera.look_at(pos,Vector3.UP)
	game.selected_target = game.player.target()
	game.action_cooldown = 0.0

func scoop_from_mountain() -> void:
	var sector := -1
	for gem in game.state.gems.values():
		if gem.stage == "pile":
			sector = int(gem.pile)
			break
	if sector < 0:
		check(false,"Mountain still has material for tutorial search")
		return
	var center: Vector3 = game.workshop.pile_centers[sector]
	await go(center + Vector3(0,0.1,2.3))
	aim(center)
	var reached: bool = int(game.target_meta("pile",-1)) >= 0 or int(game.target_meta("gem_id",-1)) >= 0
	if not reached:
		# Try the material closest to the sector centre on its exposed surface.
		var id := -1
		for gem in game.state.gems.values():
			if gem.stage == "pile" and int(gem.pile) == sector: id = int(gem.id); break
		if id >= 0:
			var surface: Vector3 = game.gem_nodes[id].global_position if game.gem_nodes.has(id) else center
			aim(surface)
	game.use_tool()
	await get_tree().create_timer(0.08).timeout

func interact_station(station: String) -> void:
	var center: Vector3 = game.workshop.stations[station]
	await go(Vector3(center.x,0.1,center.z+1.7))
	aim(center)
	game.interact()
	await get_tree().create_timer(0.08).timeout

func purchase_model(upgrade: String) -> void:
	var center: Vector3 = game.workshop.upgrade_positions[upgrade]
	await go(Vector3(center.x,0.1,center.z+1.7))
	aim(center)
	check(str(game.target_meta("upgrade","")) == upgrade,"The first-person ray targets the scoop's physical display")
	game.interact()
	await get_tree().create_timer(0.08).timeout

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	game.get_viewport().get_texture().get_image().save_png(report_dir.path_join(name+".png"))

func responsive_layouts() -> void:
	var sizes: Array[Vector2i] = [Vector2i(1280,960),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(1280,600)]
	for size in sizes:
		if DisplayServer.get_name() != "headless": DisplayServer.window_set_size(size)
		get_tree().root.size = size
		await get_tree().create_timer(0.15).timeout
		game.ui.show_menu(false)
		await get_tree().process_frame
		check(layout_fits(),"Title controls fit %d × %d" % [size.x,size.y])
		await screenshot("title_%dx%d" % [size.x,size.y])
		game.ui.show_menu(true)
		await get_tree().process_frame
		check(layout_fits(),"Pause controls fit %d × %d" % [size.x,size.y])
		game.ui._show_settings()
		await get_tree().process_frame
		check(layout_fits(),"Settings controls fit %d × %d" % [size.x,size.y])
		await screenshot("settings_%dx%d" % [size.x,size.y])
		game.resume_game()
		game.tutorial.restart()
		await get_tree().process_frame
		check(layout_fits(),"Tutorial and gameplay HUD fit %d × %d" % [size.x,size.y])
		await screenshot("tutorial_%dx%d" % [size.x,size.y])
		game.tutorial.stop()

func layout_fits() -> bool:
	var screen: Rect2 = game.ui._root.get_global_rect()
	var fits := true
	if game.ui.has_method("layout_regions"):
		var regions: Dictionary = game.ui.layout_regions()
		for key in regions:
			var rect: Rect2 = regions[key]
			if not screen.grow(2.0).encloses(rect):
				print("LAYOUT_OVERFLOW ",key," ",rect," screen ",screen)
				fits = false
		for pair in [["menu_title","menu_actions"],["tutorial","prompt"],["tutorial","toast"],["tutorial","tool"],["funds","network"],["funds","toast"],["network","toast"]]:
			if regions.has(pair[0]) and regions.has(pair[1]) and (regions[pair[0]] as Rect2).intersects(regions[pair[1]]):
				print("LAYOUT_OVERLAP ",pair[0]," / ",pair[1])
				fits=false
	else:
		# The verifier still checks the actual root surfaces if no QA inventory is
		# exposed; scroll content is intentionally allowed beyond its clipped view.
		for field in ["_menu","_modal","_inspection","_tool_card","_objective_card"]:
			var control: Variant = game.ui.get(field)
			if control is Control and control.is_visible_in_tree(): fits = fits and screen.grow(2.0).encloses(control.get_global_rect())
	return fits
