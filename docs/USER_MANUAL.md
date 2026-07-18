# User Manual

## Purpose

This workflow reduces the start-of-session audio setup to three desktop actions:

- `Focus_Beats.app`
- `Beats_Source.app`
- `Beats_Settings.app`
- `Beats_Status.app`

The first action prepares the listening environment. The second manages music sources. The third manages hardware targets, saved profiles, and app defaults.
The fourth is a read-only menu bar view for the latest workflow state.

## What Happens During Lock In

When `Focus_Beats.app` runs, it performs the following sequence:

1. Prompts for a session profile
2. Opens `Boom 3D.app`
3. Waits for Boom 3D to restore its saved local configuration
4. Verifies Bluetooth is enabled
5. Connects the configured headphones
6. Routes audio output to the headphones
7. Routes audio input to the headphones when available
8. Prompts for a music source with the profile default preselected
9. Starts the selected playlist, URL, or no-music mode
10. Shows a step-by-step status summary

## Build and Install

From the repository root:

```bash
chmod +x ./scripts/build_desktop_apps.sh ./scripts/beats-headphones.sh
./scripts/build_desktop_apps.sh
```

The generated apps will appear in `dist/`.

To place them on the Desktop:

```bash
cp -R "./dist/Focus_Beats.app" "${HOME}/Desktop/"
cp -R "./dist/Beats_Source.app" "${HOME}/Desktop/"
cp -R "./dist/Beats_Settings.app" "${HOME}/Desktop/"
cp -R "./dist/Beats_Status.app" "${HOME}/Desktop/"
```

## Desktop Actions

### Focus_Beats

This action first presents a profile picker built from `config/beats-profiles.json`. It then presents a source picker built from `config/beats-music-sources.tsv` and two reserved options:

- `Custom URL`
- `Headphones Only`

Source behavior:

- Named playlist entry: plays in Apple Music
- URL entry: opens via the default macOS URL handler
- `Custom URL`: prompts for a URL at runtime
- `Headphones Only`: skips music startup

Profile behavior:

- profiles now store an explicit source type: `apple_music`, `url`, or `none`
- that type controls the default non-interactive path used by Siri, auto-profile, and any profile run with no manual source override
- in the interactive picker, you can still override the profile default for the current run

After execution, the app shows a compact summary for:

- profile resolution
- Boom 3D readiness
- Bluetooth state
- headphone connection
- output routing
- input routing
- music startup

### Beats_Source

This action supports:

- `Add Source`
- `Remove Source`
- `View Sources`

#### Add Source

Use this to add either:

- an Apple Music playlist name
- a web URL such as YouTube or TuneIn

Rules:

- Source names must be unique
- Source names cannot contain tabs or newlines
- Reserved names cannot be reused:
  - `Custom URL`
  - `Headphones Only`

#### Remove Source

Removes one named source from the TSV registry.

#### View Sources

Displays all configured labels and their underlying values.

### Beats_Settings

This action supports:

- `View Settings`
- `Set Hardware Target`
- `Set Boom 3D App Path`
- `Set Status File Path`
- `Set Default Profile`
- `View Profiles`
- `Add or Update Profile`
- `Remove Profile`
- `View Auto-Profile Rules`
- `Set Wi-Fi Rule`
- `Remove Wi-Fi Rule`
- `Add Time Rule`
- `Remove Time Rule`
- `Set Fallback Profile`

Profiles can define:

- a default source label
- a default source type
- a Boom 3D note shown at launch time
- optional headphones name override
- optional headphones MAC override

Profile source types:

- `apple_music`: the default source must be a named playlist entry in `config/beats-music-sources.tsv`
- `url`: the default source must be a named URL entry in `config/beats-music-sources.tsv`
- `none`: the profile resolves to `Headphones Only`

Auto-profile rules can define:

- Wi-Fi SSID to profile mapping
- time range to profile mapping
- fallback profile when no rule matches

### Beats_Status

This action is an opt-in menu bar widget.

It shows:

- last known workflow status
- active profile from the most recent run
- most recent music source
- target headphones name
- battery percentage when macOS exposes it, otherwise `unknown`

Behavior:

- reads the shared workflow status file
- updates within a few seconds of a run completing
- includes a manual refresh command
- includes a Reveal Status File command
- includes a visible Quit command
- does not launch itself automatically

## Editing the Source Registry Manually

The file format is TSV:

```text
Label<TAB>Playlist or URL
```

Example:

```text
YouTube Playlist	https://youtube.com/playlist?list=PLieRSdP0b5KKYe02bLmr778MeMfX6HkUk&si=WfJEHKWp6brkXuts
Focus Noise	Focus Noise
```

The workflow ignores:

- blank lines
- lines starting with `#`
- malformed lines without a tab

## Customization Points

The main shell entry point is [scripts/beats-headphones.sh](../scripts/beats-headphones.sh).

Common edits:

- change default headphone target: update `config/beats-settings.json` or use `Beats_Settings.app`
- change default Boom 3D app path: update `config/beats-settings.json` or use `Beats_Settings.app`
- change shared status file path: update `config/beats-settings.json` or use `Beats_Settings.app`
- change session defaults: update `config/beats-profiles.json` or use `Beats_Settings.app`

Profile file note:

- each profile now carries `music_source_label` plus `music_source_type`
- older profiles without `music_source_type` are still read safely and inferred on load, but new edits should save the explicit field

Primary config files:

- `config/beats-settings.json`
- `config/beats-profiles.json`
- `config/beats-music-sources.tsv`
- `config/beats-profile-rules.json` (auto-profile rules; see [Context-Aware Auto-Profile](#context-aware-auto-profile))

## Dependencies

Install required CLI tools:

```bash
brew install blueutil switchaudio-osx
```

## Failure Modes

### Boom 3D missing

Symptom:

- workflow exits before Bluetooth or music steps

Fix:

- install `Boom 3D.app` in `/Applications`

### Bluetooth off

Symptom:

- script exits with a Bluetooth unavailable message

Fix:

- turn Bluetooth on in System Settings

### Headphones do not connect

Symptom:

- routing never completes

Fix:

- confirm the headset is powered on
- confirm the MAC address is correct
- confirm the device is already paired with macOS

### Music step times out

Symptom:

- headphones connect but playback does not start

Fix:

- verify Apple Music can play the named playlist
- verify the URL opens correctly
- rerun after Music finishes launching

### Wrong default device or profile

Symptom:

- the workflow uses the wrong target hardware or startup mode

Fix:

- open `Beats_Settings.app`
- update the hardware target or default profile

### Beats_Status shows `unknown`

Symptom:

- the menu bar app shows `Status: unknown` or no recent run details

Fix:

- run `Focus_Beats.app`, `beats-siri-trigger.sh`, or `beats-auto-profile.sh` once
- verify the status file path in `Beats_Settings.app`
- use `Reveal Status File` from the menu bar app to inspect the current JSON path

## Siri Shortcut Trigger

`scripts/beats-siri-trigger.sh` is a non-interactive entry point built for the
Shortcuts app, so the workflow can be started with "Hey Siri, beats" instead
of opening `Focus_Beats.app`. It does not add a menu picker: it takes a profile
name as its only argument (or none, for the configured default), validates it
against `config/beats-profiles.json`, then delegates to the existing
`beats-headphones.sh` runner unchanged.

Status: script is built and ready. Wiring it into an actual Shortcut still
requires the Shortcuts app GUI on this Mac, so the section below is the runbook
for that final OS-side hookup.

### What it does differently from Focus_Beats.app

- No `choose from list` dialogs — designed to run headless from Siri or a
  Shortcuts automation (e.g. arriving Wi-Fi, time of day).
- Rejects an unrecognized profile name immediately (exit code `64`) instead of
  falling through to a manual session, so a misheard Siri phrase fails loudly.
- Prints one summary line to stdout, meant for a Shortcuts "Show Notification"
  step rather than a `display dialog`.

### Build the Shortcut

1. Make the script executable (one-time):

   ```bash
   chmod +x ./scripts/beats-siri-trigger.sh
   ```

2. Open the **Shortcuts** app and create a new shortcut named `Lock In`.
3. Add action **Ask for Input** (Text) — prompt: "Which profile?", with
   "Allow Siri to ask" as needed. This lets you say "Hey Siri, Lock In" and
   either answer the prompt or, for a silent default run, add a second
   Shortcut with a hardcoded profile name instead of the prompt.
4. Add action **Run Shell Script**:
   - Shell: `/bin/zsh`
   - Pass input: `as arguments`
   - Script:

     ```bash
     /Users/eduardofgiovannini/Documents/GitHub/BEATS/scripts/beats-siri-trigger.sh "$1"
     ```

     This repository's absolute path on this Mac is:
     `/Users/eduardofgiovannini/Documents/GitHub/BEATS`.
5. Add action **Show Notification**, with its content set to the shell
   script's output (the "Shell Script Result" variable).
6. In the Shortcut's settings, enable **Use with Siri** and record a phrase
   (e.g. "Lock in").

### Validation before trusting it

- Run the script directly first, without Shortcuts, to confirm it behaves:

  ```bash
  ./scripts/beats-siri-trigger.sh "Deep Work"
  ./scripts/beats-siri-trigger.sh "Not A Real Profile"   # expect exit 64
  ```

- Only after a direct run succeeds, test it from inside Shortcuts, then from
  Siri.
- If the Shortcut runs but nothing happens, check Shortcuts' permission to
  run shell scripts (System Settings → Privacy & Security) and that the
  absolute path in step 4 is correct.

### Non-goals for this prototype

- No calendar-, location-, or Wi-Fi-based automatic profile selection (see
  `docs/PROPOSED_UPGRADES.md`, Upgrade A, for that as a separate, larger
  change).
- No changes to `beats-headphones.sh`, `beats_config.py`, or any config
  file schema.
- No handling for Shortcuts running multiple BEATS requests concurrently.

## Context-Aware Auto-Profile

`scripts/beats-auto-profile.sh` is a zero-input entry point: it resolves a
session profile from live context (current Wi-Fi SSID, current time) instead
of a manual pick or a Siri-dictated name, then hands off to
`beats-siri-trigger.sh` unchanged. It's meant for automations that can't
prompt for input at all — e.g. a Shortcuts Automation firing on "arrive at
Wi-Fi network" or a fixed time of day.

Status: script and rule engine are built. Wiring it into a real Shortcuts
Automation on this Mac has not been done or tested — same caveat as the Siri
Shortcut Trigger above.

### How resolution works

Precedence, highest first:

1. **Wi-Fi SSID match** — if the current network's SSID has a rule.
2. **Time-of-day range** — if the current time falls in a configured range.
3. **Fallback profile** — an explicit catch-all, if set.
4. **Nothing** — resolves to blank, which `beats-headphones.sh` already
   treats as "use `default_profile` from `beats-settings.json`." No
   existing default-profile behavior changes.

Rules live in `config/beats-profile-rules.json` and are only ever read
through `beats_config.py`, never edited by hand-parsing in the shell
scripts. If a rule points at a profile that's since been deleted, resolution
silently skips that rule and falls through to the next signal — a stale
rules file degrades gracefully instead of breaking a run.

Non-goal in this version: time ranges spanning midnight (e.g. `22:00`–`02:00`)
are rejected at creation time rather than silently mishandled. Calendar/
EventKit-based rules are also out of scope for this version — see
`docs/PROPOSED_UPGRADES.md`, Upgrade A, for that as explicit future scope.

### Managing rules

Preferred path:

- use `Beats_Settings.app` for viewing and editing Wi-Fi, time, and fallback rules

CLI path:

```bash
# View current rules
python3 scripts/beats_config.py view-profile-rules

# Wi-Fi rules
python3 scripts/beats_config.py set-wifi-rule "Office-5G" "Deep Work"
python3 scripts/beats_config.py remove-wifi-rule "Office-5G"

# Time-of-day rules (24-hour HH:MM, start <= end, no midnight wraparound)
python3 scripts/beats_config.py add-time-rule "13:00" "14:00" "Focus Reset"
python3 scripts/beats_config.py remove-time-rule 0   # by index shown in view-profile-rules

# Fallback profile (used when no Wi-Fi or time rule matches)
python3 scripts/beats_config.py set-fallback-profile "Silent Routing"
python3 scripts/beats_config.py set-fallback-profile ""   # clear it
```

All four rule-editing commands validate the target profile name against
`beats-profiles.json` and reject unknown profiles up front.

### Wire it into a zero-input Shortcuts Automation

1. Make the script executable (one-time):

   ```bash
   chmod +x ./scripts/beats-auto-profile.sh
   ```

2. Configure at least one Wi-Fi or time rule (see above) — with no rules
   configured, this always resolves to the existing default profile, which
   is a safe but unremarkable starting state.
3. In **Shortcuts**, go to the **Automation** tab and create a new personal
   automation (e.g. trigger: "Arrive" at a saved Wi-Fi network, or "Time of
   Day").
4. Turn off "Ask Before Running" for this automation — the entire point is
   that it runs without a prompt.
5. Add action **Run Shell Script**:
   - Shell: `/bin/zsh`
   - Script:

     ```bash
     /Users/eduardofgiovannini/Documents/GitHub/BEATS/scripts/beats-auto-profile.sh
     ```

     This repository's absolute path on this Mac is:
     `/Users/eduardofgiovannini/Documents/GitHub/BEATS`.
6. Optionally add **Show Notification** using the shell script's result, so
   a silent automation still gives visible confirmation.

### Validation before trusting it

- Run it directly first, with no Shortcuts involved:

  ```bash
  ./scripts/beats-auto-profile.sh
  ```

  Confirm the resolved profile (visible in the printed summary line) matches
  what your current Wi-Fi/time rules should produce.
- Check what SSID macOS actually reports, if resolution isn't matching:

  ```bash
  networksetup -getairportnetwork en0
  ```

  Some Macs expose Wi-Fi on `en1` instead of `en0` — if `en0` reports "not
  associated" but you are connected, this is the first thing to check.
- Only after a direct run resolves correctly, enable the Shortcuts
  Automation trigger.

### Non-goals for this version

- No calendar/EventKit signal (explicit future scope, not this version).
- No time ranges spanning midnight.
- No changes to `beats-headphones.sh`, `beats-siri-trigger.sh`, or
  existing config file formats — this is strictly an additive lookup layer.

## Operational Best Practices

- Keep Boom 3D in the preferred saved state before running the workflow.
- Use profiles for repeatable session starts.
- Use named sources for stable daily options.
- Keep ad hoc streaming links in `Custom URL`.
- Use `beats-siri-trigger.sh` for automation surfaces that cannot show dialogs.
- Use `beats-auto-profile.sh` only after rule validation on the real Mac.
- Launch `Beats_Status.app` only when you want a persistent live view; it is intentionally opt-in, not auto-installed.
- Version-control `beats-music-sources.tsv`, `beats-profiles.json`, `beats-settings.json`, and `beats-profile-rules.json` after meaningful changes.
