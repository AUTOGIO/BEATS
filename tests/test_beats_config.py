#!/usr/bin/env python3
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_MODULE_DIR = REPO_ROOT / "scripts"
sys.path.insert(0, str(CONFIG_MODULE_DIR))

import beats_config as config  # noqa: E402


class BeatsConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.config_dir = Path(self.temp_dir.name) / "config"
        self.config_dir.mkdir()
        self.settings_path = self.config_dir / "beats-settings.json"
        self.profiles_path = self.config_dir / "beats-profiles.json"
        self.sources_path = self.config_dir / "beats-music-sources.tsv"
        self.rules_path = self.config_dir / "beats-profile-rules.json"

        self.settings_path.write_text(
            json.dumps(
                {
                    "default_profile": "Deep Work",
                    "default_headphones_name": "beats4",
                    "default_headphones_mac": "58:36:53:C3:42:E9",
                    "boom_3d_app": "/Applications/Boom 3D.app",
                    "boom_3d_bundle_id": "com.globaldelight.Boom3DMAS",
                    "status_file_path": str(
                        Path(self.temp_dir.name) / "latest-status.json"
                    ),
                },
                indent=2,
            )
            + "\n"
        )
        self.profiles_path.write_text(
            json.dumps(
                [
                    {
                        "name": "Deep Work",
                        "music_source_label": "WORK",
                        "music_source_type": "url",
                        "boom_note": "Work tuning",
                        "headphones_name": "",
                        "headphones_mac": "",
                    },
                    {
                        "name": "Focus Reset",
                        "music_source_label": "Focus Noise",
                        "music_source_type": "apple_music",
                        "boom_note": "Reset tuning",
                        "headphones_name": "",
                        "headphones_mac": "",
                    },
                ],
                indent=2,
            )
            + "\n"
        )
        self.sources_path.write_text(
            "WORK\thttps://example.com/work\n"
            "Focus Noise\tFocus Noise\n"
        )
        self.rules_path.write_text(
            json.dumps(
                {
                    "wifi": {"Office-5G": "Deep Work"},
                    "time_ranges": [
                        {"start": "09:00", "end": "12:00", "profile": "Focus Reset"}
                    ],
                    "fallback_profile": "Deep Work",
                },
                indent=2,
            )
            + "\n"
        )

        self.path_patch = patch.multiple(
            config,
            CONFIG_DIR=self.config_dir,
            SETTINGS_PATH=self.settings_path,
            PROFILES_PATH=self.profiles_path,
            SOURCES_PATH=self.sources_path,
            RULES_PATH=self.rules_path,
        )
        self.path_patch.start()

    def tearDown(self) -> None:
        self.path_patch.stop()
        self.temp_dir.cleanup()

    def test_source_kind(self) -> None:
        self.assertEqual(config.source_kind(""), "none")
        self.assertEqual(config.source_kind("Headphones Only"), "none")
        self.assertEqual(config.source_kind("https://example.com"), "url")
        self.assertEqual(config.source_kind("https://music.apple.com/br/playlist/x"), "apple_music_url")
        self.assertEqual(config.source_kind("music://playlist/p.x"), "apple_music_url")
        self.assertEqual(config.source_kind("Focus Noise"), "playlist")

    def test_runtime_env_json(self) -> None:
        args = type(
            "Args",
            (),
            {
                "profile": "Deep Work",
                "music_source": "",
                "headphones_name": "",
                "headphones_mac": "",
            },
        )()
        context = config.build_runtime_context(args)
        self.assertEqual(context["PROFILE_NAME_USED"], "Deep Work")
        self.assertEqual(context["MUSIC_KIND"], "url")

    def test_validate_profile_source(self) -> None:
        self.assertEqual(
            config.validate_profile_source("Focus Noise", "apple_music"),
            "Focus Noise",
        )
        with self.assertRaises(SystemExit):
            config.validate_profile_source("Ghost", "apple_music")

    def test_reserved_source_names(self) -> None:
        with self.assertRaises(SystemExit):
            config.upsert_source(
                type("Args", (), {"label": "Headphones Only", "value": "x"})()
            )

    def test_resolve_profile_from_context(self) -> None:
        self.assertEqual(
            config.resolve_profile_from_context("Office-5G", "10:00"),
            "Deep Work",
        )
        self.assertEqual(
            config.resolve_profile_from_context("", "10:00"),
            "Focus Reset",
        )
        self.assertEqual(
            config.resolve_profile_from_context("Unknown", "18:00"),
            "Deep Work",
        )

    def test_runtime_env_rejects_unknown_profile(self) -> None:
        args = type(
            "Args",
            (),
            {
                "profile": "Ghost",
                "music_source": "",
                "headphones_name": "",
                "headphones_mac": "",
            },
        )()
        with self.assertRaises(SystemExit):
            config.runtime_env(args)

    def test_update_setting_rejects_unknown_key(self) -> None:
        args = type("Args", (), {"key": "totally_fake_key", "value": "x"})()
        with self.assertRaises(SystemExit):
            config.update_setting(args)

    def test_update_setting_rejects_bad_mac(self) -> None:
        args = type(
            "Args",
            (),
            {"key": "default_headphones_mac", "value": "not-a-mac"},
        )()
        with self.assertRaises(SystemExit):
            config.update_setting(args)

    def test_list_wifi_and_time_rules(self) -> None:
        from io import StringIO

        args = type("Args", (), {})()
        buffer = StringIO()
        with patch("sys.stdout", buffer):
            config.list_wifi_rules(args)
        self.assertIn("Office-5G\tDeep Work", buffer.getvalue())

        buffer = StringIO()
        with patch("sys.stdout", buffer):
            config.list_time_rules(args)
        self.assertIn("0\t09:00\t12:00\tFocus Reset", buffer.getvalue())


class StatusSchemaTests(unittest.TestCase):
    def test_status_json_has_exit_code(self) -> None:
        sample = {
            "success": True,
            "exit_code": 0,
            "profile": {"name": "Deep Work"},
            "device": {"headphones_name": "beats4", "headphones_mac": "58:36:53:C3:42:E9"},
            "music": {"label": "Focus Noise", "kind": "playlist"},
            "steps": [{"label": "Profile", "status": "ok", "detail": "ok"}],
        }
        self.assertIn("exit_code", sample)
        self.assertNotIn("exitCode", sample)


if __name__ == "__main__":
    unittest.main()
