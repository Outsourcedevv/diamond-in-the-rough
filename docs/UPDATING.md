# In-game Windows updates

Download the newest Windows release once to get the updater. Extract the entire flat ZIP into a writable folder and open `DiamondInTheRough.exe`. Older builds without the updater need this first manual download.

With automatic updates on (the default), the game checks on startup and every five minutes, downloads a new build in the background as soon as it finds one, and installs it by itself: straight away at the title screen, or when you return to the menu or close the game. It saves first and restarts into the new version. Nothing installs in the middle of play. You can still open **Updates** from the title or pause menu to check, download or **Save & restart to install** by hand, or turn automatic updates off in Settings. A failed save stops installation. A co-op host's restart disconnects the other players, who can reconnect after updating to the same build.

The game downloads updates from the public links of the newest release (`releases/latest/download/latest.json` and the ZIP), exactly like Space Goobers, so no sign-in is needed once the releases are public. While this repository is private those links are refused; the game then falls back to an installed [GitHub CLI](https://cli.github.com/) signed in with `gh auth login`, or a fine-grained token with **Contents: read** access pasted into the Updates panel for the session. The token stays in memory and is never written to settings, saves or logs. No owner credential is distributed with the game. Making the repository public (or publishing releases to a separate public repository) lets every player update automatically.

Downloads are verified against `latest.json` and GitHub's asset digest when provided. The installer checks the ZIP again, rejects unexpected entries, verifies the x64 executable and build, and replaces only `DiamondInTheRough.exe` and `build.json`. It leaves `.previous` backups, saves and settings intact. It restores the previous build on a replacement or immediate startup failure. Installation requires a writable game folder; it does not request administrator access. The latest result is shown on the next startup.

## What a push does

Every push to **main** triggers `.github/workflows/windows-release.yml`. A pinned Godot 4.6.2 Windows runner imports the source, exports the native executable, runs the isolated headless solo integration checks and packages it. A separate publishing job uploads both assets to a draft release, then makes the completed release Latest. Failed builds never become updates. Newer pushes cancel older builds, and the publisher verifies that it still matches main before publishing.

Each release has an increasing Actions build number and a version `0.3.<build>`. The updater compares build numbers and does not install an older or equal build. Git commits themselves cannot be installed: the game offers the completed Windows release from the workflow.

The release has two assets:

- `DIAMOND_IN_THE_ROUGH_Update.zip`: a flat native game package, version manifest and engine notices.
- `latest.json`: schema, build, version, source commit, ZIP size, SHA-256 and fixed executable name.

Only the publishing job has write permission through GitHub's job token; the build job has read permission. Tokens are not included in the executable, ZIP or manifests. Hosted-runner availability and the account's Actions allowance control when builds can run.

## Verification

The Windows installer is tested against disposable directories, including real atomic replacement, backup recovery, hostile ZIP entries and a forced replacement failure. The HTTP harness uses a loopback server and synthetic credentials; it never installs its harmless fake executable.

Run `tools/test-installer.ps1` on Windows to reproduce the installer fixtures. For HTTP verification, start `python tools/fake-update-server.py` in one terminal, then run the game with `-- --verify-updater=http --report-dir=C:/temp/rough-updater-http` in another. The server binds only `127.0.0.1:24788`. Use fresh report directories for verification.

For a real private-repository check using existing GitHub CLI credentials, run the exported game with an isolated report directory:

```powershell
.\DiamondInTheRough.exe -- --verify-updater=cli --report-dir=C:/temp/rough-updater-live
```

It checks the latest release, downloads and hashes a newer package if available, writes a report and exits. It never launches the installer or prints authentication data. The normal player save is not modified by this verification entry point.
