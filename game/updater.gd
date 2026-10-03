extends Node

## Private GitHub releases: CLI keeps its credentials; optional tokens stay in RAM.
signal status_changed(status: Dictionary)
const REPOSITORY := "Outsourcedevv/diamond-in-the-rough"
const API := "https://api.github.com/repos/" + REPOSITORY
const REPO_URL := "https://github.com/" + REPOSITORY
const ASSET := "DIAMOND_IN_THE_ROUGH_Update.zip"
const MAX_PACKAGE := 160 * 1024 * 1024
const CHECK_INTERVAL := 300.0

var game: Node
var test_mode := false
var status := {"phase":"idle","message":"Check for a new workshop build.","installed_version":"0.3.0","available_version":"","progress":0.0,"authenticated":false,"details":""}
var installed := {"schema":1,"build":0,"version":"0.3.0"}
var manifest: Dictionary = {}
var release: Dictionary = {}
var package_path := ""
var _gh_path := ""
var _mode := "http"
var _session_token := ""
var _api_base := API
var _cli: Dictionary = {}
var _cli_stage := ""
var _cli_output := PackedByteArray()
var _cli_started := 0
var _http: HTTPRequest
var _http_stage := ""
var _http_url := ""
var _http_file := ""
var _redirects := 0
var _cache := ""
var _elapsed := 0.0
var _progress_tick := 0.0
var _notified_build := -1

func build(owner_game: Node) -> void:
	game=owner_game
	name="GameUpdater"
	installed=read_json("res://build.json",32768)
	if installed.is_empty(): installed={"schema":1,"build":0,"version":"0.3.0"}
	status.installed_version=str(installed.get("version","0.3.0"))
	_cache=ProjectSettings.globalize_path("user://updates")
	DirAccess.make_dir_recursive_absolute(_cache)
	_gh_path=find_github_cli()
	_mode="cli" if not _gh_path.is_empty() else "http"
	_http=HTTPRequest.new()
	_http.use_threads=true
	_http.timeout=45
	_http.max_redirects=0
	add_child(_http)
	_http.request_completed.connect(_http_finished)
	var result:=read_json(_cache.path_join("install_result.json"),32768)
	if not result.is_empty():
		if bool(result.get("success",false)):
			status.message="Update installed. Your workshop save is ready."
		else:
			status.phase="error"
			status.message="The last update did not install. The previous build was kept."
		# Clear only our one-shot result after reading it.
		DirAccess.remove_absolute(_cache.path_join("install_result.json"))
	_emit()
	if not test_mode:
		get_tree().create_timer(4).timeout.connect(func():
			if bool(game.settings.get("auto_updates",true)): check_for_updates()
		)

func find_github_cli() -> String:
	if OS.get_name()!="Windows": return ""
	var candidates: Array[String]=[]
	for key in ["ProgramFiles","ProgramFiles(x86)","LOCALAPPDATA"]:
		var root:=OS.get_environment(key)
		if not root.is_empty(): candidates.append(root.path_join("GitHub CLI/gh.exe"))
	for directory in OS.get_environment("PATH").split(";"):
		candidates.append(directory.strip_edges().trim_prefix('"').trim_suffix('"').path_join("gh.exe"))
	for candidate in candidates:
		if FileAccess.file_exists(candidate): return candidate
	return ""

func _process(delta: float) -> void:
	_elapsed+=delta
	if _elapsed>=CHECK_INTERVAL and not test_mode:
		_elapsed=0
		if bool(game.settings.get("auto_updates",true)) and not busy(): check_for_updates()
	if not _cli.is_empty(): _poll_cli()
	_progress_tick+=delta
	if status.phase=="downloading" and _progress_tick>=0.3:
		_progress_tick=0
		var total: float=float(manifest.get("size",0))
		var bytes:=0.0
		if _mode=="http": bytes=float(_http.get_downloaded_bytes())
		elif FileAccess.file_exists(package_path):
			var file:=FileAccess.open(package_path,FileAccess.READ)
			if file: bytes=float(file.get_length())
		status.progress=clampf(bytes/maxf(total,1),0,0.99)
		_emit()

func busy() -> bool:
	return status.phase in ["checking","downloading","installing"]

func get_status() -> Dictionary:
	return status.duplicate(true)

func _status(phase: String,message: String) -> void:
	status.phase=phase
	status.message=message
	if phase=="auth_required": status.authenticated=false
	_emit()

func _emit() -> void:
	status_changed.emit(status.duplicate(true))

func use_github_cli() -> void:
	if busy(): return
	_gh_path=find_github_cli()
	_session_token=""
	if _gh_path.is_empty():
		_status("auth_required","GitHub CLI was not found. Sign in with GitHub CLI, or use a read-only token below.")
		return
	_mode="cli"
	check_for_updates()

func set_session_token(token: String) -> void:
	if busy(): return
	var clean:=token.strip_edges()
	if clean.is_empty() or clean.length()>512 or "\n" in clean or "\r" in clean:
		_status("auth_required","Enter a valid token with Contents read access to this repository.")
		return
	_session_token=clean
	_mode="http"
	check_for_updates()

func check_for_updates() -> void:
	if busy(): return
	_elapsed=0
	manifest.clear()
	release.clear()
	status.available_version=""
	status.progress=0.0
	_status("checking","Checking GitHub for a completed Windows build…")
	if _mode=="cli":
		_start_cli(["api","repos/"+REPOSITORY+"/releases/latest","--hostname","github.com"],"release")
	else:
		_request(_api_base+"/releases/latest","release")

func _start_cli(arguments: PackedStringArray,stage: String) -> void:
	_cli_stage=stage
	_cli_output.clear()
	_cli_started=Time.get_ticks_msec()
	_cli=OS.execute_with_pipe(_gh_path,arguments,false)
	if _cli.is_empty():
		_status("error","Could not start GitHub CLI. Try checking again.")

func _poll_cli() -> void:
	var output: FileAccess=_cli.stdio
	var errors: FileAccess=_cli.stderr
	_cli_output.append_array(output.get_buffer(65536))
	errors.get_buffer(65536) # Discard diagnostics; credentials never enter UI/logs.
	var pid: int=int(_cli.pid)
	var limit: int=600000 if _cli_stage=="package" else 90000
	if _cli_output.size()>1048576 or Time.get_ticks_msec()-_cli_started>limit:
		_stop_cli()
		_status("error","GitHub did not complete the request in time. Try again later.")
		return
	if OS.is_process_running(pid): return
	_cli_output.append_array(output.get_buffer(65536))
	var result:={"code":OS.get_process_exit_code(pid),"content":_cli_output.get_string_from_utf8()}
	var stage:=_cli_stage
	output.close()
	errors.close()
	_cli.clear()
	_cli_output.clear()
	_cli_stage=""
	_cli_finished(stage,result)

func _stop_cli() -> void:
	if _cli.is_empty(): return
	var pid: int=int(_cli.pid)
	if OS.is_process_running(pid): OS.kill(pid)
	_cli.stdio.close()
	_cli.stderr.close()
	_cli.clear()
	_cli_output.clear()
	_cli_stage=""

func _cli_finished(stage: String,result: Dictionary) -> void:
	if int(result.code)!=0:
		_status("auth_required" if stage=="release" else "error","GitHub access failed. Sign in with GitHub CLI and ensure this account can read the private repository." if stage=="release" else "The download failed. Check your connection and try again.")
		return
	if stage=="release":
		var parser:=JSON.new()
		if parser.parse(str(result.content))!=OK or not parser.data is Dictionary:
			_status("error","GitHub returned an unreadable release. Try again later.")
			return
		_accept_release(parser.data)
	elif stage=="manifest":
		_accept_manifest(read_json(_cache.path_join("metadata/latest.json"),32768))
	elif stage=="package":
		_verify_package()

func _headers(url: String,asset: bool) -> PackedStringArray:
	var headers:=PackedStringArray(["User-Agent: DiamondInTheRough-Updater","Accept: application/octet-stream" if asset else "Accept: application/vnd.github+json"])
	if url.begins_with(API+"/") or (test_mode and url.begins_with(_api_base+"/")):
		headers.append("X-GitHub-Api-Version: 2026-03-10")
		if not _session_token.is_empty(): headers.append("Authorization: Bearer "+_session_token)
	return headers

func _request(url: String,stage: String,path: String="",redirect: bool=false) -> void:
	if not trusted_url(url,test_mode):
		_status("error","The update download address was rejected.")
		return
	if not redirect: _redirects=0
	_http_stage=stage
	_http_url=url
	_http_file=path
	_http.download_file=path
	_http.body_size_limit=int(manifest.get("size",MAX_PACKAGE)) if stage=="package" else 1048576
	var error:=_http.request(url,_headers(url,stage!="release"))
	if error!=OK: _status("error","Could not start the update request. Try again.")

static func trusted_url(url: String,allow_local: bool=false) -> bool:
	if allow_local and url.begins_with("http://127.0.0.1:"): return true
	if url.begins_with(API+"/"): return true
	# Signed asset redirects are fetched without Authorization headers.
	return url.begins_with("https://release-assets.githubusercontent.com/") or url.begins_with("https://objects.githubusercontent.com/")

func _http_finished(result: int,code: int,headers: PackedStringArray,body: PackedByteArray) -> void:
	var stage:=_http_stage
	if code in [301,302,303,307,308]:
		var location:=""
		for header in headers:
			if header.to_lower().begins_with("location:"): location=header.substr(9).strip_edges()
		_redirects+=1
		if _redirects>3 or location.is_empty() or not trusted_url(location,test_mode):
			_status("error","GitHub redirected the download to an unsupported address.")
			return
		_request(location,stage,_http_file,true)
		return
	if code in [401,403,404] and stage=="release":
		_status("auth_required","This repository is private. Use your GitHub CLI sign-in or a read-only token for this session.")
		return
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		_status("error","The update request failed. Your installed game is unchanged; try again later.")
		return
	if stage=="package":
		_verify_package()
		return
	var data: Dictionary={}
	if stage=="manifest": data=read_json(_http_file,32768)
	else:
		var parser:=JSON.new()
		if parser.parse(body.get_string_from_utf8())==OK and parser.data is Dictionary: data=parser.data
	if stage=="release": _accept_release(data)
	else: _accept_manifest(data)

func _accept_release(data: Dictionary) -> void:
	if data.is_empty() or bool(data.get("draft",true)) or bool(data.get("prerelease",true)) or not data.get("assets") is Array or not regex_match("^[A-Za-z0-9._-]{1,100}$",str(data.get("tag_name",""))):
		_status("error","GitHub has not returned a completed update release.")
		return
	release=data
	status.authenticated=true
	status.details=str(data.get("body","")).left(2400)
	var metadata:=asset_info("latest.json")
	if metadata.is_empty():
		_status("current","The latest release has no updater package yet. Check again after the next successful build.")
		return
	if int(metadata.get("size",0))<1 or int(metadata.get("size",0))>32768:
		_status("error","The update manifest size is invalid.")
		return
	DirAccess.make_dir_recursive_absolute(_cache.path_join("metadata"))
	if _mode=="cli":
		_start_cli(["release","download",str(release.tag_name),"--repo",REPOSITORY,"--pattern","latest.json","--dir",_cache.path_join("metadata"),"--clobber"],"manifest")
	else:
		_request(asset_api_url(metadata),"manifest",_cache.path_join("metadata/latest.json"))

func asset_info(asset_name: String) -> Dictionary:
	for entry in release.get("assets",[]):
		if entry is Dictionary and str(entry.get("name",""))==asset_name and str(entry.get("state",""))=="uploaded" and int(entry.get("id",0))>0:
			return entry
	return {}

func asset_api_url(asset: Dictionary) -> String:
	return _api_base+"/releases/assets/"+str(int(asset.get("id",0)))

static func regex_match(pattern: String,value: String) -> bool:
	var regex:=RegEx.new()
	return regex.compile(pattern)==OK and regex.search(value)!=null

static func manifest_valid(data: Dictionary) -> bool:
	return int(data.get("schema",0))==1 and float(data.get("build",0))==int(data.get("build",0)) and int(data.get("build",0))>0 and int(data.get("build",0))<=2147483647 and str(data.get("asset",""))==ASSET and str(data.get("executable",""))=="DiamondInTheRough.exe" and regex_match("^[0-9a-f]{64}$",str(data.get("sha256",""))) and regex_match("^[0-9a-f]{40}$",str(data.get("commit",""))) and regex_match("^[0-9]+\\.[0-9]+\\.[0-9]+$",str(data.get("version",""))) and int(data.get("size",0))>0 and int(data.get("size",0))<=MAX_PACKAGE

func _accept_manifest(data: Dictionary) -> void:
	var asset:=asset_info(ASSET)
	if not manifest_valid(data) or asset.is_empty() or int(asset.get("size",0))!=int(data.get("size",0)):
		_status("error","The release package or checksum manifest is invalid. Nothing was installed.")
		return
	var server_digest: String=str(asset.digest) if asset.get("digest") is String else ""
	if not server_digest.is_empty() and server_digest!="sha256:"+str(data.sha256):
		_status("error","The release checksums disagree. Nothing was installed.")
		return
	manifest=data
	if int(manifest.build)<=int(installed.get("build",0)):
		status.available_version=""
		_status("current","You have the newest available build.")
		return
	status.available_version=str(manifest.version)
	_status("available","A new workshop build is ready to download.")
	if int(manifest.build)!=_notified_build:
		_notified_build=int(manifest.build)
		if game.ui.has_method("toast"): game.ui.toast("Update available · Esc → Updates")

func download_update() -> void:
	if busy() or manifest.is_empty() or int(manifest.build)<=int(installed.get("build",0)): return
	var directory:=_cache.path_join("build-"+str(int(manifest.build)))
	DirAccess.make_dir_recursive_absolute(directory)
	package_path=directory.path_join(ASSET)
	status.progress=0.0
	_status("downloading","Downloading the new build. You can keep sorting while it downloads.")
	if _mode=="cli":
		_start_cli(["release","download",str(release.tag_name),"--repo",REPOSITORY,"--pattern",ASSET,"--dir",directory,"--clobber"],"package")
	else:
		_request(asset_api_url(asset_info(ASSET)),"package",package_path)

func _verify_package() -> void:
	if not FileAccess.file_exists(package_path):
		_status("error","The downloaded update file is missing. Download it again.")
		return
	var file:=FileAccess.open(package_path,FileAccess.READ)
	if not file or file.get_length()!=int(manifest.size):
		_status("error","The update download is incomplete. Download it again.")
		return
	file.close()
	if FileAccess.get_sha256(package_path)!=str(manifest.sha256):
		_status("error","The update checksum failed. The current game was kept; download again.")
		return
	status.progress=1.0
	_status("ready","Download verified. Save and install when you are ready to restart.")

func prepare_install() -> int:
	if status.phase!="ready" or manifest.is_empty(): return -1
	if OS.get_name()!="Windows" or OS.has_feature("editor") or OS.get_executable_path().get_file().to_lower()!="diamondintherough.exe":
		_status("error","Install updates from the exported Windows game. Editor projects update through Git.")
		return -1
	# Recheck the package immediately before starting the helper.
	_verify_package()
	if status.phase!="ready": return -1
	var source:=FileAccess.open("res://updater/InstallUpdate.ps1",FileAccess.READ)
	if not source:
		_status("error","The installer helper is missing. Download the latest build from GitHub.")
		return -1
	var helper_path:=_cache.path_join("InstallUpdate.ps1")
	var helper:=FileAccess.open(helper_path,FileAccess.WRITE)
	if not helper:
		_status("error","Could not write the updater helper. Check the game data folder permissions.")
		return -1
	helper.store_buffer(source.get_buffer(source.get_length()))
	helper.close()
	var powershell:=OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var arguments:=PackedStringArray(["-NoProfile","-NonInteractive","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File",helper_path,"-InstallDir",OS.get_executable_path().get_base_dir(),"-PackagePath",package_path,"-ExpectedSha256",str(manifest.sha256),"-ExpectedBuild",str(int(manifest.build)),"-GamePid",str(OS.get_process_id()),"-ResultPath",_cache.path_join("install_result.json")])
	var pid:=OS.create_process(powershell,arguments,false)
	if pid<0:
		_status("error","Windows could not start the updater. The current game is unchanged.")
		return -1
	_status("installing","Saving and restarting to install the new build…")
	return pid

func open_repository() -> void:
	OS.shell_open(REPO_URL+"/releases/latest")

static func read_json(path: String,limit: int) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if not file or file.get_length()>limit: return {}
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary: return {}
	return parser.data

func _exit_tree() -> void:
	if _http: _http.cancel_request()
	_session_token=""
	_stop_cli()
