# APEX BEAT: Touge Drift

Portrait one-finger rhythm drift racer for Godot 4.3+. Open this folder in Godot 4.3 or newer and run `scenes/Main.tscn` (720×1280, canvas stretch, mobile renderer).

Autoloads: `SaveManager`, `AudioAnalyzer`, `GameData`, `AdMonetizationStub`.

Headless check:

```bash
godot --headless --path . --import
godot --headless --path . --rendering-driver opengl3 --rendering-method gl_compatibility -- --smoke
```

Android debug APK steps are in [EXPORT_CHECKLIST.md](EXPORT_CHECKLIST.md).
