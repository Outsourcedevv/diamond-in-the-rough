extends Node

## Local, event-driven first-session guide. It never changes the shared world.
signal changed(data: Dictionary)

const STEP_COUNT := 7
const TITLES := ["Find your footing", "Take a small batch", "Turn a find in the light", "Trade the ordinary material", "Get a larger scoop", "Keep a batch safely", "Head back to the mountain"]

var game: Node
var test_mode := false
var preferences_path := "user://tutorial.json"
var preferences := {"schema":1, "completed":false, "dismissed":false}
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
var _searched_at_step := 0
var _held_at_step := {}
var _previous_held := {}
var _previous_money := 0
var _pending_scoop := false
var _pending_scoop_time := 0.0
var _last_notice := ""
var _pending_kind := ""
var _pending_pick_id := -1
var _last_data_signature := ""
var _publish_timer := 0.0
var _established_completion := false

func build(owner_game: Node) -> void:
	game = owner_game
	load_preferences()
	if not game.state.changed.is_connected(_observe_world):
		game.state.changed.connect(_observe_world)
	if not game.state.notice.is_connected(_observe_notice):
		game.state.notice.connect(_observe_notice)
	_publish()

func load_preferences() -> void:
	preferences = {"schema":1, "completed":false, "dismissed":false}
	if test_mode or not FileAccess.file_exists(preferences_path): return
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(preferences_path))
	if decoded is Dictionary and int(decoded.get("schema",0)) == 1:
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
	_pending_scoop = false
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
	if _pending_scoop:
		_pending_scoop_time -= delta
		if _pending_scoop_time <= 0.0: _pending_scoop = false
	match step:
		0:
			var offset: Vector3 = game.player.position - _last_position
			_walked += minf(Vector2(offset.x,offset.z).length(), 1.0)
			_last_position = game.player.position
			_looked = _looked or absf(angle_difference(_view_origin.x,game.player.yaw)) >= 0.14 or absf(game.player.pitch-_view_origin.y) >= 0.12
			if _walked >= 0.9 and _looked: _advance()
		2:
			if game.player.inspecting and not game.state.held_ids().is_empty():
				if not _inspect_started:
					_inspect_started = true
					_inspect_angle = game.player.visual_angle
				elif game.player.visual_angle.distance_to(_inspect_angle) >= 0.25:
					_advance()
			else:
				_inspect_started = false
		4:
			# A replay on an established world must not ask the player to buy twice.
			if game.state.upgrades.has("scoop"): _advance()
	_publish_timer -= delta
	if _publish_timer <= 0.0:
		_publish_timer = 0.35
		_publish()

func on_action(kind: String, args: Dictionary = {}) -> void:
	if not running: return
	if kind == "pick" and not bool(args.get("from_pile",true)): return
	if kind in ["scoop", "pick"] and step in [1,6]:
		_pending_scoop = true
		_pending_scoop_time = 2.0
		_pending_kind = kind
		_pending_pick_id = int(args.get("id",-1)) if kind == "pick" else -1
		if game.state.is_authority(): _check_scoop()

func _check_scoop() -> void:
	if not running or not _pending_scoop or not step in [1,6]: return
	var committed := _last_notice.begins_with("Picked up ") if _pending_kind == "pick" else _last_notice.begins_with("Scoop collected ") or _last_notice.begins_with("Vacuum collected ")
	if not committed: return
	if game.state.searched <= _searched_at_step: return
	for id in game.state.held_ids():
		if _pending_kind == "pick" and int(id) != _pending_pick_id: continue
		if not _held_at_step.has(int(id)) and bool(game.state.gems[int(id)].get("searched",false)):
			_pending_scoop = false
			_advance()
			return

func _observe_notice(message: String) -> void:
	# A rejected command must not receive credit for an earlier successful find.
	# State emits this notice only after the authoritative transaction commits.
	_last_notice = message
	if not game.state.is_authority(): _check_scoop()

func _observe_world() -> void:
	if not is_instance_valid(game): return
	if running:
		if not _has_fresh_material():
			_finish_established()
			_capture_world()
			return
		var sold_own := false
		var stored_own := false
		for id in _previous_held:
			var gem: Dictionary = game.state.gems.get(int(id),{})
			if gem.get("stage","") == "sold": sold_own = true
			if gem.get("stage","") == "tray": stored_own = true
		match step:
			3:
				if sold_own and game.state.money > _previous_money: _advance()
			4:
				if game.state.upgrades.has("scoop"): _advance()
			5:
				if stored_own: _advance()
	_capture_world()
	_publish()

func _capture_world() -> void:
	_previous_held.clear()
	for id in game.state.held_ids(): _previous_held[int(id)] = true
	_previous_money = game.state.money

func _enter_step() -> void:
	_inspect_started = false
	_pending_scoop = false
	_last_notice = ""
	_pending_kind = ""
	_pending_pick_id = -1
	_searched_at_step = game.state.searched
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
		if gem.get("stage","") == "pile" and not bool(gem.get("searched",false)): return true
	return false

func _finish_established() -> void:
	# An existing world can have no remaining search/sale loop to demonstrate.
	# Acknowledge its earned progress and leave the controls available in Help.
	running = false
	step = STEP_COUNT
	_pending_scoop = false
	_established_completion = true
	preferences.completed = true
	preferences.dismissed = false
	_save_preferences()
	_finished_time = 12.0
	_publish()

func _nearest_pile() -> Vector3:
	var nearest := Vector3.ZERO
	var distance := INF
	var searchable := {}
	for gem in game.state.gems.values():
		if gem.stage == "pile": searchable[int(gem.pile)] = true
	for index in range(game.workshop.pile_centers.size()):
		if not searchable.has(index): continue
		var pos: Vector3 = game.workshop.pile_centers[index]
		var squared: float = pos.distance_squared_to(game.player.position)
		if squared < distance:
			distance = squared
			nearest = pos
	return nearest

func _station(name: String) -> Vector3:
	return game.workshop.stations.get(name,Vector3.ZERO)

func data() -> Dictionary:
	var result := {"visible":running or _finished_time > 0.0, "completed":bool(preferences.completed), "current":mini(step+1,STEP_COUNT), "total":STEP_COUNT, "progress":float(step)/STEP_COUNT, "title":"", "instruction":"", "key":"", "target":Vector3.ZERO, "target_label":"", "target_distance":0.0, "target_distance_metres":0.0, "direction":""}
	if not is_instance_valid(game): return result
	if not running:
		if _finished_time > 0.0:
			if _established_completion:
				result.title = "Search complete"
				result.instruction = "Your mountain is already searched. Inspect stored candidates and test them at the bench. How to play has the controls."
				result.key = "E at tray  /  Right click to inspect"
				if game.state.certified:
					result.title = "Diamond already certified"
					result.instruction = "Your diamond is certified. Explore your collection and equipment. How to play has the controls whenever you need them."
					result.key = "Tab: journal"
			else:
				result.title = "You are ready"
				result.instruction = "Keep comparing finds. The tray protects candidates; the bench confirms the evidence. Replay from How to play."
			result.progress = 1.0
		return result
	result.title = TITLES[step]
	match step:
		0:
			result.instruction = "Walk around the yard and look toward the mountain. Hold Shift to run."
			result.key = "W A S D  /  Mouse"
		1:
			result.instruction = "Move close to the material. Scoop a patch, or pick one find. Your first scoop holds three pieces."
			result.key = "E  /  Left click"
			result.target = _nearest_pile()
			result.target_label = "Searchable material"
		2:
			result.instruction = "Inspect a held find and turn it in the light. Compare mist, edges and bubbles. Wheel selects another find."
			result.key = "Right click  /  Mouse"
		3:
			result.instruction = "Close inspection and bring your batch to the exchange. Ordinary material earns money; clear crystals go safely to the tray."
			if game.state.held_ids().is_empty(): result.instruction = "Scoop another batch and sell it at the exchange. Clear crystal candidates are kept in the tray."
			result.key = "E at the exchange"
			result.target = _station("sell")
			result.target_label = "Scrap exchange"
		4:
			var shortfall: int = maxi(0,int(game.state.prices.scoop)-game.state.money)
			result.instruction = "Buy the larger scoop from its model on the counter. The price is printed below its name."
			if shortfall > 0: result.instruction = "Earn $%d more by selling ordinary batches, then buy the larger scoop from its model on the counter." % shortfall
			result.key = "E on larger scoop  /  $70"
			result.target = _station("shop")
			var positions: Variant = game.workshop.get("upgrade_positions")
			if positions is Dictionary: result.target = positions.get("scoop",result.target)
			result.target_label = "Larger scoop"
		5:
			result.instruction = "Gather a fresh batch and pour it into the tray. Stored finds stay safe and can be picked up for inspection."
			if not game.state.held_ids().is_empty(): result.instruction = "Pour your batch into the inspection tray. Stored finds stay safe and can be picked up for inspection."
			result.key = "E at the tray"
			result.target = _station("tray")
			result.target_label = "Inspection tray"
		6:
			result.instruction = "Gather another find. Compare fast-clearing mist, crisp single edges and no bubbles. Confirm the evidence at the bench."
			result.key = "E  /  Left click"
			result.target = _nearest_pile()
			result.target_label = "Searchable material"
	if step in [1,6] and game.state.held_ids().size() >= game.state.capacity():
		result.instruction = "Your hands are full. Pour this batch into the inspection tray, then return to the mountain for another find."
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
