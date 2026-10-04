# DIAMOND IN THE ROUGH — prototype source

Open `project.godot` with Godot 4.6.2. The project uses native Godot 3D rendering and ENet. There is no browser runtime, HTML renderer, or web wrapper. Export the Windows Desktop preset with the matching Windows export templates installed. The executable embeds its game data.

`mountain.gd` defines the mountain: a fixed 72 × 42 × 64 grid of 1 m cells in front of the camp. Its smooth heightmap is deterministic (fixed noise seeds, three peaks with ridged noise, a slope limit that keeps the foothills walkable but lets the upper slopes steepen into cliffs, a light blur, and a taper before the grid border). Cells are solid below the rounded height. Layers, hardness and ore veins derive from each cell's depth below the natural surface; ore veins are hashed from the world seed in 3×3×3 regions, so they cost nothing to store. Cell codes live in one `PackedByteArray`; mined cells are a bitset.

`mountain_view.gd` draws the cells as one smooth surface in 12³ chunks using surface nets over a density field: natural ground follows the smooth height (scaled by slope so steep faces do not band), mined cells are empty, and the field continues below the valley floor so the foot blends into the ground. Matching `ConcavePolygonShape3D` collision is built from the same triangles. Chunk surfaces are computed on a `WorkerThreadPool` task from a copy of the cells and applied on the main thread; mining marks only the touched chunks dirty. A local session flushes synchronously so collision exists before play starts. A spatial shader draws layered rock by depth, grass only on gentle lower ground, snow on high flats and the summit, and ore flecks whose colour and style (dull, metallic or glinting) travel in vertex colour and UV channels. Mining targets the nearest exposed solid cell behind the ray hit; loose finds are drawn on the smooth surface. `main.gd` handles hold-to-mine with progress in the prompt and rock chips, thrown explosive bodies and their fuses, explosion effects, auto-pickup, finds, paged tray contents, held objects and remote avatars. `workshop.gd` builds the camp, scenery, outfitter displays and explosive models. `player.gd` provides first-person movement, tools, close rotation and zoom. `interface.gd` supplies the compact HUD and scrolling settings/journal dialogs. `sound.gd` synthesizes the prototype sounds.

Physical equipment bodies carry an upgrade ID. A first-person interaction submits the authoritative purchase command; `state.gd` checks proximity to that display, price and ownership. Station labels and product name/price cards sit on fixed depth-tested signboards.

`tutorial.gd` observes actual movement, inspection and authoritative world changes: satchel increases, sales, the steel pickaxe purchase, finds that came loose from the mountain, and tray storage. First-session guidance is local to the solo player or host, and completion/skip preferences live separately from the shared world save. How to play can replay it. Native UI layout uses the current window dimensions, anchored panels and scrolling dialogs; text is rendered at its own aspect ratio.

`state.gd` owns the world. A new save chooses a seed, one diamond cell deep in the core (at least 14 blocks below the surface) and 219 other buried finds: 149 look-alike crystals plus fossils and curiosities. Each find has one stage (buried, loose, held, tray, collection, certified or sold) and at most one owner. Mining commands validate reach, exposure, tool tier (granite needs the steel pickaxe or drill), satchel space and accumulated hit damage before a block breaks. Ore goes to the miner's satchel (stored per player); finds become loose and settle onto the highest solid block beneath them, and settle again if that support is mined away. Explosives are two commands: `throw` (equipment, per-player preparation time, reach) assigns a fuse ID that every peer animates, and `blast` from the thrower detonates that fuse once, clearing every non-bedrock cell in the tier's radius. Clear crystals cannot become sold material. Certification requires three ordered tests on the same held candidate. Save files use JSON (schema 2) with the mined bitset in base64, temporary replacement and backup recovery. Earlier schema-1 scree saves are not loaded; they start a fresh mountain.

The ENet server accepts three clients plus its local player. Purchases, sales and other shared transactions send compressed reliable full snapshots. Frequent changes — broken blocks, satchels, picked-up or dropped finds — travel as small reliable deltas, and their saves are batched every few seconds. Clients diff the mined bitset in each full snapshot and rebuild only changed chunks. A separate unreliable ordered channel carries player poses. ENet's unreliable-packet throttle is held open on every co-op link, so a brief hitch on one machine does not silence voice for seconds. Clients do not save the host's world over their local save. A production version should still add stable account IDs, version negotiation, stronger transport-level abuse controls and reconnect handling.

`voice.gd` supplies proximity voice. Hold V to talk in active co-op; M toggles microphone mute. Voice defaults to enabled push-to-talk and does not transmit in solo play or menus. Settings provides voice enable, microphone mute, input-device selection/refresh, microphone gain and received voice volume. The microphone is not monitored through local speakers. Audio and transport queues remain in memory; no voice recordings or microphone data are written to saves. All peers in a session should use the same build.

Capture uses a muted Godot input bus and `AudioEffectCapture`, filters/downmixes stereo input and resamples to 16 kHz mono. Samples use G.711 mu-law companding in 320-byte, 20-millisecond frames. Voice RPCs travel on ENet unreliable channel 2, independently of item transactions and poses. The host derives the sender from the RPC peer ID, accepts registered players only, validates fixed frame length and sequence bounds, rejects duplicate/stale sequences, and limits each sender to 60 packets per second with a six-packet burst. Host relaying uses registered player positions and a 12-metre range. Each receiver also checks range before queuing playback.

Playback uses bounded per-speaker jitter queues and `AudioStreamGenerator` output through `AudioStreamPlayer3D`. Speech has full gain through 2 metres, fades continuously after that, and is silent at 12 metres or beyond. Playback follows the remote avatar; nearby activity is shown above its hat and local transmission appears on the HUD. Released push-to-talk and microphone mute clear input buffers. Voice disable also clears remote playback, and disconnect/session changes discard the affected voice state. Production Opus, echo cancellation, Steam voice and Steam networking are not implemented.

Steamworks is not integrated. Adding Steam invites requires a Steam App ID, the SDK and credentials/configuration, and a Steam networking/lobby adapter. Achievements should hook into successful authoritative purchases, blasts, collection milestones and certification. The command/state boundary supports replacing direct IP session discovery without rewriting the mining rules.

The prototype uses generated geometry, generated sound effects and short animated prank reactions. Rock has no structural physics (no cave-ins) and explosions do not damage players. Full ragdolls, asset-driven hand animations, matchmaking and Steam services remain future work. Client cosmetics are session-based; the host's local cosmetics are saved. No Steam release readiness is claimed.

## Reproduce integration verification

Run the executable with an isolated report directory. The verification harness performs actual game commands with an isolated save; it never replaces the normal save. It earns every purchase from ore it actually mines, buys all nine tools, blasts craters with each explosive, digs the diamond out of the core and certifies it.

```powershell
.\build\DiamondInTheRough.exe -- --verify=solo --report-dir=C:/temp/rough-solo
```

For the exported host/client test, start two separate processes with the same fresh report directory:

```powershell
.\build\DiamondInTheRough.exe -- --verify=host --report-dir=C:/temp/rough-coop
.\build\DiamondInTheRough.exe -- --verify=client --report-dir=C:/temp/rough-coop
```

The harness uses localhost UDP 24681. It writes JSON reports and rendered screenshots, then exits with code 0 when all checks pass. Coordination files only order the test steps; gameplay state and actions travel through the actual ENet connection. Use a new empty report directory for each run so prior completion files do not advance the next test prematurely.

## Reproduce proximity voice verification

Start two native executable instances with the same new, empty report directory. Run the host first and the client in a second terminal while the host remains open:

```powershell
.\build\DiamondInTheRough.exe -- --verify-voice=host --report-dir=C:/temp/rough-voice
.\build\DiamondInTheRough.exe -- --verify-voice=client --report-dir=C:/temp/rough-voice
```

This harness uses localhost UDP 24682 and an isolated test save. It generates synthetic stereo 48 kHz tones and sends them through the actual capture resampler, mu-law encoder, native ENet connection, spatial voice playback and an output measurement bus. It never opens or records a physical microphone and does not save test preferences to the normal settings file. The tests cover codec behavior, bidirectional voice, distance fading/cutoff, push-to-talk and mute gates, listener disable/re-enable and session cleanup. Read `voice_host_report.json` and `voice_client_report.json` for checks, errors, measurements and completion state; rendered screenshots are written alongside them. Each process exits with code 0 only if its checks pass. Use a fresh report directory for every run.

Physical microphone selection, Windows desktop-app microphone access and subjective speech quality still require a manual co-op check with headphones. If no input signal appears while holding V in active co-op, select the intended input device in Settings and check Windows microphone privacy settings.

The production launch options also accept `--solo`, `--host`, `--join=IP`, `--port=24680`, and `--save-slot=NAME` after `--`.

## Windows update pipeline

`game/updater.gd` checks authenticated GitHub releases, validates build metadata and downloads the fixed update asset. GitHub CLI uses nonblocking pipes so the game remains responsive; its credentials stay with CLI. Optional session tokens use HTTPS only for the repository API, and signed asset redirects receive no Authorization header. Both paths verify the same package SHA-256 and size.

`updater/InstallUpdate.ps1` is embedded in the PCK and extracted into the user update cache for an installation. It waits for the game to exit, validates and stages the two fixed files in the installation directory, preserves backups, replaces them atomically, restarts and rolls back on basic startup failure. `state.save_game()` returns success so installation stops if a solo/host save fails.

`.github/workflows/windows-release.yml` and `tools/` build and publish on main pushes. The build stamps `build.json` before export; the publishing job exposes the release only after the package and manifest have uploaded. Headless CI runs the full progression harness and the tutorial/physical-purchase/screen-layout harness. Mouse capture is checked in native-window verification; the headless tutorial test drives look/rotation directly because it has no captured pointer.

Run the tutorial and layout harness with `-- --verify-redesign --report-dir=C:/temp/rough-redesign`. It uses a separate save and tutorial preference file. A native-window run also writes screenshots at several aspect ratios.

See [docs/UPDATING.md](docs/UPDATING.md) for the release schema, private access and live verification command.
