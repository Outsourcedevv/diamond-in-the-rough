extends Node
class_name RoughState

## The server owns every block, item transition and purchase. Clients submit intentions.
## IDs and the seeded diamond are preserved even after an item has been sold.
## The mountain holds exactly one diamond; every other find is a fossil or curio.
signal changed
signal notice(text: String)
signal peer_joined(id: int)
signal peer_left(id: int)
signal pose_received(id: int, position: Vector3, yaw: float, pitch: float)
signal voice_received(peer_id: int, sequence: int, payload: PackedByteArray)
signal connection_status(text: String)
signal cells_changed(cells: PackedInt32Array)
signal world_reset
signal throw_spawned(peer_id: int, tier: String, position: Vector3, velocity: Vector3, fuse: int)
signal blasted(fuse: int, position: Vector3, tier: String)

const MountainScript = preload("res://game/mountain.gd")
const SAVE_VERSION: int = 3
const GEM_COUNT: int = 181
## How deep the diamond rests: in the bottom layers, well inside the core.
const DIAMOND_MIN_DEPTH: int = 28
## The assay loupe's bonus on every ore sale.
const LOUPE_BONUS: float = 1.25
const MAX_PLAYERS: int = 4
const MINING_REACH: float = 5.6
const VOICE_FRAME_BYTES: int = 320 # 20 ms of mono 16 kHz G.711 mu-law audio.
const VOICE_RANGE_METRES: float = 12.0
const VOICE_MAX_SEQUENCE: int = 2147483647
const VOICE_PACKETS_PER_SECOND: float = 60.0
const VOICE_BURST_PACKETS: float = 6.0
const COLLECTIBLE_NAMES: Array[String] = ["Ammonite fossil", "Trilobite", "Dinosaur tooth", "Petrified egg", "Fossil fern", "Purple geode", "Gold-rush coin", "Old miner's lamp"]
const ODDITY_NAMES: Array[String] = ["Fool's gold", "Rusty miner's helmet", "Suspicious rock-shaped rock", "Lost lunchbox"]
const EXPLOSIVES: Dictionary = {
	"dynamite": {"radius": 2.4, "fuse": 2.2, "cooldown": 2.5},
	"tnt": {"radius": 3.9, "fuse": 2.8, "cooldown": 5.0},
	"buster": {"radius": 6.5, "fuse": 3.6, "cooldown": 12.0}
}

var money: int = 0
var gems: Dictionary = {}
var upgrades: Array[String] = []
var collection: Array[String] = []
var diamond_id: int = -1
var certified: bool = false
var searched: int = 0
var players: Dictionary = {}
var seed_value: int = 0
var prices: Dictionary = {"steel_pick": 60, "satchel": 110, "loupe": 150, "dynamite": 180, "magnet": 300, "drill": 420, "tnt": 750, "sonar": 1000, "buster": 2400}
var upgrade_names: Dictionary = {"steel_pick": "Steel pickaxe", "satchel": "Big satchel", "loupe": "Assay loupe", "dynamite": "Dynamite", "magnet": "Ore magnet", "drill": "Power drill", "tnt": "TNT", "sonar": "Treasure sonar", "buster": "Mountain Buster"}
var benefits: Dictionary = {
	"steel_pick": "Mines twice as fast and cuts through granite.",
	"satchel": "Carry 90 ore and 10 finds.",
	"loupe": "Every ore sells for 25% more at the exchange.",
	"dynamite": "Press 2 to throw. Blasts a 2.4 m crater.",
	"magnet": "Pulls loose finds within 7 m into your hands.",
	"drill": "Hold left click to drill through rock at speed.",
	"tnt": "Press 3 to throw. Blasts a 3.9 m crater.",
	"sonar": "Pings the buried diamond and fossils within 16 m through solid rock.",
	"buster": "Press 4 to throw. Blasts a 6.5 m crater."
}
var station_positions: Dictionary = {}
var upgrade_positions: Dictionary = {}
var mountain = MountainScript.new()
var mined := PackedByteArray()
var cells := PackedByteArray()
## Verification only: removes explosive preparation time so tests stay fast.
var test_mode: bool = false

var _save_path: String = "user://rough_default.json"
var _network_mode: String = "solo"
var _connecting: bool = false
var _rpc_ready: bool = false
var _action_times: Dictionary = {}
var _world_is_local: bool = true
var _cell_seed: int = -1
var _buried_by_cell: Dictionary = {}
var _damage: Dictionary = {}
var _fuses: Dictionary = {}
var _next_fuse: int = 1
var _throw_ready: Dictionary = {}
var _save_dirty: bool = false
var _outdated_save: bool = false
var _last_save_ms: int = 0
# Ephemeral transport data: microphone audio and these counters are never saved.
var voice_sent_packets: int = 0
var voice_relayed_packets: int = 0
var voice_received_packets: int = 0
var _voice_sender_limits: Dictionary = {}
var _voice_received_sequences: Dictionary = {}


func _ready() -> void:
	_connect_network_signals()
	if station_positions.is_empty():
		station_positions = {"sell": Vector3(-8, 1, 4), "shop": Vector3(8, 1, 4), "tray": Vector3(-8, 1, 0), "certify": Vector3(0, 1, -8), "recover": Vector3(-5, 1, 8), "collection": Vector3(5, 1, 8)}
	if players.is_empty():
		players[1] = _player_template(1)
	if mined.is_empty():
		mined = MountainScript.empty_mined()


func _process(_delta: float) -> void:
	# Mining is frequent, so its saves are batched instead of written per block.
	if _save_dirty and is_authority() and Time.get_ticks_msec() - _last_save_ms > 3000:
		save_game()


func _connect_network_signals() -> void:
	if _rpc_ready:
		return
	_rpc_ready = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func configure_save(slot: String) -> void:
	var safe_slot: String = ""
	for character in slot.to_lower():
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe_slot += character
	if safe_slot.is_empty():
		safe_slot = "default"
	_save_path = "user://rough_%s.json" % safe_slot.substr(0, 48)


func set_player(peer_id: int, position: Vector3, yaw: float = 0.0, pitch: float = 0.0) -> void:
	if not _valid_position(position):
		return
	if peer_id <= 0:
		peer_id = local_id()
	if not players.has(peer_id):
		players[peer_id] = _player_template(peer_id)
	var entry: Dictionary = players[peer_id]
	entry["pos"] = _vector_array(position)
	entry["yaw"] = yaw
	entry["pitch"] = clampf(pitch, -1.55, 1.55)
	players[peer_id] = entry


func new_game() -> void:
	if not is_authority():
		return
	_world_is_local = true
	seed_value = int(Time.get_unix_time_from_system()) ^ int(randi())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	money = 0
	gems.clear()
	upgrades.clear()
	collection.clear()
	certified = false
	searched = 0
	mined = MountainScript.empty_mined()
	_damage.clear()
	_fuses.clear()
	for id in players:
		players[id]["ore"] = {}
	# The one diamond rests deep in the mountain's core. There are no look-alikes.
	var core: Array[int] = []
	for z: int in range(MountainScript.SIZE_Z):
		for x: int in range(MountainScript.SIZE_X):
			for y: int in range(2, 9):
				if mountain.natural_solid(x, y, z) and mountain.depth(x, y, z) >= DIAMOND_MIN_DEPTH:
					core.append(MountainScript.index(x, y, z))
	var diamond_cell: int = core[rng.randi_range(0, core.size() - 1)]
	diamond_id = rng.randi_range(0, GEM_COUNT - 1)
	var used: Dictionary = {diamond_cell: true}
	for id in range(GEM_COUNT):
		var cell: int = diamond_cell if id == diamond_id else _random_find_cell(rng, used)
		used[cell] = true
		var gem: Dictionary = {"id": id, "cell": cell, "stage": "buried", "owner": 0, "pos": _vector_array(MountainScript.cell_center(cell)), "flagged": false, "searched": false}
		if id == diamond_id:
			gem["kind"] = "diamond"
			gem["name"] = "The diamond"
			gem["value"] = 0
			gem["clue"] = "Razor-sharp facets and blue-white fire. This is the one."
		elif rng.randf() < 0.65:
			gem["kind"] = "collectible"
			gem["name"] = COLLECTIBLE_NAMES[rng.randi_range(0, COLLECTIBLE_NAMES.size() - 1)]
			gem["value"] = rng.randi_range(12, 24)
			gem["clue"] = "An excellent addition to the specimen shelf."
		else:
			gem["kind"] = "oddity"
			gem["name"] = ODDITY_NAMES[rng.randi_range(0, ODDITY_NAMES.size() - 1)]
			gem["value"] = rng.randi_range(6, 14)
			gem["clue"] = "A curious relic of the old miners."
		gems[id] = gem
	_rebuild_cells()
	var welcome: String = "A fresh mountain. One real diamond is buried deep in its core. Your pickaxe is ready."
	if _outdated_save:
		_outdated_save = false
		welcome = "The mountain has grown much bigger, so a fresh claim was staked. One real diamond is buried deep in its core."
	_commit(welcome)


## Fossils and curios lie at every depth, from just under the turf to the core.
func _random_find_cell(rng: RandomNumberGenerator, used: Dictionary) -> int:
	for _attempt: int in range(4000):
		var x: int = rng.randi_range(0, MountainScript.SIZE_X - 1)
		var z: int = rng.randi_range(0, MountainScript.SIZE_Z - 1)
		var top: int = mountain.height(x, z)
		if top < 4:
			continue
		var y: int = top - rng.randi_range(2, top - 1)
		var cell: int = MountainScript.index(x, y, z)
		if not used.has(cell):
			return cell
	return -1


func capacity() -> int:
	return 10 if "satchel" in upgrades else 4


func ore_capacity() -> int:
	return 90 if "satchel" in upgrades else 30


func ore_of(peer_id: int = -1) -> Dictionary:
	if peer_id < 0:
		peer_id = local_id()
	var ore: Variant = players.get(peer_id, {}).get("ore", {})
	return ore if ore is Dictionary else {}


func ore_total(peer_id: int = -1) -> int:
	var total: int = 0
	for kind in ore_of(peer_id):
		total += int(ore_of(peer_id)[kind])
	return total


func ore_value(peer_id: int = -1) -> int:
	var total: int = 0
	var ore: Dictionary = ore_of(peer_id)
	for kind in ore:
		total += int(MountainScript.ORE_VALUES.get(str(kind), 0)) * int(ore[kind])
	if "loupe" in upgrades:
		total = roundi(float(total) * LOUPE_BONUS)
	return total


func mining_tool() -> String:
	if "drill" in upgrades:
		return "drill"
	if "steel_pick" in upgrades:
		return "steel_pick"
	return "pickaxe"


func held_ids(peer_id: int = -1) -> Array:
	if peer_id < 0:
		peer_id = local_id()
	var result: Array = []
	for id in gems:
		var gem: Dictionary = gems[id]
		if str(gem.get("stage", "")) == "held" and int(gem.get("owner", 0)) == peer_id:
			result.append(int(id))
	result.sort()
	return result


func local_id() -> int:
	if _network_mode == "solo":
		return 1
	return multiplayer.get_unique_id()


func is_authority() -> bool:
	return _network_mode != "client"


func is_solid(cell: int) -> bool:
	return MountainScript.valid_cell(cell) and cell < cells.size() and cells[cell] != MountainScript.AIR


func solid_at(x: int, y: int, z: int) -> bool:
	if not MountainScript.in_grid(x, y, z):
		return false
	return cells.size() == MountainScript.CELL_COUNT and cells[MountainScript.index(x, y, z)] != MountainScript.AIR


func cell_code(cell: int) -> int:
	if not MountainScript.valid_cell(cell) or cell >= cells.size():
		return MountainScript.AIR
	return cells[cell]


func exposed(cell: int) -> bool:
	var c: Vector3i = MountainScript.coords(cell)
	for offset: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = c + offset
		if n.y < 0:
			continue
		if not solid_at(n.x, n.y, n.z):
			return true
	return false


func blocks_mined() -> int:
	var total: int = 0
	for byte in mined:
		var value: int = byte
		while value != 0:
			total += value & 1
			value >>= 1
	return total


func snapshot() -> Dictionary:
	return {"version": SAVE_VERSION, "seed": seed_value, "money": money, "gems": gems.duplicate(true), "upgrades": upgrades.duplicate(), "collection": collection.duplicate(), "diamond_id": diamond_id, "certified": certified, "searched": searched, "players": players.duplicate(true), "mined": Marshalls.raw_to_base64(mined)}


func save_game() -> bool:
	if not is_authority() or not _world_is_local or gems.is_empty():
		return false
	_save_dirty = false
	_last_save_ms = Time.get_ticks_msec()
	var temporary: String = _save_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		notice.emit("Save failed: the camp folder is not writable.")
		return false
	file.store_string(JSON.stringify(snapshot()))
	file.flush()
	var write_error: Error=file.get_error()
	file.close()
	if write_error!=OK:
		notice.emit("Save failed while writing. The previous save was kept.")
		return false
	var result: Error = DirAccess.rename_absolute(temporary, _save_path)
	if result != OK:
		# Windows refuses replacing an existing target on some filesystems.
		# Keep a recoverable backup throughout the replace operation.
		var backup: String = _save_path + ".bak"
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		if FileAccess.file_exists(_save_path):
			DirAccess.rename_absolute(_save_path, backup)
		result = DirAccess.rename_absolute(temporary, _save_path)
		if result == OK and FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		elif result != OK:
			notice.emit("Save could not be replaced. The previous save remains recoverable.")
	return result==OK


func load_game() -> bool:
	if not is_authority():
		return false
	var path: String = _save_path
	if not FileAccess.file_exists(path):
		path += ".bak"
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return false
	var data: Dictionary = parsed
	var version: int = int(data.get("version", -1))
	if version > 0 and version < SAVE_VERSION:
		# Claims staked on the old, smaller mountain cannot fit the new one. Keep a
		# copy of the old file and let the caller stake a fresh claim.
		DirAccess.copy_absolute(path, _save_path + ".v%d.old" % version)
		_outdated_save = true
		return false
	if version != SAVE_VERSION or not _valid_saved_world(data):
		return false
	_apply_snapshot(data)
	_world_is_local = true
	var saved_host: Dictionary = players.get(1, {})
	players.clear()
	players[1] = _player_template(1)
	players[1]["cosmetics"] = saved_host.get("cosmetics", []).duplicate()
	players[1]["hat"] = str(saved_host.get("hat", ""))
	var saved_ore: Variant = saved_host.get("ore", {})
	if saved_ore is Dictionary:
		for kind in saved_ore:
			if MountainScript.ORE_VALUES.has(str(kind)):
				players[1]["ore"][str(kind)] = maxi(0, int(saved_ore[kind]))
	for id in gems:
		var gem: Dictionary = gems[id]
		var stage: String = str(gem.get("stage", ""))
		if stage == "buried" and MountainScript.is_mined(mined, int(gem.get("cell", -1))):
			_to_tray(gem)
		elif stage == "held":
			_to_tray(gem)
		elif stage == "loose" and not _valid_position(_array_vector(gem.get("pos", []))):
			_to_tray(gem)
	_rebuild_cells()
	_commit("Camp loaded. Carried finds were returned to the inspection tray.")
	return true


func _valid_saved_world(data: Dictionary) -> bool:
	var saved_gems: Variant = data.get("gems", null)
	if not (saved_gems is Dictionary) or saved_gems.size() != GEM_COUNT:
		return false
	var saved_diamond: int = int(data.get("diamond_id", -1))
	if saved_diamond < 0 or saved_diamond >= GEM_COUNT:
		return false
	var saved_mined: Variant = data.get("mined", null)
	if not (saved_mined is String) or Marshalls.base64_to_raw(saved_mined).size() != MountainScript.empty_mined().size():
		return false
	var genuine_count: int = 0
	for id in range(GEM_COUNT):
		var gem_data: Variant = saved_gems.get(str(id), saved_gems.get(id, null))
		if not (gem_data is Dictionary) or int(gem_data.get("id", -1)) != id:
			return false
		if not str(gem_data.get("stage", "")) in ["buried", "held", "tray", "loose", "collection", "certified", "sold"]:
			return false
		if not typeof(gem_data.get("cell", null)) in [TYPE_INT, TYPE_FLOAT] or not MountainScript.valid_cell(int(gem_data.get("cell", -1))):
			return false
		var saved_pos: Variant = gem_data.get("pos", null)
		if not (saved_pos is Array) or saved_pos.size() != 3:
			return false
		for coordinate in saved_pos:
			if not typeof(coordinate) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)):
				return false
		if str(gem_data.get("kind", "")) == "diamond":
			genuine_count += 1
			if id != saved_diamond or str(gem_data.get("stage", "")) == "sold":
				return false
	return genuine_count == 1


func start_solo() -> void:
	leave()
	_network_mode = "solo"
	var saved_ore: Dictionary = ore_of(1).duplicate()
	players = {1: _player_template(1)}
	players[1]["ore"] = saved_ore
	_recover_strays()
	connection_status.emit("Solo camp")
	changed.emit()


func host(port: int = 24680) -> Error:
	if port < 1024 or port > 65535:
		return ERR_INVALID_PARAMETER
	leave()
	_connect_network_signals()
	if not _world_is_local:
		if not load_game():
			new_game()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var result: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		connection_status.emit("Could not host: port %d is busy or unavailable." % port)
		return result
	# ENet compresses MTU-sized fragments; both ends must use the same codec.
	# This substantially reduces repeated item dictionaries over reliable UDP.
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_network_mode = "host"
	var saved_ore: Dictionary = ore_of(1).duplicate()
	players = {1: _player_template(1)}
	players[1]["ore"] = saved_ore
	_recover_strays()
	connection_status.emit("Hosting up to 4 players on port %d" % port)
	_commit("Co-op claim opened. Everyone shares purchases, money and the mountain.")
	return OK


func join(address: String, port: int = 24680) -> Error:
	address = address.strip_edges()
	if address.is_empty() or port < 1024 or port > 65535:
		return ERR_INVALID_PARAMETER
	leave()
	_connect_network_signals()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var result: Error = peer.create_client(address, port)
	if result != OK:
		connection_status.emit("Could not create the connection.")
		return result
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	_network_mode = "client"
	_connecting = true
	_world_is_local = false
	multiplayer.multiplayer_peer = peer
	connection_status.emit("Connecting to %s:%d…" % [address, port])
	return OK


func leave() -> void:
	if is_authority() and not gems.is_empty():
		save_game()
	var old_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if old_peer != null:
		old_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_network_mode = "solo"
	_connecting = false
	_action_times.clear()
	_fuses.clear()
	_throw_ready.clear()
	_damage.clear()
	_reset_voice_transport()


func action(kind: String, args: Dictionary = {}) -> void:
	if not _valid_action_args(args):
		return
	if is_authority():
		_execute_action(local_id(), kind, args)
	elif not _connecting and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_action.rpc_id(1, kind, args)
	else:
		notice.emit("Waiting for the host connection.")


@rpc("any_peer", "call_remote", "reliable")
func _request_action(kind: String, args: Dictionary) -> void:
	if not is_authority():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	# Bound commands before interpreting them, and reject floods without spending money.
	if kind.length() > 32 or not _valid_action_args(args):
		return
	var now: int = Time.get_ticks_msec()
	var key: String = "%d:%s" % [sender, kind]
	if now - int(_action_times.get(key, -1000)) < 60:
		return
	_action_times[key] = now
	_execute_action(sender, kind, args)


func _valid_action_args(args: Dictionary) -> bool:
	if args.size() > 12:
		return false
	for key in args:
		if not (key is String) or key.length() > 24:
			return false
		var value: Variant = args[key]
		var value_type: int = typeof(value)
		if value_type == TYPE_STRING:
			if value.length() > 128:
				return false
		elif value_type == TYPE_ARRAY:
			if value.size() != 3:
				return false
			for coordinate in value:
				if not typeof(coordinate) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)):
					return false
		elif value_type == TYPE_FLOAT:
			if not is_finite(value):
				return false
		elif not value_type in [TYPE_INT, TYPE_BOOL]:
			return false
		if str(key) in ["id", "target", "cell", "fuse", "test"] and not value_type in [TYPE_INT, TYPE_FLOAT]:
			return false
	return true


func _execute_action(peer_id: int, kind: String, args: Dictionary) -> void:
	if not players.has(peer_id):
		return
	match kind:
		"mine":
			_mine(peer_id, int(args.get("cell", -1)))
		"throw":
			_throw(peer_id, str(args.get("tier", "")), args.get("pos", []), args.get("vel", []))
		"blast":
			_blast(peer_id, int(args.get("fuse", -1)), args.get("pos", []))
		"vacuum":
			_vacuum(peer_id)
		"pick":
			_pick(peer_id, int(args.get("id", -1)))
		"drop":
			_drop(peer_id, int(args.get("id", -1)), args.get("pos", []))
		"tray":
			if not _near_station(peer_id, "tray"):
				_reject(peer_id, "Bring your finds to the inspection tray.")
				return
			var held: Array = held_ids(peer_id)
			for id in held:
				_to_tray(gems[id])
			_commit("Placed %d %s in the inspection tray." % [held.size(), "find" if held.size() == 1 else "finds"])
		"sell":
			_sell(peer_id)
		"buy":
			_buy(peer_id, str(args.get("upgrade", "")))
		"collect":
			_collect(peer_id, int(args.get("id", -1)))
		"certify":
			_certify(peer_id, int(args.get("id", -1)))
		"recover":
			if not _near_station(peer_id, "recover", 4.5):
				_reject(peer_id, "Use the lost & found bell by the camp entrance.")
				return
			var recovered: int = _recover_strays(true)
			_commit("Recovered %d loose or stranded finds into the inspection tray." % recovered)
		"prank":
			_prank(peer_id, int(args.get("target", -1)), str(args.get("mode", "foam")), int(args.get("id", -1)))
		_:
			_reject(peer_id, "That action is unavailable.")


func _mine(peer_id: int, cell: int) -> void:
	if not is_solid(cell):
		return
	var code: int = cells[cell]
	if code == MountainScript.BEDROCK:
		_reject(peer_id, "Bedrock. Nothing gets through this.")
		return
	if _peer_position(peer_id).distance_to(MountainScript.cell_center(cell)) > MINING_REACH:
		_reject(peer_id, "Move closer to that rock.")
		return
	if not exposed(cell):
		return
	var c: Vector3i = MountainScript.coords(cell)
	var tool: String = mining_tool()
	if tool == "pickaxe" and mountain.needs_steel(c.x, c.y, c.z):
		_reject(peer_id, "Granite is too hard for the old pickaxe. Buy a steel pickaxe or blast it.")
		return
	var ore: String = MountainScript.ore_for_code(code)
	if not ore.is_empty() and ore_total(peer_id) >= ore_capacity():
		_reject(peer_id, "Your satchel is full. Sell your ore at the exchange.")
		return
	var damage: int = int(_damage.get(cell, 0)) + (1 if tool == "pickaxe" else 2)
	if damage < mountain.hardness(c.x, c.y, c.z, code):
		_damage[cell] = damage
		return
	var result: Dictionary = _break_cells(peer_id, [cell])
	var message: String = ""
	if not result.released.is_empty():
		message = "Something broke loose from the rock: %s!" % str(gems[int(result.released[0])].name).to_lower()
	_commit_mining(peer_id, result, message)


func _break_cells(peer_id: int, list: Array) -> Dictionary:
	var broken := PackedInt32Array()
	var gained: Dictionary = {}
	var lost: int = 0
	var released: Array = []
	var room: int = ore_capacity() - ore_total(peer_id)
	for value in list:
		var cell: int = int(value)
		if not is_solid(cell):
			continue
		var code: int = cells[cell]
		if code == MountainScript.BEDROCK:
			continue
		cells[cell] = MountainScript.AIR
		MountainScript.set_mined(mined, cell)
		_damage.erase(cell)
		broken.append(cell)
		var ore: String = MountainScript.ore_for_code(code)
		if not ore.is_empty():
			if room > 0:
				gained[ore] = int(gained.get(ore, 0)) + 1
				room -= 1
			else:
				lost += 1
		elif _buried_by_cell.has(cell):
			var id: int = int(_buried_by_cell[cell])
			_buried_by_cell.erase(cell)
			var gem: Dictionary = gems[id]
			var jitter := Vector3(float((id * 37) % 7 - 3) * 0.08, 0.0, float((id * 53) % 7 - 3) * 0.08)
			gem["stage"] = "loose"
			gem["owner"] = 0
			gem["pos"] = _vector_array(settle(MountainScript.cell_center(cell) + jitter))
			released.append(id)
	if not gained.is_empty() and players.has(peer_id):
		var satchel: Dictionary = ore_of(peer_id).duplicate()
		for kind in gained:
			satchel[kind] = int(satchel.get(kind, 0)) + int(gained[kind])
		players[peer_id]["ore"] = satchel
	var moved: Array = released.duplicate()
	if not broken.is_empty():
		for id in gems:
			var gem: Dictionary = gems[id]
			if str(gem.stage) != "loose" or id in released:
				continue
			var pos: Vector3 = _array_vector(gem.pos)
			var rest: Vector3 = settle(pos)
			if rest.distance_to(pos) > 0.05:
				gem["pos"] = _vector_array(rest)
				moved.append(int(id))
	return {"cells": broken, "gained": gained, "lost": lost, "released": released, "moved": moved}


## Finds rest on the highest solid block below them, or on the ground.
func settle(pos: Vector3) -> Vector3:
	var g: Vector3i = MountainScript.world_to_grid(pos)
	if g.x < 0 or g.z < 0 or g.x >= MountainScript.SIZE_X or g.z >= MountainScript.SIZE_Z:
		return Vector3(pos.x, 0.16 if absf(pos.x) < 13.0 and absf(pos.z) < 11.5 else 0.14, pos.z)
	var y: int = clampi(g.y, 0, MountainScript.SIZE_Y - 1)
	while y < MountainScript.SIZE_Y and solid_at(g.x, y, g.z):
		y += 1
	while y > 0 and not solid_at(g.x, y - 1, g.z):
		y -= 1
	return Vector3(pos.x, MountainScript.ORIGIN.y + float(y) + 0.16, pos.z)


func _commit_mining(peer_id: int, result: Dictionary, message: String = "") -> void:
	var changed_gems: Dictionary = {}
	for id in result.moved:
		changed_gems[int(id)] = gems[int(id)].duplicate(true)
	_send_delta(result.cells, changed_gems, [peer_id])
	if not message.is_empty():
		_tell(peer_id, message)


## Lightweight authoritative update for frequent changes: mined blocks, a few
## items and satchels. Saves are batched; full snapshots remain for everything else.
func _send_delta(broken: PackedInt32Array, changed_gems: Dictionary, ore_peers: Array) -> void:
	var ore: Dictionary = {}
	for peer in ore_peers:
		if players.has(int(peer)):
			ore[int(peer)] = ore_of(int(peer)).duplicate()
	changed.emit()
	if not broken.is_empty():
		cells_changed.emit(broken)
	if _network_mode == "host":
		_receive_delta.rpc({"cells": broken, "gems": changed_gems, "ore": ore, "money": money, "searched": searched})
	_save_dirty = true


@rpc("authority", "call_remote", "reliable")
func _receive_delta(data: Dictionary) -> void:
	if is_authority():
		return
	var broken: PackedInt32Array = data.get("cells", PackedInt32Array())
	for cell in broken:
		if MountainScript.valid_cell(cell):
			MountainScript.set_mined(mined, cell)
			if cell < cells.size():
				cells[cell] = MountainScript.AIR
			_buried_by_cell.erase(cell)
	var incoming: Dictionary = data.get("gems", {})
	for id in incoming:
		if incoming[id] is Dictionary:
			gems[int(id)] = incoming[id].duplicate(true)
	var ore: Dictionary = data.get("ore", {})
	for peer in ore:
		if players.has(int(peer)) and ore[peer] is Dictionary:
			players[int(peer)]["ore"] = ore[peer].duplicate()
	money = maxi(0, int(data.get("money", money)))
	searched = clampi(int(data.get("searched", searched)), 0, GEM_COUNT)
	changed.emit()
	if not broken.is_empty():
		cells_changed.emit(broken)


func _throw(peer_id: int, tier: String, origin: Variant, velocity: Variant) -> void:
	if not EXPLOSIVES.has(tier):
		return
	if not tier in upgrades:
		_reject(peer_id, "Buy %s at the outfitter first." % str(upgrade_names[tier]))
		return
	var start: Vector3 = _array_vector(origin)
	var speed: Vector3 = _array_vector(velocity)
	if not _valid_position(start) or start.distance_to(_peer_position(peer_id)) > 3.5 or speed.length() > 30.0:
		return
	var now: int = Time.get_ticks_msec()
	var key: String = "%d:%s" % [peer_id, tier]
	var ready_at: int = int(_throw_ready.get(key, 0))
	if now < ready_at and not test_mode:
		_reject(peer_id, "%s is being prepared · %.1f s" % [str(upgrade_names[tier]), float(ready_at - now) / 1000.0])
		return
	_throw_ready[key] = now + int(float(EXPLOSIVES[tier].cooldown) * 1000.0)
	var fuse: int = _next_fuse
	_next_fuse += 1
	_fuses[fuse] = {"peer": peer_id, "tier": tier, "pos": start}
	throw_spawned.emit(peer_id, tier, start, speed, fuse)
	if _network_mode == "host":
		_receive_throw.rpc(peer_id, tier, start, speed, fuse)


@rpc("authority", "call_remote", "reliable")
func _receive_throw(peer_id: int, tier: String, start: Vector3, speed: Vector3, fuse: int) -> void:
	if is_authority() or not EXPLOSIVES.has(tier):
		return
	throw_spawned.emit(peer_id, tier, start, speed, fuse)


func _blast(peer_id: int, fuse: int, location: Variant) -> void:
	if not _fuses.has(fuse) or int(_fuses[fuse].peer) != peer_id:
		return
	var info: Dictionary = _fuses[fuse]
	_fuses.erase(fuse)
	var tier: String = str(info.tier)
	var center: Vector3 = _array_vector(location)
	if not (location is Array) or not _valid_position(center) or center.distance_to(_as_vector(info.pos)) > 45.0:
		center = _as_vector(info.pos)
	var radius: float = float(EXPLOSIVES[tier].radius)
	var reach: int = ceili(radius)
	var g: Vector3i = MountainScript.world_to_grid(center)
	var targets: Array = []
	for dy: int in range(-reach, reach + 1):
		for dz: int in range(-reach, reach + 1):
			for dx: int in range(-reach, reach + 1):
				var x: int = g.x + dx
				var y: int = g.y + dy
				var z: int = g.z + dz
				if not MountainScript.in_grid(x, y, z):
					continue
				var cell: int = MountainScript.index(x, y, z)
				if cells[cell] != MountainScript.AIR and MountainScript.cell_center(cell).distance_to(center) <= radius:
					targets.append(cell)
	var result: Dictionary = _break_cells(peer_id, targets)
	blasted.emit(fuse, center, tier)
	if _network_mode == "host":
		_receive_blast.rpc(fuse, center, tier)
	var ore_count: int = 0
	for kind in result.gained:
		ore_count += int(result.gained[kind])
	var message: String = "%s blasted out %d m³ of rock · +%d ore" % [str(upgrade_names[tier]), result.cells.size(), ore_count]
	if not result.released.is_empty():
		message += " · %d %s broke loose" % [result.released.size(), "find" if result.released.size() == 1 else "finds"]
	if int(result.lost) > 0:
		message += " · %d ore lost (satchel full)" % int(result.lost)
	_commit_mining(peer_id, result, message)


@rpc("authority", "call_remote", "reliable")
func _receive_blast(fuse: int, center: Vector3, tier: String) -> void:
	if is_authority() or not EXPLOSIVES.has(tier):
		return
	blasted.emit(fuse, center, tier)


func _vacuum(peer_id: int) -> void:
	if not "magnet" in upgrades:
		return
	var room: int = capacity() - held_ids(peer_id).size()
	var taken: Array = []
	for id in gems:
		if taken.size() >= room:
			break
		var loose: Dictionary = gems[id]
		if str(loose["stage"]) == "loose" and _peer_position(peer_id).distance_to(_array_vector(loose["pos"])) < 7.5:
			_hold(loose, peer_id)
			taken.append(int(id))
	if taken.is_empty():
		return
	_commit_items(peer_id, taken, "Ore magnet pulled in %d %s." % [taken.size(), "find" if taken.size() == 1 else "finds"])


func _commit_items(peer_id: int, ids: Array, message: String) -> void:
	var changed_gems: Dictionary = {}
	for id in ids:
		changed_gems[int(id)] = gems[int(id)].duplicate(true)
	_send_delta(PackedInt32Array(), changed_gems, [])
	_tell(peer_id, message)


func _pick(peer_id: int, id: int) -> void:
	if not gems.has(id):
		return
	var gem: Dictionary = gems[id]
	var stage: String = str(gem["stage"])
	if not stage in ["tray", "loose"]:
		_reject(peer_id, "That find is already being carried or stored.")
		return
	if held_ids(peer_id).size() >= capacity():
		_reject(peer_id, "Your hands are full. Store finds in the inspection tray.")
		return
	if _peer_position(peer_id).distance_to(_array_vector(gem["pos"])) > 4.2:
		_reject(peer_id, "Move closer to pick that up.")
		return
	_hold(gem, peer_id)
	_commit_items(peer_id, [id], "Picked up %s." % str(gem["name"]).to_lower())


func _drop(peer_id: int, id: int, location: Variant) -> void:
	if not _owns(peer_id, id) or not (location is Array) or location.size() != 3:
		return
	var target: Vector3 = _array_vector(location)
	if not _valid_position(target) or _peer_position(peer_id).distance_to(target) > 4.5:
		_reject(peer_id, "Drop finds within reach.")
		return
	var gem: Dictionary = gems[id]
	gem["stage"] = "loose"
	gem["owner"] = 0
	gem["pos"] = _vector_array(settle(target))
	_commit_items(peer_id, [id], "Find dropped. The lost & found bell can always bring it back.")


func _sell(peer_id: int) -> void:
	if not _near_station(peer_id, "sell"):
		_reject(peer_id, "Bring your satchel to the scrap exchange.")
		return
	var ore_count: int = ore_total(peer_id)
	var payout: int = ore_value(peer_id)
	if players.has(peer_id):
		players[peer_id]["ore"] = {}
	var protected: int = 0
	var sold: int = 0
	for id in held_ids(peer_id):
		var gem: Dictionary = gems[id]
		if _protected(gem):
			_to_tray(gem)
			protected += 1
		else:
			payout += _sale_value(gem)
			gem["stage"] = "sold"
			gem["owner"] = 0
			sold += 1
	money += payout
	var parts: Array[String] = []
	if ore_count > 0:
		parts.append("%d ore" % ore_count)
	if sold > 0:
		parts.append("%d finds" % sold)
	if parts.is_empty():
		_commit("Nothing to sell. Mine some ore first.%s" % (" The diamond went safely to the tray." if protected > 0 else ""))
		return
	_commit("Sold %s for $%d.%s" % [" and ".join(parts), payout, " The diamond went safely to the tray." if protected > 0 else ""])


func _buy(peer_id: int, upgrade: String) -> void:
	if not prices.has(upgrade) or upgrade in upgrades:
		_reject(peer_id, "That equipment is unavailable or already owned.")
		return
	var nearby: bool = _peer_position(peer_id).distance_to(_as_vector(upgrade_positions[upgrade])) <= 4.0 if upgrade_positions.has(upgrade) else _near_station(peer_id, "shop", 6.0)
	if not nearby:
		_reject(peer_id, "Move closer to the equipment you want to buy.")
		return
	var price: int = int(prices[upgrade])
	if money < price:
		_reject(peer_id, "Need $%d more for the %s." % [price - money, str(upgrade_names[upgrade]).to_lower()])
		return
	money -= price
	upgrades.append(upgrade)
	_commit("%s bought. %s" % [upgrade_names[upgrade], str(benefits[upgrade])])


func _collect(peer_id: int, id: int) -> void:
	if not gems.has(id):
		return
	var gem: Dictionary = gems[id]
	if not _owns(peer_id, id) and not (str(gem["stage"]) == "tray" and _peer_position(peer_id).distance_to(_array_vector(gem["pos"])) < 4.2):
		return
	if not str(gem["kind"]) in ["collectible", "oddity"]:
		_reject(peer_id, "The specimen shelf is for fossils and curiosities.")
		return
	var label: String = str(gem["name"])
	var fresh: bool = not label in collection
	gem["stage"] = "collection"
	gem["owner"] = 0
	if fresh:
		collection.append(label)
		money += 12
		var cosmetics: Array = players[peer_id].get("cosmetics", [])
		var reward: String = "Gem crown" if collection.size() >= 4 else "Bucket hat"
		if not reward in cosmetics:
			cosmetics.append(reward)
		players[peer_id]["cosmetics"] = cosmetics
	_commit("Shelf discovery: %s! %s" % [label, "$12 museum grant + a silly hat unlocked." if fresh else "A spare for your magnificent collection."])


func _certify(peer_id: int, id: int) -> void:
	if certified:
		_reject(peer_id, "The diamond is already certified. Keep blasting for treasure!")
		return
	if not _near_station(peer_id, "certify") or not _owns(peer_id, id):
		_reject(peer_id, "Bring the diamond to the certification bench.")
		return
	if id != diamond_id or str(gems[id]["kind"]) != "diamond":
		_reject(peer_id, "Only the diamond goes on the bench. Fossils belong on the specimen shelf.")
		return
	certified = true
	gems[id]["stage"] = "certified"
	gems[id]["owner"] = 0
	gems[id]["pos"] = _vector_array(_station_position("certify") + Vector3(0, 0.3, 0))
	money += 1000
	if not "THE GENUINE DIAMOND" in collection:
		collection.append("THE GENUINE DIAMOND")
	_commit("THE GENUINE DIAMOND! Certified at the bench. $1,000 discovery grant. You found brilliance in the rough!")


func _prank(peer_id: int, target: int, mode: String, item_id: int = -1) -> void:
	if target == peer_id and mode == "hat":
		var hats: Array = ["", "Bucket hat"]
		if "Gem crown" in players[peer_id].get("cosmetics", []):
			hats.append("Gem crown")
		var current: int = hats.find(str(players[peer_id].get("hat", "")))
		players[peer_id]["hat"] = hats[(current + 1) % hats.size()]
		_commit("Headwear: %s." % (str(players[peer_id]["hat"]) if not str(players[peer_id]["hat"]).is_empty() else "respectable hard hat"))
		return
	if target == peer_id or not players.has(target) or _peer_position(peer_id).distance_to(_peer_position(target)) > 6.0:
		_reject(peer_id, "Get within reach of a co-op friend.")
		return
	if not mode in ["foam", "scoop", "present", "bucket"]:
		return
	var now: float = Time.get_unix_time_from_system()
	if now - float(players[peer_id].get("last_prank", 0.0)) < 2.0:
		return
	players[peer_id]["last_prank"] = now
	players[target]["prank"] = mode
	players[target]["prank_until"] = now + 2.2
	if mode == "foam":
		players[target]["foam_until"] = now + 5.0
	elif mode == "bucket":
		players[target]["hat"] = "Bucket hat"
	elif mode == "present":
		var gifts: Array = held_ids(peer_id)
		if not gifts.is_empty():
			var gift: int = int(item_id) if int(item_id) in gifts else int(gifts[0])
			if held_ids(target).size() < capacity():
				_hold(gems[gift], target)
			else:
				_to_tray(gems[gift])
	elif mode == "scoop":
		for id in held_ids(peer_id):
			gems[id]["stage"] = "loose"
			gems[id]["owner"] = 0
			gems[id]["pos"] = _vector_array(settle(_peer_position(target) + Vector3(0, 0.5, 0)))
	_commit("Player %d deployed %s-grade nonsense on player %d. Quick recovery guaranteed." % [peer_id, mode, target])


func _hold(gem: Dictionary, peer_id: int) -> void:
	_mark_searched(gem)
	gem["stage"] = "held"
	gem["owner"] = peer_id
	gem["pos"] = _vector_array(_peer_position(peer_id))


func _mark_searched(gem: Dictionary) -> void:
	if not bool(gem.get("searched", false)):
		gem["searched"] = true
		searched += 1


func _to_tray(gem: Dictionary) -> void:
	_mark_searched(gem)
	gem["stage"] = "tray"
	gem["owner"] = 0
	var id: int = int(gem["id"])
	var slot: int = id % 48
	var center: Vector3 = _station_position("tray")
	gem["pos"] = _vector_array(center + Vector3(float(slot % 8 - 4) * 0.2 + 0.1, 0.24 + float(id / 48) * 0.022, float(slot / 8 - 3) * 0.2 + 0.1))


func _recover_strays(all_loose: bool = false) -> int:
	var recovered: int = 0
	for id in gems:
		var gem: Dictionary = gems[id]
		var stage: String = str(gem["stage"])
		var pos: Vector3 = _array_vector(gem["pos"])
		var outside: bool = not _valid_position(pos) or absf(pos.x) > absf(MountainScript.ORIGIN.x) + 1.0 or pos.z > 11.5 or pos.z < MountainScript.ORIGIN.z - 1.0 or pos.y < -0.5
		if (stage == "held" and not players.has(int(gem["owner"]))) or (stage == "loose" and (all_loose or outside)):
			_to_tray(gem)
			recovered += 1
	return recovered


func _rebuild_cells() -> void:
	if mined.size() != MountainScript.empty_mined().size():
		mined = MountainScript.empty_mined()
	_buried_by_cell.clear()
	var specials: Dictionary = {}
	for id in gems:
		var gem: Dictionary = gems[id]
		if str(gem.get("stage", "")) == "buried":
			var cell: int = int(gem.get("cell", -1))
			_buried_by_cell[cell] = int(id)
			specials[cell] = MountainScript.CRYSTAL if str(gem.kind) == "diamond" else MountainScript.CURIO
	cells = mountain.build_cells(seed_value, mined, specials)
	_cell_seed = seed_value
	_damage.clear()
	world_reset.emit()


## The diamond can never be sold.
func _protected(gem: Dictionary) -> bool:
	return str(gem.get("kind", "")) == "diamond" or int(gem.get("id", -1)) == diamond_id


func _sale_value(gem: Dictionary) -> int:
	return maxi(0, int(gem.get("value", 0)))


func _owns(peer_id: int, id: int) -> bool:
	return gems.has(id) and str(gems[id]["stage"]) == "held" and int(gems[id]["owner"]) == peer_id


func _near_station(peer_id: int, station: String, reach: float = 4.0) -> bool:
	if not station_positions.has(station):
		return false
	return _peer_position(peer_id).distance_to(_station_position(station)) <= reach


func _station_position(station: String) -> Vector3:
	return _as_vector(station_positions.get(station, Vector3.ZERO))


func _peer_position(peer_id: int) -> Vector3:
	return _array_vector(players.get(peer_id, {}).get("pos", [0, 1.6, 7]))


func _vector_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _array_vector(value: Variant) -> Vector3:
	if not (value is Array) or value.size() != 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _as_vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	return _array_vector(value)


func _valid_position(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) and absf(value.x) < 500.0 and absf(value.z) < 500.0 and value.y > -50.0 and value.y < 100.0


func _player_template(id: int) -> Dictionary:
	return {"id": id, "pos": [0.0, 1.6, 7.0], "yaw": 0.0, "pitch": 0.0, "hat": "", "cosmetics": [], "prank": "", "prank_until": 0.0, "foam_until": 0.0, "last_prank": 0.0, "ore": {}}


func _commit(message: String = "") -> void:
	changed.emit()
	if not message.is_empty():
		notice.emit(message)
	if _network_mode == "host":
		_receive_snapshot.rpc(snapshot())
		if not message.is_empty():
			_receive_notice.rpc(message)
	save_game()


func _tell(peer_id: int, message: String) -> void:
	if message.is_empty():
		return
	if peer_id == local_id():
		notice.emit(message)
	elif _network_mode == "host":
		_receive_notice.rpc_id(peer_id, message)


func _reject(peer_id: int, message: String) -> void:
	_tell(peer_id, message)


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(data: Dictionary) -> void:
	if is_authority():
		return
	if int(data.get("version", -1)) != SAVE_VERSION:
		# A host on another build has a differently shaped mountain; never mix them.
		leave()
		connection_status.emit("The host is on a different version of the game. Both players need the latest update.")
		notice.emit("The host is on a different version of the game. Both players need the latest update.")
		return
	_apply_snapshot(data)
	changed.emit()


func _apply_snapshot(data: Dictionary) -> void:
	var previous_seed: int = _cell_seed
	var previous_mined: PackedByteArray = mined
	seed_value = int(data.get("seed", 0))
	money = maxi(0, int(data.get("money", 0)))
	gems.clear()
	var incoming_gems: Dictionary = data.get("gems", {})
	for id in incoming_gems:
		gems[int(id)] = incoming_gems[id].duplicate(true)
	upgrades.clear()
	for upgrade in data.get("upgrades", []):
		if prices.has(str(upgrade)) and not str(upgrade) in upgrades:
			upgrades.append(str(upgrade))
	collection.clear()
	for item in data.get("collection", []):
		collection.append(str(item))
	diamond_id = int(data.get("diamond_id", -1))
	certified = bool(data.get("certified", false))
	searched = clampi(int(data.get("searched", 0)), 0, GEM_COUNT)
	players.clear()
	var incoming_players: Dictionary = data.get("players", {})
	for id in incoming_players:
		players[int(id)] = incoming_players[id].duplicate(true)
	var incoming_mined: PackedByteArray = Marshalls.base64_to_raw(str(data.get("mined", "")))
	if incoming_mined.size() != MountainScript.empty_mined().size():
		incoming_mined = MountainScript.empty_mined()
	mined = incoming_mined
	# Snapshots arrive after every shared transaction; only rebuild what changed.
	if previous_seed == seed_value and mined == previous_mined and cells.size() == MountainScript.CELL_COUNT:
		_buried_by_cell.clear()
		for id in gems:
			if str(gems[id].get("stage", "")) == "buried":
				_buried_by_cell[int(gems[id].get("cell", -1))] = int(id)
		return
	if previous_seed != seed_value or cells.size() != MountainScript.CELL_COUNT or previous_mined.size() != mined.size():
		_rebuild_cells()
		return
	var broken := PackedInt32Array()
	for byte in range(mined.size()):
		if mined[byte] == previous_mined[byte]:
			continue
		if (previous_mined[byte] & ~mined[byte]) != 0:
			_rebuild_cells()
			return
		var fresh: int = mined[byte] & ~previous_mined[byte]
		for bit in range(8):
			if fresh & (1 << bit):
				var cell: int = byte * 8 + bit
				if cell < cells.size():
					cells[cell] = MountainScript.AIR
					broken.append(cell)
	_buried_by_cell.clear()
	for id in gems:
		if str(gems[id].get("stage", "")) == "buried":
			_buried_by_cell[int(gems[id].get("cell", -1))] = int(id)
	if not broken.is_empty():
		cells_changed.emit(broken)


@rpc("authority", "call_remote", "reliable")
func _receive_notice(message: String) -> void:
	notice.emit(message)


func send_pose(position: Vector3, yaw: float, pitch: float) -> void:
	if not _valid_position(position) or not is_finite(yaw) or not is_finite(pitch):
		return
	if is_authority():
		_accept_pose(local_id(), position, yaw, pitch)
	elif not _connecting and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		set_player(local_id(), position, yaw, pitch)
		_submit_pose.rpc_id(1, position, yaw, pitch)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_pose(position: Vector3, yaw: float, pitch: float) -> void:
	if not is_authority():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not players.has(sender) or not _valid_position(position) or not is_finite(yaw) or not is_finite(pitch):
		return
	_accept_pose(sender, position, yaw, pitch)


func _accept_pose(id: int, position: Vector3, yaw: float, pitch: float) -> void:
	set_player(id, position, yaw, pitch)
	pose_received.emit(id, position, yaw, pitch)
	if _network_mode == "host":
		_publish_pose.rpc(id, position, yaw, pitch)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _publish_pose(id: int, position: Vector3, yaw: float, pitch: float) -> void:
	if is_authority() or not _valid_position(position):
		return
	if id != local_id():
		set_player(id, position, yaw, pitch)
		pose_received.emit(id, position, yaw, pitch)


func send_voice(sequence: int, payload: PackedByteArray) -> void:
	if not _valid_voice_frame(sequence, payload) or _network_mode == "solo" or _connecting:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not players.has(local_id()):
		return
	if _network_mode == "host":
		if _accept_voice(local_id(), sequence, payload):
			voice_sent_packets += 1
	elif _network_mode == "client":
		_submit_voice.rpc_id(1, sequence, payload)
		voice_sent_packets += 1


# Voice uses its own unreliable channel; neither item transactions nor pose packets
# wait for audio. Lost or reordered frames are handled by the playback jitter buffer.
@rpc("any_peer", "call_remote", "unreliable", 2)
func _submit_voice(sequence: int, payload: PackedByteArray) -> void:
	if _network_mode != "host":
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 1 or not players.has(sender):
		return
	_accept_voice(sender, sequence, payload)


func _valid_voice_frame(sequence: int, payload: PackedByteArray) -> bool:
	return sequence >= 0 and sequence <= VOICE_MAX_SEQUENCE and payload.size() == VOICE_FRAME_BYTES


func _accept_voice(sender: int, sequence: int, payload: PackedByteArray) -> bool:
	if _network_mode != "host" or not players.has(sender) or not _valid_voice_frame(sequence, payload):
		return false
	var now: int = Time.get_ticks_msec()
	var limit: Dictionary = _voice_sender_limits.get(sender, {"tokens": VOICE_BURST_PACKETS, "time": now, "sequence": -1})
	if sequence <= int(limit["sequence"]):
		return false
	var elapsed: float = maxf(0.0, float(now - int(limit["time"])) / 1000.0)
	var tokens: float = minf(VOICE_BURST_PACKETS, float(limit["tokens"]) + elapsed * VOICE_PACKETS_PER_SECOND)
	limit["tokens"] = tokens
	limit["time"] = now
	_voice_sender_limits[sender] = limit
	if tokens < 1.0:
		return false
	limit["tokens"] = tokens - 1.0
	limit["sequence"] = sequence
	_voice_sender_limits[sender] = limit
	# Range comes only from poses associated with authenticated peer IDs. Callers
	# cannot supply a listener, a forged source ID, or their own voice position.
	var source_position: Vector3 = _peer_position(sender)
	for listener_id in players:
		var listener: int = int(listener_id)
		if listener == sender or source_position.distance_squared_to(_peer_position(listener)) > VOICE_RANGE_METRES * VOICE_RANGE_METRES:
			continue
		if listener == local_id():
			_deliver_voice(sender, sequence, payload)
		else:
			_receive_voice.rpc_id(listener, sender, sequence, payload)
			voice_relayed_packets += 1
	return true


@rpc("authority", "call_remote", "unreliable", 2)
func _receive_voice(sender: int, sequence: int, payload: PackedByteArray) -> void:
	if _network_mode != "client" or multiplayer.get_remote_sender_id() != 1:
		return
	if sender == local_id() or not players.has(sender) or not _valid_voice_frame(sequence, payload):
		return
	_deliver_voice(sender, sequence, payload)


func _deliver_voice(sender: int, sequence: int, payload: PackedByteArray) -> void:
	if sequence <= int(_voice_received_sequences.get(sender, -1)):
		return
	_voice_received_sequences[sender] = sequence
	voice_received_packets += 1
	voice_received.emit(sender, sequence, payload)


func _reset_voice_transport() -> void:
	_voice_sender_limits.clear()
	_voice_received_sequences.clear()
	voice_sent_packets = 0
	voice_relayed_packets = 0
	voice_received_packets = 0


func _on_peer_connected(id: int) -> void:
	if not is_authority():
		return
	if players.size() >= MAX_PLAYERS:
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = _player_template(id)
	_steady_voice(id)
	peer_joined.emit(id)
	_commit("Player %d joined the claim." % id)


## ENet thins out unreliable packets when a peer acknowledges slowly; a brief hitch
## (for example while the mountain loads) would silence voice for seconds. Voice is
## tiny, so keep its throttle fully open.
func _steady_voice(peer_id: int) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var link: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(peer_id)
		if link != null:
			link.throttle_configure(5000, 32, 0)


func _on_peer_disconnected(id: int) -> void:
	_voice_sender_limits.erase(id)
	_voice_received_sequences.erase(id)
	if not is_authority():
		players.erase(id)
		peer_left.emit(id)
		return
	# A departing miner's satchel is sold into the shared funds rather than lost.
	var payout: int = ore_value(id)
	money += payout
	players.erase(id)
	for fuse in _fuses.keys():
		if int(_fuses[fuse].peer) == id:
			_fuses.erase(fuse)
	var rescued: int = _recover_strays()
	peer_left.emit(id)
	_commit("Player %d left. %d carried finds returned safely to the tray; their ore sold for $%d." % [id, rescued, payout])


func _on_connected_to_server() -> void:
	_connecting = false
	_steady_voice(1)
	connection_status.emit("Connected to shared claim · player %d" % local_id())
	_request_snapshot.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if not is_authority():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if players.has(sender):
		_receive_snapshot.rpc_id(sender, snapshot())


func _on_connection_failed() -> void:
	_reset_voice_transport()
	_connecting = false
	_network_mode = "solo"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_status.emit("Connection failed. Check host address, port, and Windows Firewall.")


func _on_server_disconnected() -> void:
	_reset_voice_transport()
	_connecting = false
	# Do not save the departed host's world into this client's own save slot.
	_network_mode = "solo"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {1: _player_template(1)}
	_recover_strays()
	connection_status.emit("Host disconnected. Return to the menu to load your solo camp.")
	changed.emit()
