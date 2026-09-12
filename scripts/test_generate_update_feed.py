#!/usr/bin/env python3
"""Offline release integrity tests. These use published test vectors, never release keys.

Optional real Sparkle integration (no certificates/Keychain/notarization/network):
  SPARKLE_TEST_ARTIFACT_DIR="$PWD/.build/artifacts/sparkle/Sparkle" \
    python3 -m unittest discover -s scripts -p test_generate_update_feed.py -v
"""
import base64
import importlib.util
import json
import os
import plistlib
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import warnings
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("generate-update-feed.py")
spec = importlib.util.spec_from_file_location("generate_update_feed", SCRIPT)
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)

# Public RFC 8032 section 7.1 test vector 1; NEVER use this known seed for releases.
# https://www.rfc-editor.org/rfc/rfc8032.txt
TEST_SEED = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
PUBLIC = base64.b64encode(bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")).decode()
OTHER_PUBLIC = base64.b64encode(bytes.fromhex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")).decode()
EMPTY_SIGNATURE = base64.b64encode(bytes.fromhex(
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
    "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")).decode()
INFO = {"CFBundleName": "OpenNoType", "CFBundlePackageType": "APPL",
        "CFBundleIdentifier": "app.opennotype.mac", "CFBundleExecutable": "OpenNoType",
        "CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "42", "LSMinimumSystemVersion": "14.0"}
SETTINGS = {"SUFeedURL": feed.FEED_URL, "SUPublicEDKey": PUBLIC,
            "SUEnableAutomaticChecks": True, "SUAutomaticallyUpdate": False}


def metadata():
    return feed.release_identity(INFO, "v1.2.3") | {
        "download_url": feed.REPOSITORY_URL + "/releases/download/v1.2.3/OpenNoType-1.2.3.zip",
        "release_notes_url": feed.REPOSITORY_URL + "/releases/tag/v1.2.3",
        "distribution": "notarized", "length": 123, "signature": EMPTY_SIGNATURE, "published_at": "Sat, 12 Sep 2026 00:00:00 GMT"}


class ReleaseSettingsTests(unittest.TestCase):
    def test_signing_mode_defaults_only_when_missing_and_never_falls_back(self):
        self.assertEqual(feed.signing_mode({}), "notarized")
        self.assertEqual(feed.signing_mode({"RELEASE_SIGNING_MODE": "community"}), "community")
        for value in ("", "adhoc", "Community", None):
            with self.subTest(value=value), self.assertRaises(feed.ReleaseError):
                feed.signing_mode({"RELEASE_SIGNING_MODE": value})

    def test_release_distribution_is_injected_but_development_does_not_claim_notarization(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            channel = Path(directory) / "UpdateChannel.plist"
            channel.write_bytes(plistlib.dumps(SETTINGS))
            for mode in ("community", "notarized"):
                path.write_bytes(plistlib.dumps(INFO))
                result = feed.configure(path, channel, {"RELEASE_SIGNING_MODE": mode}, release=True, tag="v1.2.3", write=True)
                self.assertEqual(result["distribution"], mode)
                self.assertEqual(plistlib.loads(path.read_bytes())["OpenNoTypeDistribution"], mode)
                feed.configure(path, channel, {"RELEASE_SIGNING_MODE": mode}, release=False, tag=None, write=True)
                self.assertNotIn("OpenNoTypeDistribution", plistlib.loads(path.read_bytes()))

    def test_distribution_requires_a_valid_signed_app_declaration_matching_mode(self):
        for declaration in (None, "", "development", "notarized"):
            with self.subTest(declaration=declaration), self.assertRaises(feed.ReleaseError):
                feed.distribution_from_info(INFO | {"OpenNoTypeDistribution": declaration}, "community")
        self.assertEqual(feed.distribution_from_info(INFO | {"OpenNoTypeDistribution": "community"}, "community"), "community")

    def test_signature_details_cannot_relabel_adhoc_as_notarized(self):
        adhoc = "Identifier=app.opennotype.mac\nSignature=adhoc\nTeamIdentifier=not set\n"
        developer_id = "Authority=Developer ID Application: Fixture (TESTONLY)\nAuthority=Developer ID Certification Authority\n"
        feed.validate_signing_details(adhoc, "community")
        feed.validate_signing_details(developer_id, "notarized")
        for details, mode in ((adhoc, "notarized"), (developer_id, "community"), ("unsigned", "community"),
                              (adhoc + "CodeDirectory flags=0x10002(adhoc,runtime)", "community")):
            with self.subTest(mode=mode), self.assertRaises(feed.ReleaseError):
                feed.validate_signing_details(details, mode)

    def test_release_tag_must_match_exactly(self):
        self.assertEqual(feed.release_identity(INFO, "v1.2.3")["build"], 42)
        for tag in ("1.2.3", "v1.2.4", "v1.2.3-beta", "v1.2.3\n"):
            with self.subTest(tag=tag), self.assertRaises(feed.ReleaseError):
                feed.release_identity(INFO, tag)

    def test_only_stable_numeric_versions(self):
        for version in ("1.2", "01.2.3", "1.2.3-beta", "1.2.3/../../x", "1.2.3\n", 123):
            with self.subTest(version=version), self.assertRaises(feed.ReleaseError):
                feed.release_identity(INFO | {"CFBundleShortVersionString": version})

    def test_build_must_be_positive_integer_string(self):
        for build in ("0", "-1", "1.2", "01", "1\n", "", 42, True):
            with self.subTest(build=build), self.assertRaises(feed.ReleaseError):
                feed.release_identity(INFO | {"CFBundleVersion": build})

    def test_minimum_os_and_bundle_identity_are_checked(self):
        for changes in ({"LSMinimumSystemVersion": "13.0"}, {"CFBundleIdentifier": "other.app"},
                        {"CFBundleExecutable": "AnotherApp"}):
            with self.subTest(changes=changes), self.assertRaises(feed.ReleaseError):
                feed.release_identity(INFO | changes)

    def test_checked_in_blank_key_disables_development_updates(self):
        self.assertEqual(feed.update_settings({"SUFeedURL": feed.FEED_URL, "SUPublicEDKey": ""}, {}, release=False), {})

    def test_blank_release_key_fails(self):
        with self.assertRaises(feed.ReleaseError):
            feed.update_settings({"SUFeedURL": feed.FEED_URL, "SUPublicEDKey": ""}, {}, release=True)

    def test_complete_override_and_default_preferences(self):
        actual = feed.update_settings({}, {"SPARKLE_FEED_URL": feed.FEED_URL, "SPARKLE_PUBLIC_ED_KEY": PUBLIC}, release=True)
        self.assertEqual(actual, SETTINGS)
        self.assertEqual(feed.update_settings(SETTINGS, {}, release=True), SETTINGS)

    def test_partial_or_empty_overrides_fail_in_development_too(self):
        for env in ({"SPARKLE_FEED_URL": feed.FEED_URL}, {"SPARKLE_PUBLIC_ED_KEY": PUBLIC},
                    {"SPARKLE_FEED_URL": "", "SPARKLE_PUBLIC_ED_KEY": ""},
                    {"SPARKLE_FEED_URL": feed.FEED_URL, "SPARKLE_PUBLIC_ED_KEY": ""}):
            with self.subTest(fields=list(env)), self.assertRaises(feed.ReleaseError):
                feed.update_settings(SETTINGS, env, release=False)

    def test_public_key_requires_canonical_32_bytes(self):
        values = ["", "***", PUBLIC + "\n", PUBLIC[:-1], base64.b64encode(bytes(32)).decode(),
                  base64.b64encode(b"x" * 31).decode(), base64.b64encode(b"x" * 33).decode(), None]
        for value in values:
            with self.subTest(value=value), self.assertRaises(feed.ReleaseError):
                feed.validate_public_key(value)

    def test_unsafe_feeds_and_noncanonical_release_channels_fail(self):
        for value in ("http://github.com/a", "https://user:pass@github.com/a", "https://github.com/a#x",
                      "https://github.com/a\n", "https://github.com:0/a", "https://github.com:99999/a",
                      "https://github.com\\@evil.test/a", "https:///a"):
            with self.subTest(value=value), self.assertRaises(feed.ReleaseError):
                feed.validate_feed_url(value, release=False)
        for release in (False, True):
            self.assertEqual(feed.validate_feed_url(feed.FEED_URL, release=release), feed.FEED_URL)
            with self.subTest(release=release), self.assertRaises(feed.ReleaseError):
                feed.validate_feed_url("https://test.example/appcast.xml", release=release)

    def test_configure_removes_stale_keys_and_only_writes_requested_plist(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            channel = Path(directory) / "UpdateChannel.plist"
            original = plistlib.dumps(INFO | SETTINGS)
            path.write_bytes(original)
            channel.write_bytes(plistlib.dumps({"SUFeedURL": feed.FEED_URL, "SUPublicEDKey": ""}))
            feed.configure(path, channel, {}, release=False, tag=None, write=False)
            self.assertEqual(path.read_bytes(), original)
            feed.configure(path, channel, {}, release=False, tag=None, write=True)
            self.assertEqual(plistlib.loads(path.read_bytes()), INFO)
            self.assertEqual(plistlib.loads(channel.read_bytes())["SUPublicEDKey"], "")

    def test_release_configuration_requires_tag(self):
        with self.assertRaisesRegex(feed.ReleaseError, "RELEASE_TAG"):
            feed.configure(Path("unused"), Path("unused"), {}, release=True, tag=None, write=False)


class PackagingModeGateTests(unittest.TestCase):
    def run_package_gate(self, **overrides):
        with tempfile.TemporaryDirectory(prefix="opennotype-package-mode-test-") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            script = root / "scripts/package-release.sh"
            shutil.copyfile(SCRIPT.with_name("package-release.sh"), script)
            env = dict(os.environ)
            for name in ("RELEASE_SIGNING_MODE", "DEVELOPER_ID_APPLICATION", "NOTARY_PROFILE", "NOTARY_KEYCHAIN",
                         "RELEASE_TAG", "SPARKLE_PRIVATE_KEY_FILE"):
                env.pop(name, None)
            env.update(overrides)
            return subprocess.run(["/bin/bash", str(script)], env=env, capture_output=True, timeout=5)

    def test_missing_mode_still_requires_developer_id(self):
        result = self.run_package_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"DEVELOPER_ID_APPLICATION", result.stderr)

    def test_invalid_mode_is_rejected_before_other_inputs(self):
        for mode in ("", "adhoc", "automatic", "Community"):
            result = self.run_package_gate(RELEASE_SIGNING_MODE=mode)
            with self.subTest(mode=mode):
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"RELEASE_SIGNING_MODE must be", result.stderr)

    def test_community_requires_sparkle_key_without_requiring_apple_credentials(self):
        result = self.run_package_gate(RELEASE_SIGNING_MODE="community", RELEASE_TAG="v1.2.3")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"SPARKLE_PRIVATE_KEY_FILE", result.stderr)
        self.assertNotIn(b"DEVELOPER_ID_APPLICATION", result.stderr)
        self.assertNotIn(b"NOTARY_PROFILE", result.stderr)

    def test_invalid_notarized_identity_never_falls_back_to_community(self):
        result = self.run_package_gate(RELEASE_SIGNING_MODE="notarized", DEVELOPER_ID_APPLICATION="-", NOTARY_PROFILE="fixture")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"cannot produce a notarized public release", result.stderr)


class PrivateFileAndDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "test-key"
        self.path.write_bytes(base64.b64encode(TEST_SEED) + b"\n")
        self.path.chmod(0o600)

    def test_runtime_seed_format_is_accepted(self):
        feed.validate_private_key_file(self.path)

    def test_legacy_export_size_is_accepted(self):
        self.path.write_bytes(base64.b64encode(b"x" * 96))
        feed.validate_private_key_file(self.path)

    def test_public_or_executable_permissions_fail(self):
        for mode in (0o644, 0o400, 0o700, 0o660):
            self.path.chmod(mode)
            with self.subTest(mode=mode), self.assertRaises(feed.ReleaseError):
                feed.validate_private_key_file(self.path)

    def test_symlink_and_directory_fail(self):
        link = self.path.with_name("key-link")
        link.symlink_to(self.path)
        for path in (link, self.path.parent):
            with self.subTest(path=path.name), self.assertRaises(feed.ReleaseError):
                feed.validate_private_key_file(path)

    def test_malformed_private_value_never_appears_in_diagnostic(self):
        secret = "do-not-echo-this-sensitive-input!"
        self.path.write_text(secret)
        with self.assertRaises(feed.ReleaseError) as caught:
            feed.validate_private_key_file(self.path)
        self.assertNotIn(secret, str(caught.exception))

    def test_tool_failure_discards_stdout_stderr_and_command(self):
        diagnostic = "private-data-from-third-party-error"
        result = subprocess.CompletedProcess([], 1, stdout=diagnostic, stderr=diagnostic)
        with patch.object(feed.subprocess, "run", return_value=result), self.assertRaises(feed.ReleaseError) as caught:
            feed.run_tool(["sign_update", "--ed-key-file", "private-path"], "Signing")
        self.assertNotIn(diagnostic, str(caught.exception))
        self.assertNotIn("private-path", str(caught.exception))


class AppcastIntegrityTests(unittest.TestCase):
    def test_canonical_feed_round_trip_and_immutable_urls(self):
        data = feed.appcast_xml(metadata())
        self.assertEqual(feed.validate_generated_feed(data, metadata()), EMPTY_SIGNATURE)
        item = ET.fromstring(data).find("./channel/item")
        self.assertEqual(item.findtext("sparkle:releaseNotesLink", namespaces=feed.NS), metadata()["release_notes_url"])
        self.assertEqual(item.findtext("sparkle:hardwareRequirements", namespaces=feed.NS), "arm64")

    def test_community_feed_visibly_discloses_unnotarized_distribution(self):
        data = feed.appcast_xml(metadata() | {"distribution": "community"})
        item = ET.fromstring(data).find("./channel/item")
        self.assertIn("커뮤니티", item.findtext("title"))
        self.assertIn("미공증", item.findtext("title"))
        self.assertIn("공증 없이", item.findtext("description"))
        self.assertNotIn("미공증", ET.fromstring(feed.appcast_xml(metadata())).findtext("./channel/item/title"))

    def test_xml_serializer_escapes_text_and_attributes(self):
        fields = metadata() | {"release_notes_url": 'https://example.test/?a=1&b="two"'}
        data = feed.appcast_xml(fields, title="OpenNoType & <test>")
        self.assertIn(b"&amp;", data)
        self.assertIn(b"&lt;test&gt;", data)
        tree = ET.fromstring(data)
        self.assertEqual(tree.findtext("./channel/title"), "OpenNoType & <test> updates")
        self.assertEqual(tree.findtext("./channel/item/sparkle:releaseNotesLink", namespaces=feed.NS), fields["release_notes_url"])

    def test_signature_requires_canonical_64_bytes(self):
        for signature in ("", "malformed", EMPTY_SIGNATURE + "\n", base64.b64encode(b"x" * 63).decode(),
                          base64.b64encode(b"x" * 65).decode()):
            with self.subTest(signature=signature), self.assertRaises(feed.ReleaseError):
                feed.appcast_xml(metadata() | {"signature": signature})

    def test_generated_version_build_os_arch_length_url_mismatches_fail(self):
        data = feed.appcast_xml(metadata())
        for changes in ({"version": "1.2.4"}, {"build": 43}, {"min_os": "13.0"}, {"arch": "x86_64"},
                        {"length": 124}, {"download_url": "https://example.test/latest.zip"}):
            with self.subTest(changes=changes), self.assertRaises(feed.ReleaseError):
                feed.validate_generated_feed(data, metadata() | changes)

    def test_duplicate_enclosures_or_updates_fail(self):
        for duplicate in ("enclosure", "item"):
            tree = ET.fromstring(feed.appcast_xml(metadata()))
            parent = tree.find("./channel/item" if duplicate == "enclosure" else "./channel")
            parent.append(ET.fromstring(ET.tostring(parent.find(duplicate))))
            with self.subTest(duplicate=duplicate), self.assertRaises(feed.ReleaseError):
                feed.validate_generated_feed(ET.tostring(tree), metadata())

    def test_malformed_xml_fails(self):
        with self.assertRaises(feed.ReleaseError):
            feed.validate_generated_feed(b"not xml", metadata())

    def test_hash_boundary_detects_same_length_mutation_and_append(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "final.zip"
            path.write_bytes(b"final bytes")
            before = feed.fingerprint(path)
            feed.assert_unchanged(path, before)
            for mutated in (b"other bytes", b"final bytes appended"):
                path.write_bytes(mutated)
                with self.subTest(mutated=mutated), self.assertRaises(feed.ReleaseError):
                    feed.assert_unchanged(path, before)

    def test_archive_metadata_must_match_exactly_and_not_be_duplicated(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "final.zip"
            name = "OpenNoType.app/Contents/Info.plist"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr(name, plistlib.dumps(INFO | SETTINGS))
            feed.validate_archive_info(path, INFO | SETTINGS)
            with self.assertRaises(feed.ReleaseError):
                feed.validate_archive_info(path, INFO | SETTINGS | {"CFBundleVersion": "43"})
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                with zipfile.ZipFile(path, "a") as archive:
                    archive.writestr(name, plistlib.dumps(INFO | SETTINGS))
            with self.assertRaises(feed.ReleaseError):
                feed.validate_archive_info(path, INFO | SETTINGS)

    @unittest.skipUnless(sys.platform == "darwin", "CryptoKit verifier requires macOS")
    def test_cryptokit_accepts_published_vector_and_rejects_wrong_key_or_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "vector.bin"
            archive.write_bytes(b"")
            command = ["/usr/bin/swift", str(SCRIPT.with_name("verify-update-signature.swift")), str(archive)]
            self.assertEqual(subprocess.run(command + [PUBLIC, EMPTY_SIGNATURE], capture_output=True).returncode, 0)
            self.assertNotEqual(subprocess.run(command + [OTHER_PUBLIC, EMPTY_SIGNATURE], capture_output=True).returncode, 0)
            archive.write_bytes(b"changed")
            self.assertNotEqual(subprocess.run(command + [PUBLIC, EMPTY_SIGNATURE], capture_output=True).returncode, 0)


class SparkleToolProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.artifact = self.root / ".build/artifacts/sparkle/Sparkle"
        self.app = self.root / "OpenNoType.app"
        self.source_info = self.artifact / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Resources/Info.plist"
        self.bundled_info = self.app / "Contents/Frameworks/Sparkle.framework/Resources/Info.plist"
        self.framework = {"CFBundleShortVersionString": "2.9.6", "CFBundleVersion": "2061"}
        for path in (self.source_info, self.bundled_info):
            path.parent.mkdir(parents=True)
            path.write_bytes(plistlib.dumps(self.framework))
        (self.root / "Package.resolved").write_text(json.dumps({"pins": [{"identity": "sparkle", "state": {"version": "2.9.6"}}]}))
        (self.artifact / "bin").mkdir()
        for name in ("generate_appcast", "sign_update"):
            path = self.artifact / "bin" / name
            path.write_text("#!/bin/sh\nexit 0\n")
            path.chmod(0o755)

    def test_matching_pinned_artifact_is_required(self):
        generator, verifier = feed.sparkle_tools(self.root, self.app)
        self.assertEqual(generator.name, "generate_appcast")
        self.assertEqual(verifier.name, "sign_update")
        self.source_info.write_bytes(plistlib.dumps(self.framework | {"CFBundleShortVersionString": "2.9.5"}))
        with self.assertRaises(feed.ReleaseError):
            feed.sparkle_tools(self.root, self.app)

    def test_bundled_framework_build_must_match_tools_distribution(self):
        self.bundled_info.write_bytes(plistlib.dumps(self.framework | {"CFBundleVersion": "2060"}))
        with self.assertRaises(feed.ReleaseError):
            feed.sparkle_tools(self.root, self.app)

    def test_missing_or_redirected_tool_fails(self):
        verifier = self.artifact / "bin/sign_update"
        verifier.unlink()
        with self.assertRaises(feed.ReleaseError):
            feed.sparkle_tools(self.root, self.app)
        unrelated = self.root / "another-tool"
        unrelated.write_text("#!/bin/sh\nexit 0\n")
        unrelated.chmod(0o755)
        verifier.symlink_to(unrelated)
        with self.assertRaises(feed.ReleaseError):
            feed.sparkle_tools(self.root, self.app)


@unittest.skipUnless(sys.platform == "darwin" and os.environ.get("SPARKLE_TEST_ARTIFACT_DIR"),
                     "Set SPARKLE_TEST_ARTIFACT_DIR for the offline real-tool integration test")
class SparkleIntegrationTests(unittest.TestCase):
    def make_fixture(self, root):
        artifact = Path(os.environ["SPARKLE_TEST_ARTIFACT_DIR"]).resolve()
        local_artifact = root / ".build/artifacts/sparkle/Sparkle"
        local_artifact.parent.mkdir(parents=True)
        local_artifact.symlink_to(artifact, target_is_directory=True)
        framework = artifact / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
        version = plistlib.loads((framework / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
        (root / "Package.resolved").write_text(json.dumps({"pins": [{"identity": "sparkle", "state": {"version": version}}]}))
        scripts = root / "scripts"
        scripts.mkdir()
        for name in ("generate-update-feed.py", "verify-update-signature.swift", "package-release.sh", "release-preflight.py"):
            shutil.copyfile(SCRIPT.with_name(name), scripts / name)
        resources = root / "Resources"
        resources.mkdir()
        (resources / "Info.plist").write_bytes(plistlib.dumps(INFO))
        (resources / "UpdateChannel.plist").write_bytes(plistlib.dumps(SETTINGS))
        shutil.copyfile(SCRIPT.parent.parent / "Resources/OpenNoType.entitlements", resources / "OpenNoType.entitlements")
        app = root / "fixture/OpenNoType.app"
        frameworks = app / "Contents/Frameworks"
        frameworks.mkdir(parents=True)
        subprocess.run(["/usr/bin/ditto", str(framework), str(frameworks / "Sparkle.framework")], check=True, capture_output=True)
        executable = app / "Contents/MacOS/OpenNoType"
        executable.parent.mkdir()
        driver = root / "sparkle-load.swift"
        driver.write_text("import Sparkle\nprint(String(describing: SPUUpdater.self))\n")
        subprocess.run(["/usr/bin/swiftc", "-target", "arm64-apple-macos14.0", "-F", str(framework.parent),
                        "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                        str(driver), "-o", str(executable)], check=True, capture_output=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(INFO | SETTINGS | {"OpenNoTypeDistribution": "community"}))
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(app)], check=True, capture_output=True)
        key_file = root / "rfc8032-test-seed"
        key_file.write_bytes(base64.b64encode(TEST_SEED))
        key_file.chmod(0o600)
        return app, key_file, artifact

    def test_real_tools_sign_verify_and_emit_bound_final_zip_metadata(self):
        with tempfile.TemporaryDirectory(prefix="opennotype-release-test-") as directory:
            root = Path(directory)
            app, key_file, artifact = self.make_fixture(root)
            dist = root / "dist"
            dist.mkdir()
            archive = dist / "OpenNoType-1.2.3.zip"
            subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True, capture_output=True)
            before = feed.fingerprint(archive)
            result = feed.generate(app, archive, dist, "v1.2.3", key_file, project_root=root, distribution="community")
            self.assertEqual(feed.fingerprint(archive), before)
            self.assertEqual((result["length"], result["zip_sha256"]), before)
            self.assertEqual(result["public_key"], PUBLIC)
            self.assertEqual(result["distribution"], "community")
            self.assertEqual(feed.validate_generated_feed((dist / "appcast.xml").read_bytes(), result), result["signature"])
            self.assertEqual((dist / f"{archive.name}.sha256").read_text(), f"{before[1]}  {archive.name}\n")
            self.assertEqual(json.loads((dist / "release-metadata.json").read_text()), result)
            # A changed JSON label cannot make the actual ad-hoc application notarized.
            with self.assertRaises(feed.ReleaseError):
                feed.validate_code_signing(app, "notarized")
            archive.write_bytes(archive.read_bytes() + b"tampered")
            with self.assertRaises(feed.ReleaseError):
                feed.run_tool([str(artifact / "bin/sign_update"), "--ed-key-file", str(key_file), "--verify", str(archive), result["signature"]], "Verification")

    def test_community_packager_produces_six_verified_artifacts_without_apple_services(self):
        with tempfile.TemporaryDirectory(prefix="opennotype-community-package-test-") as directory:
            root = Path(directory)
            app, key_file, _ = self.make_fixture(root)
            # Start with the actual hardened-runtime flag used by notarized
            # signing. Community packaging must explicitly remove it.
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime",
                            "--timestamp=none", str(app)], check=True, capture_output=True)
            def signing_flags(path):
                details = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=4", str(path)],
                                         check=True, capture_output=True, text=True)
                match = re.search(r"\bflags=0x([0-9a-fA-F]+)", details.stderr)
                self.assertIsNotNone(match, "Actual code signature did not report flags")
                return int(match.group(1), 16)
            self.assertNotEqual(signing_flags(app) & 0x10000, 0)
            with self.assertRaises(feed.ReleaseError):
                feed.validate_code_signing(app, "community")
            # This substitutes only the expensive product compilation. The real
            # package script signs its real Sparkle helpers/app/DMG and final ZIP.
            builder = root / "scripts/build-app.sh"
            builder.write_text('#!/bin/bash\nset -eu\ncd "$(dirname "$0")/.."\nmkdir -p build\n/usr/bin/ditto fixture/OpenNoType.app build/OpenNoType.app\n')
            builder.chmod(0o755)
            blocked_tools = root / "blocked-apple-services"
            blocked_tools.mkdir()
            for name in ("xcrun", "spctl"):
                path = blocked_tools / name
                path.write_text("#!/bin/sh\nexit 99\n")
                path.chmod(0o755)
            # Execute every real signing operation while rejecting the argument
            # order that causes codesign to silently ignore signing options.
            codesign = blocked_tools / "codesign"
            codesign.write_text("#!/usr/bin/env python3\nimport os, sys\na = sys.argv[1:]\n"
                "if '--sign' in a:\n"
                "    for i, option in enumerate(a):\n"
                "        if option.split('=')[0] in ('--options', '--preserve-metadata', '--entitlements', '--timestamp'):\n"
                "            assert a.index('--sign') < i, 'Signing option precedes --sign'\n"
                "os.execv('/usr/bin/codesign', ['/usr/bin/codesign'] + a)\n")
            codesign.chmod(0o755)
            env = dict(os.environ, RELEASE_SIGNING_MODE="community", RELEASE_TAG="v1.2.3",
                       SPARKLE_PRIVATE_KEY_FILE=str(key_file), DEVELOPER_ID_APPLICATION="", NOTARY_PROFILE="", NOTARY_KEYCHAIN="",
                       PATH=str(blocked_tools) + ":" + os.environ["PATH"])
            for name in ("SPARKLE_FEED_URL", "SPARKLE_PUBLIC_ED_KEY"):
                env.pop(name, None)
            result = subprocess.run(["/bin/bash", "scripts/package-release.sh"], cwd=root, env=env, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 0, "Offline community packaging failed")
            dist = root / "dist"
            self.assertEqual({p.name for p in dist.iterdir()}, {"OpenNoType-1.2.3.zip", "OpenNoType-1.2.3.dmg",
                "OpenNoType-1.2.3.zip.sha256", "OpenNoType-1.2.3.dmg.sha256", "appcast.xml", "release-metadata.json"})
            feed.validate_code_signing(root / "build/OpenNoType.app", "community")
            self.assertEqual(signing_flags(root / "build/OpenNoType.app") & 0x10000, 0)
            feed.validate_code_signing(dist / "OpenNoType-1.2.3.dmg", "community")
            if platform.machine() == "arm64":
                loaded = subprocess.run([str(root / "build/OpenNoType.app/Contents/MacOS/OpenNoType")],
                                        capture_output=True, timeout=15)
                self.assertEqual(loaded.returncode, 0, "Community-signed app could not load Sparkle at runtime")
                self.assertIn(b"SPUUpdater", loaded.stdout)
            result = subprocess.run([sys.executable, "scripts/release-preflight.py", "--tag", "v1.2.3", "--artifacts", "dist"],
                                    cwd=root, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, "Community package preflight failed")


if __name__ == "__main__":
    unittest.main()
