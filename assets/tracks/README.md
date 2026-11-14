# Track assets

Drop chapter art and optional chart overrides here. Nothing in this folder is required for the foundation build.

| Path | Use |
| --- | --- |
| `assets/tracks/<chapter_id>/` | Road, sky, and prop art for `haruna`, `shuto`, `docklands`, `apex` |
| `assets/tracks/charts/<level_id>.json` | Optional authored beat map that later replaces the generated chart |

`AudioAnalyzer.generate_campaign_track(style)` already returns a version 1 beat map. `style` may be a chapter style (`haruna_dry_night`, `shuto_rain`, `docklands_fog`, `apex_storm`) or a level id (`haruna_01` … `apex_04`).

Beat fields: `t` seconds, `lane` (`0` left, `1` center, `2` right, `3` apex), `kind` (`tap`, `hold`, `boost`), `dur` seconds. Lane ids live in `scripts/track/TrackLanes.gd`.

User songs are not stored here. `AudioAnalyzer.load_user_audio(path)` reads `ogg`, `mp3`, and 16-bit PCM `wav` from any path Godot can open.
