extends Node3D

## Live proximity voice: 16 kHz mono G.711 mu-law, 20 ms frames, no disk recordings.
const SAMPLE_RATE := 16000
const FRAME_SAMPLES := 320
const RANGE := 12.0
const OUTPUT_BUS := &"ProximityVoice"
const INPUT_BUS := &"MicrophoneCapture"

var game: Node
var transmitting := false
var mic_level := 0.0
var test_mode := false
var focused := true
var received_packets := 0
var played_packets := 0
var decoded_samples := 0
var captured_packets := 0
var received_rms: Dictionary = {}
var playback_streams: Dictionary = {}
var capture: AudioEffectCapture
var microphone: AudioStreamPlayer
var _resample_samples := PackedFloat32Array()
var _resample_position := 0.0
var _packet_samples := PackedFloat32Array()
var _sequence := 0
var _filter_sample := 0.0
var _last_device := ""
var _signal_since := 0
var _lookup_decode := PackedFloat32Array()

func build(owner_game: Node) -> void:
	game=owner_game
	name="ProximityVoice"
	for i in range(256): _lookup_decode.append(decode_mulaw(i))
	if AudioServer.get_bus_index(OUTPUT_BUS)<0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,OUTPUT_BUS)
	if AudioServer.get_bus_index(INPUT_BUS)<0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,INPUT_BUS)
	var input_index:=AudioServer.get_bus_index(INPUT_BUS)
	capture=AudioEffectCapture.new()
	capture.buffer_length=0.16
	AudioServer.add_bus_effect(input_index,capture)
	# Capture taps the pre-volume signal. The microphone is never locally monitored.
	AudioServer.set_bus_volume_db(input_index,-80)
	AudioServer.set_bus_mute(input_index,true)
	microphone=AudioStreamPlayer.new()
	microphone.name="Microphone"
	microphone.bus=INPUT_BUS
	microphone.stream=AudioStreamMicrophone.new()
	add_child(microphone)
	game.state.voice_received.connect(receive_voice)
	game.state.peer_left.connect(remove_peer)
	apply_settings(game.settings)

func input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()

func apply_settings(settings: Dictionary) -> void:
	var requested: String=str(settings.get("input_device","Default"))
	var chosen: String=requested if requested in input_devices() else "Default"
	if chosen!=_last_device:
		stop_capture()
		AudioServer.input_device=chosen
		_last_device=chosen
	var index:=AudioServer.get_bus_index(OUTPUT_BUS)
	var volume: float=clampf(float(settings.get("voice_volume",0.85)),0,1)
	AudioServer.set_bus_volume_db(index,linear_to_db(maxf(volume,0.00001)))
	AudioServer.set_bus_mute(index,volume==0 or not bool(settings.get("voice_enabled",true)))
	if not bool(settings.get("voice_enabled",true)) or volume==0:
		clear_receivers()
	if bool(settings.get("mic_muted",false)) or not bool(settings.get("voice_enabled",true)):
		stop_capture()

func joined_coop() -> bool:
	return game.active and game.state._network_mode in ["host","client"] and game.state.players.size()>1

func can_send(requested: bool) -> bool:
	return requested and joined_coop() and not game.ui.menu_visible and bool(game.settings.get("voice_enabled",true)) and not bool(game.settings.get("mic_muted",false))

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	var talking: bool=can_send(focused and Input.is_physical_key_pressed(KEY_V)) and not test_mode
	if talking:
		if not microphone.playing:
			clear_capture()
			_signal_since=Time.get_ticks_msec()
			microphone.play()
		transmitting=true
		var available:=capture.get_frames_available()
		if available>0:
			var samples: PackedVector2Array=capture.get_buffer(mini(available,8192))
			ingest_capture(samples,AudioServer.get_mix_rate(),true)
	else:
		if transmitting or microphone.playing: stop_capture()
		mic_level=move_toward(mic_level,0,delta*2)
	update_receivers()
	if game.ui.has_method("update_voice_status"):
		game.ui.update_voice_status(status_text(),mic_level,transmitting)

func status_text() -> String:
	if not bool(game.settings.get("voice_enabled",true)): return "Proximity voice disabled"
	if not joined_coop(): return "Solo · voice off"
	if bool(game.settings.get("mic_muted",false)): return "Mic muted · M to unmute"
	if game.ui.menu_visible: return "V to talk while sorting · M to mute"
	if transmitting:
		if mic_level<0.005 and Time.get_ticks_msec()-_signal_since>1400: return "No mic signal · check Settings"
		return "TRANSMITTING · nearby players"
	return "Hold V to talk · M to mute"

func ingest_capture(samples: PackedVector2Array,source_rate: float,allow_send: bool=true) -> void:
	if not can_send(allow_send) or source_rate<8000 or source_rate>192000:
		clear_capture()
		return
	var gain: float=clampf(float(game.settings.get("mic_gain",1.0)),0.25,3)
	var peak:=0.0
	var alpha: float=1.0-exp(-TAU*6500/source_rate)
	for stereo in samples:
		var mono: float=clampf((stereo.x+stereo.y)*0.5*gain,-1,1)
		peak=maxf(peak,absf(mono))
		_filter_sample+=alpha*(mono-_filter_sample)
		_resample_samples.append(_filter_sample)
	mic_level=maxf(peak,mic_level*0.8)
	var step: float=source_rate/SAMPLE_RATE
	while _resample_position+1<_resample_samples.size():
		var at: int=int(_resample_position)
		var sample: float=lerpf(_resample_samples[at],_resample_samples[at+1],_resample_position-at)
		_packet_samples.append(sample)
		_resample_position+=step
		if _packet_samples.size()==FRAME_SAMPLES:
			var packet:=PackedByteArray()
			packet.resize(FRAME_SAMPLES)
			var packet_peak:=0.0
			for i in range(FRAME_SAMPLES):
				packet[i]=encode_mulaw(_packet_samples[i])
				packet_peak=maxf(packet_peak,absf(_packet_samples[i]))
			# A small silence gate avoids a constant stream of microphone noise.
			if packet_peak>=0.003:
				game.state.send_voice(_sequence,packet)
				_sequence+=1
				captured_packets+=1
			_packet_samples.clear()
	var consumed: int=mini(int(_resample_position),maxi(0,_resample_samples.size()-1))
	if consumed>0:
		_resample_samples=_resample_samples.slice(consumed)
		_resample_position-=consumed

func send_test_frame(samples: PackedFloat32Array) -> void:
	if not test_mode: return
	var stereo:=PackedVector2Array()
	for sample in samples: stereo.append(Vector2(sample,sample))
	ingest_capture(stereo,SAMPLE_RATE,true)

static func encode_mulaw(sample: float) -> int:
	var pcm: int=int(clampf(sample,-1,1)*32767)
	var sign: int=(pcm>>8)&0x80
	if sign!=0: pcm=-pcm
	pcm=mini(pcm,32635)+132
	var exponent:=7
	var mask:=0x4000
	while exponent>0 and (pcm&mask)==0:
		exponent-=1
		mask>>=1
	var mantissa: int=(pcm>>(exponent+3))&15
	return (~(sign|(exponent<<4)|mantissa))&255

static func decode_mulaw(code: int) -> float:
	var value: int=(~code)&255
	var sample: int=((value&15)<<3)+132
	sample<<=(value&112)>>4
	return float(132-sample if (value&128)!=0 else sample-132)/32768.0

static func speech_gain(distance: float) -> float:
	if distance>=RANGE: return 0.0
	return pow(clampf(1.0-(maxf(distance,2.0)-2.0)/(RANGE-2.0),0,1),1.3)

func receive_voice(peer_id: int,sequence: int,payload: PackedByteArray) -> void:
	if not joined_coop() or not bool(game.settings.get("voice_enabled",true)) or float(game.settings.get("voice_volume",0.85))<=0:
		return
	if peer_id==game.state.local_id() or payload.size()!=FRAME_SAMPLES or not game.state.players.has(peer_id): return
	var pos:=peer_position(peer_id)
	if game.player.position.distance_to(pos)>=RANGE: return
	if not playback_streams.has(peer_id): create_receiver(peer_id,pos)
	var entry: Dictionary=playback_streams[peer_id]
	if sequence<int(entry.expected): return
	var samples:=PackedVector2Array()
	var squared:=0.0
	for code in payload:
		var value: float=_lookup_decode[code]
		squared+=value*value
		samples.append(Vector2(value,value))
	received_rms[peer_id]=sqrt(squared/FRAME_SAMPLES)
	entry.queue[sequence]=samples
	entry.last=Time.get_ticks_msec()
	if entry.queue.size()>12:
		var ordered: Array=entry.queue.keys()
		ordered.sort()
		entry.queue.erase(ordered[0])
		entry.expected=int(ordered[1])
	received_packets+=1
	decoded_samples+=FRAME_SAMPLES

func create_receiver(peer_id: int,pos: Vector3) -> void:
	var remote:=AudioStreamPlayer3D.new()
	remote.name="Voice_%s" % peer_id
	remote.bus=OUTPUT_BUS
	remote.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED
	remote.max_distance=0
	remote.attenuation_filter_cutoff_hz=20500
	remote.max_db=0
	var generator:=AudioStreamGenerator.new()
	generator.mix_rate=SAMPLE_RATE
	generator.buffer_length=0.18
	remote.stream=generator
	add_child(remote)
	remote.position=pos+Vector3.UP*1.55
	remote.volume_db=linear_to_db(maxf(speech_gain(game.player.position.distance_to(pos)),0.00001))
	remote.play()
	playback_streams[peer_id]={"player":remote,"playback":null,"queue":{},"expected":-1,"last":Time.get_ticks_msec(),"prime_at":Time.get_ticks_msec()+60,"started":false}

func update_receivers() -> void:
	var now:=Time.get_ticks_msec()
	for key in playback_streams.keys():
		var peer_id: int=int(key)
		var entry: Dictionary=playback_streams[peer_id]
		var remote: AudioStreamPlayer3D=entry.player
		if not joined_coop() or not game.state.players.has(peer_id) or now-int(entry.last)>450:
			remove_peer(peer_id)
			continue
		var pos:=peer_position(peer_id)
		remote.position=pos+Vector3.UP*1.55
		var attenuation: float=speech_gain(game.player.position.distance_to(pos))
		remote.volume_db=linear_to_db(maxf(attenuation,0.00001))
		if attenuation==0:
			remove_peer(peer_id)
			continue
		if not remote.has_stream_playback(): continue
		var playback: AudioStreamGeneratorPlayback=remote.get_stream_playback()
		entry.playback=playback
		if not bool(entry.started):
			if now<int(entry.prime_at) or entry.queue.is_empty(): continue
			var ordered: Array=entry.queue.keys()
			ordered.sort()
			entry.expected=int(ordered[0])
			entry.started=true
		var pushed:=0
		while playback.can_push_buffer(FRAME_SAMPLES) and pushed<6 and not entry.queue.is_empty():
			var expected: int=int(entry.expected)
			if entry.queue.has(expected):
				playback.push_buffer(entry.queue[expected])
				entry.queue.erase(expected)
				played_packets+=1
			else:
				# Missing unreliable frame: conceal with silence, never stall the stream.
				var ordered: Array=entry.queue.keys()
				ordered.sort()
				if int(ordered[0])<expected:
					entry.queue.erase(ordered[0])
					continue
				if int(ordered[0])-expected>6:
					entry.expected=int(ordered[0])
					continue
				var silence:=PackedVector2Array()
				silence.resize(FRAME_SAMPLES)
				playback.push_buffer(silence)
			entry.expected=int(entry.expected)+1
			pushed+=1

func peer_position(peer_id: int) -> Vector3:
	var array: Array=game.state.players.get(peer_id,{}).get("pos",[0,0,0])
	return Vector3(float(array[0]),float(array[1]),float(array[2]))

func is_speaking(peer_id: int) -> bool:
	return playback_streams.has(peer_id) and Time.get_ticks_msec()-int(playback_streams[peer_id].last)<220 and float(received_rms.get(peer_id,0))>0.006

func clear_capture() -> void:
	if capture: capture.clear_buffer()
	_resample_samples.clear()
	_packet_samples.clear()
	_resample_position=0
	_filter_sample=0

func stop_capture() -> void:
	if is_instance_valid(microphone): microphone.stop()
	transmitting=false
	mic_level=0
	clear_capture()

func remove_peer(peer_id: int) -> void:
	if playback_streams.has(peer_id):
		var remote: AudioStreamPlayer3D=playback_streams[peer_id].player
		remote.stop()
		remote.queue_free()
		playback_streams.erase(peer_id)
	received_rms.erase(peer_id)

func clear_receivers() -> void:
	for peer_id in playback_streams.keys(): remove_peer(int(peer_id))

func stop_session() -> void:
	stop_capture()
	clear_receivers()
	_sequence=0

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused=false
		stop_capture()
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:
		focused=true
