extends Node

## Synthetic voice integration test. Never opens or records a physical microphone.
## Native host/client instances share --report-dir and --verify-voice=host/client.
## The tones traverse capture resampling, mu-law, ENet and spatial generator output.
var game: Node
var role := ""
var report_dir := ""
var phase := "boot"
var stage := 0
var checks: Array[String] = []
var errors: Array[String] = []
var measurements: Dictionary = {}
var started := 0
var remote_peer := -1
var tone_cursor := 0
var test_settings: Dictionary = {}
var output_capture: AudioEffectCapture
var output_bus := ""
var output_bus_index := -1
var original_voice_send := "Master"

func begin(owner_game: Node, mode: String, args: PackedStringArray) -> void:
	game = owner_game
	role = mode
	started = Time.get_ticks_msec()
	for arg in args:
		if arg.begins_with("--report-dir="):
			report_dir = arg.trim_prefix("--report-dir=")
	if report_dir.is_empty():
		report_dir = OS.get_user_data_dir().path_join("voice-verification")
	DirAccess.make_dir_recursive_absolute(report_dir)
	game.state._save_path = report_dir.path_join("verify_voice_%s_save.json" % role)
	game.voice.test_mode = true
	test_settings = game.settings.duplicate()
	test_settings["voice_enabled"] = true
	test_settings["mic_muted"] = false
	test_settings["mic_gain"] = 1.0
	test_settings["voice_volume"] = 0.7
	# The component reads the live game settings when capture or packets arrive.
	# These test settings remain in memory and are never saved to the user's file.
	game.settings = test_settings
	game.voice.apply_settings(test_settings)
	write_report()
	call_deferred("run")

func run() -> void:
	await pause(0.3)
	codec_probe()
	install_output_probe()
	if role == "host":
		await host_probe()
	elif role == "client":
		await client_probe()
	else:
		errors.append("Unknown synthetic voice verification role")
	measurements["final_voice_counters"] = counters()
	game.voice.stop_session()
	check(game.voice.playback_streams.is_empty(), "Stopping a session clears all remote playback queues")
	phase = "complete"
	stage = 20
	write_report()
	print("VOICE_VERIFY_RESULT ", role, " ", JSON.stringify({"checks": checks, "errors": errors, "measurements": measurements}))
	game.state.leave()
	if output_bus_index >= 0:
		var voice_bus_index := AudioServer.get_bus_index("ProximityVoice")
		if voice_bus_index >= 0:
			AudioServer.set_bus_send(voice_bus_index, original_voice_send)
		AudioServer.remove_bus(output_bus_index)
	get_tree().quit(0 if errors.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if condition:
		checks.append(message)
		print("VOICE_PASS ", message)
	else:
		errors.append(message)
		push_error("VOICE_VERIFY_FAIL " + message)
	write_report()

func advance(value: int, name: String) -> void:
	stage = value
	phase = name
	write_report()

func write_report() -> void:
	var data := {"role": role, "phase": phase, "stage": stage, "checks": checks, "errors": errors, "elapsed_ms": Time.get_ticks_msec() - started, "local_id": game.state.local_id(), "players": game.state.players.size(), "measurements": measurements, "counters": counters()}
	var file := FileAccess.open(report_dir.path_join("voice_%s_report.json" % role), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))

func counters() -> Dictionary:
	return {"captured": game.voice.captured_packets, "received": game.voice.received_packets, "played": game.voice.played_packets, "decoded_samples": game.voice.decoded_samples, "network_sent": game.state.voice_sent_packets, "network_received": game.state.voice_received_packets, "network_relayed": game.state.voice_relayed_packets}

func peer_report() -> Dictionary:
	var peer_role := "client" if role == "host" else "host"
	var path := report_dir.path_join("voice_%s_report.json" % peer_role)
	if not FileAccess.file_exists(path):
		return {}
	# The other instance can be writing this coordination file. Retry an
	# incomplete read on the next poll without printing a parser error.
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var value: Variant = parser.data
	return value if value is Dictionary else {}

func wait_for(condition: Callable, limit: float = 30.0) -> bool:
	var ticks := Time.get_ticks_msec()
	while Time.get_ticks_msec() - ticks < int(limit * 1000):
		if condition.call():
			return true
		await pause(0.08)
	return false

func peer_reached(value: int) -> bool:
	return int(peer_report().get("stage", -1)) >= value

func pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func go(pos: Vector3, yaw: float) -> void:
	game.player.position = pos
	game.player.velocity = Vector3.ZERO
	game.player.yaw = yaw
	game.player.pitch = -0.06
	game.player.update_view()
	game.player.set_physics_process(false)
	game.state.send_pose(pos, yaw, game.player.pitch)
	await pause(0.25)

func codec_probe() -> void:
	var max_error := 0.0
	for sample in [-1.0, -0.7, -0.25, 0.0, 0.25, 0.7, 1.0]:
		var encoded: int = game.voice.encode_mulaw(sample)
		var decoded: float = game.voice.decode_mulaw(encoded)
		max_error = maxf(max_error, absf(sample - decoded))
	measurements["codec_max_roundtrip_error"] = max_error
	check(max_error < 0.04, "Mu-law codec preserves signed voice samples within 4 percent")
	check(absf(game.voice.decode_mulaw(game.voice.encode_mulaw(0.0))) < 0.001, "Encoded silence decodes to silence")
	check(is_equal_approx(game.voice.speech_gain(0.0), 1.0) and is_equal_approx(game.voice.speech_gain(2.0), 1.0), "Nearby speech has full gain through two metres")
	var middle: float = game.voice.speech_gain(7.0)
	check(middle > 0.0 and middle < 1.0 and game.voice.speech_gain(3.0) > game.voice.speech_gain(10.0), "Speech fades continuously between two and twelve metres")
	check(is_zero_approx(game.voice.speech_gain(12.0)) and is_zero_approx(game.voice.speech_gain(30.0)), "Speech is silent at twelve metres and beyond")
	measurements["speech_gain_7_metres"] = middle

func install_output_probe() -> void:
	# This captures synthetic speaker output after AudioStreamPlayer3D, not input.
	# Insert before the existing voice bus so its normal volume and mute settings
	# remain in the audio path. Godot buses route toward earlier bus indices.
	output_bus_index = 1
	AudioServer.add_bus(output_bus_index)
	output_bus = "SyntheticVoiceVerification"
	AudioServer.set_bus_name(output_bus_index, output_bus)
	var voice_bus_index := AudioServer.get_bus_index("ProximityVoice")
	original_voice_send = AudioServer.get_bus_send(voice_bus_index)
	AudioServer.set_bus_send(output_bus_index, original_voice_send)
	AudioServer.set_bus_send(voice_bus_index, output_bus)
	output_capture = AudioEffectCapture.new()
	output_capture.buffer_length = 0.25
	AudioServer.add_bus_effect(output_bus_index, output_capture)

func output_rms() -> float:
	var frames := output_capture.get_buffer(output_capture.get_frames_available())
	if frames.is_empty():
		return 0.0
	var energy := 0.0
	for frame in frames:
		energy += (frame.x * frame.x + frame.y * frame.y) * 0.5
	return sqrt(energy / frames.size())

func tone_capture(allow_send: bool = true) -> void:
	# Stereo 48 kHz microphone-shaped samples exercise the actual resampler.
	var samples := PackedVector2Array()
	samples.resize(960)
	var frequency := 440.0 if role == "host" else 660.0
	for index in range(samples.size()):
		var sample := sin(TAU * frequency * float(tone_cursor) / 48000.0) * 0.24
		samples[index] = Vector2(sample, sample)
		tone_cursor += 1
	game.voice.ingest_capture(samples, 48000.0, allow_send)

func tones(count: int, take_screenshot: bool = false) -> void:
	for index in range(count):
		tone_capture()
		if take_screenshot and index == count - 5:
			await screenshot("voice_near_%s" % role)
		await pause(0.02)

func near_probe() -> void:
	var before := counters()
	output_capture.clear_buffer()
	await tones(72, true)
	await pause(0.1)
	var after := counters()
	measurements["near_before"] = before
	measurements["near_after"] = after
	measurements["near_output_rms"] = output_rms()
	measurements["received_decoded_rms"] = float(game.voice.received_rms.get(remote_peer, 0.0))
	check(int(after.captured) - int(before.captured) >= 60, "48 kHz stereo capture resamples into 16 kHz twenty-millisecond frames")
	check(int(after.network_sent) - int(before.network_sent) >= 60, "Synthetic speech uses the live ENet voice sender")
	check(int(after.received) - int(before.received) >= 30, "Nearby remote peer is heard through real two-process ENet")
	check(int(after.played) - int(before.played) >= 20, "Received voice passes through the bounded playback buffer")
	check(int(after.decoded_samples) - int(before.decoded_samples) >= 30 * 320, "Received mu-law frames decode into real float audio samples")
	check(float(measurements.received_decoded_rms) > 0.08, "Remote synthetic voice retains audible decoded energy")
	check(not game.voice.playback_streams.has(game.state.local_id()), "Local speech never creates a local echo stream")
	check(game.voice.playback_streams.has(remote_peer), "Remote speech creates an individual spatial speaker")
	if game.voice.playback_streams.has(remote_peer):
		var entry: Dictionary = game.voice.playback_streams[remote_peer]
		var speaker: Variant = entry.get("player")
		check(speaker is AudioStreamPlayer3D and speaker.stream is AudioStreamGenerator and is_equal_approx(speaker.stream.mix_rate, 16000.0), "Remote voice uses a 16 kHz AudioStreamGenerator on a 3D speaker")
	if DisplayServer.get_name() != "headless":
		check(float(measurements.near_output_rms) > 0.005, "Native audio bus contains synthetic voice after spatial speaker output")
	else:
		measurements["audio_output_note"] = "Headless driver: physical output RMS not asserted"
	var sent_before: int = game.state.voice_sent_packets
	game.state.send_voice(-1, PackedByteArray())
	var short_frame := PackedByteArray()
	short_frame.resize(319)
	game.state.send_voice(1, short_frame)
	check(game.state.voice_sent_packets == sent_before, "Malformed voice sequence and frame length do not enter the transport")

func blocked_capture_probe() -> void:
	var before: int = game.state.voice_sent_packets
	for index in range(6):
		tone_capture(false)
		await pause(0.02)
	check(game.state.voice_sent_packets == before, "Released push-to-talk gate discards captured microphone-shaped samples")
	test_settings["mic_muted"] = true
	game.voice.apply_settings(test_settings)
	for index in range(6):
		tone_capture()
		await pause(0.02)
	check(game.state.voice_sent_packets == before, "Muted microphone sends no synthetic capture packets")
	test_settings["mic_muted"] = false
	game.voice.apply_settings(test_settings)

func far_probe() -> void:
	await pause(0.35)
	var before := counters()
	output_capture.clear_buffer()
	await tones(24)
	await pause(0.15)
	var after := counters()
	measurements["far_before"] = before
	measurements["far_after"] = after
	measurements["far_output_rms"] = output_rms()
	check(int(after.network_sent) > int(before.network_sent), "Out-of-range speech still exercises authenticated sending")
	check(int(after.network_received) == int(before.network_received), "Server relays no speech between players more than twelve metres apart")
	check(int(after.played) == int(before.played), "Out-of-range speech produces no new playback frames")
	if DisplayServer.get_name() != "headless":
		check(float(measurements.far_output_rms) < 0.001, "Spatial output is silent when the other player leaves voice range")

func disable_listening() -> int:
	test_settings["voice_enabled"] = false
	game.voice.apply_settings(test_settings)
	check(game.voice.playback_streams.is_empty(), "Disabling voice immediately removes active remote speakers and queues")
	await pause(0.15)
	output_capture.clear_buffer()
	return int(game.voice.played_packets)

func check_disabled(played_before: int) -> void:
	await pause(0.12)
	check(game.voice.played_packets == played_before and game.voice.playback_streams.is_empty(), "Disabled listener ignores incoming speech without rebuilding a speaker")
	if DisplayServer.get_name() != "headless":
		check(output_rms() < 0.001, "Disabling voice stops buffered synthetic audio output")
	test_settings["voice_enabled"] = true
	game.voice.apply_settings(test_settings)

func resume_probe() -> void:
	var played_before: int = game.voice.played_packets
	output_capture.clear_buffer()
	await tones(24)
	await pause(0.12)
	check(game.voice.played_packets > played_before and game.voice.playback_streams.has(remote_peer), "Re-enabling voice restores live remote playback in the same session")
	var resumed_rms := output_rms()
	measurements["resumed_output_rms"] = resumed_rms
	if DisplayServer.get_name() != "headless":
		check(resumed_rms > 0.005, "Re-enabled spatial speaker resumes synthetic audio output")

func host_probe() -> void:
	game.start_session("solo", "", 24682, true)
	check(game.state.host(24682) == OK, "Synthetic voice host opens a native ENet socket on UDP 24682")
	await go(Vector3(0, 0.12, 7.2), -PI / 2.0)
	advance(1, "host_ready")
	if not await wait_for(func(): return game.state.players.size() >= 2 and peer_reached(1), 45.0):
		check(false, "Synthetic voice client joins the native host")
		return
	for id in game.state.players:
		if int(id) != game.state.local_id():
			remote_peer = int(id)
	check(remote_peer > 1, "Synthetic voice client has an authenticated remote peer ID")
	advance(2, "near_ready")
	check(await wait_for(func(): return peer_reached(2)), "Both processes enter the near-range voice phase")
	await near_probe()
	advance(3, "near_complete")
	check(await wait_for(func(): return peer_reached(3)), "Client completes its independent near-range audio checks")
	await blocked_capture_probe()
	advance(4, "far_ready")
	check(await wait_for(func(): return peer_reached(4)), "Client moves beyond the proximity-chat radius")
	await far_probe()
	advance(5, "far_complete")
	check(await wait_for(func(): return peer_reached(5)), "Client independently verifies far-range silence")
	advance(6, "near_returned")
	check(await wait_for(func(): return peer_reached(7)), "Client disables voice while the session remains connected")
	await tones(24)
	advance(8, "disabled_client_sent")
	check(await wait_for(func(): return peer_reached(8)), "Disabled client clears its playback queue")
	var played_before: int = await disable_listening()
	advance(9, "host_disabled")
	check(await wait_for(func(): return peer_reached(10)), "Client sends voice while the host listener is disabled")
	await check_disabled(played_before)
	advance(10, "host_reenabled")
	check(await wait_for(func(): return peer_reached(11)), "Client completes listener-disable checks")
	advance(11, "resume_ready")
	await resume_probe()
	advance(12, "voice_resumed")
	check(await wait_for(func(): return peer_reached(12)), "Client independently verifies resumed voice output")
	await screenshot("voice_settings_host", true)

func client_probe() -> void:
	if not await wait_for(func(): return peer_reached(1), 45.0):
		check(false, "Native voice host becomes ready")
		return
	game.start_session("join", "127.0.0.1", 24682, false)
	if not await wait_for(func(): return game.state.players.size() >= 2, 30.0):
		check(false, "Native voice client receives the host player snapshot")
		return
	remote_peer = 1
	await go(Vector3(2.0, 0.12, 7.2), PI / 2.0)
	advance(1, "client_joined")
	check(await wait_for(func(): return peer_reached(2)), "Native host synchronizes the near-range voice phase")
	advance(2, "near_ready")
	await near_probe()
	advance(3, "near_complete")
	check(await wait_for(func(): return peer_reached(3)), "Host independently completes near-range audio checks")
	await blocked_capture_probe()
	await go(Vector3(15.0, 0.12, 7.2), PI / 2.0)
	advance(4, "far_ready")
	check(await wait_for(func(): return peer_reached(4)), "Host synchronizes the far-range voice phase")
	await far_probe()
	advance(5, "far_complete")
	check(await wait_for(func(): return peer_reached(5)), "Host independently verifies far-range silence")
	await go(Vector3(2.0, 0.12, 7.2), PI / 2.0)
	advance(6, "near_returned")
	check(await wait_for(func(): return peer_reached(6)), "Both peers return within voice range")
	var played_before: int = await disable_listening()
	advance(7, "client_disabled")
	check(await wait_for(func(): return peer_reached(8)), "Host sends real network speech to a disabled listener")
	await check_disabled(played_before)
	advance(8, "client_reenabled")
	check(await wait_for(func(): return peer_reached(9)), "Host disables its own listener")
	await tones(24)
	advance(10, "disabled_host_sent")
	check(await wait_for(func(): return peer_reached(10)), "Host clears buffered output and re-enables voice")
	advance(11, "resume_ready")
	check(await wait_for(func(): return peer_reached(11)), "Host synchronizes the restored voice phase")
	await resume_probe()
	advance(12, "voice_resumed")
	check(await wait_for(func(): return peer_reached(12)), "Host independently verifies resumed voice output")
	await screenshot("voice_settings_client", true)
	await pause(0.25)

func screenshot(name: String, settings_view: bool = false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if settings_view:
		game.ui._show_settings()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	game.get_viewport().get_texture().get_image().save_png(report_dir.path_join(name + ".png"))
