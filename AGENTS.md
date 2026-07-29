# AGENTS

Personal Mac automation repo for **BEATS** (Boom 3D + headphones + music session launcher).

## Folder layout

- `src/` — application source (AppleScript, Swift)
- `scripts/` — runnable helpers (`.sh`, Python CLI, build/install, `beats` CLI, doctor)
- `config/` — non-secret settings (JSON, TSV); copy `beats-settings.example.json` for local hardware
- `assets/` — shared icon source used by `build_desktop_apps.sh`
- `docs/` — guides and design notes
- `dist/` — built `.app` bundles (gitignored; rebuild with `./scripts/build_desktop_apps.sh`)
- `tests/` — unit tests (`/usr/bin/python3 -m unittest discover -s tests`)
- `.github/workflows/` — CI unit tests

Root may only contain: `README.md`, `AGENTS.md`, `.gitignore`, and toolchain files.

Prefer move over copy. Prefer edit over new files. Do not invent new top-level folders without asking.

Built apps bake `__REPO_ROOT__` and `__BEATS_PYTHON__` at compile time — rebuild after moving the repository. Prefer `/usr/bin/python3` (override with `BEATS_PYTHON`). Boom notes are reminders only.
