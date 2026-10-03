extends Node
class_name RoughState

## The server owns every item transition and purchase. Clients submit intentions.
## IDs and the seeded diamond are preserved even after an item has been sold.
signal changed
signal notice(text: String)
signal peer_joined(id: int)
signal peer_left(id: int)
signal pose_received(id: int, position: Vector3, yaw: float, pitch: float)
signal voice_received(peer_id: int, sequence: int, payload: PackedByteArray)
signal connection_status(text: String)

const SAVE_VERSION: int = 1
const GEM_COUNT: int = 720
const SECTOR_COUNT: int = 12
const MAX_PLAYERS: int = 4
const VOICE_FRAME_BYTES: int = 320 # 20 ms of mono 16 kHz G.711 mu-law audio.
const VOICE_RANGE_METRES: float = 12.0
const VOICE_MAX_SEQUENCE: int = 2147483647
const VOICE_PACKETS_PER_SECOND: float = 60.0
const VOICE_BURST_PACKETS: float = 6.0
const COLLECTIBLE_NAMES: Array[String] = ["Disco pebble", "Royal plastic emerald", "Forbidden gummy", "Tiny trophy", "Space potato", "Emotional support ruby", "Executive button", "Suspiciously fancy marble"]

var money: int = 22
var gems: Dictionary = {}
var upgrades: Array[String] = []
var collection: Array[String] = []
var diamond_id: int = -1
var certified: bool = false
var searched: int = 0
var players: Dictionary = {}
var seed_value: int = 0
var certification_step: int = 0
var certification_id: int = -1
var prices: Dictionary = {"scoop": 70, "trays": 100, "loupe": 145, "wash": 180, "sorter": 330, "vacuum": 440, "conveyor": 560, "scanner": 850}
var benefits: Dictionary = {
	"scoop": "Carry 9 objects and scoop bigger batches.",
	"trays": "Carry 14 objects; expanded candidate storage.",
	"loupe": "Sharper optical clues under the inspection lamp.",
	"wash": "Clean discoveries; clean recyclables sell for 60% more.",
	"sorter": "Process 18 objects per pull; candidates go safely to the tray.",
	"vacuum": "Gather loose objects from a wider area, or fill your hands from a sector.",
	"conveyor": "Double sorter throughput to 36 objects per pull.",
	"scanner": "Flag promising objects in a 24-object local batch. Inspect to identify."
}
var pile_positions: Dictionary = {}
var station_positions: Dictionary = {}

var _save_path: String = "user://rough_default.json"
var _network_mode: String = "solo"
var _connecting: bool = false
var _rpc_ready: bool = false
var _action_times: Dictionary = {}
var _world_is_local: bool = true
# Ephemeral transport data: microphone audio and these counters are never saved.
var voice_sent_packets: int = 0
var voice_relayed_packets: int = 0
var voice_received_packets: int = 0
var _voice_sender_limits: Dictionary = {}
var _voice_received_sequences: Dictionary = {}


func _ready() -> void:
	_connect_network_signals()
	for sector in range(SECTOR_COUNT):
		if not pile_positions.has(sector):
			pile_positions[sector] = Vector3(-4.5 + float(sector % 4) * 3.0, 0.25, -4.4 + float(sector / 4) * 2.4)
	if station_positions.is_empty():
		station_positions = {"sell": Vector3(-8, 1, 4), "shop": Vector3(8, 1, 4), "tray": Vector3(-8, 1, 0), "wash": Vector3(-8, 1, -4), "sorter": Vector3(8, 1, -4), "certify": Vector3(0, 1, -8), "scanner": Vector3(8, 1, 0), "recover": Vector3(-5, 1, 8), "collection": Vector3(5, 1, 8)}
	if players.is_empty():
		players[1] = _player_template(1)


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
	diamond_id = rng.randi_range(0, GEM_COUNT - 1)
	money = 22
	gems.clear()
	upgrades.clear()
	collection.clear()
	certified = false
	searched = 0
	certification_step = 0
	certification_id = -1
	for id in range(GEM_COUNT):
		var roll: float = rng.randf()
		var kind: String = "glass"
		var label: String = "Bottle-glass gem"
		var value: int = rng.randi_range(2, 5)
		var clue: String = "Rounded edges, a few bubbles. Very convincing from across the room."
		var tint: Array = [0.18 + rng.randf() * 0.35, 0.35 + rng.randf() * 0.45, 0.55 + rng.randf() * 0.4]
		if roll < 0.105:
			kind = "suspect"
			label = "Promising clear crystal"
			value = 9
			clue = "Look closely: a doubled internal line, soft facet edges, or a tiny round bubble."
			tint = [0.72, 0.91, 1.0]
		elif roll < 0.255:
			kind = "metal"
			label = "Shiny workshop scrap"
			value = rng.randi_range(7, 13)
			clue = "Heavy, metallic, and destined to fund irresponsible machinery."
			tint = [0.76, 0.58, 0.25]
		elif roll < 0.335:
			kind = "cash"
			label = "Crumpled emergency money"
			value = rng.randi_range(15, 28)
			clue = "The previous owner called this a financial crystal."
			tint = [0.29, 0.78, 0.39]
		elif roll < 0.425:
			kind = "collectible"
			label = COLLECTIBLE_NAMES[rng.randi_range(0, COLLECTIBLE_NAMES.size() - 1)]
			value = rng.randi_range(10, 18)
			clue = "An excellent addition to the shelf of questionable treasures."
			tint = [0.95, 0.3 + rng.randf() * 0.45, 0.76]
		elif roll < 0.49:
			kind = "oddity"
			label = "Fake diamond with a moustache" if id % 2 == 0 else "Premium industrial nonsense"
			value = rng.randi_range(6, 11)
			clue = "Clearly certified by a man wearing a bucket."
			tint = [0.75, 0.27, 0.93]
		if id == diamond_id:
			kind = "diamond"
			label = "Promising clear crystal"
			value = 0
			clue = "Razor-sharp facets. One crisp internal edge, no round bubbles. Blue-white light stays bright as it turns."
			tint = [0.72, 0.94, 1.0]
		var sector: int = id / 60
		gems[id] = {"id": id, "kind": kind, "name": label, "pile": sector, "stage": "pile", "owner": 0, "pos": _vector_array(_pile_gem_position(id, sector)), "clean": false, "tag": false, "flagged": false, "searched": false, "value": value, "clue": clue, "color": tint}
	_commit("A fresh mountain of questionable treasure. Your first upgrade costs $70.")


func capacity() -> int:
	if "trays" in upgrades:
		return 14
	if "scoop" in upgrades:
		return 9
	return 3


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


func snapshot() -> Dictionary:
	return {"version": SAVE_VERSION, "seed": seed_value, "money": money, "gems": gems.duplicate(true), "upgrades": upgrades.duplicate(), "collection": collection.duplicate(), "diamond_id": diamond_id, "certified": certified, "searched": searched, "players": players.duplicate(true), "certification_step": certification_step, "certification_id": certification_id}


func save_game() -> void:
	if not is_authority() or not _world_is_local or gems.is_empty():
		return
	var temporary: String = _save_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		notice.emit("Save failed: the workshop folder is not writable.")
		return
	file.store_string(JSON.stringify(snapshot()))
	file.flush()
	file.close()
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
	if int(data.get("version", -1)) != SAVE_VERSION or not _valid_saved_world(data):
		return false
	_apply_snapshot(data)
	_world_is_local = true
	var saved_cosmetics: Array = players.get(1, {}).get("cosmetics", []).duplicate()
	var saved_hat: String = str(players.get(1, {}).get("hat", ""))
	players.clear()
	players[1] = _player_template(1)
	players[1]["cosmetics"] = saved_cosmetics
	players[1]["hat"] = saved_hat
	for id in gems:
		var gem: Dictionary = gems[id]
		if str(gem.get("stage", "")) == "held":
			_to_tray(gem)
		elif str(gem.get("stage", "")) == "loose" and not _valid_position(_array_vector(gem.get("pos", []))):
			_to_tray(gem)
	certification_step = 0 if not certified else 3
	certification_id = -1 if not certified else diamond_id
	_commit("Workshop loaded. Carried items were returned to the inspection tray.")
	return true


func _valid_saved_world(data: Dictionary) -> bool:
	var saved_gems: Variant = data.get("gems", null)
	if not (saved_gems is Dictionary) or saved_gems.size() != GEM_COUNT:
		return false
	var saved_diamond: int = int(data.get("diamond_id", -1))
	if saved_diamond < 0 or saved_diamond >= GEM_COUNT:
		return false
	var genuine_count: int = 0
	for id in range(GEM_COUNT):
		var gem_data: Variant = saved_gems.get(str(id), saved_gems.get(id, null))
		if not (gem_data is Dictionary) or int(gem_data.get("id", -1)) != id:
			return false
		if not str(gem_data.get("stage", "")) in ["pile", "held", "tray", "loose", "collection", "certified", "sold"] or int(gem_data.get("pile", -1)) < 0 or int(gem_data.get("pile", -1)) >= SECTOR_COUNT:
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
	players = {1: _player_template(1)}
	_recover_strays()
	connection_status.emit("Solo workshop")
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
	# This substantially reduces repeated gem dictionaries over reliable UDP.
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_network_mode = "host"
	players = {1: _player_template(1)}
	_recover_strays()
	connection_status.emit("Hosting up to 4 players on port %d" % port)
	_commit("Co-op workshop opened. Everyone shares purchases, money, and progress.")
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
	if now - int(_action_times.get(sender, -1000)) < 90:
		return
	_action_times[sender] = now
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
		if str(key) in ["id", "target", "pile", "test"] and not value_type in [TYPE_INT, TYPE_FLOAT]:
			return false
	return true


func _execute_action(peer_id: int, kind: String, args: Dictionary) -> void:
	if not players.has(peer_id):
		return
	match kind:
		"scoop", "vacuum":
			_scoop(peer_id, args, kind == "vacuum")
		"pick":
			_pick(peer_id, int(args.get("id", -1)))
		"drop":
			_drop(peer_id, int(args.get("id", -1)), args.get("pos", []))
		"tray":
			if not _near_station(peer_id, "tray"):
				_reject(peer_id, "Bring the batch to the inspection tray.")
				return
			var held: Array = held_ids(peer_id)
			for id in held:
				_to_tray(gems[id])
			_commit("Poured %d objects into the inspection tray." % held.size())
		"sell":
			_sell(peer_id)
		"buy":
			_buy(peer_id, str(args.get("upgrade", "")))
		"wash":
			_wash(peer_id)
		"process":
			_process_pile(peer_id, int(args.get("pile", -1)))
		"scan":
			_scan(peer_id, int(args.get("pile", -1)), bool(args.get("portable", false)))
		"collect":
			_collect(peer_id, int(args.get("id", -1)))
		"certify":
			_certify(peer_id, int(args.get("id", -1)), int(args.get("test", -1)))
		"recover", "machine_reset":
			if not _near_station(peer_id, "recover", 4.5):
				_reject(peer_id, "Use the recovery bell by the workshop entrance.")
				return
			var recovered: int = _recover_strays(true)
			if not certified:
				certification_step = 0
				certification_id = -1
			_commit("Recovered %d loose or stranded items. Machinery is ready." % recovered)
		"prank":
			_prank(peer_id, int(args.get("target", -1)), str(args.get("mode", "foam")), int(args.get("id", -1)))
		_:
			_reject(peer_id, "That workshop action is unavailable.")


func _scoop(peer_id: int, args: Dictionary, force_vacuum: bool = false) -> void:
	var vacuum: bool = force_vacuum or str(args.get("tool", "")) == "vacuum"
	if vacuum and not ("vacuum" in upgrades):
		_reject(peer_id, "Buy the vacuum before using it.")
		return
	var room: int = capacity() - held_ids(peer_id).size()
	if room <= 0:
		_reject(peer_id, "Your hands are full. Pour the batch into a tray.")
		return
	var pile: int = int(args.get("pile", -1))
	if pile >= 0 and pile < SECTOR_COUNT and not _near_pile(peer_id, pile, 5.5 if vacuum else 3.8):
		_reject(peer_id, "Move closer to that pile sector.")
		return
	var taken: int = 0
	if vacuum:
		for id in gems:
			var loose: Dictionary = gems[id]
			if taken >= room:
				break
			if str(loose["stage"]) == "loose" and _peer_position(peer_id).distance_to(_array_vector(loose["pos"])) < 6.5:
				_hold(loose, peer_id)
				taken += 1
	if pile >= 0 and pile < SECTOR_COUNT:
		for id in _pile_ids(pile):
			if taken >= room:
				break
			_hold(gems[id], peer_id)
			taken += 1
	if taken == 0:
		_reject(peer_id, "No reachable material here. Try another sector or recover loose items.")
		return
	_commit("%s collected %d objects." % ["Vacuum" if vacuum else "Scoop", taken])


func _pick(peer_id: int, id: int) -> void:
	if not gems.has(id):
		return
	var gem: Dictionary = gems[id]
	var stage: String = str(gem["stage"])
	if not stage in ["pile", "tray", "loose"]:
		_reject(peer_id, "That object is already being carried or stored.")
		return
	if held_ids(peer_id).size() >= capacity():
		_reject(peer_id, "Your hands are full.")
		return
	if _peer_position(peer_id).distance_to(_array_vector(gem["pos"])) > 4.2:
		_reject(peer_id, "Move closer to pick that up.")
		return
	_hold(gem, peer_id)
	_commit("Picked up %s." % str(gem["name"]))


func _drop(peer_id: int, id: int, location: Variant) -> void:
	if not _owns(peer_id, id) or not (location is Array) or location.size() != 3:
		return
	var target: Vector3 = _array_vector(location)
	if not _valid_position(target) or _peer_position(peer_id).distance_to(target) > 4.5:
		_reject(peer_id, "Drop objects within reach.")
		return
	var gem: Dictionary = gems[id]
	gem["stage"] = "loose"
	gem["owner"] = 0
	gem["pos"] = _vector_array(target)
	_commit("Object dropped. The recovery bell can always bring it back.")


func _sell(peer_id: int) -> void:
	if not _near_station(peer_id, "sell"):
		_reject(peer_id, "Bring the batch to the recycling counter.")
		return
	var payout: int = 0
	var protected: int = 0
	var sold: int = 0
	for id in held_ids(peer_id):
		var gem: Dictionary = gems[id]
		if _suspicious(gem):
			_to_tray(gem)
			protected += 1
		else:
			payout += _sale_value(gem)
			gem["stage"] = "sold"
			gem["owner"] = 0
			sold += 1
	money += payout
	_commit("Sold %d objects for $%d. %d candidates routed safely to the tray." % [sold, payout, protected])


func _buy(peer_id: int, upgrade: String) -> void:
	if not _near_station(peer_id, "shop"):
		_reject(peer_id, "Visit the upgrade counter.")
		return
	if not prices.has(upgrade) or upgrade in upgrades:
		_reject(peer_id, "That upgrade is unavailable or already installed.")
		return
	var price: int = int(prices[upgrade])
	if money < price:
		_reject(peer_id, "Need $%d more for %s." % [price - money, upgrade.capitalize()])
		return
	money -= price
	upgrades.append(upgrade)
	_commit("%s installed! %s" % [upgrade.capitalize(), str(benefits[upgrade])])


func _wash(peer_id: int) -> void:
	if not "wash" in upgrades or not _near_station(peer_id, "wash"):
		_reject(peer_id, "Buy the washing station, then bring your discoveries to it.")
		return
	var cleaned: int = 0
	for id in gems:
		var gem: Dictionary = gems[id]
		if (str(gem["stage"]) == "tray" or _owns(peer_id, int(id))) and not bool(gem["clean"]):
			gem["clean"] = true
			cleaned += 1
	for id in players:
		players[id]["foam_until"] = 0.0
	_commit("Washed %d discoveries. Clean recyclables earn 60%% more. Foam removed!" % cleaned)


func _process_pile(peer_id: int, pile: int) -> void:
	if not "sorter" in upgrades or not _near_station(peer_id, "sorter"):
		_reject(peer_id, "Buy the sorting machine, then pull its lever.")
		return
	if pile < 0 or pile >= SECTOR_COUNT:
		_reject(peer_id, "Choose a pile sector to feed into the machine.")
		return
	var batch: int = 36 if "conveyor" in upgrades else 18
	var count: int = 0
	var candidates: int = 0
	var payout: int = 0
	for id in _pile_ids(pile):
		if count >= batch:
			break
		var gem: Dictionary = gems[id]
		_mark_searched(gem)
		if _suspicious(gem) or str(gem["kind"]) == "collectible":
			_to_tray(gem)
			candidates += 1
		else:
			payout += _sale_value(gem)
			gem["stage"] = "sold"
			gem["owner"] = 0
		count += 1
	money += payout
	_commit("Sorter processed %d objects: $%d recycled, %d discoveries in the tray." % [count, payout, candidates])


func _scan(peer_id: int, pile: int, portable: bool = false) -> void:
	if pile < 0 or pile >= SECTOR_COUNT:
		return
	if not "scanner" in upgrades:
		_reject(peer_id, "Buy the scanner before scanning a batch.")
		return
	if (portable and not _near_pile(peer_id, pile, 4.5)) or (not portable and not _near_station(peer_id, "scanner")):
		_reject(peer_id, "Scan within reach of a pile sector, or use the scanner control panel.")
		return
	var checked: int = 0
	var promising: int = 0
	for id in _pile_ids(pile):
		if checked >= 24:
			break
		var gem: Dictionary = gems[id]
		if bool(gem.get("scanned", false)):
			continue
		gem["scanned"] = true
		gem["flagged"] = _suspicious(gem) or int(id) % 19 == 0
		if bool(gem["flagged"]):
			promising += 1
		checked += 1
	_commit("Scanned %d objects in sector %d: %d promising candidates. Inspect the clues." % [checked, pile + 1, promising])


func _collect(peer_id: int, id: int) -> void:
	if not gems.has(id):
		return
	var gem: Dictionary = gems[id]
	if not _owns(peer_id, id) and not (str(gem["stage"]) == "tray" and _peer_position(peer_id).distance_to(_array_vector(gem["pos"])) < 4.2):
		return
	if not str(gem["kind"]) in ["collectible", "oddity"]:
		_reject(peer_id, "The display shelf prefers properly ridiculous treasures.")
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
	_commit("Shelf discovery: %s! %s" % [label, "$12 curator grant + a silly hat unlocked." if fresh else "A spare for your magnificent collection."])


func _certify(peer_id: int, id: int, test: int) -> void:
	if certified:
		_reject(peer_id, "The genuine diamond is already certified. Keep building your ridiculous workshop!")
		return
	if not _near_station(peer_id, "certify") or not _owns(peer_id, id):
		_reject(peer_id, "Bring a held candidate to the certification bench.")
		return
	if not gems.has(id) or not _suspicious(gems[id]):
		_reject(peer_id, "The bench needs a promising crystal candidate.")
		return
	if certification_id != id:
		if test != 0:
			_reject(peer_id, "Start this candidate with test 1: optical inspection.")
			return
		certification_id = id
		certification_step = 0
	if test != certification_step or test < 0 or test > 2:
		_reject(peer_id, "Complete the three bench tests in order.")
		return
	certification_step += 1
	if certification_step == 1:
		_commit("Test 1/3: optical inspection recorded. Next: facet and hardness test.")
	elif certification_step == 2:
		_commit("Test 2/3: facet response recorded. Next: final blue-light certification.")
	elif id == diamond_id and str(gems[id]["kind"]) == "diamond":
		certified = true
		gems[id]["stage"] = "certified"
		gems[id]["owner"] = 0
		gems[id]["pos"] = _vector_array(_station_position("certify") + Vector3(0, 0.3, 0))
		money += 1000
		if not "THE GENUINE DIAMOND" in collection:
			collection.append("THE GENUINE DIAMOND")
		_commit("THE GENUINE DIAMOND! Certified after all three tests. $1,000 discovery grant. You found brilliance in the rough!")
	else:
		certification_step = 0
		certification_id = -1
		gems[id]["tag"] = true
		_commit("Expert verdict: an exceptionally confident imitation. Candidate returned unharmed. Follow the sharp-edge, single-line clues.")


func _prank(peer_id: int, target: int, mode: String, item_id: int = -1) -> void:
	if target == peer_id and mode == "hat":
		var hats: Array = ["", "Bucket hat"]
		if "Gem crown" in players[peer_id].get("cosmetics", []):
			hats.append("Gem crown")
		var current: int = hats.find(str(players[peer_id].get("hat", "")))
		players[peer_id]["hat"] = hats[(current + 1) % hats.size()]
		_commit("Headwear: %s." % (str(players[peer_id]["hat"]) if not str(players[peer_id]["hat"]).is_empty() else "respectable bare head"))
		return
	if target == peer_id and mode == "label":
		var tagged: int = 0
		for id in held_ids(peer_id):
			if item_id < 0 or int(id) == item_id:
				gems[id]["tag"] = true
				tagged += 1
		_commit("Applied %d absolutely unofficial CERTIFIED DIAMOND labels." % tagged)
		return
	if target == peer_id or not players.has(target) or _peer_position(peer_id).distance_to(_peer_position(target)) > 6.0:
		_reject(peer_id, "Get within reach of a co-op friend.")
		return
	if not mode in ["foam", "scoop", "present", "label", "bucket", "reverse", "vacuum"]:
		return
	if mode == "reverse" and not "conveyor" in upgrades:
		_reject(peer_id, "A reversible conveyor would help with this terrible idea.")
		return
	if mode == "vacuum" and not "vacuum" in upgrades:
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
	elif mode == "label":
		for id in held_ids(target):
			gems[id]["tag"] = true
	elif mode == "present":
		for id in held_ids(peer_id):
			if _suspicious(gems[id]):
				if held_ids(target).size() < capacity():
					_hold(gems[id], target)
				else:
					_to_tray(gems[id])
				break
	elif mode == "scoop":
		for id in held_ids(peer_id):
			gems[id]["stage"] = "loose"
			gems[id]["owner"] = 0
			gems[id]["pos"] = _vector_array(_peer_position(target) + Vector3(0, 0.1, 0))
	elif mode == "vacuum":
		var room: int = capacity() - held_ids(peer_id).size()
		for id in gems:
			if room <= 0:
				break
			var gem: Dictionary = gems[id]
			if str(gem["stage"]) == "loose" and _peer_position(target).distance_to(_array_vector(gem["pos"])) < 3.5:
				_hold(gem, peer_id)
				room -= 1
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
		if (stage == "held" and not players.has(int(gem["owner"]))) or (stage == "loose" and (all_loose or not _valid_position(_array_vector(gem["pos"])) or absf(_array_vector(gem["pos"]).x) > 11.5 or absf(_array_vector(gem["pos"]).z) > 10.5 or _array_vector(gem["pos"]).y < -0.5)):
			_to_tray(gem)
			recovered += 1
	return recovered


func _pile_ids(pile: int) -> Array:
	var ids: Array = []
	for id in gems:
		if int(gems[id]["pile"]) == pile and str(gems[id]["stage"]) == "pile":
			ids.append(int(id))
	ids.sort()
	return ids


func _suspicious(gem: Dictionary) -> bool:
	return str(gem.get("kind", "")) in ["diamond", "suspect"] or int(gem.get("id", -1)) == diamond_id


func _sale_value(gem: Dictionary) -> int:
	return maxi(0, int(round(float(gem.get("value", 0)) * (1.6 if bool(gem.get("clean", false)) else 1.0))))


func _owns(peer_id: int, id: int) -> bool:
	return gems.has(id) and str(gems[id]["stage"]) == "held" and int(gems[id]["owner"]) == peer_id


func _near_station(peer_id: int, station: String, reach: float = 4.0) -> bool:
	if not station_positions.has(station):
		return false
	return _peer_position(peer_id).distance_to(_station_position(station)) <= reach


func _near_pile(peer_id: int, pile: int, reach: float) -> bool:
	if not pile_positions.has(pile):
		return false
	var center: Vector3 = _as_vector(pile_positions[pile])
	return _peer_position(peer_id).distance_to(center) <= reach


func _station_position(station: String) -> Vector3:
	return _as_vector(station_positions.get(station, Vector3.ZERO))


func _peer_position(peer_id: int) -> Vector3:
	return _array_vector(players.get(peer_id, {}).get("pos", [0, 1.6, 7]))


func _pile_gem_position(id: int, sector: int) -> Vector3:
	var center: Vector3 = _as_vector(pile_positions.get(sector, Vector3(-4.5 + float(sector % 4) * 3.0, 0.25, -4.4 + float(sector / 4) * 2.4)))
	var slot: int = id % 60
	return center + Vector3(float(slot % 10) * 0.235 - 1.06, 0.08 + float(slot % 7) * 0.025, float(slot / 10) * 0.25 - 0.625)


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
	return {"id": id, "pos": [0.0, 1.6, 7.0], "yaw": 0.0, "pitch": 0.0, "hat": "", "cosmetics": [], "prank": "", "prank_until": 0.0, "foam_until": 0.0, "last_prank": 0.0}


func _commit(message: String = "") -> void:
	changed.emit()
	if not message.is_empty():
		notice.emit(message)
	if _network_mode == "host":
		_receive_snapshot.rpc(snapshot())
		if not message.is_empty():
			_receive_notice.rpc(message)
	save_game()


func _reject(peer_id: int, message: String) -> void:
	if peer_id == local_id():
		notice.emit(message)
	elif _network_mode == "host":
		_receive_notice.rpc_id(peer_id, message)


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(data: Dictionary) -> void:
	if is_authority():
		return
	_apply_snapshot(data)
	changed.emit()


func _apply_snapshot(data: Dictionary) -> void:
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
	certification_step = int(data.get("certification_step", 0))
	certification_id = int(data.get("certification_id", -1))


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
	peer_joined.emit(id)
	_commit("Player %d joined the shared workshop." % id)


func _on_peer_disconnected(id: int) -> void:
	_voice_sender_limits.erase(id)
	_voice_received_sequences.erase(id)
	if not is_authority():
		players.erase(id)
		peer_left.emit(id)
		return
	players.erase(id)
	_action_times.erase(id)
	var rescued: int = _recover_strays()
	peer_left.emit(id)
	_commit("Player %d left. %d carried objects returned safely to the tray." % [id, rescued])


func _on_connected_to_server() -> void:
	_connecting = false
	connection_status.emit("Connected to shared workshop · player %d" % local_id())
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
	connection_status.emit("Host disconnected. Return to the menu to load your solo workshop.")
	changed.emit()
