# BEATS

Mac focus-session launcher: connect Beats headphones, open Boom 3D, and start a music profile in one shot.

## Quick start

```bash
brew install blueutil switchaudio-osx
./scripts/install_desktop_apps.sh
./scripts/doctor.sh
```

`install_desktop_apps.sh` builds the Desktop apps, applies the shared icon, and links `~/.local/bin/beats`.

Then run `Focus_Beats.app`, or:

```bash
beats lock-in "Deep Work"
beats auto
```

Copy `config/beats-settings.example.json` to `config/beats-settings.json` and set your headphones name and MAC before the first run (if you do not already have a local settings file). That live file is gitignored.

## Install and rebuild

Desktop apps embed the repository path and Python path at build time. After moving or recloning this repo, run:

```bash
./scripts/install_desktop_apps.sh
```

Ensure `~/.local/bin` is on your `PATH`. Shortcuts should call the stable CLI:

```bash
beats lock-in "$1"
beats auto
```

## Doctor

```bash
beats doctor
```

Checks Python, Homebrew CLIs, Boom 3D, headphones settings, and status-file writability.

## Tests

```bash
/usr/bin/python3 -m unittest discover -s tests -v
```

Apps and shell runners prefer `/usr/bin/python3` for parity (override with `BEATS_PYTHON`). On this Mac that binary is an Xcode shim (`xcode-select`), so error dialogs may show `Xcode-beta.app/.../python3` even when the baked path is `/usr/bin/python3`.

## Privacy

No cloud credentials are stored in this repo. `config/beats-settings.json` is gitignored because it may contain your Bluetooth MAC and local paths. Keep `beats-settings.example.json` as the tracked template.

## Layout

- `src/` — AppleScript / Swift app sources
- `scripts/` — shell + Python helpers (`beats`, `doctor.sh`, config CLI, runners, build/install)
- `config/` — profiles, settings, music sources, auto-profile rules
- `assets/` — shared app icon source (`zR5UJ.jpg`)
- `docs/` — user manual and design notes
- `tests/` — unit tests for config logic

Runtime status still lives under `~/Library/Application Support/LockInAudioWorkflow/` (unchanged on purpose).

Boom notes are reminders only — BEATS opens Boom 3D but does not switch its presets.
