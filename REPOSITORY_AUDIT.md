# Repository Audit Report

## 1. Executive Summary

BEATS is a personal macOS focus-session launcher that connects Beats headphones, opens Boom 3D, routes audio, and starts a configured music profile. The implementation is a small, cohesive stack: Zsh runners, a Python config CLI, AppleScript desktop apps, and one Swift menu-bar viewer.

The core runner path is coherent and locally operable on this machine (Homebrew tools present, Boom 3D installed, Python/Swift available). The highest-confidence defect is that **Beats_Status cannot decode the status JSON it is meant to display** because Swift expects `exitCode` while the runner writes `exit_code`. Built apps also **bake an absolute repository path**, so moving or recloning the repo breaks the apps until rebuild. There are **no automated tests**, Shortcuts/Siri wiring is documented but not verified in-repo, and auto-profile rules are empty.

No committed cloud credentials or private keys were found. The main security exposures are local: a personal Bluetooth MAC and absolute home paths in config/docs, AppleScript playlist string interpolation, and ad hoc–signed local apps.

**Verdict:** Suitable as a personal Mac automation toolbox after fixing the status decoder and rebuild/path coupling. Do not expand toward EventKit/calendar or more background agents until the current surface is stabilized and lightly tested.

## 2. Audit Scope and Limitations

- **Scope:** Full repository content under `/Users/eduardofgiovannini/Documents/GitHub/BEATS`, including `src/`, `scripts/`, `config/`, `docs/`, local `dist/`, and hygiene around ignored/generated paths.
- **Mode:** Read-only except creation of this report file.
- **Not executed (intentionally skipped):**
  - Full session run of `beats-headphones.sh` / `Focus_Beats.app` (changes Bluetooth, audio routing, launches Boom 3D / Music / URLs).
  - `./scripts/build_desktop_apps.sh` (writes/replaces `dist/`).
  - Shortcuts/Siri GUI hookup.
  - Package installs (`brew install`, etc.).
- **Blocked / unverified at runtime:** Live headphone connect success, Boom 3D restore timing, Music playlist playback, Wi-Fi SSID resolution on this macOS version, IOBluetooth/battery accuracy, concurrent-run races.
- **External services:** None required beyond local apps (Boom 3D, Music, browser URL handler) and Homebrew CLIs.

## 3. Initial Repository State

| Item | Value |
|---|---|
| Repository root | `/Users/eduardofgiovannini/Documents/GitHub/BEATS` |
| Current branch | `main` (tracks `origin/main`) |
| HEAD | `0b89430` — *Reorganize as BEATS with a clean src/scripts/config layout.* |
| Remote | `https://github.com/AUTOGIO/BEATS.git` |
| Submodules | None |
| Worktrees | Single worktree at repo root |
| Nested repos | None |
| Size | ~2.9M working tree; `.git` ~760K; local `dist/` ~1.9M |
| Uncommitted changes | Modified `config/beats-music-sources.tsv` (+CODE, +CCC); untracked `BEATS.code-workspace` |
| Generated / local | `dist/*.app` present but gitignored; `reports/session/` locally excluded |
| Prior audit file | None (`REPOSITORY_AUDIT.md` created by this audit) |

## 4. Repository Purpose

### Documented behavior

- One-shot “lock in” workflow: profile → Boom 3D → Bluetooth/headphones → audio I/O → music source.
- Desktop apps: `Focus_Beats`, `Beats_Source`, `Beats_Settings`, `Beats_Status`.
- Non-interactive entry points: `beats-siri-trigger.sh`, `beats-auto-profile.sh`.
- Config in `config/` (settings, profiles, music sources TSV, auto-profile rules).
- Runtime status under `~/Library/Application Support/LockInAudioWorkflow/` (legacy path name retained).

### Implemented behavior

- Matches the documented control flow in `scripts/beats-headphones.sh` + `scripts/beats_config.py`.
- AppleScript UIs call the Python helper and shell runner with a build-time `__REPO_ROOT__` substitution.
- Auto-profile rule engine exists; committed rules file is empty (always falls through to default profile).
- Status menu bar app exists and is built into local `dist/`, but JSON decode is broken (see AUDIT-001).

### Inferred behavior

- Intended sole user: the repository owner on a personal Mac (hard-coded username paths, device MAC, personal playlists).
- Deployment model: local rebuild + Desktop copies; not a distributed product.

### Unresolved assumptions

- Whether Shortcuts automations are actually installed on this Mac.
- Whether `networksetup -getairportnetwork` still reports SSIDs reliably on current macOS.
- Whether Boom 3D “saved configuration” restore is sufficient without further UI automation.

## 5. Repository Map

| Path | Purpose |
|---|---|
| `src/` | AppleScript app templates + Swift menu-bar source (`__REPO_ROOT__` placeholders) |
| `scripts/` | Build script, headphones runner, Siri/auto triggers, Python config CLI |
| `config/` | Non-secret but machine-specific settings, profiles, sources, rules |
| `docs/` | User manual + proposed upgrades notes; empty `docs/prompts/` |
| `assets/` | Single JPEG (`zR5UJ.jpg`); not referenced by build scripts |
| `dist/` | Built `.app` bundles (gitignored; present locally) |
| `reports/` | Local session note; not part of product runtime |
| `README.md` / `AGENTS.md` | Quick start and agent layout rules |
| `tests/` / `archive/` | Referenced in `AGENTS.md` but **absent** |
| `.github/` | **Absent** — no CI |

## 6. Technology Stack

| Technology | Evidence |
|---|---|
| Zsh shell scripts | `scripts/*.sh` (`#!/bin/zsh`, `set -euo pipefail`) |
| Python 3 (stdlib only) | `scripts/beats_config.py`; no `requirements.txt` / lockfile |
| AppleScript + `osacompile` | `src/*.applescript`, `scripts/build_desktop_apps.sh` |
| Swift + AppKit | `src/beats_status.swift`, `swiftc -framework AppKit` |
| Homebrew CLIs | `blueutil`, `switchaudio-osx` (`SwitchAudioSource`) — README / runner |
| macOS system tools | `system_profiler`, `networksetup`, `osascript`, `open`, `pgrep` |
| Boom 3D | External app path in settings |
| Apple Music / URL handlers | Music AppleScript; `open` for URLs |
| Shortcuts / Siri | Documented in `docs/USER_MANUAL.md` (OS-side, not in repo) |
| GitHub remote | Present; **no** workflows |

No Node, Docker, SPM package manifest, Xcode project, or cloud deploy assets.

## 7. Architecture Overview

```text
[Focus_Beats.app / Beats_Source.app / Beats_Settings.app]
        │  (AppleScript UI, absolute REPO_ROOT baked at build)
        ▼
[beats_config.py]  ←→  config/*.json + beats-music-sources.tsv
        │
[beats-auto-profile.sh] → [beats-siri-trigger.sh] → [beats-headphones.sh]
                                                          │
                    ┌─────────────────────────────────────┼──────────────────┐
                    ▼                                     ▼                  ▼
              Boom 3D / blueutil / SwitchAudioSource   Music/URL      status JSON file
                                                                              ▲
                                                              [Beats_Status.app] (read-only)
```

- **Boundary:** Personal local automation; config is the source of truth; status JSON is a side-channel.
- **Coupling:** All UIs and runners depend on `beats_config.py` and repo-relative paths.
- **Shared state:** Config files in-repo; status file under Application Support.
- **Ambition–Capacity Mismatch:** Feature surface (Siri, auto-profile, menu bar, rich Settings) exceeds proven operational coverage (no tests, empty rules, Shortcuts unwired, status viewer broken). Calendar/EventKit in `docs/PROPOSED_UPGRADES.md` would widen that gap further and should stay deferred.

## 8. Build, Test, and Run Procedure

### Prepare

1. macOS with AppleScript, Python 3, Swift toolchain (`swiftc`).
2. `brew install blueutil switchaudio-osx`
3. Install Boom 3D at configured path (default `/Applications/Boom 3D.app`).
4. Pair headphones; set name/MAC in `config/beats-settings.json` or Settings app.

### Build

```bash
chmod +x ./scripts/build_desktop_apps.sh ./scripts/beats-headphones.sh
./scripts/build_desktop_apps.sh
```

Produces `dist/Focus_Beats.app`, `Beats_Source.app`, `Beats_Settings.app`, `Beats_Status.app`.

### Run

- Interactive: open apps under `dist/` (or Desktop copies).
- CLI: `./scripts/beats-siri-trigger.sh "Deep Work"` or `./scripts/beats-auto-profile.sh`.
- Config CLI: `python3 scripts/beats_config.py <subcommand>`.

### Test

- **No automated test suite or test command exists.**
- Manual checks are documented in `docs/USER_MANUAL.md` (unknown profile → exit 64; direct auto-profile run).

### Stop / recover

- Runners are one-shot (exit after workflow).
- `Beats_Status.app` is quit from its menu.
- Recovery: fix Bluetooth/hardware/config; re-run; inspect status file via Settings or Reveal Status File.

### Conflicts / gaps

- README is minimal; operational detail lives in `USER_MANUAL.md`.
- Manual embeds absolute `/Users/eduardofgiovannini/...` paths for Shortcuts.
- `PROPOSED_UPGRADES.md` still reads partly as future work while stating Upgrades A/B are built.
- No documented “Security and Privacy” README section despite reference from upgrades doc.

## 9. Commands Executed

| Command | Exit | Result |
|---|---|---|
| `pwd` / `git status` / `git branch` / `git remote -v` / `git log` / `du -sh .` | 0 | State captured |
| `git submodule status` | 0 | No submodules |
| `git diff --check` | 0 | No whitespace errors |
| `swift --version` | 0 | Swift 6.4, arm64 |
| `python3 --version` | 0 | Python 3.14.6 |
| `zsh --version` / `bash --version` | 0 | zsh 5.9; bash 3.2 |
| `blueutil --version` | 0 | 2.13.0 present |
| `SwitchAudioSource -c` | 0 | Present; current device printed |
| `test -d "/Applications/Boom 3D.app"` | 0 | Present |
| `python3 -m py_compile scripts/beats_config.py` | 0 | OK |
| `python3 scripts/beats_config.py view-settings\|list-profiles\|view-profile-rules\|resolve-profile\|get-default-profile` | 0 | Config readable; rules empty; default Deep Work |
| `./scripts/beats-siri-trigger.sh "Not A Real Profile"` | 64 | Rejects unknown profile as documented |
| `zsh -n` on all four shell scripts | 0 | Syntax OK |
| Swift decode probe vs sample status JSON | 0 | **DECODE_FAIL** without CodingKeys; **DECODE_OK** with `exit_code` mapping |
| `codesign -dv` on Focus_Beats / Beats_Status | 0 | Ad hoc signatures |
| Full headphones / Focus_Beats run | skipped | Would mutate audio/Bluetooth session |
| `./scripts/build_desktop_apps.sh` | skipped | Would rewrite `dist/` |
| Dependency installs | skipped | Policy |

## 10. Findings Summary

| ID | Severity | Priority | Category | Finding | Confidence |
|---|---|---|---|---|---|
| AUDIT-001 | High | P1 | Correctness | Beats_Status cannot decode status JSON (`exit_code`) | Confirmed |
| AUDIT-002 | High | P1 | Reliability | Built apps embed absolute `__REPO_ROOT__` | Confirmed |
| AUDIT-003 | Medium | P2 | Security | Personal MAC + absolute home paths committed | Confirmed |
| AUDIT-004 | Medium | P2 | Correctness | Unknown `--profile` silently ignored by runner | Confirmed |
| AUDIT-005 | Medium | P2 | Security | Music playlist embedded unsafely in `osascript` | High confidence |
| AUDIT-006 | Medium | P2 | Testing | No automated tests for critical paths | Confirmed |
| AUDIT-007 | Medium | P2 | Correctness | Wi-Fi rule UI heuristic breaks on `-` in SSID | High confidence |
| AUDIT-008 | Medium | P2 | Reliability | Profile default source missing from TSV breaks picker | High confidence |
| AUDIT-009 | Medium | P2 | Documentation | Docs drift / missing Security section / stale upgrade framing | Confirmed |
| AUDIT-010 | Low | P3 | Correctness | `Headphones Only` not reserved in upsert | Confirmed |
| AUDIT-011 | Low | P3 | Reliability | Non-atomic status writes; no run lock | Confirmed |
| AUDIT-012 | Low | P3 | macOS | Status app runs `system_profiler` every 5s | Confirmed |
| AUDIT-013 | Low | P3 | macOS | Ad hoc signing; Automation permission needs undocumented | Confirmed |
| AUDIT-014 | Low | P3 | Repository hygiene | Layout drift (`reports/`, empty prompts, no tests/) | Confirmed |
| AUDIT-015 | Low | P3 | Correctness | `update-setting` accepts arbitrary keys | Confirmed |
| AUDIT-016 | Informational | P3 | Architecture | Ambition–capacity: defer EventKit; unused auto-rules | Confirmed |
| AUDIT-017 | Informational | P3 | Shell | `eval` of `runtime-env` (mitigated by `shlex.quote`) | Confirmed |
| AUDIT-018 | Informational | P3 | Correctness | `music.apple.com` sources open as URLs, not Music playlists | Confirmed |

## 11. Critical Findings

None.

## 12. High Findings

### [AUDIT-001] Beats_Status cannot decode status JSON (`exit_code`)

- Severity: High
- Priority: P1
- Confidence: Confirmed
- Category: Correctness
- File: `src/beats_status.swift`
- Location: `struct StatusFile`, property `exitCode` (approx. lines 22–54, decode at 147–158)
- Evidence:
  - Runner writes `"exit_code"` in `scripts/beats-headphones.sh` `write_status_file()`.
  - Swift `StatusFile` declares `let exitCode: Int` with **no** `CodingKeys` and **no** `.convertFromSnakeCase`.
  - Nested `Device` correctly maps snake_case; top-level does not.
  - Isolated `swiftc` probe against the real schema: `DECODE_FAIL: Key 'exitCode' not found`; with `exitCode = "exit_code"` CodingKeys: `DECODE_OK`.
  - Live status file at Application Support uses `exit_code` (verified present).
- Impact:
  - Menu bar always falls into the “unknown / no usable decode” path whenever a real status file exists, defeating Upgrade B’s purpose.
- Recommendation:
  - Add `CodingKeys` mapping `exitCode = "exit_code"` (or enable `keyDecodingStrategy = .convertFromSnakeCase` consistently), rebuild `Beats_Status.app`, confirm menu shows profile/music after one Focus_Beats run.
- Validation:
  - Decode the existing `latest-status.json` in a one-off Swift snippet; launch Status app and confirm `FB: …` updates within a few seconds.

### [AUDIT-002] Built apps embed absolute repository path

- Severity: High
- Priority: P1
- Confidence: Confirmed
- Category: Reliability
- File: `scripts/build_desktop_apps.sh`, `src/*.applescript`, `src/beats_status.swift`
- Location: `sed "s|__REPO_ROOT__|${REPO_ROOT}|g"`; baked path visible in compiled artifacts
- Evidence:
  - Build substitutes `__REPO_ROOT__` with the absolute clone path.
  - `strings` on built Focus_Beats / Beats_Status show `/Users/eduardofgiovannini/Documents/GitHub/BEATS`.
  - Apps invoke `…/scripts/beats_config.py` and the runner from that path.
- Impact:
  - Renaming, moving, or cloning the repo elsewhere makes Desktop apps fail until rebuild; Shortcuts hard-coded to the old path also fail.
- Recommendation:
  - Prefer resolving repo root at runtime (e.g. env var, symlink in fixed Application Support location, or install scripts that rewrite one known path), or document “rebuild required after move” as a hard operational rule and provide a single install wrapper.
- Validation:
  - Move/rename clone (or build from a second path) and confirm apps still resolve config, or that install docs force rebuild successfully.

## 13. Medium Findings

### [AUDIT-003] Personal device identifiers and absolute home paths committed

- Severity: Medium
- Priority: P2
- Confidence: Confirmed
- Category: Security
- File: `config/beats-settings.json`, `scripts/beats_config.py` (`DEFAULT_SETTINGS`), `docs/USER_MANUAL.md`
- Location: `default_headphones_mac`; `status_file_path`; Shortcuts path examples
- Evidence:
  - Committed MAC `58:36:53:C3:42:E9` and username-absolute status path.
  - Manual instructs Shortcuts to call `/Users/eduardofgiovannini/Documents/GitHub/BEATS/scripts/…`.
  - Not a cloud API secret; is machine/user fingerprinting data in a public remote (`AUTOGIO/BEATS`).
- Impact:
  - Privacy exposure if the repo is public; onboarding friction for any other machine/user.
- Recommendation:
  - Keep a tracked `*-example` template with placeholders; gitignore or locally override real MAC/paths; document `$HOME`-relative status path (Python defaults already use `Path.home()`).
- Validation:
  - Fresh clone uses placeholders until local configure; `rg '/Users/|:[0-9A-Fa-f]{2}:'` clean on tracked templates.

### [AUDIT-004] Unknown `--profile` silently ignored by runner helper

- Severity: Medium
- Priority: P2
- Confidence: Confirmed
- Category: Correctness
- File: `scripts/beats_config.py`
- Location: `runtime_env()` (approx. lines 308–315)
- Evidence:
  - If `--profile Ghost` is passed and no profile matches, `profile` stays `None` and the run continues as a manual session defaulting music toward `Focus Noise`.
  - `beats-siri-trigger.sh` validates profiles (exit 64); `beats-headphones.sh` does not.
- Impact:
  - Direct CLI / future callers can silently run the wrong session.
- Recommendation:
  - Fail loudly in `runtime_env` when a non-empty profile name does not resolve (match Siri trigger behavior).
- Validation:
  - `python3 scripts/beats_config.py runtime-env --profile 'Ghost'` should exit non-zero; Siri unknown-profile test remains exit 64.

### [AUDIT-005] Music playlist name interpolated into AppleScript

- Severity: Medium
- Priority: P2
- Confidence: High confidence
- Category: Security
- File: `scripts/beats-headphones.sh`
- Location: Music startup `osascript` block (approx. lines 398–401)
- Evidence:
  - `-e "tell application \"Music\" to play playlist \"${MUSIC_SOURCE}\""` embeds `MUSIC_SOURCE` without AppleScript escaping.
  - Source values come from editable TSV / UI.
- Impact:
  - A playlist/value containing `"` can break or inject AppleScript (local trust boundary, not remote RCE).
- Recommendation:
  - Pass the playlist via `osascript` argv / `quoted form of` equivalent, or escape AppleScript string literals in Python before emission.
- Validation:
  - Registry entry with embedded quote should not execute injected AppleScript; playback either works safely or fails cleanly.

### [AUDIT-006] No automated tests

- Severity: Medium
- Priority: P2
- Confidence: Confirmed
- Category: Testing
- File: (missing) `tests/`
- Location: Repository root; `AGENTS.md` mentions `tests/` but directory absent
- Evidence:
  - No pytest/unittest/Swift tests; no CI; critical logic lives in `beats_config.py` (resolution, validation, rules).
- Impact:
  - Regressions in profile/source typing, rule precedence, and status schema can ship unnoticed (as with AUDIT-001).
- Recommendation:
  - Add a small pure-Python unit suite for `resolve_profile_from_context`, `source_kind`, `validate_profile_source`, and status schema fixtures; optionally a Swift decode test for `StatusFile`.
- Validation:
  - `python3 -m pytest` (or `unittest`) green on a fresh clone without hardware.

### [AUDIT-007] Wi-Fi rule removal heuristic breaks on SSIDs containing `-`

- Severity: Medium
- Priority: P2
- Confidence: High confidence
- Category: Correctness
- File: `src/beats_settings.applescript`
- Location: Remove Wi-Fi Rule branch (approx. lines 163–178); `readTimeRuleLabels` (approx. lines 34–45)
- Evidence:
  - Wi-Fi lines selected with `does not contain "-"`; time rules selected with `contains "-"`.
  - Many real SSIDs include hyphens (e.g. `Office-5G` in docs examples).
- Impact:
  - Settings UI may mis-list or fail to remove Wi-Fi rules; time-rule parsing can confuse Wi-Fi lines.
- Recommendation:
  - Stop scraping human `view-profile-rules` text; add machine-readable list subcommands (e.g. `list-wifi-rules`, `list-time-rules`) and drive the UI from those.
- Validation:
  - Create Wi-Fi rule for SSID containing `-`; remove via Settings; confirm rule gone in `view-profile-rules`.

### [AUDIT-008] Missing profile default source can break Focus_Beats picker

- Severity: Medium
- Priority: P2
- Confidence: High confidence
- Category: Reliability
- File: `src/focus_beats.applescript`
- Location: `choose from list … default items {profileDefaultSource}` (approx. lines 62–84)
- Evidence:
  - Default item must exist in the list; deleted TSV labels leave profile pointing at a missing source.
  - Current committed profiles resolve OK; failure mode is latent.
- Impact:
  - Interactive launch errors before the runner starts.
- Recommendation:
  - If default not in `sourceOptions`, fall back to first source / Headphones Only and optionally warn.
- Validation:
  - Point a profile at a removed label; Focus_Beats still opens a chooser.

### [AUDIT-009] Documentation drift versus implementation

- Severity: Medium
- Priority: P2
- Confidence: Confirmed
- Category: Documentation
- File: `docs/PROPOSED_UPGRADES.md`, `README.md`, `docs/USER_MANUAL.md`, `AGENTS.md`
- Location: Upgrade status framing; README Security reference; absolute Shortcuts paths; missing `tests/`/`archive/`
- Evidence:
  - Upgrades doc references “README, Security and Privacy” but README has no such section.
  - Upgrade A/B marked built while long “future” spec text remains; easy to misread.
  - `AGENTS.md` documents folders that do not exist; root also has untracked workspace + `reports/`.
- Impact:
  - Operators and agents follow stale or incomplete instructions.
- Recommendation:
  - Trim README with a short privacy note; mark built upgrades as historical; replace absolute paths with `$REPO_ROOT` placeholders; align `AGENTS.md` with actual tree.
- Validation:
  - Manual pass: every documented command/path resolves; no references to missing Security section.

## 14. Low and Informational Findings

### [AUDIT-010] `Headphones Only` not reserved when adding sources

- Severity: Low
- Priority: P3
- Confidence: Confirmed
- Category: Correctness
- File: `scripts/beats_config.py`
- Location: `RESERVED_SOURCE_NAMES = {"Custom URL"}` (approx. line 55)
- Evidence:
  - Docs forbid reusing `Headphones Only`; upsert only blocks `Custom URL`.
- Impact:
  - User can create a conflicting registry label and confuse resolution.
- Recommendation:
  - Add `Headphones Only` to `RESERVED_SOURCE_NAMES`.
- Validation:
  - `upsert-source "Headphones Only" …` exits with reserved error.

### [AUDIT-011] Non-atomic status writes and no concurrency lock

- Severity: Low
- Priority: P3
- Confidence: Confirmed
- Category: Reliability
- File: `scripts/beats-headphones.sh`
- Location: `write_status_file()` `Path.write_text(...)`; no flock around runner
- Evidence:
  - Direct overwrite; overlapping runs can interleave Bluetooth/audio steps and truncate readers’ view of JSON.
- Impact:
  - Rare for personal one-user use; Status/Siri summary could read partial JSON.
- Recommendation:
  - Write to temp file then `rename`; optional `flock` on a lock file for the runner.
- Validation:
  - Kill mid-write / parallel runs; reader always sees valid JSON or prior complete file.

### [AUDIT-012] Frequent `system_profiler` polling in Status app

- Severity: Low
- Priority: P3
- Confidence: Confirmed
- Category: macOS
- File: `src/beats_status.swift`
- Location: `Timer.scheduledTimer(timeInterval: 5.0, …)` + `readBatteryPercentage` via `SPBluetoothDataType`
- Evidence:
  - Every refresh may spawn `system_profiler`, which is relatively heavy.
- Impact:
  - Unnecessary CPU/energy use while Status is open.
- Recommendation:
  - Cache battery for longer; refresh battery less often than status file; keep file watcher for JSON.
- Validation:
  - Sample CPU with Status open for several minutes before/after change.

### [AUDIT-013] Ad hoc code signing and undocumented TCC needs

- Severity: Low
- Priority: P3
- Confidence: Confirmed
- Category: macOS
- File: built `dist/*.app`; docs
- Location: `codesign -dv` → ad hoc; Automation for Music/Boom likely required at runtime
- Evidence:
  - No Developer ID / hardened runtime; personal use is expected.
- Impact:
  - Gatekeeper prompts; Automation permission dialogs may surprise users; not suitable for unsigned distribution.
- Recommendation:
  - Document required Privacy & Security permissions; keep personal/ad hoc unless distributing.
- Validation:
  - Fresh macOS user runbook completes with listed prompts only.

### [AUDIT-014] Repository hygiene and layout drift

- Severity: Low
- Priority: P3
- Confidence: Confirmed
- Category: Repository hygiene
- File: `AGENTS.md`, `reports/`, `docs/prompts/`, `BEATS.code-workspace`, `.gitignore`
- Location: Top-level extras; empty prompts dir; local `dist/` present
- Evidence:
  - `AGENTS.md` forbids inventing top-level folders and lists `tests/`/`archive/` that are missing; `reports/` exists; prompts empty; workspace untracked.
- Impact:
  - Mild agent/human confusion; fresh clone is still usable if README followed.
- Recommendation:
  - Either create promised dirs or remove mentions; decide whether to track workspace file; keep `dist/` ignored.
- Validation:
  - Tree matches `AGENTS.md`; `git status` clean after intentional ignores.

### [AUDIT-015] Unvalidated `update-setting` keys

- Severity: Low
- Priority: P3
- Confidence: Confirmed
- Category: Correctness
- File: `scripts/beats_config.py`
- Location: `update_setting()` (approx. lines 503–506)
- Evidence:
  - Arbitrary keys accepted (`get-setting totally_fake_key` returns empty, exit 0); no MAC/path validation.
- Impact:
  - Typos create inert settings; malformed MAC fails later at connect time.
- Recommendation:
  - Allowlist known keys; lightly validate MAC format and Boom path existence on set.
- Validation:
  - Unknown key rejected; bad MAC rejected.

### [AUDIT-016] Ambition–capacity mismatch (defer further platform scope)

- Severity: Informational
- Priority: P3
- Confidence: Confirmed
- Category: Architecture
- File: `docs/PROPOSED_UPGRADES.md`, `config/beats-profile-rules.json`
- Location: Calendar/EventKit future scope; empty `wifi` / `time_ranges`
- Evidence:
  - Auto-profile shipped but unused (empty rules); Shortcuts not wired in-repo; Status broken (AUDIT-001).
- Impact:
  - Further features (EventKit, daemons) would increase permission and maintenance cost without stabilizing current flows.
- Recommendation:
  - Stabilize decode + path story + light tests before any calendar work; wire Shortcuts only after CLI validation.
- Validation:
  - Rules file used in daily life OR feature surface slimmed in docs.

### [AUDIT-017] `eval` of `runtime-env` output

- Severity: Informational
- Priority: P3
- Confidence: Confirmed
- Category: Shell
- File: `scripts/beats-headphones.sh`
- Location: `eval "$("${helper_cmd[@]}")"` (approx. line 282)
- Evidence:
  - Values emitted via `shlex.quote` in Python, which mitigates injection from config values.
- Impact:
  - Pattern remains sensitive to helper-output integrity; acceptable within same-repo trust boundary.
- Recommendation:
  - Prefer parsing `key=value` lines without `eval`, or use a JSON env dump + Python/`jq` loader.
- Validation:
  - Config values with spaces/quotes still load; malicious helper output no longer arbitrary shell.

### [AUDIT-018] Apple Music web URLs treated as generic URL opens

- Severity: Informational
- Priority: P3
- Confidence: Confirmed
- Category: Correctness
- File: `scripts/beats_config.py` `source_kind()`; `config/beats-music-sources.tsv` (uncommitted CODE/CCC lines)
- Location: `http(s)://` → `url` kind → `open`
- Evidence:
  - `music.apple.com/...` entries are opened as URLs, not `Music` app playlists.
- Impact:
  - Behavior may surprise users expecting in-app playlist playback.
- Recommendation:
  - Document distinction; or add an explicit source type if native Music open is required.
- Validation:
  - Manual run of those labels matches documented behavior.

## 15. Security Assessment

- **No** committed API keys, passwords, private keys, or `.env` secrets found.
- **Personal identifiers** (Bluetooth MAC, absolute home/repo paths) are committed — treat as privacy/hygiene risk if the GitHub repo is public (AUDIT-003).
- **Local injection risk** in Music AppleScript string building (AUDIT-005); config-driven, not network-facing.
- **`eval` + quoted env** is mitigated but still a risky pattern (AUDIT-017).
- Subprocess usage generally passes argv arrays / quoted forms in AppleScript UIs.
- Apps are **ad hoc signed**; appropriate for personal use, not distribution (AUDIT-013).
- No `curl | sh`, no `sudo` in scripts, no network listeners.

Overall security posture: acceptable for a single-user local automation repo after reducing committed personal identifiers and hardening the Music AppleScript boundary.

## 16. Correctness Assessment

- Profile/source typing and rule precedence in Python are thoughtfully designed and fail soft on stale rules.
- Confirmed correctness defects: Status JSON schema mismatch (AUDIT-001); silent unknown profile in `runtime_env` (AUDIT-004); Settings Wi-Fi parsing heuristic (AUDIT-007); reserved-name gap (AUDIT-010).
- Latent interactive failure when profile defaults reference missing sources (AUDIT-008).
- End-to-end hardware correctness **not** runtime-verified in this audit.

## 17. Reliability and Operational Stability

- One-shot runners with `set -euo pipefail`, timeouts, and EXIT trap status writes — generally solid for personal use.
- Stability risks: absolute baked paths (AUDIT-002), missing source defaults (AUDIT-008), non-atomic status I/O (AUDIT-011), heavy Status polling (AUDIT-012), empty auto-rules making auto-profile a no-op until configured.
- No health checks, monitoring, or log rotation (stdout logs only); appropriate to scope, but failures depend on dialogs/notifications.
- Common failure modes are documented in the user manual (Boom missing, Bluetooth off, connect failure).

## 18. Architecture and Complexity Assessment

- **Strengths:** Clear separation (UI / config CLI / runner / status viewer); additive auto-profile layer; stdlib-only Python.
- **Weaknesses:** Path baking couples binaries to one clone; human-readable rules scraping in AppleScript; status schema not shared as a single typed contract across Python and Swift.
- **Ambition–Capacity Mismatch:** Ship-stabilize the four apps + two shell entry points before EventKit, prediction, or background daemons. Empty rules + broken Status indicate capacity should focus on verification, not new signals.

Complexity to **remove or defer:**
- EventKit/calendar auto-profile (explicit future scope — keep deferred).
- Any launchd/login-item auto-start of Status (docs already discourage hidden agents).
- Further Settings actions that scrape text UIs instead of structured CLI output.

## 19. Dependency Assessment

- **Runtime:** Python 3 stdlib; system `osascript`/`swiftc`; Homebrew `blueutil`, `switchaudio-osx`; Boom 3D; Music.
- **No** language package lockfiles (none needed today).
- **No** unused npm/pip dependency graphs.
- Supply-chain surface is small; main risk is Homebrew formula availability and Boom 3D continued installability.

## 20. Testing Assessment

- Automated tests: **none**.
- Manual validation exists in docs; this audit confirmed unknown-profile exit 64, config CLI reads, shell syntax, and Status decode failure.
- Untested critical paths: Bluetooth connect, audio routing, Boom launch timing, Music playlist play, URL open, Wi-Fi SSID resolution, Status battery, concurrent runs.
- Recommended minimum: pure unit tests for `beats_config.py` + status schema decode fixture.

## 21. Documentation Assessment

- `docs/USER_MANUAL.md` is the real operational guide and is largely aligned with code.
- Gaps: absolute user paths; Shortcuts unwired caveat; missing Security/Privacy README section referenced elsewhere; `PROPOSED_UPGRADES.md` historical vs aspirational mixing; `AGENTS.md` layout drift; empty `docs/prompts/`.
- README quick start is accurate but incomplete for Settings/Status/Siri.

## 22. macOS and Apple-Specific Assessment

- Apple Silicon native Status binary (`arm64`); AppleScript applets universal.
- LSMinimumSystemVersion 13.0 for Status; LSUIElement accessory app — appropriate.
- Hard-coded `/Users/eduardofgiovannini/...` in settings/docs/binaries (AUDIT-002/003).
- Bluetooth via `system_profiler` JSON and `blueutil` — workable but brittle across OS updates.
- Wi-Fi via `networksetup -getairportnetwork en0/en1` — documented caveat; may need refresh on newer macOS.
- Ad hoc signing only; Automation permissions for controlling Music/other apps likely required (undocumented checklist).
- No sandbox entitlements file; expected for these applet-style apps.
- Runtime status directory name `LockInAudioWorkflow` is legacy branding — intentional per README.

## 23. Shell Script Assessment

| Script | Notes |
|---|---|
| `beats-headphones.sh` | Strict mode; good structure; `eval` mitigated; Music string interpolation risk; custom timeout helper |
| `beats-siri-trigger.sh` | Clean validation + summary; executable bit odd (`711`) vs others |
| `beats-auto-profile.sh` | Fail-soft Wi-Fi; `exec` to trigger; good |
| `build_desktop_apps.sh` | `rm -rf` only on known output/temp paths; embeds absolute root |

No `sudo`, no `curl | sh`. Temporary files cleaned in build script.

## 24. Repository Hygiene

- `.gitignore` covers `dist/`, `.env*`, caches, logs — good.
- Local `dist/` present (expected for daily use).
- Uncommitted music source edits; untracked workspace file.
- `reports/` locally excluded via `.git/info/exclude` pattern — fine.
- Fresh clone can build if Xcode CLT + Homebrew deps + Boom 3D exist; apps must be rebuilt on that machine (AUDIT-002).
- No nested repos or large binaries beyond one JPEG and local apps.

## 25. Prioritized Remediation Plan

### Stage 0 — Preserve and Validate

- Commit or discard intentional `beats-music-sources.tsv` edits deliberately.
- Keep a known-good status JSON sample for decode tests.
- Do not rewrite architecture.
- **Validation:** `git status` understood; sample JSON retained.
- **Rollback:** N/A (read-only baseline).

### Stage 1 — Critical Stabilization

1. Fix StatusFile `exit_code` CodingKeys (AUDIT-001); rebuild Status app.
2. Document or fix absolute REPO_ROOT coupling (AUDIT-002) — at minimum “rebuild after move” + install script.
3. Reject unknown `--profile` in `runtime_env` (AUDIT-004).
- **Validation:** Status shows last run; unknown profile fails; apps run from documented install path.
- **Rollback:** Revert single-file Swift/Python changes; keep prior `dist/` backup.

### Stage 2 — Reliability Improvements

- Harden Music AppleScript argument passing (AUDIT-005).
- Fix Settings rules listing via structured CLI (AUDIT-007).
- Soft-fallback when profile default source missing (AUDIT-008).
- Atomic status write (AUDIT-011).
- **Validation:** Manual matrix for Deep Work / Focus Reset / Silent Routing + hyphenated SSID rule edit.

### Stage 3 — Simplification

- Defer EventKit entirely.
- Either configure auto-profile rules for real use or mark the feature “optional/advanced” more prominently.
- Avoid new background agents.
- **Validation:** Docs match actually used entry points only.

### Stage 4 — Maintainability

- Minimal Python unit tests (AUDIT-006).
- Template-ize personal MAC/paths (AUDIT-003).
- Align `AGENTS.md` / README privacy note (AUDIT-009/014).
- Reserve `Headphones Only`; allowlist settings keys (AUDIT-010/015).
- **Validation:** Tests in CI or local one-command check; templates clone cleanly.

**Do not attempt yet:** distribution signing program, EventKit integration, ML/prediction, launchd daemons, large SwiftUI rewrite.

## 26. Quick Wins

1. Add `exitCode = "exit_code"` CodingKeys in `StatusFile`.
2. Add `Headphones Only` to `RESERVED_SOURCE_NAMES`.
3. Fail `runtime_env` on unknown non-empty `--profile`.
4. Replace absolute Shortcuts paths in the manual with `$REPO_ROOT` / copy-paste instructions.
5. Add a one-line README privacy note (no secrets; local MAC may be personal).
6. Atomic status file write (`tmp` + rename).
7. Guard Focus_Beats default source membership before `choose from list`.
8. Reduce Status battery poll interval (e.g. 60s) separately from JSON refresh.
9. Normalize script modes to `755`.
10. Delete or explain empty `docs/prompts/` and align `AGENTS.md` folder list.

## 27. Deferred Improvements

- EventKit / calendar auto-profile.
- Developer ID signing and notarization.
- Shared schema package between Python and Swift.
- Full concurrency locking / queueing of sessions.
- Cross-Mac portable installer.
- CI on GitHub Actions (low urgency for personal tooling).

## 28. Unresolved Questions

- Are Shortcuts / Siri phrases actually installed and working on this Mac?
- Does `networksetup -getairportnetwork` still return usable SSIDs on this OS build?
- Is Boom 3D restore timing (10s poll) reliable on cold start?
- Should `music.apple.com` links remain URL-open semantics?
- Is the GitHub remote public, and should the Bluetooth MAC be rotated/redacted in history?

## 29. Final Recommendation

Treat BEATS as a **valuable personal automation toolkit that is mostly well-structured but not fully operationally proven**. Before any new features, fix the Status JSON decode bug, make path/install coupling explicit (or runtime-dynamic), add a thin unit-test layer around `beats_config.py`, and redact or template machine-specific identifiers if the remote is shared. Defer calendar integration and further background complexity until the current four apps and two shell entry points behave correctly on this Mac end-to-end.
