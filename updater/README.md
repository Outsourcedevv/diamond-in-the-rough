# Windows installation helper

`InstallUpdate.ps1` applies an update only after the player clicks the in-game install button. The game copies this helper from its embedded resources to the update cache, saves the current session, starts the helper, and exits. The helper needs no administrator rights. A launch using `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...` affects that process only.

Required parameters:

| Parameter | Value |
| --- | --- |
| `InstallDir` | Absolute local folder containing `DiamondInTheRough.exe`. |
| `PackagePath` | Absolute path of the downloaded ZIP in the update cache. |
| `ExpectedSha256` | SHA-256 from the selected release, as 64 hexadecimal characters. |
| `ExpectedBuild` | Positive integer build number from the selected release. |
| `GamePid` | PID of the game that is saving and quitting. |
| `ResultPath` | Absolute `.json` path in the game's update cache. |

The package is a **flat ZIP** containing `DiamondInTheRough.exe` and `build.json`. The executable includes the Godot PCK. The manifest contains an integer `build`, with optional `version` and `executable`; when supplied, `executable` must equal `DiamondInTheRough.exe`.

```json
{"schema":1,"build":3,"version":"0.3.3","commit":"0123456789abcdef0123456789abcdef01234567"}
```

Optional files are `README.txt`, `README.md`, `GODOT_LICENSE.txt`, `GODOT_THIRD_PARTY.txt`, `LICENSE.txt`, and `LICENSE.md`. The helper validates but does not install these extras. Nested paths, duplicate entries, additional executables, links, alternate data streams, and oversized files are rejected. The entire package and its extracted contents are limited to 160 MiB; the game executable is limited to 140 MiB and each text file to 2 MiB. The ZIP is held open exclusively while its SHA-256 is checked and its two installation files are extracted.

The helper validates the selected build against the packaged manifest and rejects the same or an older build than the installed manifest. It checks the x64 Windows executable header, waits up to 60 seconds for the game to exit, and stages files alongside the existing executable. It atomically replaces only the game executable and build manifest, retaining `.previous` copies. It preserves saves, settings, downloaded packages, and other files in the installation folder. No directory is recursively deleted or replaced.

After installation it launches the game from the same folder. A launch error or an immediate nonzero exit restores the previous version. This catches basic startup failures; it does not claim to detect all gameplay regressions. On an installation failure, the player sees a Windows error dialog and can read the same result on the next startup. `install_result.json` records `success`, `build`, `phase`, `message`, `rolled_back`, and `timestamp_utc`; it never contains authentication tokens.

`-NoRestart` suppresses restarting and the error dialog for disposable installation tests. `-NoWait` is accepted only together with `-NoRestart`. The game must never pass either switch for a player installation.
