extends Node

## Explicit QA entry only. HTTP fixture credentials are synthetic; never installs.
var game: Node
var updater: Node
var _fixture_url := "http://127.0.0.1:24788"
var _report_dir := "user://updater-verification"
var _checks: Array[Dictionary] = []
var _observed: Array[String] = []
var _saw_progress := false
var _control: HTTPRequest
var _live_cli := false

func begin(owner_game: Node,args: PackedStringArray) -> void:
	game=owner_game
	updater=game.updater
	for argument in args:
		if argument=="--verify-updater=cli":
			_live_cli=true
		elif argument.begins_with("--update-test-url="):
			_fixture_url=argument.trim_prefix("--update-test-url=").trim_suffix("/")
		elif argument.begins_with("--report-dir="):
			_report_dir=argument.trim_prefix("--report-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_report_dir))
	call_deferred("_run_cli" if _live_cli else "_run")

func _run_cli() -> void:
	updater.test_mode=true
	updater._cache=ProjectSettings.globalize_path("user://updates-live-verification")
	DirAccess.make_dir_recursive_absolute(updater._cache)
	updater.use_github_cli()
	_record("GitHub CLI is installed",not str(updater._gh_path).is_empty())
	var phase:=await _wait_done(100)
	_record("Private release access succeeds",phase in ["available","current"] and bool(updater.status.authenticated),"phase="+phase)
	if phase=="available":
		updater.download_update()
		_record("Private download starts without blocking the game",updater.status.phase=="downloading")
		phase=await _wait_done(600)
		_record("Live private release download verifies",phase=="ready","phase="+phase)
		if phase=="ready":
			_record("Live package digest matches GitHub manifest",FileAccess.get_sha256(updater.package_path)==str(updater.manifest.sha256))
			_record("Live package byte count matches",FileAccess.open(updater.package_path,FileAccess.READ).get_length()==int(updater.manifest.size))
	elif phase=="current":
		_record("Installed build cannot be downgraded",updater.manifest.is_empty() or int(updater.manifest.build)<=int(updater.installed.get("build",0)))
	_finish()

func _record(name: String,passed: bool,detail: String="") -> void:
	_checks.append({"name":name,"passed":passed,"detail":detail})
	if not passed:
		print("Updater verification failed: ",name," (",detail,")")

func _on_status(value: Dictionary) -> void:
	var phase: String=str(value.get("phase",""))
	_observed.append(phase)
	if phase=="downloading" and float(value.get("progress",0.0))>0 and float(value.get("progress",0.0))<1:
		_saw_progress=true

func _fetch_control(path: String) -> Dictionary:
	var error:=_control.request(_fixture_url+path)
	if error!=OK:
		return {}
	var response: Array=await _control.request_completed
	if int(response[0])!=HTTPRequest.RESULT_SUCCESS or int(response[1])!=200:
		return {}
	var parser:=JSON.new()
	if parser.parse((response[3] as PackedByteArray).get_string_from_utf8())!=OK or not parser.data is Dictionary:
		return {}
	return parser.data

func _wait_done(seconds: float=12.0) -> String:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while updater.busy() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	return str(updater.status.get("phase",""))

func _select_fixture(mode: String) -> void:
	if is_instance_valid(updater._http):
		updater._http.cancel_request()
	updater._mode="http"
	updater._api_base=_fixture_url+"/"+mode
	updater._session_token="synthetic-read-token-for-qa-only"
	updater.manifest={}
	updater.release={}
	updater.installed={"schema":1,"build":1,"version":"0.3.1"}
	updater.status.phase="idle"
	updater.status.authenticated=false
	updater.status.available_version=""
	updater.status.details=""
	_observed.clear()

func _check_fixture(mode: String,phase: String) -> bool:
	_select_fixture(mode)
	updater.check_for_updates()
	_record(mode+" starts checking",str(updater.status.phase)=="checking")
	var final_phase:=await _wait_done()
	_record(mode+" terminal status",final_phase==phase,"expected "+phase+", got "+final_phase)
	return final_phase==phase

func _capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":
		return
	game.ui.show_updates(updater.status)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(_report_dir).path_join(name+".png"))

func _run() -> void:
	if not _fixture_url.begins_with("http://127.0.0.1:"):
		_record("fixture is loopback only",false,"Refusing to send synthetic fixture requests outside loopback.")
		_finish()
		return
	updater.test_mode=true
	updater._cache=ProjectSettings.globalize_path("user://updates-verification")
	DirAccess.make_dir_recursive_absolute(updater._cache)
	updater.status_changed.connect(_on_status)
	_control=HTTPRequest.new()
	_control.timeout=5
	_control.max_redirects=0
	add_child(_control)
	var control:=await _fetch_control("/control/reset")
	_record("loopback fixture responds",bool(control.get("reset",false)))
	var initial_audit:=await _fetch_control("/control/audit")
	_record("loopback audit endpoint",initial_audit.has("requests"))
	if not initial_audit.has("requests"):
		_finish()
		return
	_record("loopback prohibited outside test mode",not updater.trusted_url(_fixture_url+"/good/releases/latest"))
	_record("loopback permitted in test mode",updater.trusted_url(_fixture_url+"/good/releases/latest",true))
	_record("GitHub API URL trusted",updater.trusted_url(updater.API+"/releases/latest"))
	_record("GitHub signed asset URL trusted",updater.trusted_url("https://release-assets.githubusercontent.com/asset/test"))
	for attack in ["http://api.github.com/repos/Outsourcedevv/diamond-in-the-rough/releases/latest","https://api.github.com.evil.test/releases/latest","https://api.github.com@evil.test/releases/latest","https://release-assets.githubusercontent.com.evil.test/asset/test"]:
		_record("untrusted URL rejected "+attack,not updater.trusted_url(attack))
	if await _check_fixture("good","available"):
		_record("available version from manifest",str(updater.status.available_version)=="0.3.2")
		_record("valid fixture manifest",updater.manifest_valid(updater.manifest))
		var valid: Dictionary=updater.manifest.duplicate(true)
		for mutation in [{"build":0},{"build":1.5},{"build":2147483648},{"sha256":"A".repeat(64)},{"commit":"not-a-commit"},{"size":updater.MAX_PACKAGE+1},{"asset":"../evil.zip"},{"executable":"evil.exe"},{"version":"0.3.2-preview"}]:
			var changed: Dictionary=valid.duplicate(true)
			changed.merge(mutation,true)
			_record("manifest field rejected "+str(mutation.keys()[0]),not updater.manifest_valid(changed))
		_record("missing manifest rejected",not updater.manifest_valid({}))
		await _capture("updates-available")
		_saw_progress=false
		updater.download_update()
		_record("download starts asynchronously",str(updater.status.phase)=="downloading")
		var final_phase:=await _wait_done(20)
		_record("verified download ready",final_phase=="ready","got "+final_phase)
		_record("download progress reported",_saw_progress)
		_record("download completed at full progress",float(updater.status.progress)==1.0)
		_record("downloaded archive exists",FileAccess.file_exists(updater.package_path))
		_record("download SHA256 matches manifest",FileAccess.get_sha256(updater.package_path)==str(updater.manifest.sha256))
		await _capture("updates-ready")
		if OS.has_feature("editor"):
			var install_pid: int=updater.prepare_install()
			_record("editor install safely rejected",install_pid<0 and str(updater.status.phase)=="error")
	await _check_fixture("downgrade","current")
	updater.download_update()
	_record("same or older build cannot download",str(updater.status.phase)=="current")
	await _check_fixture("bad-manifest","error")
	_record("bad manifest not accepted",updater.manifest.is_empty())
	await _check_fixture("digest-mismatch","error")
	_record("GitHub asset digest mismatch rejected",updater.manifest.is_empty())
	if await _check_fixture("bad-hash","available"):
		updater.download_update()
		var final_phase:=await _wait_done(20)
		_record("corrupted ZIP checksum rejected",final_phase=="error","got "+final_phase)
		_record("corrupted ZIP cannot be installed",updater.prepare_install()<0)
	await _check_fixture("unauth","auth_required")
	_record("401 does not authenticate",not bool(updater.status.authenticated))
	await _capture("updates-auth-required")
	await _check_fixture("hostile-redirect","error")
	_record("off-host token headers empty",not "Authorization:" in "\n".join(updater._headers("https://objects.githubusercontent.com/signed-asset",true)))
	await _check_fixture("redirect-safe","available")
	var audit:=await _fetch_control("/control/audit")
	var outside_count:=0
	var leaked:=false
	var api_authorized:=false
	var hostile_followed:=false
	for entry in audit.get("requests",[]):
		var path: String=str(entry.get("path",""))
		if path=="/off-api/release":
			outside_count+=1
			if bool(entry.get("authorized",false)): leaked=true
		if path=="/good/releases/latest" and bool(entry.get("authorized",false)): api_authorized=true
		if path=="/leak": hostile_followed=true
	_record("synthetic credential scoped to configured API",api_authorized)
	_record("trusted off-API redirect completed",outside_count==1)
	_record("authorization not forwarded to off-API redirect",not leaked)
	_record("hostile redirect never requested",not hostile_followed)
	_finish()

func _finish() -> void:
	var failed:=0
	for check in _checks:
		if not bool(check.passed): failed+=1
	var report: Dictionary={"feature":"in-game updater","test":"private GitHub CLI release integration" if _live_cli else "native loopback HTTP fixture","checks":_checks,"passed":_checks.size()-failed,"failed":failed,"total":_checks.size(),"physical_install":false,"notes":"No credentials recorded. This test never launches the installer.","package_path":updater.package_path if _live_cli else "","manifest":updater.manifest if _live_cli else {}}
	var file:=FileAccess.open(ProjectSettings.globalize_path(_report_dir).path_join("updater_report.json"),FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print("Updater verification: %d checks, %d failures" % [_checks.size(),failed])
	if is_instance_valid(updater._http): updater._http.cancel_request()
	updater._session_token=""
	get_tree().quit(1 if failed>0 else 0)
