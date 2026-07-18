# AGENTS

Personal Mac automation repo for **BEATS** (Boom 3D + headphones + music session launcher).

## Folder layout

- `src/` — application source (AppleScript, Swift)
- `scripts/` — runnable helpers (`.sh`, Python CLI, build script)
- `config/` — non-secret settings (JSON, TSV)
- `assets/` — images and icons
- `docs/` — guides and design notes (`docs/prompts/` for AI prompts)
- `dist/` — built `.app` bundles (gitignored; rebuild with `./scripts/build_desktop_apps.sh`)
- `tests/` — tests only (if present)
- `archive/` — obsolete files kept for reference

Root may only contain: `README.md`, `AGENTS.md`, `.gitignore`, and toolchain files.

Prefer move over copy. Prefer edit over new files. Do not invent new top-level folders without asking.
