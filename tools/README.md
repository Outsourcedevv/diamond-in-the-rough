# Windows release pipeline

Every push to `main` runs `.github/workflows/windows-release.yml`. Manual dispatch is also available on `main`. The pipeline downloads **Godot 4.6.2 Standard** and matching export templates from the official `godotengine/godot-builds` release, checks their pinned SHA256 values, imports and checks the project, exports the Windows x64 game and runs the exported game's solo integration harness with isolated saves. A failed check leaves the previous release available.

The Windows build job has read-only repository access. Only the separate publish job has `contents: write`, using its temporary `GITHUB_TOKEN`. The game receives no Actions token or maintainer credential. Actions dependencies are pinned to official action commit revisions.

The Actions run number is the monotonic build number. The build stamps `build.json` before export:

```json
{"schema":1,"build":27,"commit":"0123456789abcdef0123456789abcdef01234567","version":"0.3.27"}
```

`package-update.ps1` creates `build/release/DIAMOND_IN_THE_ROUGH_Update.zip`. Its five files have no enclosing folder:

- `DiamondInTheRough.exe` (embedded Godot game data)
- `build.json`
- `README.txt`
- `GODOT_LICENSE.txt`
- `GODOT_THIRD_PARTY.txt`

The companion release asset is named `latest.json`:

```json
{
  "schema": 1,
  "build": 27,
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "version": "0.3.27",
  "asset": "DIAMOND_IN_THE_ROUGH_Update.zip",
  "sha256": "<64 lowercase hexadecimal characters>",
  "size": 40000000,
  "executable": "DiamondInTheRough.exe"
}
```

The publisher verifies the transferred ZIP, uploads both assets to a draft `build-27` release, checks that the commit is still the `main` head and then publishes it as Latest. A newer push cancels the older run. Reruns do not overwrite an already published build or move Latest to a lower build number. A cancelled publish can leave an invisible draft; rerunning that workflow resumes its asset upload.

Build artifacts and diagnostics remain available in Actions for 14 days. Native binaries, engine downloads and generated reports remain outside Git.

For a local Windows build, install the engine or use `install-godot.ps1`, then run:

```powershell
./tools/test-package-update.ps1 -ScratchDirectory ./build/package-tests
./tools/test-publish-release.ps1 -ScratchDirectory ./build/publish-tests
./tools/build-windows.ps1 -Godot C:/Tools/Godot_v4.6.2-stable_win64_console.exe -BuildNumber 27 -Commit (git rev-parse HEAD)
```

Use a build number for local development only; push to `main` to publish. The local script stamps the project metadata and Windows file properties, which can be restored from Git after export. Do not commit generated version stamps from a local build. `-SkipVerification` is available for local development; the published workflow never uses it.

Official references: [Godot 4.6.2 downloads](https://godotengine.org/download/archive/4.6.2-stable/), [GitHub workflow token permissions](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token), [GitHub release publishing](https://cli.github.com/manual/gh_release_edit).
