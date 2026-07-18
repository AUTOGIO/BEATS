# BEATS

Mac focus-session launcher: connect Beats headphones, open Boom 3D, and start a music profile in one shot.

## Quick start

```bash
brew install blueutil switchaudio-osx
chmod +x ./scripts/build_desktop_apps.sh ./scripts/beats-headphones.sh
./scripts/build_desktop_apps.sh
```

Run `dist/Focus_Beats.app`, or `./scripts/beats-siri-trigger.sh "Deep Work"` / `./scripts/beats-auto-profile.sh`.

## Layout

- `src/` — AppleScript / Swift app sources
- `scripts/` — shell + Python helpers (`beats_config.py`, headphones runner, Siri/auto triggers, build)
- `config/` — profiles, settings, music sources, auto-profile rules
- `docs/` — user manual and design notes

Runtime status still lives under `~/Library/Application Support/LockInAudioWorkflow/` (unchanged on purpose).
