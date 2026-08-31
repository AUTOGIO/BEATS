#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
CONFIG_DIR = REPO_ROOT / "config"
APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "LockInAudioWorkflow"
SETTINGS_PATH = CONFIG_DIR / "beats-settings.json"
PROFILES_PATH = CONFIG_DIR / "beats-profiles.json"
SOURCES_PATH = CONFIG_DIR / "beats-music-sources.tsv"
RULES_PATH = CONFIG_DIR / "beats-profile-rules.json"

DEFAULT_SETTINGS = {
    "default_profile": "Deep Work",
    "default_headphones_name": "Your Beats Name",
    "default_headphones_mac": "00:00:00:00:00:00",
    "boom_3d_app": "/Applications/Boom 3D.app",
    "boom_3d_bundle_id": "com.globaldelight.Boom3DMAS",
    "status_file_path": str(APP_SUPPORT_DIR / "latest-status.json"),
    "youtube_app": "",
}

DEFAULT_PROFILES = [
    {
        "name": "Deep Work",
        "music_source_label": "WORK",
        "music_source_type": "url",
        "boom_note": "Reminder: keep Boom 3D on your saved work tuning (not auto-switched).",
        "headphones_name": "",
        "headphones_mac": "",
    },
    {
        "name": "Focus Reset",
        "music_source_label": "Focus Noise",
        "music_source_type": "apple_music",
        "boom_note": "Reminder: keep Boom 3D on your saved focus-reset tuning (not auto-switched).",
        "headphones_name": "",
        "headphones_mac": "",
    },
    {
        "name": "Silent Routing",
        "music_source_label": "Headphones Only",
        "music_source_type": "none",
        "boom_note": "Prepares Boom 3D and routes audio without starting playback.",
        "headphones_name": "",
        "headphones_mac": "",
    },
]

RESERVED_SOURCE_NAMES = {"Custom URL", "Headphones Only"}
PROFILE_SOURCE_TYPES = {"apple_music", "url", "none"}
ALLOWED_SETTING_KEYS = {
    "default_profile",
    "default_headphones_name",
    "default_headphones_mac",
    "boom_3d_app",
    "boom_3d_bundle_id",
    "status_file_path",
    "youtube_app",
}

STATUS_STEP_SPECS = (
    ("profile", "Profile", "STEP_PROFILE"),
    ("boom", "Boom 3D", "STEP_BOOM"),
    ("bluetooth", "Bluetooth", "STEP_BLUETOOTH"),
    ("headphones", "Headphones", "STEP_HEADPHONES"),
    ("output", "Output", "STEP_OUTPUT"),
    ("input", "Input", "STEP_INPUT"),
    ("music", "Music", "STEP_MUSIC"),
)

# Upgrade A (Context-Aware Auto-Profile, see docs/PROPOSED_UPGRADES.md).
# Pure rule lookup, no prediction: Wi-Fi SSID match takes precedence over
# time-of-day ranges, which take precedence over an explicit fallback
# profile. If nothing matches, resolution returns "" (empty), which the
# rest of the pipeline already treats as "use config/beats-settings.json
# default_profile" -- so this file adds a lookup layer without duplicating
# or overriding existing default-profile logic.
DEFAULT_RULES: dict[str, object] = {
    "wifi": {},
    "time_ranges": [],
    "fallback_profile": "",
}


def _run_text(argv: list[str], timeout: int = 8) -> str:
    try:
        return subprocess.check_output(
            argv,
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return ""


def resolve_youtube_app(configured: str = "") -> str:
    candidate = configured.strip()
    if candidate:
        path = Path(candidate).expanduser()
        if path.is_dir():
            return str(path)
        return ""

    for path in (
        Path.home() / "Applications" / "YouTube.app",
        Path("/Applications/YouTube.app"),
    ):
        if path.is_dir():
            return str(path)
    return ""


def _ssid_from_networksetup() -> str:
    for iface in ("en0", "en1"):
        output = _run_text(["networksetup", "-getairportnetwork", iface])
        prefix = "Current Wi-Fi Network: "
        for line in output.splitlines():
            if line.startswith(prefix):
                ssid = line[len(prefix) :].strip()
                if ssid:
                    return ssid
    return ""


def _ssid_from_ipconfig() -> str:
    for iface in ("en0", "en1"):
        output = _run_text(["ipconfig", "getsummary", iface])
        match = re.search(r"\bSSID\s*:\s*(.+)$", output, re.MULTILINE)
        if match:
            ssid = match.group(1).strip()
            if ssid:
                return ssid
    return ""


def _walk_ssid(value: object) -> str:
    if isinstance(value, dict):
        for key, child in value.items():
            lower = str(key).lower()
            if "ssid" in lower and isinstance(child, str) and child.strip():
                if child.strip().lower() not in {"yes", "no", "true", "false"}:
                    return child.strip()
            found = _walk_ssid(child)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _walk_ssid(child)
            if found:
                return found
    return ""


def _ssid_from_system_profiler() -> str:
    raw = _run_text(["system_profiler", "SPAirPortDataType", "-json"], timeout=20)
    if not raw:
        return ""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return ""
    return _walk_ssid(data)


def current_wifi_ssid() -> str:
    for resolver in (_ssid_from_networksetup, _ssid_from_ipconfig, _ssid_from_system_profiler):
        ssid = resolver()
        if ssid:
            return ssid
    return ""


def build_status_document(
    exit_code: int,
    profile_name: str = "",
    profile_default_source_label: str = "",
    profile_default_source_type: str = "",
    boom_note: str = "",
    headphones_name: str = "",
    headphones_mac: str = "",
    music_label: str = "",
    music_source: str = "",
    music_kind: str = "",
    steps: list[dict[str, str]] | None = None,
) -> dict[str, object]:
    if steps is None:
        steps = [
            {"id": step_id, "label": label, "status": "pending", "detail": ""}
            for step_id, label, _prefix in STATUS_STEP_SPECS
        ]
    return {
        "success": exit_code == 0,
        "exit_code": int(exit_code),
        "profile": {
            "name": profile_name,
            "default_source_label": profile_default_source_label,
            "default_source_type": profile_default_source_type,
            "boom_note": boom_note,
        },
        "device": {
            "headphones_name": headphones_name,
            "headphones_mac": headphones_mac,
        },
        "music": {
            "label": music_label,
            "source": music_source,
            "kind": music_kind,
        },
        "steps": steps,
    }


def write_status(_: argparse.Namespace) -> None:
    path_value = os.environ.get("STATUS_FILE_PATH", "").strip()
    if not path_value:
        return
    exit_raw = os.environ.get("EXIT_CODE", "1")
    try:
        exit_code = int(exit_raw)
    except ValueError:
        exit_code = 1

    steps = [
        {
            "id": step_id,
            "label": label,
            "status": os.environ.get(f"{prefix}_STATUS", "pending"),
            "detail": os.environ.get(f"{prefix}_DETAIL", ""),
        }
        for step_id, label, prefix in STATUS_STEP_SPECS
    ]
    data = build_status_document(
        exit_code=exit_code,
        profile_name=os.environ.get("PROFILE_NAME_USED", ""),
        profile_default_source_label=os.environ.get("PROFILE_DEFAULT_SOURCE_LABEL", ""),
        profile_default_source_type=os.environ.get("PROFILE_DEFAULT_SOURCE_TYPE", ""),
        boom_note=os.environ.get("BOOM_NOTE", ""),
        headphones_name=os.environ.get("HEADPHONES_NAME", ""),
        headphones_mac=os.environ.get("HEADPHONES_MAC", ""),
        music_label=os.environ.get("MUSIC_LABEL", ""),
        music_source=os.environ.get("MUSIC_SOURCE", ""),
        music_kind=os.environ.get("MUSIC_KIND", ""),
        steps=steps,
    )
    path = Path(path_value)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(data, indent=2) + "\n")
    tmp_path.replace(path)


def print_wifi_ssid(_: argparse.Namespace) -> None:
    print(current_wifi_ssid())


def ensure_file(path: Path, default_content: str) -> None:
    if not path.exists():
        path.write_text(default_content)


def load_settings() -> dict[str, str]:
    ensure_file(SETTINGS_PATH, json.dumps(DEFAULT_SETTINGS, indent=2) + "\n")
    settings = DEFAULT_SETTINGS.copy()
    raw = json.loads(SETTINGS_PATH.read_text())
    for key, value in raw.items():
        settings[key] = value
    return settings


def save_settings(settings: dict[str, str]) -> None:
    SETTINGS_PATH.write_text(json.dumps(settings, indent=2) + "\n")


def load_profiles() -> list[dict[str, str]]:
    ensure_file(PROFILES_PATH, json.dumps(DEFAULT_PROFILES, indent=2) + "\n")
    profiles = json.loads(PROFILES_PATH.read_text())
    sources = source_lookup()
    cleaned: list[dict[str, str]] = []
    for profile in profiles:
        name = str(profile.get("name", "")).strip()
        if not name:
            continue
        music_source_label = str(profile.get("music_source_label", "")).strip()
        cleaned.append(
            {
                "name": name,
                "music_source_label": music_source_label,
                "music_source_type": resolve_profile_source_type(
                    str(profile.get("music_source_type", "")).strip(),
                    music_source_label,
                    sources,
                ),
                "boom_note": str(profile.get("boom_note", "")).strip(),
                "headphones_name": str(profile.get("headphones_name", "")).strip(),
                "headphones_mac": str(profile.get("headphones_mac", "")).strip(),
            }
        )
    return cleaned


def save_profiles(profiles: list[dict[str, str]]) -> None:
    PROFILES_PATH.write_text(json.dumps(profiles, indent=2) + "\n")


def load_sources() -> list[tuple[str, str]]:
    SOURCES_PATH.touch(exist_ok=True)
    rows: list[tuple[str, str]] = []
    for raw_line in SOURCES_PATH.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "\t" not in line:
            continue
        label, source = line.split("\t", 1)
        label = label.strip()
        source = source.strip()
        if label and source:
            rows.append((label, source))
    return rows


def save_sources(rows: list[tuple[str, str]]) -> None:
    SOURCES_PATH.write_text("".join(f"{label}\t{source}\n" for label, source in rows))


def print_tsv(rows: list[tuple[str, ...]]) -> None:
    for row in rows:
        print("\t".join(row))


def get_profile(name: str) -> dict[str, str] | None:
    for profile in load_profiles():
        if profile["name"] == name:
            return profile
    return None


def get_default_profile_name() -> str:
    settings = load_settings()
    candidate = str(settings.get("default_profile", "")).strip()
    if candidate and get_profile(candidate):
        return candidate
    profiles = load_profiles()
    return profiles[0]["name"] if profiles else ""


def load_rules() -> dict[str, object]:
    ensure_file(RULES_PATH, json.dumps(DEFAULT_RULES, indent=2) + "\n")
    raw = json.loads(RULES_PATH.read_text())
    rules = json.loads(json.dumps(DEFAULT_RULES))  # deep copy of defaults
    wifi = raw.get("wifi", {})
    if isinstance(wifi, dict):
        rules["wifi"] = {
            str(ssid).strip(): str(profile).strip()
            for ssid, profile in wifi.items()
            if str(ssid).strip() and str(profile).strip()
        }

    time_ranges = raw.get("time_ranges", [])
    cleaned_ranges: list[dict[str, str]] = []
    if isinstance(time_ranges, list):
        for entry in time_ranges:
            if not isinstance(entry, dict):
                continue
            start = str(entry.get("start", "")).strip()
            end = str(entry.get("end", "")).strip()
            profile = str(entry.get("profile", "")).strip()
            if start and end and profile:
                cleaned_ranges.append({"start": start, "end": end, "profile": profile})
    rules["time_ranges"] = cleaned_ranges

    rules["fallback_profile"] = str(raw.get("fallback_profile", "")).strip()
    return rules


def save_rules(rules: dict[str, object]) -> None:
    RULES_PATH.write_text(json.dumps(rules, indent=2) + "\n")


def _valid_time_hhmm(value: str) -> bool:
    parts = value.split(":")
    if len(parts) != 2:
        return False
    hour_str, minute_str = parts
    if not (hour_str.isdigit() and minute_str.isdigit()):
        return False
    hour, minute = int(hour_str), int(minute_str)
    return 0 <= hour <= 23 and 0 <= minute <= 59


def _time_in_range(now: str, start: str, end: str) -> bool:
    # Simple lexicographic HH:MM comparison. Non-goal: ranges that wrap past
    # midnight (e.g. 22:00-02:00) are not supported in v1 -- document this
    # rather than adding wraparound logic before it's actually needed.
    if start <= end:
        return start <= now <= end
    return False


def resolve_profile_from_context(wifi_ssid: str, now_hhmm: str) -> str:
    """Return a profile name from context signals, or "" if nothing matches.

    Precedence: Wi-Fi SSID match, then time-of-day range, then explicit
    fallback_profile. Any rule pointing at a profile that no longer exists
    is skipped (fail-safe, not fail-loud) so a stale rules file can't break
    a run -- it just falls through to the next signal.
    """
    rules = load_rules()
    wifi_ssid = wifi_ssid.strip()
    now_hhmm = now_hhmm.strip()

    if wifi_ssid:
        candidate = rules["wifi"].get(wifi_ssid, "")
        if candidate and get_profile(candidate):
            return candidate

    if now_hhmm and _valid_time_hhmm(now_hhmm):
        for entry in rules["time_ranges"]:
            if _time_in_range(now_hhmm, entry["start"], entry["end"]):
                if get_profile(entry["profile"]):
                    return entry["profile"]

    fallback = rules["fallback_profile"]
    if fallback and get_profile(fallback):
        return fallback

    return ""


def source_lookup() -> dict[str, str]:
    return {label: source for label, source in load_sources()}


def source_kind(value: str) -> str:
    if not value or value == "Headphones Only":
        return "none"
    if value.startswith("music://"):
        return "apple_music_url"
    if value.startswith(("http://", "https://")):
        if "music.apple.com" in value:
            return "apple_music_url"
        return "url"
    return "playlist"


def resolve_profile_source_type(
    raw_type: str,
    music_source_label: str,
    sources: dict[str, str] | None = None,
) -> str:
    normalized = raw_type.strip().lower()
    if normalized in PROFILE_SOURCE_TYPES:
        return normalized

    label = music_source_label.strip()
    if not label or label == "Headphones Only":
        return "none"

    if sources is None:
        sources = source_lookup()
    source_value = sources.get(label, label)
    return "url" if source_kind(source_value) == "url" else "apple_music"


def validate_profile_source(label: str, source_type: str) -> str:
    normalized_type = source_type.strip().lower()
    if normalized_type not in PROFILE_SOURCE_TYPES:
        raise SystemExit(
            "Source type must be one of: apple_music, url, none."
        )

    normalized_label = label.strip()
    if normalized_type == "none":
        return "Headphones Only"

    if not normalized_label:
        raise SystemExit("Profile source label is required for apple_music or url profiles.")

    sources = source_lookup()
    if normalized_label not in sources:
        raise SystemExit(
            f"Unknown source label: {normalized_label}. "
            "Add it to the music source registry first."
        )

    actual_kind = source_kind(sources[normalized_label])
    if normalized_type == "apple_music" and actual_kind != "playlist":
        raise SystemExit(
            f"Source label {normalized_label} is not an Apple Music playlist entry."
        )
    if normalized_type == "url" and actual_kind not in ("url", "apple_music_url"):
        raise SystemExit(
            f"Source label {normalized_label} is not a URL entry."
        )
    return normalized_label


def _valid_mac(value: str) -> bool:
    parts = value.split(":")
    if len(parts) != 6:
        return False
    return all(len(part) == 2 and all(ch in "0123456789abcdefABCDEF" for ch in part) for part in parts)


def validate_setting(key: str, value: str) -> None:
    if key not in ALLOWED_SETTING_KEYS:
        raise SystemExit(f"Unknown setting key: {key}")
    if key == "default_headphones_mac" and value.strip() and not _valid_mac(value.strip()):
        raise SystemExit("Headphones MAC must be six colon-separated hex pairs (e.g. AA:BB:CC:DD:EE:FF).")
    if key == "default_profile" and value.strip() and not get_profile(value.strip()):
        raise SystemExit(f"Unknown profile: {value.strip()}")
    if key == "boom_3d_app" and value.strip() and not Path(value.strip()).exists():
        raise SystemExit(f"Boom 3D app not found at: {value.strip()}")
    if key == "youtube_app" and value.strip() and not Path(value.strip()).expanduser().exists():
        raise SystemExit(f"YouTube app not found at: {value.strip()}")


def build_runtime_context(args: argparse.Namespace) -> dict[str, str]:
    settings = load_settings()
    sources = source_lookup()
    selected_profile = args.profile.strip() if args.profile else ""
    if selected_profile and not get_profile(selected_profile):
        raise SystemExit(f"Unknown profile: {selected_profile}")
    profile = get_profile(selected_profile) if selected_profile else None
    if profile is None and not selected_profile:
        default_profile_name = get_default_profile_name()
        profile = get_profile(default_profile_name) if default_profile_name else None

    music_token = (args.music_source or "").strip()
    explicit_music_input = bool(music_token)
    profile_source_type = profile.get("music_source_type", "") if profile else ""
    if not music_token and profile:
        music_token = profile.get("music_source_label", "").strip()
    if not music_token:
        music_token = "Focus Noise"

    music_label = music_token
    music_source = music_token
    if explicit_music_input and music_token in sources:
        music_label = music_token
        music_source = sources[music_token]
    elif explicit_music_input and music_token == "Headphones Only":
        music_label = "Headphones Only"
        music_source = ""
    elif not explicit_music_input and profile:
        music_label = profile.get("music_source_label", "").strip() or "Headphones Only"
        if profile_source_type == "none":
            music_label = "Headphones Only"
            music_source = ""
        else:
            music_source = sources.get(music_label, music_label)
    elif music_token in sources:
        music_label = music_token
        music_source = sources[music_token]
    elif music_token == "Headphones Only":
        music_label = "Headphones Only"
        music_source = ""

    if explicit_music_input:
        resolved_music_kind = source_kind(music_source)
    elif profile_source_type == "apple_music":
        resolved_music_kind = "playlist"
    elif profile_source_type == "url":
        resolved_music_kind = source_kind(music_source)
    elif profile_source_type == "none":
        resolved_music_kind = "none"
    else:
        resolved_music_kind = source_kind(music_source)

    resolved = {
        "PROFILE_NAME_USED": profile["name"] if profile else "",
        "PROFILE_DEFAULT_SOURCE_LABEL": profile.get("music_source_label", "").strip() if profile else "",
        "PROFILE_DEFAULT_SOURCE_TYPE": profile_source_type if profile else "",
        "BOOM_NOTE": profile.get("boom_note", "").strip() if profile else "",
        "HEADPHONES_NAME": args.headphones_name.strip() if args.headphones_name else "",
        "HEADPHONES_MAC": args.headphones_mac.strip() if args.headphones_mac else "",
        "MUSIC_LABEL": music_label,
        "MUSIC_SOURCE": music_source,
        "MUSIC_KIND": resolved_music_kind,
        "BOOM_3D_APP": str(settings["boom_3d_app"]),
        "BOOM_3D_BUNDLE_ID": str(settings["boom_3d_bundle_id"]),
        "STATUS_FILE_DEFAULT": str(settings["status_file_path"]),
        "YOUTUBE_APP": resolve_youtube_app(str(settings.get("youtube_app", ""))),
    }

    if not resolved["HEADPHONES_NAME"]:
        resolved["HEADPHONES_NAME"] = (
            profile.get("headphones_name", "").strip() if profile else ""
        ) or str(settings["default_headphones_name"])
    if not resolved["HEADPHONES_MAC"]:
        resolved["HEADPHONES_MAC"] = (
            profile.get("headphones_mac", "").strip() if profile else ""
        ) or str(settings["default_headphones_mac"])

    return resolved


def runtime_env(args: argparse.Namespace) -> None:
    resolved = build_runtime_context(args)
    for key, value in resolved.items():
        print(f"{key}={shlex.quote(value)}")


def runtime_env_json(args: argparse.Namespace) -> None:
    print(json.dumps(build_runtime_context(args)))


def resolve_profile(args: argparse.Namespace) -> None:
    print(resolve_profile_from_context(args.wifi_ssid or "", args.now or ""))


def list_wifi_rules(_: argparse.Namespace) -> None:
    rules = load_rules()
    for ssid, profile in rules["wifi"].items():
        print(f"{ssid}\t{profile}")


def list_time_rules(_: argparse.Namespace) -> None:
    rules = load_rules()
    for index, entry in enumerate(rules["time_ranges"]):
        print(f"{index}\t{entry['start']}\t{entry['end']}\t{entry['profile']}")


def view_profile_rules(_: argparse.Namespace) -> None:
    rules = load_rules()
    if not rules["wifi"] and not rules["time_ranges"] and not rules["fallback_profile"]:
        print("No profile rules configured.")
        return
    lines = []
    if rules["wifi"]:
        lines.append("Wi-Fi rules:")
        for ssid, profile in rules["wifi"].items():
            lines.append(f"  {ssid} -> {profile}")
    if rules["time_ranges"]:
        lines.append("Time rules:")
        for entry in rules["time_ranges"]:
            lines.append(f"  {entry['start']}-{entry['end']} -> {entry['profile']}")
    if rules["fallback_profile"]:
        lines.append(f"Fallback profile: {rules['fallback_profile']}")
    print("\n".join(lines))


def set_wifi_rule(args: argparse.Namespace) -> None:
    ssid = args.ssid.strip()
    profile = args.profile.strip()
    if not ssid or not profile:
        raise SystemExit("SSID and profile are required.")
    if not get_profile(profile):
        raise SystemExit(f"Unknown profile: {profile}")
    rules = load_rules()
    rules["wifi"][ssid] = profile
    save_rules(rules)


def remove_wifi_rule(args: argparse.Namespace) -> None:
    ssid = args.ssid.strip()
    rules = load_rules()
    rules["wifi"].pop(ssid, None)
    save_rules(rules)


def add_time_rule(args: argparse.Namespace) -> None:
    start = args.start.strip()
    end = args.end.strip()
    profile = args.profile.strip()
    if not _valid_time_hhmm(start) or not _valid_time_hhmm(end):
        raise SystemExit("Start and end must be HH:MM (24-hour).")
    if start > end:
        raise SystemExit(
            "Ranges spanning midnight are not supported in v1; "
            "use a start time earlier than or equal to the end time."
        )
    if not get_profile(profile):
        raise SystemExit(f"Unknown profile: {profile}")
    rules = load_rules()
    rules["time_ranges"].append({"start": start, "end": end, "profile": profile})
    save_rules(rules)


def remove_time_rule(args: argparse.Namespace) -> None:
    index = args.index
    rules = load_rules()
    if 0 <= index < len(rules["time_ranges"]):
        rules["time_ranges"].pop(index)
        save_rules(rules)
    else:
        raise SystemExit(f"No time rule at index {index}.")


def set_fallback_profile(args: argparse.Namespace) -> None:
    name = args.name.strip()
    if name and not get_profile(name):
        raise SystemExit(f"Unknown profile: {name}")
    rules = load_rules()
    rules["fallback_profile"] = name
    save_rules(rules)


def list_profiles(_: argparse.Namespace) -> None:
    rows = [
        (
            profile["name"],
            profile["music_source_label"],
            profile["music_source_type"],
            profile["boom_note"],
            profile["headphones_name"],
            profile["headphones_mac"],
        )
        for profile in load_profiles()
    ]
    print_tsv(rows)


def list_sources(args: argparse.Namespace) -> None:
    rows = load_sources()
    if args.kind == "all":
        print_tsv(rows)
        return

    filtered_rows = []
    for label, value in rows:
        kind = source_kind(value)
        if kind == "playlist":
            list_kind = "apple_music"
        elif kind in ("url", "apple_music_url"):
            list_kind = "url"
        else:
            list_kind = kind
        if list_kind == args.kind:
            filtered_rows.append((label, value))
    print_tsv(filtered_rows)


def get_default_profile(_: argparse.Namespace) -> None:
    print(get_default_profile_name())


def get_setting(args: argparse.Namespace) -> None:
    settings = load_settings()
    print(settings.get(args.key, ""))


def update_setting(args: argparse.Namespace) -> None:
    key = args.key.strip()
    value = args.value
    validate_setting(key, value)
    settings = load_settings()
    settings[key] = value
    save_settings(settings)


def view_settings(_: argparse.Namespace) -> None:
    settings = load_settings()
    print(
        "\n".join(
            [
                f"Default profile: {settings['default_profile']}",
                f"Headphones name: {settings['default_headphones_name']}",
                f"Headphones MAC: {settings['default_headphones_mac']}",
                f"Boom 3D app: {settings['boom_3d_app']}",
                f"Boom 3D bundle ID: {settings['boom_3d_bundle_id']}",
                f"Status file: {settings['status_file_path']}",
                f"YouTube app: {settings.get('youtube_app') or resolve_youtube_app() or '(auto, not found)'}",
            ]
        )
    )


def view_profiles(_: argparse.Namespace) -> None:
    profiles = load_profiles()
    if not profiles:
        print("No profiles configured.")
        return
    chunks = []
    for profile in profiles:
        chunks.append(
            "\n".join(
                [
                    f"Profile: {profile['name']}",
                    f"Source: {profile['music_source_label'] or 'None'}",
                    f"Source type: {profile['music_source_type']}",
                    f"Boom note: {profile['boom_note'] or 'None'}",
                    f"Headphones override: {profile['headphones_name'] or 'Default'}",
                    f"Headphones MAC override: {profile['headphones_mac'] or 'Default'}",
                ]
            )
        )
    print("\n\n".join(chunks))


def upsert_source(args: argparse.Namespace) -> None:
    label = args.label.strip()
    value = args.value.strip()
    if not label or not value:
        raise SystemExit("Label and value are required.")
    if any(ch in label for ch in ("\t", "\n", "\r")):
        raise SystemExit("Source name cannot contain tabs or newlines.")
    if any(ch in value for ch in ("\t", "\n", "\r")):
        raise SystemExit("Source value cannot contain tabs or newlines.")
    if label in RESERVED_SOURCE_NAMES:
        raise SystemExit(f"{label} is reserved.")

    rows = load_sources()
    replaced = False
    updated: list[tuple[str, str]] = []
    for existing_label, existing_value in rows:
        if existing_label == label:
            updated.append((label, value))
            replaced = True
        else:
            updated.append((existing_label, existing_value))
    if not replaced:
        updated.append((label, value))
    save_sources(updated)


def remove_source(args: argparse.Namespace) -> None:
    label = args.label.strip()
    rows = [(existing_label, existing_value) for existing_label, existing_value in load_sources() if existing_label != label]
    save_sources(rows)


def upsert_profile(args: argparse.Namespace) -> None:
    name = args.name.strip()
    if not name:
      raise SystemExit("Profile name is required.")

    music_source_type = args.music_source_type.strip().lower()
    music_source_label = validate_profile_source(args.music_source_label.strip(), music_source_type)
    boom_note = args.boom_note.strip()
    headphones_name = args.headphones_name.strip()
    headphones_mac = args.headphones_mac.strip()

    profiles = load_profiles()
    updated: list[dict[str, str]] = []
    replaced = False
    for profile in profiles:
        if profile["name"] == name:
            updated.append(
                {
                    "name": name,
                    "music_source_label": music_source_label,
                    "music_source_type": music_source_type,
                    "boom_note": boom_note,
                    "headphones_name": headphones_name,
                    "headphones_mac": headphones_mac,
                }
            )
            replaced = True
        else:
            updated.append(profile)
    if not replaced:
        updated.append(
            {
                "name": name,
                "music_source_label": music_source_label,
                "music_source_type": music_source_type,
                "boom_note": boom_note,
                "headphones_name": headphones_name,
                "headphones_mac": headphones_mac,
            }
        )
    save_profiles(updated)


def remove_profile(args: argparse.Namespace) -> None:
    name = args.name.strip()
    profiles = [profile for profile in load_profiles() if profile["name"] != name]
    save_profiles(profiles)
    settings = load_settings()
    if settings.get("default_profile") == name:
        settings["default_profile"] = profiles[0]["name"] if profiles else ""
        save_settings(settings)


def set_default_profile(args: argparse.Namespace) -> None:
    name = args.name.strip()
    if name and not get_profile(name):
        raise SystemExit(f"Unknown profile: {name}")
    settings = load_settings()
    settings["default_profile"] = name
    save_settings(settings)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    runtime = subparsers.add_parser("runtime-env")
    runtime.add_argument("--profile")
    runtime.add_argument("--music-source")
    runtime.add_argument("--headphones-name")
    runtime.add_argument("--headphones-mac")
    runtime.set_defaults(func=runtime_env)

    runtime_json = subparsers.add_parser("runtime-env-json")
    runtime_json.add_argument("--profile")
    runtime_json.add_argument("--music-source")
    runtime_json.add_argument("--headphones-name")
    runtime_json.add_argument("--headphones-mac")
    runtime_json.set_defaults(func=runtime_env_json)

    list_sources_parser = subparsers.add_parser("list-sources")
    list_sources_parser.add_argument(
        "--kind",
        choices=("all", "apple_music", "url"),
        default="all",
    )
    list_sources_parser.set_defaults(func=list_sources)
    subparsers.add_parser("list-profiles").set_defaults(func=list_profiles)
    subparsers.add_parser("get-default-profile").set_defaults(func=get_default_profile)
    subparsers.add_parser("view-settings").set_defaults(func=view_settings)
    subparsers.add_parser("view-profiles").set_defaults(func=view_profiles)

    get_setting_parser = subparsers.add_parser("get-setting")
    get_setting_parser.add_argument("key")
    get_setting_parser.set_defaults(func=get_setting)

    update_setting_parser = subparsers.add_parser("update-setting")
    update_setting_parser.add_argument("key")
    update_setting_parser.add_argument("value")
    update_setting_parser.set_defaults(func=update_setting)

    upsert_source_parser = subparsers.add_parser("upsert-source")
    upsert_source_parser.add_argument("label")
    upsert_source_parser.add_argument("value")
    upsert_source_parser.set_defaults(func=upsert_source)

    remove_source_parser = subparsers.add_parser("remove-source")
    remove_source_parser.add_argument("label")
    remove_source_parser.set_defaults(func=remove_source)

    upsert_profile_parser = subparsers.add_parser("upsert-profile")
    upsert_profile_parser.add_argument("name")
    upsert_profile_parser.add_argument("music_source_label")
    upsert_profile_parser.add_argument("music_source_type")
    upsert_profile_parser.add_argument("boom_note")
    upsert_profile_parser.add_argument("headphones_name")
    upsert_profile_parser.add_argument("headphones_mac")
    upsert_profile_parser.set_defaults(func=upsert_profile)

    remove_profile_parser = subparsers.add_parser("remove-profile")
    remove_profile_parser.add_argument("name")
    remove_profile_parser.set_defaults(func=remove_profile)

    set_default_profile_parser = subparsers.add_parser("set-default-profile")
    set_default_profile_parser.add_argument("name")
    set_default_profile_parser.set_defaults(func=set_default_profile)

    resolve_profile_parser = subparsers.add_parser("resolve-profile")
    resolve_profile_parser.add_argument("--wifi-ssid")
    resolve_profile_parser.add_argument("--now", help="Current time as HH:MM (24-hour)")
    resolve_profile_parser.set_defaults(func=resolve_profile)

    subparsers.add_parser("view-profile-rules").set_defaults(func=view_profile_rules)
    subparsers.add_parser("list-wifi-rules").set_defaults(func=list_wifi_rules)
    subparsers.add_parser("list-time-rules").set_defaults(func=list_time_rules)

    set_wifi_rule_parser = subparsers.add_parser("set-wifi-rule")
    set_wifi_rule_parser.add_argument("ssid")
    set_wifi_rule_parser.add_argument("profile")
    set_wifi_rule_parser.set_defaults(func=set_wifi_rule)

    remove_wifi_rule_parser = subparsers.add_parser("remove-wifi-rule")
    remove_wifi_rule_parser.add_argument("ssid")
    remove_wifi_rule_parser.set_defaults(func=remove_wifi_rule)

    add_time_rule_parser = subparsers.add_parser("add-time-rule")
    add_time_rule_parser.add_argument("start")
    add_time_rule_parser.add_argument("end")
    add_time_rule_parser.add_argument("profile")
    add_time_rule_parser.set_defaults(func=add_time_rule)

    remove_time_rule_parser = subparsers.add_parser("remove-time-rule")
    remove_time_rule_parser.add_argument("index", type=int)
    remove_time_rule_parser.set_defaults(func=remove_time_rule)

    set_fallback_profile_parser = subparsers.add_parser("set-fallback-profile")
    set_fallback_profile_parser.add_argument("name")
    set_fallback_profile_parser.set_defaults(func=set_fallback_profile)

    subparsers.add_parser("write-status").set_defaults(func=write_status)
    subparsers.add_parser("current-wifi-ssid").set_defaults(func=print_wifi_ssid)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
