# Bass Drift — Android debug APK

How the sideloadable **debug APK** is built and where to download it.

## What CI produces

| Item | Value |
|------|--------|
| Workflow | [`.github/workflows/android-debug-apk.yml`](../.github/workflows/android-debug-apk.yml) |
| Godot | **4.3** (`barichello/godot-ci:4.3`) |
| Preset | `Android` in [`export_presets.cfg`](../export_presets.cfg) |
| Package | `com.bassdrift.game` |
| Orientation | Portrait (`project.godot` → `window/handheld/orientation=1`) |
| Artifact name | **`bass-drift-debug.apk`** |
| Signing | Ephemeral **debug** keystore generated in CI (`android/ci/generate-debug-keystore.sh`). Not for Play Store. |

Triggers: push to `cursor/bass-drift-game-48ce`, `cursor/bass-drift-apk-ci-48ce`, or any `cursor/**-48ce` branch, plus **workflow_dispatch** (Actions → Android Debug APK → Run workflow).

Internet permission is **off** (local audio only).

## Download the APK

1. Open the repo on GitHub → **Actions**.
2. Select workflow **Android Debug APK**.
3. Open the latest **green** run for your branch.
4. Under **Artifacts**, download **`bass-drift-debug.apk`**.
5. Unzip the artifact if your browser saved a `.zip` — inside is `bass-drift-debug.apk`.

Artifacts expire after **14 days**. Re-run the workflow if needed.

## Install on Android (sideload)

1. On the phone: **Settings → Security** (or Apps) → allow **Install unknown apps** for Files / Chrome / your file manager.
2. Copy `bass-drift-debug.apk` to the phone and open it.
3. Confirm install. This build is **debug-signed** — fine for testing, not for Play Store.

If install is blocked, use a file manager’s “Install” flow after enabling unknown sources for that app.

## Local / CI signing notes

- CI sets `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `_USER`, and `_PASSWORD` (standard Android debug alias `androiddebugkey` / password `android`).
- No production keystore or GitHub secrets are required for this pipeline.
- Do **not** commit real release keystores or passwords.

## If the workflow fails early

- **`project.godot` missing** — game project not on the branch yet; wait for the game agent, then re-run.
- **Main scene missing** — expected path is `res://scenes/Main.tscn` (must exist in the repo).
- **Export templates / SDK** — image `barichello/godot-ci:4.3` must provide templates; check the “Setup Godot” step logs.
