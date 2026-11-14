# APEX BEAT Android export

Package id: `com.apexbeat.tougedrift`. Portrait comes from `display/window/handheld/orientation` in `project.godot` (value `1`). Godot 4.3 copies that into the APK manifest. The debug preset writes an APK (`gradle_build/export_format=0`).

The debug build is signed with `keys/debug.keystore` (alias `androiddebugkey`, store password `android`, key password `android`). That key is a public debug key so CI artifacts stay installable across runs. Do not upload it to Google Play or RuStore.

## Download the debug APK

1. Push to `cursor/apex-beat-touge-drift-4b39`, or re-run the latest **Build Android APK** workflow. The workflow also declares `workflow_dispatch`; GitHub shows the manual button once this file is on the default branch.
2. Open the repository **Actions** tab and select **Build Android APK**.
3. Open the run for your commit. Wait until **Export debug APK** is green.
4. Download the artifact named `apex-beat-debug.apk`.
5. Unzip it. The file inside is `apex-beat-debug.apk`.
6. Install on an arm64 device:

```bash
adb install -r apex-beat-debug.apk
```

The APK includes `arm64-v8a` only. It requests `READ_MEDIA_AUDIO` (Android 13+ user music), `READ_EXTERNAL_STORAGE` (older devices), and `MODIFY_AUDIO_SETTINGS`. `RECORD_AUDIO` and `INTERNET` stay off until a feature needs them.

## Release `.aab` for Google Play and RuStore

The debug workflow does not produce a store bundle.

1. Create a release keystore offline and keep it out of git. Bump `version/code` on every upload and set `version/name`.
2. In `export_presets.cfg`, set `gradle_build/export_format=1` (AAB). Point `keystore/release`, `keystore/release_user`, and `keystore/release_password` at the release key through the editor, or inject them in CI from secrets. Godot stores passwords in `.godot/export_credentials.cfg`, which is gitignored.
3. In Godot 4.3 choose **Project → Install Android Build Template** once, then **Project → Export → Android → Export AAB**. Headless export is `godot --headless --install-android-build-template --export-release "Android" build/apex-beat.aab`.
4. Google Play: upload the `.aab`, enroll in Play App Signing, and keep `com.apexbeat.tougedrift` stable. Target SDK is 34. Declare the audio-file permission if the build still reads user music.
5. RuStore: upload an `.aab` (preferred) or a release APK signed with the same certificate you will keep using. `versionCode` must increase. The debug keystore cannot update a store build.

Switch `export_format` back to `0` if you still want the debug workflow to upload an APK.
