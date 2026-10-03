extends Node

var sounds := {}
var bus_player: AudioStreamPlayer
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	for id in ["pick", "drop", "sell", "buy", "scan", "test", "win", "prank", "mine", "drill", "break", "clank", "fuse", "boom"]:
		sounds[id] = synth(id)

func synth(id: String) -> AudioStreamWAV:
	var length := 0.22
	if id == "win": length = 2.4
	if id == "buy": length = 0.6
	if id == "break": length = 0.35
	if id == "fuse": length = 0.9
	if id == "boom": length = 1.8
	if id in ["mine", "clank"]: length = 0.14
	if id == "drill": length = 0.12
	var rate := 22050
	var samples := PackedByteArray()
	var count := int(length*rate)
	samples.resize(count*2)
	var freq: float = {"pick":790.0,"drop":210.0,"sell":960.0,"buy":660.0,"scan":1150.0,"test":540.0,"win":440.0,"prank":220.0,"mine":180.0,"drill":95.0,"break":120.0,"clank":1400.0,"fuse":3000.0,"boom":48.0}.get(id,440.0)
	for i in range(count):
		var t := float(i)/rate
		var envelope := pow(1.0 - float(i)/count, 1.6)*minf(t*120,1)
		var wave := sin(TAU * freq * t) * 0.42
		if id in ["drop","break","mine"]:
			wave = rng.randf_range(-0.45,0.45)*0.55 + sin(TAU*freq*t)*0.25
		elif id == "boom":
			# A low rumble with a sharp crack at the start.
			wave = rng.randf_range(-1.0,1.0)*(0.5+0.5*exp(-t*14.0)) + sin(TAU*freq*t)*0.6
			envelope = pow(1.0 - float(i)/count, 2.2)*minf(t*400,1)
		elif id == "fuse":
			wave = rng.randf_range(-0.3,0.3)*(0.6+0.4*sin(TAU*31.0*t))
		elif id == "drill":
			wave = (fmod(t*freq,1.0)-0.5)*0.7 + rng.randf_range(-0.1,0.1)
		elif id == "clank":
			wave = (sin(TAU*freq*t)+sin(TAU*freq*1.52*t))*0.3
		elif id in ["win","buy"]:
			var note: int = mini(int(t*5), 5)
			freq = 440.0*pow(2.0, float([0,4,7,12,16,19][note])/12.0)
			wave = (sin(TAU*freq*t)+sin(TAU*freq*2*t)*0.23)*0.3
		var value := int(clampf(wave*envelope,-1,1)*22000)
		samples.encode_s16(i*2,value)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = samples
	return wav

func play(id: String, volume_db: float = -13.0) -> void:
	if not sounds.has(id): return
	var player := AudioStreamPlayer.new()
	player.stream = sounds[id]
	player.pitch_scale = rng.randf_range(0.94,1.05) if id != "win" else 1.0
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
