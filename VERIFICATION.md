# Windows game verification

## Big mountain update

Verified on 4 October 2026 with the official Godot 4.6.2 Linux editor binary, headless and in a native OpenGL window (Mesa software rendering under a virtual display). The release workflow reruns the solo and tutorial suites on the exported Windows executable before it publishes, and now requires 78 and 101 checks.

The mountain grid grew from 72 × 42 × 64 to 144 × 72 × 128 cells. The generated mountain rises 70 m and holds 227,917 rock cells, about eight times as many as before, with 40,391 ore cells across fourteen ore kinds. The 149 look-alike clear crystals are gone, along with the CERTIFIED DIAMOND label prank. The diamond is the only crystal block and the only crystal find; the other 180 finds are fossils and curios. A new world builds in about one second on this four-core machine, because chunk surfaces now build on every core instead of one.

The solo progression suite passed **78 checks** headless and in the rendered window. New checks confirm:

- No fake diamonds are generated, and only the diamond's block glitters.
- The diamond lies at least 28 m deep (40 m in the tested world).
- All fourteen ore kinds occur.
- The assay loupe pays 25% more for ore.
- The treasure sonar pings fossils, and the diamond through 12 m of rock, but not from 30 m away.
- The bench refuses a fossil.
- Bringing the diamond to the bench certifies it in one step, with the $1,000 grant.

The tutorial and layout suite passed **101 checks**, including 33 collision probes spread across the larger footprint. Their tolerance is now 0.75 m: across all 11,192 mountain columns the largest gap between the collision surface and the smooth height was 0.68 m, on sharp ridge crests.

The native co-op suite passed **25 host and 20 client checks**, the proximity voice pair **42 host and 41 client checks**, and the loopback HTTP updater suite **56 checks**.

A save from the previous build is not loaded. It is copied to `<save>.v2.old`, and a fresh claim starts with a message explaining that the mountain has grown. A client refuses a host snapshot from a different save schema.

The screenshots in `screenshots/` of the camp, the overview, dynamite, a Mountain Buster crater and the diamond under inspection were rendered from this build and reviewed. Windows rendering performance on the larger mountain and internet co-op remain unverified.

## Mining update (previous build)

Verified on 3 October 2026 with the official Godot 4.6.2 Linux editor binary, headless and in a native OpenGL window (Mesa software rendering under a virtual display). The Windows export was not rebuilt for this update; the release workflow runs the solo and tutorial suites on the exported Windows executable before it publishes.

The mountain is now drawn as one smooth rock surface (grassy foothills, rocky cliffs, snowy summit) over the same diggable 1 m cells. All suites were rerun after that change.

The solo progression suite passed **74 checks** headless and in the rendered window. It covers a mountain of 28,838 cells rising 39 m, with 3,857 ore cells; one diamond buried at least 14 m deep behind an ordinary crystal-vein cell; the summit's collision height; WASD movement; breaking ore by swinging through the real crosshair path; granite refusing the old pickaxe and yielding to the steel pickaxe; all nine physical purchases funded only by mined ore; dynamite, TNT and Mountain Buster craters; bedrock surviving explosions; crystal sonar; released finds resting on solid rock; the ore magnet; blasting the diamond free intact; protection from sale; drop and Lost & Found recovery; a full satchel refusing ore; save/reload of money, equipment, the diamond and every mined block; and the three-test certification ending surviving save/load.

The tutorial and layout suite passed **96 checks**. It probes 28 mountain columns for solid collision at their natural heights, climbs the slope with real WASD and jump input, and follows all seven tutorial steps through real mining, selling, a physical purchase, digging a find out of a shaft, inspection and tray storage. Rejected or out-of-reach commands, taking finds back out of the tray, replays with full hands, a dug-out existing save, skip/replay persistence, joined sessions and title/pause/settings/HUD layouts at five screen shapes are covered.

The native co-op suite passed **25 host and 20 client checks** across two processes on a real localhost ENet connection: the joining client receives every block the host had mined; remote mining breaks blocks through the host and fills the client's own satchel; a client buys and throws dynamite and both processes agree on every blasted block; released finds are picked up and handed between players; shared purchases spend once; pranks synchronize; and a disconnect returns the client's held finds to the tray and sells its satchel ore into shared funds.

The proximity voice pair still passes **42 host and 41 client checks**, the same as before this update, and the loopback HTTP updater suite still passes **56 checks**. With two game processes sharing four cores, the joining client's mountain build briefly slowed its acknowledgements and ENet's unreliable throttle on the host dropped most of the client's voice; the throttle is now held open on co-op links and the voice pair passed four consecutive runs.

Rendered screenshots of the camp, mining, dynamite, a Mountain Buster crater, the outfitter and inspection were reviewed; the current ones are in `screenshots/`. Physical microphone hardware, Windows rendering performance with large blasts and internet co-op remain unverified for this update.

## Scree mountain redesign (previous build)

Verified on 3 October 2026 with Godot 4.6.2, including the exported Windows x64 executable and native OpenGL rendering on this machine's AMD Radeon graphics.

The current solo progression suite passed **55 headless checks**, covering all eight physical purchase displays, real ray interactions, normal earnings, equipment and machinery, protected diamond ownership, certification, storage and save reload. Purchase interactions keep the first-person view active without opening a buying menu. Existing saves retain their diamond identity, funds and upgrades while pile objects move onto the new terrain.

The redesigned gameplay suite passed **76 checks** in both headless and native exported runs. Top-down collision rays hit the correct surface in all twelve scree sectors, and actual movement climbs the continuous slope. Tests follow the seven tutorial steps through real movement, successful scooping or individual pickup, object rotation, ordinary sales, a physical purchase and safe storage. Rejected actions and stale notices cannot advance the guide. Replay, skip, local persistence and joined-session behavior are covered. Full hands receive safe-storage directions; an exhausted existing save receives useful stored-find guidance without resetting the world or granting items or money.

The native co-op suite passed **26 host and 12 client checks** using two processes with a real localhost ENet connection. It covers synchronized positions, avatars, item ownership, shared physical purchases, machinery, pranks and disconnect recovery.

An independent UI run passed **278 layout checks** at 800×600, 1024×768, 1280×720, 1280×1024, 1920×1080, 2560×1080 and 3440×1440. The integrated gameplay suite also checks title, pause, settings and tutorial bounds and overlaps at five screen shapes. Native screenshots were reviewed for readable text, title/button separation, physical price cards, attached signs and gameplay HUD placement. The updater menu retained its **44 passing UI checks**.

Packaging and draft-release publishing fixture tests pass. The Windows release workflow requires both solo and redesigned gameplay checks before publishing an update. Verification uses isolated AppData directories and disposable saves; it does not overwrite normal player progression.

The sections below record the earlier builds' verification.

## Original prototype verification

Verified on 3 October 2026 using native Godot 4.6.2 and the exported Windows x64 executable, rendered with OpenGL 3.3 on this machine's AMD Radeon graphics.

The full progression integration run passed **41 checks**. It started with the normal $22 budget and earned the money through actual scoop, collection, wash and sale commands. It bought all eight upgrades, operated the sorting machine and local scanner, covered first-person movement and mouse-driven object rotation, opened the physical shop through a ray interaction, checked all storage pages, preserved the genuine diamond through sale/drop/recovery, loaded the save with the same diamond identity, rejected skipped certification steps, completed all three tests, and reloaded the ending.

The co-op integration run used **two separate instances of `DiamondInTheRough.exe`**, with actual native windows and a localhost ENet connection. The host and client passed **20 and 12 checks** respectively. They synchronized the 720-object world and diamond identity, rendered each other's player avatars, scooped without duplicate ownership, handed off a dropped object, spent shared funds exactly once on a purchase, operated the machine remotely, synchronized a washable foam prank, and returned the disconnected client's held finds to the inspection tray.

An additional independent networking probe used one Godot host and **three simultaneous clients**, verifying the four-player limit, three distinct item owners, one shared purchase despite repeated requests, cross-owner protection and disconnect recovery. All four processes completed with exit code 0. This probe tested the state/network layer rather than four rendered game windows.

The proximity voice update was verified with synthetic microphone-shaped tones in two separate exported game processes. The host and client passed **39 and 38 checks** respectively, covering 48 kHz stereo capture resampling into 16 kHz mono, mu-law encoding/decoding, real ENet delivery, individual 3D speakers, native audio output, push-to-talk gating, microphone mute, voice disable/re-enable and session cleanup. Nearby output contained the test tones; output beyond 12 metres was silent. The final output probe preserves the normal proximity voice volume bus. Rendered screenshots confirm the speaking indicator and microphone settings panel.

An independent four-process voice transport probe passed **160 checks**, including host/client and client/client routing, distance suppression, movement, payload integrity, no self echo, sender validation, malformed/replayed packet rejection, rate limits and disconnect cleanup. A further **16 checks** verified irregular capture chunks at 16, 44.1, 48 and 96 kHz, silent capture, mute and reset behavior. A synthetic generator through the muted microphone bus confirmed that its capture effect receives samples before mute, without local monitoring.

Voice tests used generated tones; they never opened or recorded a physical microphone. Human speech, microphone hardware and remote internet voice connections remain untested. Audio frames are not written to saves, reports or recordings. The test reports contain counters and aggregate signal measurements.

Selected native game screenshots are in `screenshots/`. Raw local logs and report artifacts are not committed to this repository. `game/verification.gd`, `game/voice_verification.gd` and the commands in `DEVELOPMENT.md` reproduce the integrated checks using isolated saves and generate JSON reports locally. No normal player save was overwritten by verification. The gameplay host/client integration checks were also rerun with the voice update.

This confirms the prototype on the tested machine and local transport. Internet routing, other hardware, Steam lobbies/invites/achievements, production matchmaking, full ragdolls, and long-session load tests remain outside this verification. Steamworks is not implemented. Machine feeding and conveyor throughput use the simplified sector model described in the launch guide.

## In-game updater verification

The updater passed **56 loopback HTTP checks** in Godot and **55 checks** in the exported Windows game (the editor-only install guard accounts for the difference). These cover asynchronous metadata/downloads, progress, build comparisons, invalid manifests, asset digests, corrupted downloads, private authentication failures and redirects that do not forward credentials off the API. The menu passed **44 native UI checks** with its status phases and masked session-token handling.

The Windows PowerShell 5.1 installer passed **13 fixture checks**, including actual atomic executable/manifest swaps, preservation of another save file, backups, a forced replacement failure and rollback, process-exit waiting, and rejection of unsafe archive paths, duplicate/link entries, extra executables, bad PE headers and excessive sizes. Packaging and draft-release publishing also passed local tests. Fixture files and generated reports are isolated from normal game saves.

The updated exported game passed the **40 headless solo checks** used by the build workflow. Mouse capture is omitted in headless verification and remains asserted in native-window runs. The first hosted Actions build and publishing jobs completed successfully, including the installer fixtures. A live private GitHub CLI integration run passed **6 checks** for authentication, responsive downloads, the actual build-1 ZIP, its byte count and SHA-256. No authentication credentials were exposed in reports.

The exported build-1 game then downloaded the published build-2 update and passed the same **6 live checks**. The native PowerShell 5.1 helper installed that real package into a disposable build-1 installation, preserved both installation and AppData player-file markers, and kept an exact previous-executable backup. The updated executable started successfully and passed **3 live checks**, including recognition of the current release and rejection of a downgrade. This physical installation used the fixture switches to skip the helper's automatic restart; verification launched the updated executable separately. Both hosted builds and publishing jobs passed.
