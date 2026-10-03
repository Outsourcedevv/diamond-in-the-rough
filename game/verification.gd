extends Node

## Reproducible integration verification. Uses isolated saves and the live game API.
## Run with --verify=solo/host/client --report-dir=... (no player save is modified).
var game: Node
var report_dir := ""
var role := ""
var checks: Array[String] = []
var errors: Array[String] = []
var started := 0
var phase := "boot"

func begin(owner_game: Node, mode: String, args: PackedStringArray) -> void:
	game=owner_game
	role=mode
	started=Time.get_ticks_msec()
	for arg in args:
		if arg.begins_with("--report-dir="): report_dir=arg.trim_prefix("--report-dir=")
	if report_dir.is_empty(): report_dir=OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(report_dir)
	game.state._save_path=report_dir.path_join("verify_%s_save.json" % role)
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
	var data: Dictionary={"role":role,"phase":phase,"checks":checks,"errors":errors,"elapsed_ms":Time.get_ticks_msec()-started,"money":game.state.money,"diamond_id":game.state.diamond_id,"searched":game.state.searched,"upgrades":game.state.upgrades,"certified":game.state.certified,"players":game.state.players.size(),"local_id":game.state.local_id()}
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
	await get_tree().create_timer(0.14).timeout

func act(kind: String,args:Dictionary={}) -> void:
	game.state.action(kind,args)
	await get_tree().create_timer(0.14 if role=="client" else 0.015).timeout

func station(id: String) -> Vector3:
	var pos: Vector3=game.workshop.stations[id]
	return Vector3(pos.x,0.1,pos.z+1.8)

func fund(amount: int) -> void:
	var guard:=0
	while game.state.money<amount and guard<260:
		var sector: int=-1
		for gem in game.state.gems.values():
			if gem.stage=="pile":
				sector=int(gem.pile)
				break
		if sector<0: break
		await go(game.workshop.pile_centers[sector]+Vector3(0,0.1,0))
		await act("scoop",{"pile":sector})
		for id in game.state.held_ids().duplicate():
			if game.state.gems[int(id)].kind=="collectible": await act("collect",{"id":int(id)})
		await go(station("sell"))
		await act("sell")
		guard+=1
	check(game.state.money>=amount,"Natural payouts reached $%s" % amount)

func buy(id: String) -> void:
	await fund(int(game.state.prices[id]))
	await go(station("shop"))
	await act("buy",{"upgrade":id})
	check(id in game.state.upgrades,"Purchased working upgrade: "+id)

func screenshot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var path:=report_dir.path_join(name+".png")
	game.get_viewport().get_texture().get_image().save_png(path)

func solo() -> void:
	game.start_session("solo","",24680,true)
	check(game.state.gems.size()==720,"Generated 720 stable searchable objects")
	var original_diamond: int=game.state.diamond_id
	var real_count:=0
	for gem in game.state.gems.values():
		if gem.kind=="diamond": real_count+=1
	check(real_count==1,"Exactly one genuine diamond generated")
	await screenshot("01_workshop")
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
	await buy("scoop")
	check(game.state.capacity()==9,"Larger scoop changes carrying capacity from 3 to 9")
	game.player.yaw=0
	game.player.pitch=-0.45
	game.player.update_view()
	game.selected_target=game.player.target()
	var physical_station: Object=game.selected_target.get("collider")
	check(is_instance_valid(physical_station) and physical_station.get_meta("station","")=="shop","First-person ray reaches the physical upgrade counter")
	game.interact()
	check(game.ui.menu_visible,"E opens the actual shop interface")
	game.resume_game()
	check(not game.ui.menu_visible and not game.player.inspecting,"Leaving a modal restores first-person controls")
	await buy("trays")
	check(game.state.capacity()==14,"Sorting trays expand carrying capacity to 14")
	await buy("loupe")
	await buy("wash")
	var sector: int=11
	await go(game.workshop.pile_centers[sector]+Vector3(0,0.1,0))
	await act("scoop",{"pile":sector})
	var ids: Array=game.state.held_ids().duplicate()
	check(not ids.is_empty(),"Scoop fills held batch with unique objects")
	if not ids.is_empty():
		game.selection=0
		game.toggle_inspection()
		await get_tree().process_frame
		check(game.player.inspecting and game.ui.inspecting,"Close inspection presents learnable identification clues")
		var mouse:=InputEventMouseMotion.new()
		mouse.relative=Vector2(52,24)
		Input.parse_input_event(mouse)
		await get_tree().process_frame
		if DisplayServer.get_name()!="headless":
			check(game.player.visual_angle.length()>0.1,"Held object rotates with mouse during inspection")
		else:
			print("Headless verification: mouse rotation requires the native window test.")
		await screenshot("02_inspection")
		game.toggle_inspection()
	await go(station("wash"))
	await act("wash")
	var clean:=true
	for id in ids: clean=clean and bool(game.state.gems[int(id)].clean)
	check(clean,"Washing cleans discoveries for improved sale value")
	await go(station("sell"))
	await act("sell")
	await buy("sorter")
	await go(station("sorter"))
	var old_searched: int=game.state.searched
	await act("process",{"pile":11})
	check(game.state.searched>old_searched,"Sorting machine processes a real persistent batch")
	await buy("vacuum")
	await buy("conveyor")
	await buy("scanner")
	var scan_sector: int=-1
	for gem in game.state.gems.values():
		if gem.stage=="pile": scan_sector=int(gem.pile); break
	check(scan_sector>=0,"Full upgrade path leaves material to search")
	if scan_sector>=0:
		await go(game.workshop.pile_centers[scan_sector]+Vector3(0,0.1,0))
		await act("scan",{"pile":scan_sector,"portable":true})
		var scanned:=0
		for gem in game.state.gems.values():
			if gem.get("scanned",false): scanned+=1
		check(scanned>0 and scanned<=24,"Advanced scanner examines only one local batch")
	await go(Vector3(0,0.1,7.2))
	game.player.yaw=0
	game.player.pitch=-0.03
	game.player.update_view()
	await screenshot("03_upgraded_workshop")
	await go(station("sorter"))
	for pile in range(12):
		for batch in range(4): await act("process",{"pile":pile})
	check(game.state.gems[original_diamond].stage=="tray","Machinery diverts the real diamond into the safe inspection tray")
	var reachable:= {}
	var page_count: int=maxi(1,ceili(float(game.tray_count())/48))
	for page in range(page_count):
		game.tray_page=page
		game.refresh()
		await get_tree().process_frame
		for id in game.gem_nodes:
			if game.state.gems[int(id)].stage=="tray": reachable[int(id)]=true
	check(reachable.size()==game.tray_count() and reachable.has(original_diamond),"Every stored candidate including the genuine diamond has an accessible physical tray page")
	await go(station("tray"))
	await act("pick",{"id":original_diamond})
	await go(station("sell"))
	await act("sell")
	check(game.state.gems[original_diamond].stage=="tray","Accidental sale cannot remove the genuine diamond")
	await go(station("tray"))
	await act("pick",{"id":original_diamond})
	await go(Vector3(0,0.1,7.2))
	await act("drop",{"id":original_diamond,"pos":[0,1.8,6.3]})
	check(game.state.gems[original_diamond].stage=="loose","Dropped genuine diamond remains recoverable in the world")
	await go(station("recover"))
	await act("recover")
	check(game.state.gems[original_diamond].stage=="tray","Lost-item bell recovers genuine diamond safely")
	game.state.save_game()
	var money_before: int=game.state.money
	check(game.state.load_game(),"Saved world reloads successfully")
	check(game.state.diamond_id==original_diamond and game.state.money==money_before and game.state.upgrades.size()==8,"Save preserves diamond identity, money, upgrades and progress")
	await go(station("tray"))
	await act("pick",{"id":original_diamond})
	await go(station("certify"))
	await act("certify",{"id":original_diamond,"test":2})
	check(not game.state.certified,"Certification cannot skip inspection tests")
	for step in range(3): await act("certify",{"id":original_diamond,"test":step})
	check(game.state.certified and game.state.gems[original_diamond].stage=="certified","Three earned certification tests trigger the final discovery ending")
	await screenshot("04_certification")
	game.state.save_game()
	check(game.state.load_game() and game.state.certified,"Certification ending survives save/load")

func host_probe() -> void:
	game.start_session("solo","",24681,true)
	await buy("scoop")
	await buy("sorter")
	await buy("wash")
	await fund(250)
	check(game.state.host(24681)==OK,"Native ENet host opens actual UDP socket")
	await go(Vector3(1.5,0.1,2.8))
	phase="ready"
	write_report()
	var joined: bool=await wait_for(func(): return game.state.players.size()>=2,35)
	check(joined,"Separate client instance joins shared workshop")
	if not joined: return
	var client: int=-1
	for id in game.state.players:
		if int(id)!=1: client=int(id)
	check(await wait_for(func(): return game.avatars.has(client)),"Remote player has synchronized visible 3D avatar")
	check(await wait_for(func(): return peer_report("client").get("phase","")=="picked"),"Client performed networked scoop action")
	check(game.state.held_ids(client).size()>0,"Host sees client held objects with unique server ownership")
	await go(game.workshop.pile_centers[10]+Vector3(0,0.1,0))
	await act("scoop",{"pile":10})
	var overlap:=false
	for id in game.state.held_ids(1):
		if id in game.state.held_ids(client): overlap=true
	check(not overlap,"Two players cannot duplicate a held object")
	phase="host_holding"
	write_report()
	check(await wait_for(func(): return peer_report("client").get("phase","")=="dropped"),"Client drops a synchronized object")
	var dropped: int=int(peer_report("client").get("drop_id",-1))
	await go(Vector3(1.5,0.1,2.8))
	var host_held: Array=game.state.held_ids(1)
	if host_held.size()>=game.state.capacity():
		await act("drop",{"id":int(host_held[0]),"pos":[1.0,1.4,2.8]})
	if dropped>=0:
		await act("pick",{"id":dropped})
		check(int(game.state.gems[dropped].owner)==1,"Host can pick up client's dropped physical object")
	phase="picked_drop"
	write_report({"drop_id":dropped})
	await go(Vector3(1.5,0.1,6.5))
	check(await wait_for(func(): return "trays" in game.state.upgrades),"Client purchase synchronizes shared money and equipment")
	check(await wait_for(func(): return float(game.state.players[1].get("foam_until",0))>Time.get_unix_time_from_system()),"Client's harmless polishing prank reaches host")
	await screenshot("05_coop_host")
	check(await wait_for(func(): return peer_report("client").get("phase","")=="disconnecting"),"Client verified machine processing and snapshots")
	var held_disconnect: Array=peer_report("client").get("held",[])
	check(await wait_for(func(): return game.state.players.size()==1),"Client disconnect is handled by the running host")
	var rescued:=true
	for id in held_disconnect: rescued=rescued and game.state.gems[int(id)].stage=="tray"
	check(rescued and not held_disconnect.is_empty(),"Disconnected player's held objects return safely to inspection tray")

func client_probe() -> void:
	var ready: bool=await wait_for(func(): return peer_report("host").get("phase","")=="ready",55)
	check(ready,"Second native instance starts after host is ready")
	if not ready: return
	game.start_session("join","127.0.0.1",24681,false)
	check(await wait_for(func(): return game.state.gems.size()==720 and game.state.players.size()>=2),"Client receives full persistent world via real ENet")
	check(game.state.diamond_id==int(peer_report("host").get("diamond_id",-1)),"Both instances share the same unique diamond location")
	await go(game.workshop.pile_centers[10]+Vector3(0,0.1,0))
	await act("scoop",{"pile":10})
	check(await wait_for(func(): return game.state.held_ids().size()==9),"Remote scoop obeys authoritative capacity")
	phase="picked"
	write_report()
	check(await wait_for(func(): return peer_report("host").get("phase","")=="host_holding"),"Host and client act concurrently")
	await go(Vector3(1.5,0.1,2.8))
	var held: Array=game.state.held_ids().duplicate()
	var drop_id: int=int(held[0]) if not held.is_empty() else -1
	await act("drop",{"id":drop_id,"pos":[1.5,1.5,2.2]})
	check(await wait_for(func(): return game.state.gems[drop_id].stage=="loose"),"Client receives authoritative drop transition")
	phase="dropped"
	write_report({"drop_id":drop_id})
	check(await wait_for(func(): return int(game.state.gems[drop_id].owner)==1),"Client sees host take its dropped object")
	await go(station("shop"))
	var previous: int=game.state.money
	await act("buy",{"upgrade":"trays"})
	await wait_for(func(): return "trays" in game.state.upgrades)
	check("trays" in game.state.upgrades and game.state.money==previous-100,"Remote purchase spends shared funds exactly once")
	await act("buy",{"upgrade":"trays"})
	check(game.state.money==previous-100,"Duplicate purchase does not spend money twice")
	await go(station("sorter"))
	var old_searched: int=game.state.searched
	await act("process",{"pile":10})
	check(await wait_for(func(): return game.state.searched>old_searched),"Remote client operates synchronized processing machine")
	game.player.yaw=PI
	game.player.pitch=-0.04
	game.player.update_view()
	await go(Vector3(1.5,0.1,4.3))
	await act("prank",{"target":1,"mode":"foam"})
	check(await wait_for(func(): return float(game.state.players[1].get("foam_until",0))>Time.get_unix_time_from_system()),"Foam prank synchronizes quick recoverable interruption")
	check(game.avatars.has(1),"Client renders actual host avatar rather than an AI teammate")
	await screenshot("06_coop_client")
	phase="disconnecting"
	write_report({"held":game.state.held_ids().duplicate()})
	await get_tree().create_timer(0.8).timeout
	game.state.leave()
	await get_tree().create_timer(1.0).timeout
