# User Manual

## Purpose

This workflow reduces the start-of-session audio setup to a few app actions under `dist/`:

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
./scripts/install_desktop_apps.sh
```

That rebuilds the apps under `dist/` and links `~/.local/bin/beats` to this clone. After moving or recloning the repo, run it again — the apps bake the repository path at compile time.

Open the apps from `dist/` (for example `open dist/Focus_Beats.app`). They are not copied to the Desktop.

### First-run permissions

The applets are ad hoc–signed for personal use. On first launch, macOS may ask for Automation (Music, System Events), and Shortcuts needs permission to run shell scripts. Grant those prompts or the workflow fails with a generic AppleScript error.

## App actions (`dist/`)

### Focus_Beats

This action first presents a profile picker built from `config/beats-profiles.json`. It then presents a source picker built from `config/beats-music-sources.tsv` and two reserved options:

- `Custom URL`
- `Headphones Only`

Source behavior:

- Named playlist entry: plays in Apple Music
- URL entry: opens via the default macOS URL handler
- `music.apple.com` / `music://` links: open in the Music app (`open -a Music`)
- `Custom URL`: prompts for a URL at runtime
- `Headphones Only`: skips music startup

Profile behavior:

- profiles now store an explicit source type: `apple_music`, `url`, or `none`
- that type controls the default non-interactive path used by Siri and any profile run with no manual source override
- in the interactive picker, you can still override the profile default for the current run

If `config/beats-settings.json` has more than one saved headset, Focus_Beats asks **Which headphones?** before starting the run. One saved device skips the dialog. See [Multiple headphones](#multiple-headphones).

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
- `Set YouTube App Path`
- `Set Status File Path`
- `Set Default Profile`
- `View Profiles`
- `Add or Update Profile`
- `Remove Profile`

Profiles can define:

- a default source label
- a default source type
- a Boom note reminder shown at launch time (informational only — BEATS does not switch Boom 3D presets)
- optional headphones name override
- optional headphones MAC override

Profile source types:

- `apple_music`: the default source must be a named playlist entry in `config/beats-music-sources.tsv`
- `url`: the default source must be a named URL entry in `config/beats-music-sources.tsv`
- `none`: the profile resolves to `Headphones Only`

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

## Multiple headphones

`default_headphones_name` / `default_headphones_mac` stay the default headset. Extra devices live in an optional `headphones_devices` map in `config/beats-settings.json` (name → MAC). There is no editor in `Beats_Settings.app` — edit the JSON by hand:

```json
"default_headphones_name": "beats4",
"default_headphones_mac": "AA:BB:CC:DD:EE:FF",
"headphones_devices": {
  "WH-1000XM6": "11:22:33:44:55:66"
}
```

The Bluetooth name must match `blueutil --paired` and `SwitchAudioSource -a -t output` exactly. After adding a second device, rebuild apps with `./scripts/install_desktop_apps.sh` so `Focus_Beats.app` can show the picker.

`Focus_Beats.app` passes `--headphones-name` into the runner; the MAC is looked up from the map. `beats lock-in` still uses the default headset. To pick a named device from the shell:

```bash
./scripts/beats-headphones.sh --profile "Deep Work" --headphones-name "WH-1000XM6"
```

`Stop_Beats.app` / `beats stop` disconnects every saved device that is currently connected, not only the default.

## Editing the Source Registry Manually

The file format is TSV:

```text
Label<TAB>Playlist or URL
```

Example:

```text
YouTube Playlist	https://youtube.com/playlist?list=PLieRSdP0b5KKYe02bLmr778MeMfX6HkUk
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
- change default YouTube.app path: update `config/beats-settings.json` (`youtube_app`, blank = auto-detect `~/Applications` then `/Applications`) or use `Beats_Settings.app`
- change shared status file path: update `config/beats-settings.json` or use `Beats_Settings.app`
- change session defaults: update `config/beats-profiles.json` or use `Beats_Settings.app`

Profile file note:

- each profile now carries `music_source_label` plus `music_source_type`
- older profiles without `music_source_type` are still read safely and inferred on load, but new edits should save the explicit field

Primary config files:

- `config/beats-settings.json`
- `config/beats-profiles.json`
- `config/beats-music-sources.tsv`

## Dependencies

Install required CLI tools:

```bash
brew install blueutil switchaudio-osx
```

## Failure Modes

### Focus_Beats cannot open `beats_config.py`

Symptom:

- dialog `Focus_Beats failed:` with `[Errno 2] No such file or directory` for `scripts/beats_config.py`

Fix:

- the `dist/` apps still point at an old clone path
- from the current repository root run `./scripts/install_desktop_apps.sh`
- confirm `readlink ~/.local/bin/beats` points at this clone

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

- run `Focus_Beats.app` or `beats-siri-trigger.sh` once
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

1. Install the stable CLI (one-time, or after moving the repo):

   ```bash
   ./scripts/install_desktop_apps.sh
   # ensure ~/.local/bin is on PATH
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
     export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
     beats lock-in "$1"
     ```

5. Add action **Show Notification**, with its content set to the shell
   script's output (the "Shell Script Result" variable).
6. In the Shortcut's settings, enable **Use with Siri** and record a phrase
   (e.g. "Lock in").

### Validation before trusting it

- Run the script directly first, without Shortcuts, to confirm it behaves:

  ```bash
  beats doctor
  beats lock-in "Deep Work"
  beats lock-in "Not A Real Profile"   # expect exit 64
  ```

- Only after a direct run succeeds, test it from inside Shortcuts, then from
  Siri.
- If the Shortcut runs but nothing happens, check Shortcuts' permission to
  run shell scripts (System Settings → Privacy & Security) and that
  `~/.local/bin/beats` resolves.

### Non-goals for this prototype

- No calendar-, location-, or Wi-Fi-based automatic profile selection (see
  `docs/PROPOSED_UPGRADES.md`, Upgrade A, for that as a separate, larger
  change).
- No changes to `beats-headphones.sh`, `beats_config.py`, or any config
  file schema.
- No handling for Shortcuts running multiple BEATS requests concurrently.

## Operational Best Practices

- Keep Boom 3D in the preferred saved state before running the workflow.
- Use profiles for repeatable session starts.
- Use named sources for stable daily options.
- Keep ad hoc streaming links in `Custom URL`.
- Use `beats-siri-trigger.sh` for automation surfaces that cannot show dialogs.
- Launch `Beats_Status.app` only when you want a persistent live view; it is intentionally opt-in, not auto-installed.
- Version-control `beats-music-sources.tsv` and `beats-profiles.json` after meaningful changes. Keep `beats-settings.json` local (gitignored).
