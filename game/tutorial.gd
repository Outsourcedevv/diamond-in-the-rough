extends Node

## Local, event-driven first-session guide. It never changes the shared world.
signal changed(data: Dictionary)

const MountainScript = preload("res://game/mountain.gd")
const STEP_COUNT := 7
const TITLES := ["Find your footing", "Break into the mountain", "Sell your ore", "Buy a steel pickaxe", "Dig out a find", "Turn a find in the light", "Keep finds safe"]

var game: Node
var test_mode := false
var preferences_path := "user://tutorial.json"
var preferences := {"schema":2, "completed":false, "dismissed":false}
var running := false
var step := 0
var session_mode := ""
var _finished_time := 0.0
var _view_origin := Vector2.ZERO
var _walked := 0.0
var _last_position := Vector3.ZERO
var _looked := false
var _inspect_started := false
var _inspect_angle := Vector2.ZERO
var _held_at_step := {}
var _previous_held := {}
var _loose_before := {}
var _previous_money := 0
var _previous_ore := 0
var _last_data_signature := ""
var _publish_timer := 0.0
var _established_completion := false

func build(owner_game: Node) -> void:
	game = owner_game
	load_preferences()
	if not game.state.changed.is_connected(_observe_world):
		game.state.changed.connect(_observe_world)
	_publish()

func load_preferences() -> void:
	preferences = {"schema":2, "completed":false, "dismissed":false}
	if test_mode or not FileAccess.file_exists(preferences_path): return
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(preferences_path))
	# The mining guide replaced the scree guide, so earlier completions start fresh.
	if decoded is Dictionary and int(decoded.get("schema",0)) == 2:
		preferences.completed = bool(decoded.get("completed",false))
		preferences.dismissed = bool(decoded.get("dismissed",false))

func _save_preferences() -> void:
	if test_mode: return
	var file := FileAccess.open(preferences_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(preferences))

func start_session(mode: String) -> void:
	session_mode = mode.to_lower()
	running = false
	_finished_time = 0.0
	if not test_mode and session_mode in ["solo", "host"] and not bool(preferences.completed) and not bool(preferences.dismissed):
		_start()
	else:
		_capture_world()
		_publish()

func restart() -> void:
	if not is_instance_valid(game) or not game.active:
		preferences.completed = false
		preferences.dismissed = false
		_save_preferences()
		_publish()
		return
	preferences.completed = false
	preferences.dismissed = false
	_save_preferences()
	_start()

func skip() -> void:
	preferences.dismissed = true
	_save_preferences()
	stop()

func stop() -> void:
	running = false
	_finished_time = 0.0
	_publish()

func _start() -> void:
	running = true
	step = 0
	_finished_time = 0.0
	_established_completion = false
	_walked = 0.0
	_looked = false
	_last_position = game.player.position
	_view_origin = Vector2(game.player.yaw, game.player.pitch)
	_capture_world()
	_enter_step()
	if not _has_fresh_material():
		_finish_established()
		return
	_publish_timer = 0.0
	_publish()

func tick(delta: float) -> void:
	if _finished_time > 0.0:
		_finished_time = maxf(0.0, _finished_time - delta)
		if _finished_time == 0.0: _publish()
	if not running or not game.active: return
	if game.ui.menu_visible: return
	match step:
		0:
			var offset: Vector3 = game.player.position - _last_position
			_walked += minf(Vector2(offset.x,offset.z).length(), 1.0)
			_last_position = game.player.position
			_looked = _looked or absf(angle_difference(_view_origin.x,game.player.yaw)) >= 0.14 or absf(game.player.pitch-_view_origin.y) >= 0.12
			if _walked >= 0.9 and _looked: _advance()
		3:
			# A replay on an established world must not ask the player to buy twice.
			if game.state.upgrades.has("steel_pick"): _advance()
		5:
			if game.player.inspecting and not game.state.held_ids().is_empty():
				if not _inspect_started:
					_inspect_started = true
					_inspect_angle = game.player.visual_angle
				elif game.player.visual_angle.distance_to(_inspect_angle) >= 0.25:
					_advance()
			else:
				_inspect_started = false
	_publish_timer -= delta
	if _publish_timer <= 0.0:
		_publish_timer = 0.35
		_publish()

## Kept for callers; progress is judged from the authoritative world instead.
func on_action(_kind: String, _args: Dictionary = {}) -> void:
	pass

func _observe_world() -> void:
	if not is_instance_valid(game): return
	if running:
		if not _has_fresh_material():
			_finish_established()
			_capture_world()
			return
		var ore: int = game.state.ore_total()
		var stored_own := false
		for id in _previous_held:
			if game.state.gems.get(int(id),{}).get("stage","") == "tray": stored_own = true
		match step:
			1:
				if ore > _previous_ore: _advance()
			2:
				if game.state.money > _previous_money and ore < _previous_ore: _advance()
			3:
				if game.state.upgrades.has("steel_pick"): _advance()
			4:
				# Only a find that came loose from the mountain counts, not one from the tray.
				for id in game.state.held_ids():
					if not _held_at_step.has(int(id)) and _loose_before.has(int(id)):
						_advance()
						break
			6:
				if stored_own: _advance()
	_capture_world()
	_publish()

func _capture_world() -> void:
	_previous_held.clear()
	for id in game.state.held_ids(): _previous_held[int(id)] = true
	_previous_money = game.state.money
	_previous_ore = game.state.ore_total()
	_loose_before.clear()
	for gem in game.state.gems.values():
		if gem.get("stage","") in ["loose","buried"]: _loose_before[int(gem.id)] = true

func _enter_step() -> void:
	_inspect_started = false
	_held_at_step.clear()
	for id in game.state.held_ids(): _held_at_step[int(id)] = true

func _advance() -> void:
	step += 1
	if step >= STEP_COUNT:
		running = false
		preferences.completed = true
		preferences.dismissed = false
		_save_preferences()
		_finished_time = 8.0
	else:
		_enter_step()
	_publish()

func _has_fresh_material() -> bool:
	for gem in game.state.gems.values():
		if gem.get("stage","") == "buried": return true
	return false

func _finish_established() -> void:
	# A world with every find already dug out has no discovery loop to demonstrate.
	# Acknowledge its earned progress and leave the controls available in Help.
	running = false
	step = STEP_COUNT
	_established_completion = true
	preferences.completed = true
	preferences.dismissed = false
	_save_preferences()
	_finished_time = 12.0
	_publish()

## Nearest surface ore the player can reach with the starting pickaxe.
func _nearest_ore() -> Vector3:
	var grid = game.state.mountain
	var here: Vector3 = game.player.position
	var best := Vector3(clampf(here.x,-12.0,12.0),1.0,-15.5)
	var distance := INF
	for z in range(0,MountainScript.SIZE_Z,2):
		for x in range(0,MountainScript.SIZE_X,2):
			for y in range(grid.height(x,z)-1,maxi(0,grid.height(x,z)-3),-1):
				var cell: int = MountainScript.index(x,y,z)
				if MountainScript.ore_for_code(game.state.cell_code(cell)).is_empty() or grid.needs_steel(x,y,z) or not game.state.exposed(cell): continue
				var at: Vector3 = MountainScript.cell_center(cell)
				var squared: float = at.distance_squared_to(here)
				if squared < distance:
					distance = squared
					best = at
	return best

## Nearest buried fossil or curio close to the surface.
func _nearest_find() -> Vector3:
	var grid = game.state.mountain
	var here: Vector3 = game.player.position
	var best := Vector3.ZERO
	var distance := INF
	for gem in game.state.gems.values():
		if gem.get("stage","") != "buried": continue
		var c: Vector3i = MountainScript.coords(int(gem.cell))
		if grid.depth(c.x,c.y,c.z) > 4: continue
		var at: Vector3 = MountainScript.cell_center(int(gem.cell))
		var squared: float = at.distance_squared_to(here)
		if squared < distance:
			distance = squared
			best = at
	return best

func _station(name: String) -> Vector3:
	return game.workshop.stations.get(name,Vector3.ZERO)

func data() -> Dictionary:
	var result := {"visible":running or _finished_time > 0.0, "completed":bool(preferences.completed), "current":mini(step+1,STEP_COUNT), "total":STEP_COUNT, "progress":float(step)/STEP_COUNT, "title":"", "instruction":"", "key":"", "target":Vector3.ZERO, "target_label":"", "target_distance":0.0, "target_distance_metres":0.0, "direction":""}
	if not is_instance_valid(game): return result
	if not running:
		if _finished_time > 0.0:
			if _established_completion:
				result.title = "Mountain searched"
				result.instruction = "Every find is already dug out. Pick stored finds from the tray to shelve or sell them. How to play has the controls."
				result.key = "E at tray  /  Right click to inspect"
				if game.state.certified:
					result.title = "Diamond already certified"
					result.instruction = "Your diamond is certified. Keep blasting for ore and fill your collection. How to play has the controls whenever you need them."
					result.key = "Tab: journal"
			else:
				result.title = "You are ready"
				result.instruction = "Blast deeper for richer ore. The one real diamond is buried deep in the core; bring it to the certification bench. Replay from How to play."
			result.progress = 1.0
		return result
	result.title = TITLES[step]
	match step:
		0:
			result.instruction = "Walk around the camp and look toward the mountain. Hold Shift to run, Space to jump."
			result.key = "W A S D  /  Mouse"
		1:
			result.instruction = "Walk up to the mountain and hold left click on rock flecked with ore. Ore goes straight into your satchel."
			result.key = "Hold left click"
			result.target = _nearest_ore()
			result.target_label = "Surface ore"
			if game.state.ore_total() >= game.state.ore_capacity():
				result.instruction = "Your satchel is full. Sell it at the exchange, then mine one more ore block."
				result.target = _station("sell")
				result.target_label = "Scrap exchange"
		2:
			result.instruction = "Bring your ore to the scrap exchange and sell it. Each ore has its own price; deeper ore is worth more."
			if game.state.ore_total() == 0: result.instruction = "Mine a little more ore, then sell it at the exchange."
			result.key = "E at the exchange"
			result.target = _station("sell")
			result.target_label = "Scrap exchange"
		3:
			var shortfall: int = maxi(0,int(game.state.prices.steel_pick)-game.state.money)
			result.instruction = "Buy the steel pickaxe from its display at the camp outfitter. It mines twice as fast and cuts granite."
			if shortfall > 0: result.instruction = "Earn $%d more by mining and selling ore, then buy the steel pickaxe at the outfitter." % shortfall
			result.key = "E on the steel pickaxe  /  $60"
			result.target = _station("shop")
			var positions: Variant = game.workshop.get("upgrade_positions")
			if positions is Dictionary: result.target = positions.get("steel_pick",result.target)
			result.target_label = "Steel pickaxe"
		4:
			result.instruction = "Pale seams in the rock hold fossils and curios. Mine one and walk over what falls out."
			result.key = "Hold left click  /  walk over it"
			result.target = _nearest_find()
			result.target_label = "Buried fossil" if result.target != Vector3.ZERO else ""
		5:
			result.instruction = "Inspect a held find and turn it in the light. Wheel selects another find."
			if game.state.held_ids().is_empty(): result.instruction = "Pick up a fossil or curio, then right click to inspect it and move the mouse to turn it."
			result.key = "Right click  /  Mouse"
		6:
			result.instruction = "Store your finds in the inspection tray. They stay safe there until you shelve or sell them."
			if game.state.held_ids().is_empty(): result.instruction = "Pick up a find and place it in the inspection tray. Stored finds stay safe."
			result.key = "E at the tray"
			result.target = _station("tray")
			result.target_label = "Inspection tray"
	if step == 4 and game.state.held_ids().size() >= game.state.capacity():
		result.instruction = "Your hands are full. Store finds in the inspection tray, then dig out another."
		result.key = "E at the tray"
		result.target = _station("tray")
		result.target_label = "Inspection tray"
	if not str(result.target_label).is_empty():
		var offset: Vector3 = result.target - game.player.position
		result.target_distance = offset.length()
		result.target_distance_metres = result.target_distance
		offset.y = 0.0
		var forward: Vector3 = -game.player.camera.global_basis.z
		forward.y = 0.0
		var alignment: float = offset.normalized().dot(forward.normalized())
		result.direction = "ahead" if alignment >= 0.65 else ("behind" if alignment <= -0.65 else ("right" if offset.dot(game.player.camera.global_basis.x) > 0.0 else "left"))
	return result

func _publish() -> void:
	var current := data()
	var signature := str(current)
	if signature == _last_data_signature: return
	_last_data_signature = signature
	changed.emit(current)
