# Bass Drift

One-finger neon rhythm drift arcade — Godot 4.3+ (GDScript), portrait 720×1280.

## Open in Godot 4

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build).
2. Project → Import → select `project.godot` in this repo root (or Open).
3. Press **F5** (Run Project). Main scene: `res://scenes/Main.tscn`.
4. Desktop: click/hold left mouse to drift (touch is emulated from mouse).

### Controls

| Input | Action |
|--------|--------|
| Finger / LMB **up** (released) | Steer toward isometric **LEFT** |
| Finger / LMB **down** (held) | Steer toward isometric **RIGHT** |
| ⚙ | Volume, audio offset (−200…+200 ms), neon car skins |

## Custom music

Drop an OGG file at:

```text
res://assets/music.ogg
```

If missing, the game synthesizes a procedural funk/DnB loop at **130 BPM** via `AudioStreamGenerator` (kick / snare / hats / overdriven sub). BPM presets in the start screen still drive track section timing.

## Track sections (64-beat loop)

| Beats | Section | Turn every | Road width | Score |
|------:|---------|------------|------------|-------|
| 0–16 | Intro | 4 beats | 170 | ×1 |
| 17–32 | Buildup | 2 beats | 145 | ×1 |
| 33–64 | Drop | 1 (0.5 peak) | 125 | ×4 + glitch |

**PERFECT DRIFT** when a turn starts within 30 px of a neon crystal vertex.

## Android debug APK

CI exports a **debug APK** you can sideload on a phone:

1. GitHub → **Actions** → **Android Debug APK** → latest green run
2. Download artifact **`bass-drift-debug.apk`**
3. Allow unknown sources and install on the device

Full details: [docs/ANDROID_APK.md](docs/ANDROID_APK.md)

Export presets / workflows are owned by the CI agent (`.github/workflows/**`). Main scene for export: `res://scenes/Main.tscn`. Local desktop run does not require Android SDK.

## Layout

```text
autoload/   AudioBeatManager.gd, GameState.gd
scenes/     Main.tscn, Car.tscn, RoadManager.tscn, UI.tscn
scripts/    Main.gd, Car.gd, RoadManager.gd, CameraJuice.gd, UI.gd
shaders/    neon_grid.gdshader, drop_glitch.gdshader
assets/     optional music.ogg
```
