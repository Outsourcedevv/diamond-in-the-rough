extends Node

## Exercises the actual first-person interaction path using an isolated save.
const MountainScript = preload("res://game/mountain.gd")

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
	game.auto_collect = false
	await probe_mountain_geometry()
	var initial_funds: int = game.state.money
	await purchase_model("steel_pick")
	check(game.state.money == initial_funds and not game.state.upgrades.has("steel_pick"),"Insufficient funds cannot purchase equipment or spend the balance")
	check(not game.ui.menu_visible,"An unaffordable model keeps the player inside the game")
	var card: Label3D = game.workshop._product_cards.steel_pick
	var name_card: Label3D
	for child in card.get_parent().get_children():
		if child is Label3D and child.text == game.workshop.get_upgrade_name("steel_pick"): name_card = child
	check(card.text == "$60" and name_card != null and card.position.y < name_card.position.y,"The steel pickaxe's physical price sits underneath its name")
	check(not card.no_depth_test and card.billboard == BaseMaterial3D.BILLBOARD_DISABLED,"Equipment text stays attached to its depth-tested placard")
	check(game.workshop.upgrade_positions.size() == 9,"The camp outfitter displays all nine tools and explosives")
	await go(Vector3(0,0.12,7.2))
	game.player.yaw = 0.0
	game.player.pitch = -0.10
	game.player.update_view()
	game.player.set_physics_process(true)
	game.tutorial.test_mode = false
	game.tutorial.preferences = {"schema":2,"completed":false,"dismissed":false}
	game.tutorial.start_session("solo")
	check(game.tutorial.running,"A first solo session starts guidance automatically")
	game.tutorial.test_mode = true
	game.tutorial.restart()
	check(game.tutorial.running and game.tutorial.step == 0,"A fresh tutorial starts inside the playable world")
	game.tutorial.tick(30.0)
	check(game.tutorial.step == 0,"Waiting alone does not complete the movement lesson")
	var before: Vector3 = game.player.position
	await hold_key(KEY_D,0.4)
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
	var guide: Dictionary = game.tutorial.data()
	check(guide.target_label == "Surface ore" and guide.target.z < -14.0,"The mining lesson points at real ore on the mountain")
	var far_cell: int = surface_cell(true,false)
	game.state.action("mine",{"cell":far_cell})
	check(game.state.ore_total() == 0 and game.tutorial.step == 1,"An out-of-reach mining command cannot complete the lesson")
	await mine_with_crosshair(far_cell)
	check(game.state.ore_total() > 0 and game.tutorial.step == 2,"Breaking a real ore block with the pickaxe advances the guide")
	await screenshot("02_tutorial_mining")
	var money_before: int = game.state.money
	await interact_station("sell")
	check(game.state.money > money_before and game.state.ore_total() == 0 and game.tutorial.step == 3,"Actual exchange payouts complete the selling lesson")
	var guard := 0
	while game.state.money < int(game.state.prices.steel_pick) and guard < 80:
		var cell: int = surface_cell(true,false)
		if cell < 0: break
		await mine_cell(cell)
		if game.state.ore_total() >= game.state.ore_capacity() - 2 or guard % 10 == 9:
			await interact_station("sell")
		guard += 1
	if game.state.ore_total() > 0: await interact_station("sell")
	check(game.state.money >= int(game.state.prices.steel_pick),"Repeated ordinary mining naturally funds the first upgrade")
	await purchase_model("steel_pick")
	check(game.state.upgrades.has("steel_pick") and game.state.mining_tool() == "steel_pick","The displayed steel pickaxe purchase changes the real mining tool")
	check(not game.ui.menu_visible and game.tutorial.step == 4,"Buying a physical model opens no buying menu and advances the guide")
	var funds_after_purchase: int = game.state.money
	await purchase_model("steel_pick")
	check(game.state.money == funds_after_purchase and game.state.upgrades.count("steel_pick") == 1,"An owned model cannot charge for a duplicate purchase")
	check(game.workshop._product_cards.steel_pick.text == "OWNED","The physical price plate changes to owned after purchase")
	await screenshot("03_physical_purchase")
	guide = game.tutorial.data()
	check(guide.target_label == "Crystal or fossil","The discovery lesson points at a buried crystal or fossil")
	var found: int = await dig_out_find()
	check(found >= 0 and game.state.gems[found].stage == "loose","Digging down to a buried find breaks it loose from the rock")
	if found >= 0:
		var at: Array = game.state.gems[found].pos
		var spot := Vector3(float(at[0]),float(at[1]),float(at[2]))
		# Finds rest at the bottom of the dug shaft, so look straight down into it once
		# the background surface rebuild has opened the shaft (slow CI machines lag).
		await settle_surface()
		if game.gem_nodes.has(found): spot = game.gem_nodes[found].global_position
		await go(spot + Vector3(0,0.6,0))
		aim(spot,Vector3.FORWARD)
		var reached_id: int = int(game.target_meta("gem_id",-1))
		if reached_id != found: print("SHAFT_DEBUG idle=",game.mountain_view.idle()," spot=",spot," hit=",game.selected_target.get("position")," collider=",game.selected_target.get("collider")," node=",game.gem_nodes.get(found).position if game.gem_nodes.has(found) else null)
		check(reached_id == found,"The first-person ray reaches the released find")
		game.interact()
		await get_tree().create_timer(0.08).timeout
		check(game.state.held_ids().has(found) and game.tutorial.step == 5,"Picking up the find with E advances the guide")
	game.toggle_inspection()
	await get_tree().create_timer(0.12).timeout
	check(game.player.inspecting and game.tutorial.step == 5,"Opening inspection alone does not skip turning the stone")
	mouse = InputEventMouseMotion.new()
	mouse.relative = Vector2(52,24)
	if DisplayServer.get_name() == "headless":
		game.player.visual_angle += mouse.relative * 0.009
	else:
		Input.parse_input_event(mouse)
	await get_tree().create_timer(0.12).timeout
	check(game.player.visual_angle.length() > 0.25 and game.tutorial.step == 6,"Turning a held find advances the evidence lesson")
	await screenshot("04_tutorial_inspection")
	game.toggle_inspection()
	var stored_ids: Array = game.state.held_ids().duplicate()
	await interact_station("tray")
	var all_safe := not stored_ids.is_empty()
	for id in stored_ids: all_safe = all_safe and game.state.gems[int(id)].stage == "tray"
	check(all_safe and game.tutorial.preferences.completed and not game.tutorial.running,"Storing the find in the tray completes the entire guided first shift")
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
	game.tutorial.preferences = {"schema":2,"completed":false,"dismissed":false}
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

func hold_key(key_code: Key, seconds: float, also: Key = KEY_NONE) -> void:
	for code in [key_code, also]:
		if code == KEY_NONE: continue
		var key := InputEventKey.new()
		key.physical_keycode = code
		key.pressed = true
		Input.parse_input_event(key)
	await get_tree().create_timer(seconds).timeout
	for code in [key_code, also]:
		if code == KEY_NONE: continue
		var key := InputEventKey.new()
		key.physical_keycode = code
		key.pressed = false
		Input.parse_input_event(key)

func probe_mountain_geometry() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var grid = game.state.mountain
	var probes := 0
	for z in range(6,MountainScript.SIZE_Z,9):
		for x in range(6,MountainScript.SIZE_X,11):
			var top: float = grid.smooth_height(x,z)
			if top < 2.0: continue
			var at: Vector3 = MountainScript.cell_center(MountainScript.index(x,0,z))
			var ray := PhysicsRayQueryParameters3D.create(Vector3(at.x,60,at.z),Vector3(at.x,-5,at.z),1)
			var hit: Dictionary = game.player.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty() and bool(hit.collider.get_meta("mountain",false)) and absf(hit.position.y-top) < 0.6,"Mountain column %d,%d is solid at its natural height of %.1f m" % [x,z,top])
			probes += 1
	check(probes >= 12,"The mountain's surface was probed across its whole footprint")
	# Walk to the foot of the slope and climb it with real movement and jumps.
	var x: int = MountainScript.SIZE_X / 2
	var foot: int = MountainScript.SIZE_Z - 1
	while foot > 0 and grid.height(x,foot) == 0: foot -= 1
	var start: Vector3 = MountainScript.cell_center(MountainScript.index(x,0,foot)) + Vector3(0,-0.4,1.6)
	game.player.position = start
	game.player.velocity = Vector3.ZERO
	game.player.yaw = 0.0
	game.player.update_view()
	game.player.set_physics_process(true)
	await hold_key(KEY_W,2.2,KEY_SPACE)
	await get_tree().create_timer(1.2).timeout
	check(game.player.position.y > start.y + 2.5 and game.player.position.z < start.z - 3.0 and game.player.is_on_floor(),"WASD and jumping climb the mountain's lower slopes (%.1f m up)" % (game.player.position.y-start.y))
	await screenshot("00_walkable_mountain")

## An exposed block with open air above it, so a miner can stand on top of it.
func surface_cell(want_ore: bool, allow_granite: bool) -> int:
	var grid = game.state.mountain
	var best := -1
	var distance := INF
	for z in range(MountainScript.SIZE_Z):
		for x in range(MountainScript.SIZE_X):
			for y in range(MountainScript.SIZE_Y-2,0,-1):
				var cell: int = MountainScript.index(x,y,z)
				if not game.state.is_solid(cell): continue
				var ore: bool = not MountainScript.ore_for_code(game.state.cell_code(cell)).is_empty()
				if want_ore == ore and game.state.cell_code(cell) != MountainScript.BEDROCK and (allow_granite or not grid.needs_steel(x,y,z)):
					var squared: float = MountainScript.cell_center(cell).distance_squared_to(Vector3(0,0,-14))
					if squared < distance:
						distance = squared
						best = cell
				break
	return best

func mine_cell(cell: int) -> void:
	var at: Vector3 = MountainScript.cell_center(cell)
	await go(Vector3(at.x,at.y+0.5,at.z))
	for hit in range(14):
		if not game.state.is_solid(cell): return
		game.state.action("mine",{"cell":cell})
		await get_tree().create_timer(0.01).timeout

## Swings through the real crosshair path until the aimed block breaks.
func mine_with_crosshair(cell: int) -> void:
	var at: Vector3 = MountainScript.cell_center(cell)
	await go(Vector3(at.x,at.y+0.5,at.z))
	for swing in range(16):
		if not game.state.is_solid(cell): return
		game.player.camera.look_at(at,Vector3.FORWARD)
		await get_tree().physics_frame
		game.selected_target = game.player.target()
		game.action_cooldown = 0.0
		game.use_tool()
		await get_tree().create_timer(0.02).timeout

## Mines the column above the nearest shallow find, then the find's own block.
func dig_out_find() -> int:
	var grid = game.state.mountain
	var target := -1
	var distance := INF
	for gem in game.state.gems.values():
		if gem.stage != "buried": continue
		var c: Vector3i = MountainScript.coords(int(gem.cell))
		if grid.depth(c.x,c.y,c.z) > 4: continue
		var squared: float = MountainScript.cell_center(int(gem.cell)).distance_squared_to(game.player.position)
		if squared < distance:
			distance = squared
			target = int(gem.id)
	if target < 0: return -1
	var c: Vector3i = MountainScript.coords(int(game.state.gems[target].cell))
	for y in range(MountainScript.SIZE_Y-1,c.y-1,-1):
		var cell: int = MountainScript.index(c.x,y,c.z)
		if game.state.is_solid(cell):
			if MountainScript.ore_for_code(game.state.cell_code(cell)) != "" and game.state.ore_total() >= game.state.ore_capacity():
				await interact_station("sell")
			await mine_cell(cell)
	return target

func adaptive_tutorial_cases() -> void:
	var saved_world: Dictionary = game.state.snapshot().duplicate(true)
	var saved_preferences: Dictionary = game.tutorial.preferences.duplicate(true)
	var saved_test_mode: bool = game.tutorial.test_mode
	# Dig out a few more finds and store them, so the replay can fill its hands.
	var guard := 0
	while tray_count() < game.state.capacity() and guard < 12:
		guard += 1
		var id: int = await dig_out_find()
		if id < 0: break
		var at: Array = game.state.gems[id].pos
		await go(Vector3(float(at[0]),float(at[1])+0.1,float(at[2])+1.0))
		game.state.action("pick",{"id":id})
		if game.state.held_ids().size() >= game.state.capacity(): await interact_station("tray")
	if not game.state.held_ids().is_empty(): await interact_station("tray")
	check(tray_count() >= game.state.capacity(),"The replay fixture has enough naturally dug finds in storage")
	await go(Vector3(0,0.1,7.2))
	game.player.yaw = 0.0
	game.player.pitch = -0.1
	game.player.update_view()
	game.player.set_physics_process(true)
	game.tutorial.restart()
	await hold_key(KEY_D,0.4)
	game.player.yaw -= 0.3
	game.player.update_view()
	await get_tree().create_timer(0.1).timeout
	if game.state.ore_total() > 0: await interact_station("sell")
	await mine_cell(surface_cell(true,true))
	await interact_station("sell")
	await get_tree().create_timer(0.1).timeout
	check(game.tutorial.step == 4,"Replay skips the pickaxe lesson when a steel pickaxe is already owned")
	await go(Vector3(game.workshop.stations.tray.x,0.1,game.workshop.stations.tray.z+1.6))
	for gem in game.state.gems.values():
		if game.state.held_ids().size() >= game.state.capacity(): break
		if gem.stage == "tray": game.state.action("pick",{"id":int(gem.id)})
	await get_tree().create_timer(0.1).timeout
	var guide: Dictionary = game.tutorial.data()
	check(game.tutorial.step == 4 and game.state.held_ids().size() == game.state.capacity(),"Taking stored finds back out of the tray does not count as digging")
	check(guide.instruction.contains("hands are full") and guide.target_label == "Inspection tray","Full hands are directed to safe storage before digging again")
	await screenshot("05_full_hands_replay")
	var carried: Array = game.state.held_ids().duplicate()
	await interact_station("tray")
	var safely_stored: bool = game.state.held_ids().is_empty()
	for id in carried: safely_stored = safely_stored and game.state.gems[int(id)].stage == "tray"
	guide = game.tutorial.data()
	check(safely_stored and game.tutorial.step == 4 and guide.target_label == "Crystal or fossil","Storing the replay batch restores the digging instruction")
	var found: int = await dig_out_find()
	if found >= 0:
		var at: Array = game.state.gems[found].pos
		await go(Vector3(float(at[0]),float(at[1])+0.1,float(at[2])+1.0))
		game.state.action("pick",{"id":found})
	check(game.tutorial.step == 5,"A full-hands replay continues after storing and digging normally")
	game.tutorial.stop()
	# Load a completely dug-out world through the real save path. This fixture
	# changes only the disposable QA world, without creating funds or upgrades.
	for gem in game.state.gems.values():
		if gem.stage == "buried":
			game.state._to_tray(gem)
	check(game.state.save_game() and game.state.load_game(),"A dug-out existing world reloads through the save format")
	var unchanged_world: String = JSON.stringify(game.state.snapshot())
	game.tutorial.test_mode = false
	game.tutorial.preferences = {"schema":2,"completed":false,"dismissed":false}
	game.tutorial.start_session("solo")
	guide = game.tutorial.data()
	check(not game.tutorial.running and guide.visible and guide.completed and guide.instruction.contains("stored candidates"),"First guidance on a dug-out save offers stored-find help instead of an impossible dig")
	check(JSON.stringify(game.state.snapshot()) == unchanged_world,"Adaptive guidance grants no items or money and preserves completed world progress")
	await screenshot("06_established_save_help")
	game.tutorial.restart()
	guide = game.tutorial.data()
	check(not game.tutorial.running and guide.visible and guide.title == "Mountain searched","Replaying a dug-out save follows the same bounded useful help path")
	game.tutorial.load_preferences()
	check(bool(game.tutorial.preferences.completed),"The dug-out save help path persists its local completion")
	game.tutorial.test_mode = saved_test_mode
	game.tutorial.stop()
	game.state._apply_snapshot(saved_world)
	game.state._rebuild_cells()
	game.state.changed.emit()
	game.state.save_game()
	game.tutorial.preferences = saved_preferences

func tray_count() -> int:
	var count := 0
	for gem in game.state.gems.values():
		if gem.stage == "tray": count += 1
	return count

func settle_surface() -> void:
	var waited := 0
	while not game.mountain_view.idle() and waited < 100:
		await get_tree().create_timer(0.05).timeout
		waited += 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	game.refresh()
	# Let a find that moved onto the rebuilt surface finish settling.
	await get_tree().create_timer(0.5).timeout

func aim(pos: Vector3, up: Vector3 = Vector3.UP) -> void:
	game.player.camera.look_at(pos,up)
	game.selected_target = game.player.target()
	game.action_cooldown = 0.0

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
	check(str(game.target_meta("upgrade","")) == upgrade,"The first-person ray targets the %s's physical display" % game.workshop.get_upgrade_name(upgrade).to_lower())
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
		for field in ["_menu","_modal","_inspection","_tool_card","_objective_card"]:
			var control: Variant = game.ui.get(field)
			if control is Control and control.is_visible_in_tree(): fits = fits and screen.grow(2.0).encloses(control.get_global_rect())
	return fits
