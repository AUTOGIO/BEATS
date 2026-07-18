# Proposed Upgrades

Two capability extensions. Both assume the built prototype in
`docs/USER_MANUAL.md#siri-shortcut-trigger`
(`scripts/beats-siri-trigger.sh`) as the non-interactive entry point they
build on, so neither one touches `beats-headphones.sh` directly.

**Upgrade A has since been built** (Wi-Fi + time-of-day rules only, no
calendar/EventKit — that piece remains explicit future scope). See
`docs/USER_MANUAL.md#context-aware-auto-profile` for how it works,
`scripts/beats-auto-profile.sh` for the entry point, and the
`resolve-profile` / `*-rule` subcommands added to `beats_config.py`. The
spec below is left as originally written for context on why it was scoped
this way; it no longer describes unbuilt work for the Wi-Fi/time portion.

**Upgrade B has now been built** as an opt-in menu bar app. See
`src/beats_status.swift`, the `Beats_Status.app` output from
`scripts/build_desktop_apps.sh`, and `docs/USER_MANUAL.md#beats_status`.

Non-goal for both: neither should become a persistent background daemon by
default. Both are designed to run on-demand or on an explicit trigger, in
keeping with "no hidden background agents required" (README, Security and
Privacy).

---

## Upgrade A — Context-Aware Auto-Profile

### What it does

Resolves the session profile automatically instead of requiring a manual
pick — from calendar state (EventKit), time-of-day, or current Wi-Fi SSID —
so `beats-siri-trigger.sh` (or a Shortcut) can run with zero profile
argument and still land on the right one.

### Mechanism

- A small Swift or `osascript`-driven helper reads context signals:
  - Wi-Fi SSID via `networksetup -getairportnetwork`
  - Calendar event titles/keywords in the next N minutes via EventKit
    (requires a compiled Swift binary or a Shortcuts "Get Upcoming Events"
    action — AppleScript cannot query EventKit directly)
  - Time-of-day as a pure fallback (no permission needed)
- A new, additive config file, e.g. `config/beats-profile-rules.json`,
  maps signals to profile names: `{"wifi": {"Office-5G": "Deep Work"},
  "calendar_keywords": {"call": "Silent Routing"}, "time_ranges": [...]}`.
  This does not change the schema of `beats-profiles.json`; it only adds a
  lookup layer in front of it.
- The resolved profile name is passed to `beats-siri-trigger.sh` as `$1`,
  exactly as a human-typed profile name would be. No change to the trigger
  script itself.

### Complexity / risk cost

- New dependency: EventKit access needs either a small compiled Swift binary
  (new build target, new signing/permission prompt) or reliance on
  Shortcuts' own calendar action (no compile step, more portable, less
  flexible about keyword matching).
- New failure mode: ambiguous or conflicting signals (e.g. right Wi-Fi,
  wrong calendar event) need a defined precedence order and a safe fallback
  to the existing default profile — must not silently pick nothing.
- New permission prompts (Calendar access, and Location if Wi-Fi SSID
  reading requires it on the target macOS version) that the user has to
  grant once, out of band.

### Non-goals

- No prediction/ML — pure rule lookup, so behavior stays auditable and
  debuggable by reading one JSON file.
- No modification to how profiles themselves are defined or edited via
  `Beats_Settings.app`.

### Stop condition

Ship as done once: Wi-Fi-based and time-of-day rules resolve correctly in
manual testing across at least 3 real scenarios, there's a documented
fallback profile when no rule matches, and the rules file has a
`view-profile-rules`-style read path documented. Calendar/EventKit
integration is explicitly optional follow-on scope, not required for v1.

---

## Upgrade B — Live Menu Bar Status Widget

Status: built, with best-effort battery display and explicit `unknown`
fallback when macOS does not expose battery percentage for the configured
headset.

### What it does

Replaces the current one-shot `display dialog` summary (built at the end of
`focus_beats.applescript`, reading the JSON status file written by
`write_status_file()` in `beats-headphones.sh`) with a persistent menu bar
item that shows the current state at a glance: connected headset + battery,
active profile, and music source — not just a summary of the last run.

### Mechanism

- A small Swift `NSStatusItem` menu bar app (new target, built alongside the
  existing `src/*.applescript` → `dist/*.app` pipeline in
  `build_desktop_apps.sh`, or as a separate build step).
- Reads the same status JSON file format `beats-headphones.sh` already
  writes via `--status-file` — no new data contract, just a second consumer
  of the existing schema (`profile`, `device`, `music`, `steps`).
- For live headset battery: `IOBluetooth` framework (Swift) can read battery
  percentage for a paired device by MAC address, which the AppleScript/shell
  side currently does not expose at all.
- Menu bar item polls the status file for changes (e.g. via a `DispatchSource`
  file watcher) rather than running its own audio/Bluetooth logic — it is a
  read-only viewer, not a second control path into Boom 3D or the headset.

### Complexity / risk cost

- New long-lived process: unlike A and the Siri trigger (both run-once and
  exit), this is the one piece of these three upgrades that runs
  continuously. That's a direct tension with the repo's "no hidden
  background agents" stance — it should be started deliberately (login item
  the user opts into) and clearly visible (menu bar icon, quit option), not
  installed as a silent `launchd` daemon.
- New build target: a Swift app is a heavier addition to the toolchain than
  a shell script — needs its own Xcode project or Swift Package, separate
  from the current AppleScript compile step.
- Battery-via-IOBluetooth is not officially documented/stable API for all
  device types; needs a manual spot-check against the actual `beats4`
  hardware before relying on it, with a "unknown" fallback state.

### Non-goals

- Not a replacement for `Focus_Beats.app`'s launch flow — it only displays
  state, it does not trigger reconnects, replay music, or reopen Boom 3D.
- No historical log/graph of past sessions — current-state only, v1.

### Stop condition

Ship as done once: the menu bar item reflects the most recent status file
within a few seconds of a run completing, shows a clear "unknown"/dash state
when no status file exists yet, and has a working Quit item. Battery display
is a nice-to-have, not a blocker — ship without it if `IOBluetooth` battery
reads prove unreliable on the actual hardware, rather than spending more
cycles making that specific API deterministic.
