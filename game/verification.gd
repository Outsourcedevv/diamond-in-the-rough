extends Node

## Reproducible integration verification. Uses isolated saves and the live game API.
## Run with --verify=solo/host/client --report-dir=... (no player save is modified).
const MountainScript = preload("res://game/mountain.gd")

var game: Node
var report_dir := ""
var role := ""
var checks: Array[String] = []
var errors: Array[String] = []
var started := 0
var phase := "boot"
var last_fuse := -1

func begin(owner_game: Node, mode: String, args: PackedStringArray) -> void:
	game=owner_game
	role=mode
	started=Time.get_ticks_msec()
	for arg in args:
		if arg.begins_with("--report-dir="): report_dir=arg.trim_prefix("--report-dir=")
	if report_dir.is_empty(): report_dir=OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(report_dir)
	game.state._save_path=report_dir.path_join("verify_%s_save.json" % role)
	game.state.throw_spawned.connect(func(_peer,_tier,_pos,_vel,fuse): last_fuse=fuse)
	call_deferred("run")

func run() -> void:
	await get_tree().create_timer(0.5).timeout
	match role:
		"solo": await solo()
		"host": await host_probe()
		"client": await client_probe()
		_: errors.append("Unknown verification role")
	phase="complete"
	write_report()
	print("VERIFY_RESULT ",role," ",JSON.stringify({"checks":checks,"errors":errors}))
	game.state.leave()
	get_tree().quit(0 if errors.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if condition:
		checks.append(message)
		print("PASS ",message)
	else:
		errors.append(message)
		push_error("VERIFY_FAIL "+message)
	write_report()

func write_report(extra: Dictionary={}) -> void:
	var data: Dictionary={"role":role,"phase":phase,"checks":checks,"errors":errors,"elapsed_ms":Time.get_ticks_msec()-started,"money":game.state.money,"diamond_id":game.state.diamond_id,"searched":game.state.searched,"blocks_mined":game.state.blocks_mined(),"upgrades":game.state.upgrades,"certified":game.state.certified,"players":game.state.players.size(),"local_id":game.state.local_id()}
	data.merge(extra,true)
	var file:=FileAccess.open(report_dir.path_join(role+"_report.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(data,"  "))

func peer_report(peer: String) -> Dictionary:
	var path:=report_dir.path_join(peer+"_report.json")
	if not FileAccess.file_exists(path): return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func wait_for(condition: Callable, limit: float=20.0) -> bool:
	var ticks:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-ticks<int(limit*1000):
		if condition.call(): return true
		await get_tree().create_timer(0.08).timeout
	return false

func go(pos: Vector3) -> void:
	game.player.position=pos
	game.player.velocity=Vector3.ZERO
	game.player.set_physics_process(false)
	game.state.send_pose(pos,game.player.yaw,game.player.pitch)
	await get_tree().create_timer(0.1).timeout

func act(kind: String,args:Dictionary={}) -> void:
	game.state.action(kind,args)
	await get_tree().create_timer(0.14 if role=="client" else 0.015).timeout

func station(id: String) -> Vector3:
	var pos: Vector3=game.workshop.stations[id]
	return Vector3(pos.x,0.1,pos.z+1.8)

## An exposed block with open air above it, so a miner can stand on top of it.
func surface_cell(want_ore: bool, allow_granite: bool) -> int:
	var grid = game.state.mountain
	var best := -1
	var distance := INF
	for z in range(MountainScript.SIZE_Z):
		for x in range(MountainScript.SIZE_X):
			for y in range(MountainScript.SIZE_Y-2,0,-1):
				var cell: int=MountainScript.index(x,y,z)
				if not game.state.is_solid(cell): continue
				var code: int=game.state.cell_code(cell)
				var ore: bool=not MountainScript.ore_for_code(code).is_empty()
				if want_ore==ore and code!=MountainScript.BEDROCK and (allow_granite or not grid.needs_steel(x,y,z)):
					var at: Vector3=MountainScript.cell_center(cell)
					var squared: float=at.distance_squared_to(Vector3(0,0,-14))
					if squared<distance:
						distance=squared
						best=cell
				break
	return best

func stand_on(cell: int) -> void:
	var at: Vector3=MountainScript.cell_center(cell)
	await go(Vector3(at.x,at.y+0.5,at.z))

func mine_out(cell: int) -> bool:
	await stand_on(cell)
	for hit in range(16):
		if not game.state.is_solid(cell): return true
		await act("mine",{"cell":cell})
	return not game.state.is_solid(cell)

## Throws a real charge from near the target, then detonates it where it rests.
func blast(tier: String, at: Vector3) -> int:
	var before: int=game.state.blocks_mined()
	await go(Vector3(at.x,maxf(at.y,1.0)+1.0,at.z+2.0))
	last_fuse=-1
	var origin: Vector3=game.player.position+Vector3(0,1.4,0)
	await act("throw",{"tier":tier,"pos":[origin.x,origin.y,origin.z],"vel":[0,0,-3]})
	await wait_for(func(): return last_fuse>=0,5.0)
	if last_fuse<0: return 0
	await act("blast",{"fuse":last_fuse,"pos":[at.x,at.y,at.z]})
	await wait_for(func(): return game.state.blocks_mined()>before,5.0)
	return game.state.blocks_mined()-before

func sell_all() -> void:
	await go(station("sell"))
	await act("sell")

## Earns money only from ore the game actually mined: pick work at first, then
## the explosives once they are owned.
func fund(amount: int) -> void:
	var guard:=0
	while game.state.money<amount and guard<400:
		guard+=1
		if game.state.ore_total()>=game.state.ore_capacity()-4:
			await sell_all()
			continue
		var tier:=""
		for candidate in ["tnt","dynamite"]:
			if candidate in game.state.upgrades: tier=candidate; break
		if tier.is_empty():
			var cell: int=surface_cell(true,"steel_pick" in game.state.upgrades)
			if cell<0: break
			await mine_out(cell)
		else:
			await blast(tier,rich_blast_point())
		if game.state.ore_total()>0 and (guard%6==0 or game.state.ore_total()>=game.state.ore_capacity()-4):
			await sell_all()
	if game.state.money<amount and game.state.ore_total()>0: await sell_all()
	check(game.state.money>=amount,"Natural mining payouts reached $%s" % amount)

var _blast_index := 0
func rich_blast_point() -> Vector3:
	# Work inward along deep, unmined rock away from the diamond's protected core.
	var grid = game.state.mountain
	for attempt in range(400):
		_blast_index+=1
		var x: int=4+(_blast_index*7)%64
		var z: int=4+(_blast_index*11)%56
		var top: int=grid.height(x,z)
		if top<10: continue
		var y: int=top-8
		var cell: int=MountainScript.index(x,y,z)
		if game.state.is_solid(cell) and MountainScript.cell_center(cell).distance_to(MountainScript.cell_center(int(game.state.gems[game.state.diamond_id].cell)))>9.0:
			return MountainScript.cell_center(cell)
	return MountainScript.cell_center(MountainScript.index(37,6,30))

func buy(id: String) -> void:
	await fund(int(game.state.prices[id]))
	var display: Vector3=game.workshop.upgrade_positions[id]
	await go(Vector3(display.x,0.1,display.z+1.65))
	game.player.camera.look_at(display,Vector3.UP)
	await get_tree().physics_frame
	game.selected_target=game.player.target()
	var displayed: Object=game.selected_target.get("collider")
	check(is_instance_valid(displayed) and str(displayed.get_meta("upgrade",""))==id,"First-person ray reaches equipment display: "+id)
	game.action_cooldown=0
	game.interact()
	await get_tree().create_timer(0.14 if role=="client" else 0.02).timeout
	check(id in game.state.upgrades,"Bought working equipment: "+id)
	check(not game.ui.menu_visible,"Physical purchase keeps first-person controls: "+id)

## Frames a view for the native-window screenshots; headless runs skip it.
func vantage(name: String, from: Vector3, at: Vector3, wait: float=0.25) -> void:
	if DisplayServer.get_name()=="headless": return
	await go(from)
	game.player.camera.look_at(at,Vector3.UP)
	await get_tree().create_timer(wait).timeout
	await screenshot(name)
	game.player.update_view()

func screenshot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var path:=report_dir.path_join(name+".png")
	game.get_viewport().get_texture().get_image().save_png(path)

func solo() -> void:
	var load_started: int=Time.get_ticks_msec()
	game.start_session("solo","",24680,true)
	print("World build ms ",Time.get_ticks_msec()-load_started)
	game.state.test_mode=true
	game.auto_collect=false
	check(game.state.gems.size()==game.state.GEM_COUNT,"Generated %d buried finds" % game.state.GEM_COUNT)
	var original_diamond: int=game.state.diamond_id
	var real_count:=0
	for gem in game.state.gems.values():
		if gem.kind=="diamond": real_count+=1
	check(real_count==1,"Exactly one genuine diamond generated")
	var diamond_cell: int=int(game.state.gems[original_diamond].cell)
	var dc: Vector3i=MountainScript.coords(diamond_cell)
	check(game.state.gems[original_diamond].stage=="buried" and game.state.mountain.depth(dc.x,dc.y,dc.z)>=14,"The diamond is buried deep in the mountain's core")
	check(game.state.cell_code(diamond_cell)==MountainScript.CRYSTAL,"The diamond's block looks like every other crystal vein")
	var tallest:=0
	for z in range(MountainScript.SIZE_Z):
		for x in range(MountainScript.SIZE_X): tallest=maxi(tallest,game.state.mountain.height(x,z))
	var solid:=0
	var ore:=0
	for code in game.state.cells:
		if code!=0: solid+=1
		if code>=10 and code<20: ore+=1
	check(tallest>=24 and solid>20000,"The mountain is big: %d blocks tall and %d blocks of rock" % [tallest,solid])
	check(ore>2000,"The mountain holds %d ore blocks across several ore types" % ore)
	var peak := Vector3i(37,0,30)
	var peak_top: float=float(game.state.mountain.height(peak.x,peak.z))
	var probe: Vector3=MountainScript.cell_center(MountainScript.index(peak.x,0,peak.z))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit: Dictionary=game.player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(probe.x,60,probe.z),Vector3(probe.x,-5,probe.z),1))
	if hit.is_empty() or absf(hit.position.y-peak_top)>=0.02: print("SUMMIT_PROBE ",hit.get("position","none")," expected ",peak_top," collider ",hit.get("collider"))
	check(not hit.is_empty() and bool(hit.collider.get_meta("mountain",false)) and absf(hit.position.y-peak_top)<0.02,"The summit is solid to walk on at its true height")
	await screenshot("01_mountain")
	await go(Vector3(0.9,0.1,3.7))
	game.player.yaw=0.0
	game.player.pitch=-0.15
	game.player.update_view()
	game.player.set_physics_process(true)
	var initial: Vector3=game.player.position
	var input:=InputEventKey.new()
	input.physical_keycode=KEY_D
	input.pressed=true
	Input.parse_input_event(input)
	await get_tree().create_timer(0.35).timeout
	input=InputEventKey.new()
	input.physical_keycode=KEY_D
	input.pressed=false
	Input.parse_input_event(input)
	check(game.player.position.x>initial.x+0.2,"First-person WASD moves the physical player")
	# The real crosshair path: aim at an ore block and swing until it breaks.
	var first_ore: int=surface_cell(true,false)
	check(first_ore>=0,"Surface ore is reachable with the starting pickaxe")
	await stand_on(first_ore)
	var ore_before: int=game.state.ore_total()
	var swings:=0
	while game.state.is_solid(first_ore) and swings<16:
		game.player.camera.look_at(MountainScript.cell_center(first_ore),Vector3.FORWARD)
		await get_tree().physics_frame
		game.selected_target=game.player.target()
		game.action_cooldown=0.0
		game.use_tool()
		swings+=1
		await get_tree().create_timer(0.02).timeout
	check(not game.state.is_solid(first_ore) and swings>=2,"The pickaxe takes several swings to break a block (%d)" % swings)
	var next_ore: int=surface_cell(true,false)
	if next_ore>=0:
		var ore_at: Vector3=MountainScript.cell_center(next_ore)
		await vantage("02_mining",ore_at+Vector3(0,0.5,2.6),ore_at)
	check(game.state.ore_total()==ore_before+1,"Breaking an ore block puts the ore in the satchel")
	await go(Vector3(0,0.1,6.0))
	check(game.mountain_view._chunks.size()>0 and game.state.exposed(MountainScript.index(MountainScript.coords(first_ore).x,MountainScript.coords(first_ore).y-1,MountainScript.coords(first_ore).z)),"Mining exposes the block underneath")
	# Granite needs better tools.
	var granite: int=-1
	for y in range(4,12):
		var cell: int=MountainScript.index(37,y,26)
		if game.state.mountain.needs_steel(37,y,26): granite=cell; break
	if granite>=0:
		var shaft: Array=[]
		var gc: Vector3i=MountainScript.coords(granite)
		for y in range(gc.y+1,game.state.mountain.height(gc.x,gc.z)): shaft.append(MountainScript.index(gc.x,y,gc.z))
		game.state._break_cells(1,shaft) # Excavation fixture: open a shaft above granite.
		game.state.players[1]["ore"]={}
		await stand_on(granite)
		for hit_index in range(8): await act("mine",{"cell":granite})
		check(game.state.is_solid(granite),"The old pickaxe cannot break granite")
	var bedrock: int=MountainScript.index(37,0,30)
	await sell_all()
	var shop: Vector3=game.workshop.upgrade_positions["dynamite"]
	await vantage("06_outfitter",shop+Vector3(-3.6,0.4,4.6),shop+Vector3(0,-0.2,-1.2))
	await buy("steel_pick")
	check(game.state.mining_tool()=="steel_pick","The steel pickaxe replaces the old pickaxe")
	if granite>=0:
		check(await mine_out(granite),"The steel pickaxe cuts granite")
	await buy("satchel")
	check(game.state.capacity()==10 and game.state.ore_capacity()==90,"The big satchel carries 90 ore and 10 finds")
	await buy("loupe")
	await buy("dynamite")
	var cleared: int=await blast("dynamite",rich_blast_point())
	check(cleared>=20,"Dynamite blasts a real crater (%d blocks)" % cleared)
	check(game.state.is_solid(bedrock),"Bedrock survives explosions")
	await buy("magnet")
	await buy("drill")
	check(game.state.mining_tool()=="drill","The power drill becomes the mining tool")
	await buy("tnt")
	var tnt_at: Vector3=rich_blast_point()
	cleared=await blast("tnt",tnt_at)
	await vantage("03_tnt_blast",tnt_at+Vector3(0,7,13),tnt_at,0.12)
	await vantage("04_tnt_crater",tnt_at+Vector3(0,9,12),tnt_at,1.2)
	check(cleared>=100,"TNT clears a much larger crater (%d blocks)" % cleared)
	await buy("sonar")
	var near_crystal: Vector3=Vector3.ZERO
	for gem in game.state.gems.values():
		if gem.stage=="buried" and gem.kind=="suspect":
			near_crystal=MountainScript.cell_center(int(gem.cell))
			break
	await go(near_crystal+Vector3(0,3,0))
	await get_tree().create_timer(1.2).timeout
	check(game.mountain_view._sonar_root.get_child_count()>0,"Crystal sonar pings buried crystal veins through rock")
	await buy("buster")
	var buster_at: Vector3=rich_blast_point()
	cleared=await blast("buster",buster_at)
	await vantage("05_buster_crater",buster_at+Vector3(0,14,20),buster_at,1.5)
	check(cleared>=500,"The Mountain Buster blows out a huge crater (%d blocks)" % cleared)
	# Finds released by blasts sit on solid ground and can be collected.
	var loose:=-1
	for gem in game.state.gems.values():
		if gem.stage=="loose": loose=int(gem.id); break
	check(loose>=0,"Blasts release buried finds as loose objects")
	if loose>=0:
		var at: Array=game.state.gems[loose].pos
		var spot := Vector3(float(at[0]),float(at[1]),float(at[2]))
		var below: Vector3i=MountainScript.world_to_grid(spot-Vector3(0,0.3,0))
		check(not MountainScript.in_grid(below.x,below.y,below.z) or game.state.solid_at(below.x,below.y,below.z),"Released finds rest on solid rock instead of floating")
		while game.state.held_ids().size()>=game.state.capacity():
			await go(station("tray"))
			await act("tray")
		await go(spot+Vector3(0,0.2,1.0))
		await act("vacuum")
		check(game.state.gems[loose].stage=="held","The ore magnet pulls loose finds into your hands")
	if not game.state.held_ids().is_empty():
		game.selection=0
		game.toggle_inspection()
		await get_tree().process_frame
		check(game.player.inspecting and game.ui.inspecting,"Close inspection presents learnable identification clues")
		await screenshot("07_inspection")
		game.toggle_inspection()
		await go(station("tray"))
		await act("tray")
	# Blast into the core until the genuine diamond breaks loose. It is never destroyed.
	var core: Vector3=MountainScript.cell_center(diamond_cell)
	var attempts:=0
	while game.state.gems[original_diamond].stage=="buried" and attempts<6:
		await blast("buster" if attempts%2==0 else "tnt",core+Vector3(0,float(attempts%3),0))
		attempts+=1
	check(game.state.gems[original_diamond].stage=="loose","Blasting the core releases the genuine diamond intact")
	if game.state.ore_total()>0: await sell_all()
	if game.state.gems[original_diamond].stage=="loose":
		var d: Array=game.state.gems[original_diamond].pos
		if not game.state.held_ids().is_empty():
			await go(station("tray"))
			await act("tray")
		await go(Vector3(float(d[0]),float(d[1])+0.2,float(d[2])+1.0))
		await act("pick",{"id":original_diamond})
		check(game.state.gems[original_diamond].stage=="held","The diamond can be picked up from the crater")
	await go(station("sell"))
	await act("sell")
	check(game.state.gems[original_diamond].stage=="tray","Selling cannot remove the genuine diamond; it goes to the tray")
	await go(station("tray"))
	await act("pick",{"id":original_diamond})
	await go(Vector3(0,0.1,7.2))
	await act("drop",{"id":original_diamond,"pos":[0,1.8,6.3]})
	check(game.state.gems[original_diamond].stage=="loose","Dropped genuine diamond remains recoverable in the world")
	await go(station("recover"))
	await act("recover")
	check(game.state.gems[original_diamond].stage=="tray","Lost & found recovers the genuine diamond safely")
	# A full satchel refuses more ore instead of silently losing it.
	game.state.players[1]["ore"]={"coal":game.state.ore_capacity()}
	var full_ore: int=surface_cell(true,true)
	if full_ore>=0:
		await stand_on(full_ore)
		for hit_index in range(6): await act("mine",{"cell":full_ore})
		check(game.state.is_solid(full_ore) and game.state.ore_total()==game.state.ore_capacity(),"A full satchel stops ore blocks from being mined")
	await sell_all()
	var mined_before: int=game.state.blocks_mined()
	var cells_before: PackedByteArray=game.state.cells.duplicate()
	game.state.save_game()
	var money_before: int=game.state.money
	check(game.state.load_game(),"Saved claim reloads successfully")
	check(game.state.diamond_id==original_diamond and game.state.money==money_before and game.state.upgrades.size()==9,"Save preserves diamond identity, money and equipment")
	check(game.state.blocks_mined()==mined_before and game.state.cells==cells_before,"Save preserves every mined block (%d)" % mined_before)
	await go(station("tray"))
	await act("pick",{"id":original_diamond})
	await go(station("certify"))
	await act("certify",{"id":original_diamond,"test":2})
	check(not game.state.certified,"Certification cannot skip inspection tests")
	for step in range(3): await act("certify",{"id":original_diamond,"test":step})
	check(game.state.certified and game.state.gems[original_diamond].stage=="certified","Three earned certification tests trigger the final discovery ending")
	await screenshot("08_certification")
	await vantage("09_mountain_after",Vector3(0,6,4),Vector3(0,10,-45),0.5)
	game.state.save_game()
	check(game.state.load_game() and game.state.certified,"Certification ending survives save/load")

func host_probe() -> void:
	game.start_session("solo","",24681,true)
	game.state.test_mode=true
	game.auto_collect=false
	await buy("steel_pick")
	await buy("satchel")
	await fund(400)
	check(game.state.host(24681)==OK,"Native ENet host opens actual UDP socket")
	await go(Vector3(1.5,0.1,2.8))
	phase="ready"
	write_report()
	var joined: bool=await wait_for(func(): return game.state.players.size()>=2,35)
	check(joined,"Separate client instance joins shared claim")
	if not joined: return
	var client: int=-1
	for id in game.state.players:
		if int(id)!=1: client=int(id)
	check(await wait_for(func(): return game.avatars.has(client)),"Remote player has synchronized visible 3D avatar")
	check(await wait_for(func(): return peer_report("client").get("phase","")=="mined"),"Client mined a block over the network")
	var client_cell: int=int(peer_report("client").get("cell",-1))
	check(client_cell>=0 and not game.state.is_solid(client_cell),"Host sees the block the client mined")
	check(game.state.ore_total(client)>0,"Client ore lands in the client's own satchel on the host")
	check(await wait_for(func(): return peer_report("client").get("phase","")=="blasted"),"Client threw and detonated dynamite")
	check(int(peer_report("client").get("crater",0))>=20 and game.state.blocks_mined()==int(peer_report("client").get("mined",-1)),"Host and client agree on every blasted block")
	phase="host_checked"
	write_report()
	check(await wait_for(func(): return peer_report("client").get("phase","")=="dropped"),"Client drops a synchronized find")
	var dropped: int=int(peer_report("client").get("drop_id",-1))
	if dropped>=0:
		var at: Array=game.state.gems[dropped].pos
		await go(Vector3(float(at[0]),0.1,float(at[2])+1.0))
		await act("pick",{"id":dropped})
		check(int(game.state.gems[dropped].owner)==1,"Host can pick up client's dropped find")
	phase="picked_drop"
	write_report({"drop_id":dropped})
	await go(Vector3(1.5,0.1,6.5))
	check(await wait_for(func(): return "loupe" in game.state.upgrades),"Client purchase synchronizes shared money and equipment")
	check(await wait_for(func(): return float(game.state.players[1].get("foam_until",0))>Time.get_unix_time_from_system()),"Client's harmless polishing prank reaches host")
	await screenshot("05_coop_host")
	check(await wait_for(func(): return peer_report("client").get("phase","")=="disconnecting"),"Client finished its networked checks")
	var held_disconnect: Array=peer_report("client").get("held",[])
	var money_before: int=game.state.money
	var client_ore_value: int=int(peer_report("client").get("ore_value",0))
	check(await wait_for(func(): return game.state.players.size()==1),"Client disconnect is handled by the running host")
	var rescued:=true
	for id in held_disconnect: rescued=rescued and game.state.gems[int(id)].stage=="tray"
	check(rescued and not held_disconnect.is_empty(),"Disconnected player's held finds return safely to the inspection tray")
	check(client_ore_value>0 and game.state.money==money_before+client_ore_value,"Disconnected player's ore is sold into the shared funds")

func client_probe() -> void:
	var ready: bool=await wait_for(func(): return peer_report("host").get("phase","")=="ready",90)
	check(ready,"Second native instance starts after host is ready")
	if not ready: return
	game.start_session("join","127.0.0.1",24681,false)
	game.state.test_mode=true
	game.auto_collect=false
	check(await wait_for(func(): return game.state.gems.size()==game.state.GEM_COUNT and game.state.players.size()>=2),"Client receives the full claim via real ENet")
	check(game.state.diamond_id==int(peer_report("host").get("diamond_id",-1)),"Both instances share the same unique diamond")
	check(game.state.blocks_mined()>0 and game.state.blocks_mined()==int(peer_report("host").get("blocks_mined",-1)),"Client starts with every block the host already mined")
	var cell: int=surface_cell(true,true)
	await stand_on(cell)
	for hit in range(10):
		if not game.state.is_solid(cell): break
		await act("mine",{"cell":cell})
	check(await wait_for(func(): return not game.state.is_solid(cell)),"Remote mining breaks the block through the host")
	check(await wait_for(func(): return game.state.ore_total()>0),"Client satchel fills from its own mining")
	phase="mined"
	write_report({"cell":cell})
	var before: int=game.state.blocks_mined()
	var target: Vector3=MountainScript.cell_center(MountainScript.index(26,8,36))
	await go(target+Vector3(0,3,2))
	last_fuse=-1
	var origin: Vector3=game.player.position+Vector3(0,1.4,0)
	await act("throw",{"tier":"dynamite","pos":[origin.x,origin.y,origin.z],"vel":[0,0,-3]})
	check(not "dynamite" in game.state.upgrades and last_fuse<0,"Unbought dynamite cannot be thrown")
	check(game.state.money>=330,"Shared funds are visible to the client")
	var display: Vector3=game.workshop.upgrade_positions["dynamite"]
	await go(Vector3(display.x,0.1,display.z+1.65))
	await act("buy",{"upgrade":"dynamite"})
	check(await wait_for(func(): return "dynamite" in game.state.upgrades),"Client buys dynamite with shared funds")
	await go(target+Vector3(0,3,2))
	origin=game.player.position+Vector3(0,1.4,0)
	await act("throw",{"tier":"dynamite","pos":[origin.x,origin.y,origin.z],"vel":[0,0,-3]})
	check(await wait_for(func(): return last_fuse>=0),"Client sees its own lit dynamite")
	await act("blast",{"fuse":last_fuse,"pos":[target.x,target.y,target.z]})
	check(await wait_for(func(): return game.state.blocks_mined()>before+20),"Client receives the dynamite crater")
	await get_tree().create_timer(0.5).timeout
	phase="blasted"
	write_report({"crater":game.state.blocks_mined()-before,"mined":game.state.blocks_mined()})
	check(await wait_for(func(): return peer_report("host").get("phase","")=="host_checked"),"Host and client act concurrently")
	var loose:=-1
	for gem in game.state.gems.values():
		if gem.stage=="loose": loose=int(gem.id); break
	if loose<0:
		var buried:=-1
		for gem in game.state.gems.values():
			if gem.stage=="buried": buried=int(gem.cell); break
		var c: Vector3=MountainScript.cell_center(buried)
		await go(c+Vector3(0,3,2))
		origin=game.player.position+Vector3(0,1.4,0)
		last_fuse=-1
		await act("throw",{"tier":"dynamite","pos":[origin.x,origin.y,origin.z],"vel":[0,0,-3]})
		await wait_for(func(): return last_fuse>=0)
		await act("blast",{"fuse":last_fuse,"pos":[c.x,c.y,c.z]})
		await wait_for(func():
			for gem in game.state.gems.values():
				if gem.stage=="loose": return true
			return false)
		for gem in game.state.gems.values():
			if gem.stage=="loose": loose=int(gem.id); break
	check(loose>=0,"Client sees finds released by blasting")
	if loose>=0:
		var at: Array=game.state.gems[loose].pos
		await go(Vector3(float(at[0]),float(at[1])+0.1,float(at[2])+1.0))
		await act("pick",{"id":loose})
		check(await wait_for(func(): return game.state.held_ids().has(loose)),"Client picks up a released find")
	var held: Array=game.state.held_ids().duplicate()
	var drop_id: int=int(held[0]) if not held.is_empty() else -1
	await go(Vector3(1.5,0.1,2.8))
	await act("drop",{"id":drop_id,"pos":[1.5,1.5,2.2]})
	check(await wait_for(func(): return game.state.gems[drop_id].stage=="loose"),"Client receives authoritative drop transition")
	phase="dropped"
	write_report({"drop_id":drop_id})
	check(await wait_for(func(): return int(game.state.gems[drop_id].owner)==1),"Client sees host take its dropped find")
	var previous: int=game.state.money
	var loupe: Vector3=game.workshop.upgrade_positions["loupe"]
	await go(Vector3(loupe.x,0.1,loupe.z+1.65))
	await act("buy",{"upgrade":"loupe"})
	await wait_for(func(): return "loupe" in game.state.upgrades)
	check("loupe" in game.state.upgrades and game.state.money==previous-150,"Remote purchase spends shared funds exactly once")
	await act("buy",{"upgrade":"loupe"})
	check(game.state.money==previous-150,"Duplicate purchase does not spend money twice")
	# Keep one find in hand so the disconnect rescue can be observed by the host.
	if game.state.held_ids().is_empty():
		for gem in game.state.gems.values():
			if gem.stage=="loose":
				var at: Array=gem.pos
				await go(Vector3(float(at[0]),float(at[1])+0.1,float(at[2])+1.0))
				await act("pick",{"id":int(gem.id)})
				break
	if game.state.ore_total()==0:
		var more: int=surface_cell(true,true)
		await stand_on(more)
		for hit in range(10): await act("mine",{"cell":more})
	game.player.yaw=PI
	game.player.pitch=-0.04
	game.player.update_view()
	await go(Vector3(1.5,0.1,4.3))
	await act("prank",{"target":1,"mode":"foam"})
	check(await wait_for(func(): return float(game.state.players[1].get("foam_until",0))>Time.get_unix_time_from_system()),"Foam prank synchronizes quick recoverable interruption")
	check(game.avatars.has(1),"Client renders actual host avatar rather than an AI teammate")
	await screenshot("06_coop_client")
	await wait_for(func(): return not game.state.held_ids().is_empty(),3.0)
	phase="disconnecting"
	write_report({"held":game.state.held_ids().duplicate(),"ore_value":game.state.ore_value()})
	await get_tree().create_timer(0.8).timeout
	game.state.leave()
	await get_tree().create_timer(1.0).timeout
