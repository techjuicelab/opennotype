import importlib.util
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest


class PromptTestPackagingPaths(unittest.TestCase):
    def assert_rejects_staging_link(self, relative_path):
        source = pathlib.Path(__file__).with_name("build-prompt-test.sh")
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            scripts = root / "project/scripts"
            scripts.mkdir(parents=True)
            wrapper = scripts / source.name
            shutil.copy2(source, wrapper)
            called = root / "builder-was-called"
            (scripts / "build-app.sh").write_text(f"#!/bin/bash\ntouch '{called}'\nexit 0\n")
            (scripts / "build-app.sh").chmod(0o700)
            victim = root / "existing-install"
            victim.mkdir()
            marker = victim / "keep"
            marker.write_text("existing app must stay intact")
            link = root / "project" / relative_path
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(victim, target_is_directory=True)
            result = subprocess.run(["bash", str(wrapper)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Refusing a symlink", result.stderr)
            self.assertFalse(called.exists())
            self.assertEqual(marker.read_text(), "existing app must stay intact")

    def test_rejects_shared_builder_staging_parent_link_before_build(self):
        self.assert_rejects_staging_link("build/.staging")

    def test_rejects_shared_builder_staged_app_link_before_build(self):
        self.assert_rejects_staging_link("build/.staging/OpenNoType.app")


class PromptTestMetadata(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.project = pathlib.Path(__file__).resolve().parent.parent
        helper = cls.project / "scripts/configure-prompt-test.py"
        spec = importlib.util.spec_from_file_location("configure_prompt_test", helper)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        cls.configure = staticmethod(module.configure_prompt_test)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.source_app = self.root / "source/OpenNoType.app"
        self.staged_app = self.root / "staged/OpenNoType Prompt Test.app"
        self.production_info = self.root / "Resources/Info.plist"
        self.version_path = self.root / "Resources/PromptTestVersion.plist"
        self.production_info.parent.mkdir(parents=True)
        shutil.copy2(self.project / "Resources/Info.plist", self.production_info)
        info = plistlib.loads(self.production_info.read_bytes())
        info.update({
            "SUEnableAutomaticChecks": True,
            "SUAutomaticallyUpdate": True,
            "SUFeedURL": "https://example.invalid/appcast.xml",
            "SUPublicEDKey": "fixture-public-key",
            "OpenNoTypeDistribution": "community",
            "OpenNoTypePreviewVersion": "fixture-preview",
            "OpenNoTypePreviewURL": "https://example.invalid/preview",
            "UnrelatedFixtureSetting": ["preserve", 7, True],
        })
        self.source_app.joinpath("Contents/MacOS").mkdir(parents=True)
        self.source_app.joinpath("Contents/MacOS/OpenNoType").write_bytes(b"fixture, never executed")
        self.source_app.joinpath("Contents/Info.plist").write_bytes(plistlib.dumps(info))
        for language in ("en", "ko"):
            localized = self.source_app / f"Contents/Resources/{language}.lproj/InfoPlist.strings"
            localized.parent.mkdir(parents=True)
            original = (self.project / f"Resources/{language}.lproj/InfoPlist.strings").read_text()
            localized.write_text(original + '\n"UnrelatedFixtureString" = "preserve me";\n')
        shutil.copytree(self.source_app, self.staged_app)
        self.write_version({"CFBundleShortVersionString": "7.8.9", "CFBundleVersion": "777"})
        self.commit = "0123456789abcdef" * 2 + "01234567"
        self.dirty = False
        self.built_at = "2026-10-09T12:34:56Z"

    def write_version(self, value):
        self.version_path.write_bytes(plistlib.dumps(value))

    def snapshot(self, root):
        return {
            str(path.relative_to(root)): path.read_bytes()
            for path in root.rglob("*") if path.is_file()
        }

    def apply_configuration(self, **overrides):
        arguments = {
            "app_path": self.staged_app,
            "version_path": self.version_path,
            "source_commit": self.commit,
            "source_dirty": self.dirty,
            "built_at": self.built_at,
        }
        arguments.update(overrides)
        self.configure(**arguments)

    def assert_rejected_without_changes(self, **overrides):
        before = self.snapshot(self.root)
        with self.assertRaises((ValueError, OSError)):
            self.apply_configuration(**overrides)
        self.assertEqual(self.snapshot(self.root), before)

    def test_applies_version_identity_and_provenance_only_to_staged_bundle(self):
        original_bundle = self.snapshot(self.source_app)
        production_bytes = self.production_info.read_bytes()
        version_bytes = self.version_path.read_bytes()
        self.apply_configuration()
        configured = plistlib.loads(self.staged_app.joinpath("Contents/Info.plist").read_bytes())
        self.assertEqual(configured["CFBundleIdentifier"], "app.opennotype.prompt-test")
        self.assertEqual(configured["CFBundleName"], "OpenNoType Prompt Test")
        self.assertEqual(configured["CFBundleDisplayName"], "OpenNoType Prompt Test")
        self.assertEqual(configured["CFBundleExecutable"], "OpenNoType")
        self.assertEqual(configured["CFBundleShortVersionString"], "7.8.9")
        self.assertEqual(configured["CFBundleVersion"], "777")
        self.assertEqual(configured["OpenNoTypeTestSourceCommit"], self.commit)
        self.assertIs(configured["OpenNoTypeTestSourceDirty"], False)
        self.assertEqual(configured["OpenNoTypeTestBuiltAt"], self.built_at)
        self.assertEqual(configured["UnrelatedFixtureSetting"], ["preserve", 7, True])
        self.assertTrue(configured["LSUIElement"])
        self.assertIs(configured["SUEnableAutomaticChecks"], False)
        self.assertIs(configured["SUAutomaticallyUpdate"], False)
        for key in ("SUFeedURL", "SUPublicEDKey", "OpenNoTypeDistribution"):
            self.assertNotIn(key, configured)
        self.assertFalse(any(key.startswith("OpenNoTypePreview") for key in configured))
        for key in ("NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"):
            self.assertIn("OpenNoType Prompt Test", configured[key])
            for language in ("en", "ko"):
                text = self.staged_app.joinpath(f"Contents/Resources/{language}.lproj/InfoPlist.strings").read_text()
                values = re.findall(r'^"' + key + r'"\s*=\s*("(?:\\.|[^"\\])*")\s*;', text, re.MULTILINE)
                self.assertEqual(len(values), 1)
                self.assertIn("OpenNoType Prompt Test", json.loads(values[0]))
                self.assertIn('"UnrelatedFixtureString" = "preserve me";', text)
        self.assertEqual(self.snapshot(self.source_app), original_bundle)
        self.assertEqual(self.production_info.read_bytes(), production_bytes)
        self.assertEqual(self.version_path.read_bytes(), version_bytes)

    def test_accepts_sha_lengths_boolean_provenance_and_numeric_version_boundaries(self):
        cases = [
            ("0.0.0", "1", "0" * 40, False),
            ("123.0.456", "999999", "abcdef01" * 8, True),
        ]
        for version, build, commit, dirty in cases:
            with self.subTest(version=version, commit_length=len(commit), dirty=dirty):
                shutil.rmtree(self.staged_app)
                shutil.copytree(self.source_app, self.staged_app)
                self.write_version({"CFBundleShortVersionString": version, "CFBundleVersion": build})
                self.apply_configuration(source_commit=commit, source_dirty=dirty, built_at="2024-02-29T00:00:00Z")
                configured = plistlib.loads(self.staged_app.joinpath("Contents/Info.plist").read_bytes())
                self.assertEqual(configured["CFBundleShortVersionString"], version)
                self.assertEqual(configured["CFBundleVersion"], build)
                self.assertEqual(configured["OpenNoTypeTestSourceCommit"], commit)
                self.assertIs(configured["OpenNoTypeTestSourceDirty"], dirty)

    def test_uses_tracked_version_configuration_without_modifying_it(self):
        tracked = self.project / "Resources/PromptTestVersion.plist"
        before = tracked.read_bytes()
        expected = plistlib.loads(before)
        self.apply_configuration(version_path=tracked)
        configured = plistlib.loads(self.staged_app.joinpath("Contents/Info.plist").read_bytes())
        self.assertEqual(set(expected), {"CFBundleShortVersionString", "CFBundleVersion"})
        for key, value in expected.items():
            self.assertEqual(configured[key], value)
        self.assertEqual(tracked.read_bytes(), before)

    def test_rejects_missing_extra_or_non_dictionary_version_configuration_atomically(self):
        for value in (
            {},
            {"CFBundleShortVersionString": "1.2.3"},
            {"CFBundleVersion": "41"},
            {"CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "41", "extra": "reject"},
            ["1.2.3", "41"],
        ):
            with self.subTest(value=value):
                self.write_version(value)
                self.assert_rejected_without_changes()
        self.version_path.write_bytes(b"not a property list")
        self.assert_rejected_without_changes()

    def test_rejects_ambiguous_or_non_string_version_and_build_atomically(self):
        invalid_values = {
            "CFBundleShortVersionString": (
                123, True, [], "1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.03",
                "-1.2.3", "1.2.3-beta", " 1.2.3", "1.2.3\n", "１.2.3",
            ),
            "CFBundleVersion": (41, True, [], "0", "01", "-1", "1.0", " 41", "41\n", "４１"),
        }
        for key, values in invalid_values.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    configuration = {"CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "41"}
                    configuration[key] = value
                    self.write_version(configuration)
                    self.assert_rejected_without_changes()

    def test_rejects_invalid_source_commit_and_non_boolean_dirty_flag_atomically(self):
        for commit in ("", "a" * 39, "a" * 41, "a" * 63, "a" * 65, "A" * 40, "g" * 40, "a" * 40 + "\n", 123, None):
            with self.subTest(commit=commit):
                self.assert_rejected_without_changes(source_commit=commit)
        for dirty in (0, 1, "true", "false", None, []):
            with self.subTest(dirty=dirty):
                self.assert_rejected_without_changes(source_dirty=dirty)

    def test_rejects_non_utc_or_impossible_build_time_atomically(self):
        for timestamp in (
            "2026-10-09 12:34:56Z", "2026-10-09T12:34:56+00:00", "2026-10-09T12:34:56z",
            "2026-10-09T12:34Z", "2026-10-09T12:34:56.000Z", "2026-10-09T12:34:56Z\n",
            "2026-02-29T12:34:56Z", "2026-02-30T12:34:56Z", "2026-10-09T24:00:00Z",
            "2026-10-09T12:34:60Z", "0000-10-09T12:34:56Z", 123, None,
        ):
            with self.subTest(timestamp=timestamp):
                self.assert_rejected_without_changes(built_at=timestamp)

    def test_rejects_unexpected_base_bundle_identity_before_modifying_files(self):
        info_path = self.staged_app / "Contents/Info.plist"
        original = plistlib.loads(info_path.read_bytes())
        for key, value in (
            ("CFBundleIdentifier", "app.opennotype.prompt-test"),
            ("CFBundleIdentifier", "com.example.other"),
            ("CFBundleExecutable", "OtherExecutable"),
        ):
            with self.subTest(key=key, value=value):
                info = dict(original)
                info[key] = value
                info_path.write_bytes(plistlib.dumps(info))
                self.assert_rejected_without_changes()

    def test_rejects_missing_or_duplicate_localizations_before_any_write(self):
        for language in ("en", "ko"):
            path = self.staged_app / f"Contents/Resources/{language}.lproj/InfoPlist.strings"
            original = path.read_text()
            for key in ("NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"):
                for duplicate in (False, True):
                    with self.subTest(language=language, key=key, duplicate=duplicate):
                        if duplicate:
                            invalid = original + f'\n"{key}" = "duplicate";\n'
                        else:
                            invalid = "\n".join(line for line in original.splitlines() if not line.startswith(f'"{key}"'))
                        path.write_text(invalid)
                        self.assert_rejected_without_changes()
                        path.write_text(original)
            path.unlink()
            self.assert_rejected_without_changes()
            path.write_text(original)


if __name__ == "__main__":
    unittest.main()
