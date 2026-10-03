extends Node

var sounds := {}
var bus_player: AudioStreamPlayer
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	for id in ["scoop", "pick", "drop", "sell", "buy", "wash", "sort", "scan", "test", "win", "prank"]:
		sounds[id] = synth(id)

func synth(id: String) -> AudioStreamWAV:
	var length := 0.22
	if id == "win": length = 2.4
	if id == "wash": length = 0.65
	if id == "sort": length = 0.7
	if id == "buy": length = 0.6
	var rate := 22050
	var samples := PackedByteArray()
	var count := int(length*rate)
	samples.resize(count*2)
	var freq: float = {"scoop":320.0,"pick":790.0,"drop":210.0,"sell":960.0,"buy":660.0,"wash":90.0,"sort":180.0,"scan":1150.0,"test":540.0,"win":440.0,"prank":220.0}.get(id,440.0)
	for i in range(count):
		var t := float(i)/rate
		var envelope := pow(1.0 - float(i)/count, 1.6)*minf(t*120,1)
		var wave := sin(TAU * freq * t) * 0.42
		if id in ["scoop","drop","wash","sort"]:
			wave = rng.randf_range(-0.45,0.45)*0.55 + sin(TAU*freq*t)*0.15
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

func play(id: String) -> void:
	if not sounds.has(id): return
	var player := AudioStreamPlayer.new()
	player.stream = sounds[id]
	player.pitch_scale = rng.randf_range(0.94,1.05) if id != "win" else 1.0
	player.volume_db = -13
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
