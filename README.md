# DIAMOND IN THE ROUGH

**One real diamond. An unreasonable amount of rubbish.**

A playable native first-person 3D gem-sorting game built with Godot 4.6.2. Work an alpine mountain claim, climb the gem scree, inspect suspicious stones, sell scrap and certify the genuine diamond. Sort alone or share the claim with up to three friends.

![The mountain claim and first-session guide](screenshots/01_workshop.png)

![Physical equipment displays with attached prices](screenshots/03_equipment.png)

## Features

- One persistent genuine diamond among 720 searchable objects and batched decorative scree.
- First-person movement, scooping, physical pickups, object inspection and recoverable dropped finds.
- Eight shared upgrades, washing, batch sorting, a vacuum, conveyor and local scanner.
- Physical equipment models with attached names and prices: point at a model and press E to buy it.
- A seven-step playable tutorial, attached station signs and a compact UI that adapts to screen proportions.
- Collectibles, cosmetic rewards, harmless pranks and three-step diamond certification.
- Host-authoritative ENet co-op for up to four players with shared funds and progression.
- Spatial push-to-talk voice: full volume within 2 metres, fading to silence at 12 metres.
- Automatic solo/host saves, disconnect recovery and a Lost & Found station.

## Play the Windows build

Download the ZIP from the [latest release](https://github.com/Outsourcedevv/diamond-in-the-rough/releases/latest), extract it and open `DiamondInTheRough.exe`. Godot is not required to play the exported game.

## Run and edit

1. Install **Godot 4.6.2 Standard**. The project uses GDScript and does not require the .NET edition.
2. Clone or download this repository.
3. Import the root `project.godot` file in Godot and press **F5** to play.

With Godot on your `PATH`, you can also launch it from the repository directory:

```powershell
godot --path .
```

The project uses the GL Compatibility renderer. The verified export target is Windows x64; other platforms have not been verified.

## Windows build

Install the matching **Godot 4.6.2 export templates** in the editor. Export the **Windows Desktop** preset to `build/DiamondInTheRough.exe`, or use:

```powershell
New-Item -ItemType Directory -Force build | Out-Null
godot --headless --path . --export-release "Windows Desktop"
```

The export embeds its game data in the executable. Builds and generated engine caches are ignored by Git.

## Controls

| Input | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Shift / Space | Move faster / jump |
| E | Pick up a find, scoop a patch, use a station or buy displayed equipment |
| Left mouse | Scoop or use the selected tool |
| Right mouse | Start or finish close inspection |
| Mouse / Ctrl + wheel | Rotate / zoom while inspecting |
| Wheel / Q | Select a carried find / drop it |
| 1–4 | Scoop / hands / purchased vacuum / purchased scanner |
| C | Keep a collectible on display |
| Tab / Esc | Ledger / pause |
| V / M | Hold to talk / toggle microphone mute |

See [the playing guide](docs/PLAYING.md) for progression, pranks, saving and recovery.

## Co-op and proximity voice

Choose **Co-op → Host game** on one PC. Friends choose **Co-op**, enter its IP address and the same UDP port (**24680** by default), then choose **Join game**. Allow the game through the host's firewall. For multiple instances on one PC, join `127.0.0.1`. Direct internet hosting requires a reachable host and may require port forwarding. The host must remain running.

Hold **V** to speak to nearby players; **M** toggles your microphone mute. Settings provides input-device selection, microphone gain and nearby voice volume. Voices follow player positions and stop beyond 12 metres. Solo play and menus do not transmit. The game does not record voice or store it in saves. All peers must run the same version.

Voice uses 16 kHz mono G.711 mu-law audio over a dedicated ENet channel. Physical microphone hardware and speech quality still require a manual co-op check. Use headphones; echo cancellation is not implemented.

## In-game updates

Open **Updates** from the title or pause menu to download a newer build and **Save & restart to install**. Automatic checks run on startup and every five minutes. Successful pushes to `main` are built and published by GitHub Actions; failed builds are not offered. The private repository requires an existing GitHub CLI sign-in or a read-only token kept for the game session. Read [the update guide](docs/UPDATING.md) for setup, recovery and build behavior.

## Development and verification

The workshop geometry, materials and sound effects are generated in code. The root scene loads the scripts in `game/`:

| File | Responsibility |
| --- | --- |
| `game/main.gd` | Session orchestration, interactions and visible objects |
| `game/state.gd` | Persistent catalog, authoritative rules, saves and networking |
| `game/player.gd` | First-person movement and held-object inspection |
| `game/workshop.gd` | Mountain terrain, physical equipment displays, stations and animations |
| `game/interface.gd` | Menus, settings, ledger and HUD |
| `game/sound.gd` | Synthesized sound effects |
| `game/voice.gd` | Microphone capture, codec and spatial voice playback |
| `game/tutorial.gd` | Event-driven first-session guidance and local completion preferences |
| `game/redesign_verification.gd` | Physical purchases, tutorial progression and screen-layout checks |
| `game/verification.gd` | Solo and native co-op integration harness |
| `game/voice_verification.gd` | Synthetic native voice integration harness |

Read [DEVELOPMENT.md](DEVELOPMENT.md) for architecture and reproducible commands, and [VERIFICATION.md](VERIFICATION.md) for tested behavior and limits. Integrated verification uses isolated saves and generates reports locally.

## Prototype scope

This is a playable prototype. Steamworks, invitations, achievements, internet matchmaking, relay/NAT traversal, Opus, full ragdolls and production conveyor logistics are not implemented. Sorting machinery processes selected pile sectors in batches. See the development notes for these simplifications.

## License notices

No license has been selected for this game's original source and assets. The Godot Engine and its third-party notices are included in [licenses/](licenses/); those notices do not grant a license to the game's original code or assets.
