"""Offline installer transactions; synthetic bundles, no network or app launch.

Native plutil/ditto/xattr/Foundation operate only inside TemporaryDirectory.
Hardware, downloads, code signature and executable architecture are test doubles.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

INSTALLER = Path(__file__).with_name("install-release.sh").resolve()
BASE = "https://github.com/techjuicelab/opennotype/releases/download/v0.2.0"
ZIP_NAME = "OpenNoType-0.2.0.zip"

STUB = r'''
import json, os, pathlib, shutil, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ["INSTALL_TEST_ROOT"])
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps([name, args]) + "\n")
if name == "sysctl":
    print(os.environ.get("TEST_ARM64", "1"))
elif name == "sw_vers":
    print(os.environ.get("TEST_OS_VERSION", "27.0"))
elif name == "uname":
    print("Darwin" if args == ["-s"] else "x86_64")  # Rosetta process
elif name == "curl":
    url = args[-1]
    fixture = "release.json" if url.endswith("/latest") else "checksum" if url.endswith(".sha256") else "release.zip"
    shutil.copyfile(root / fixture, args[args.index("-o") + 1])
elif name == "pgrep":
    count_file = root / "pgrep-count"
    count = int(count_file.read_text()) + 1 if count_file.exists() else 1
    count_file.write_text(str(count))
    if count == int(os.environ.get("TEST_REPLACE_APP_AFTER", "999")):
        app = pathlib.Path(os.environ["INSTALL_TEST_DESTINATION"]) / "OpenNoType.app"
        app.rename(root / "externally-moved.app")
        app.mkdir()
        (app / "external-marker").write_text("external replacement")
    sys.exit(0 if count >= int(os.environ.get("TEST_RUNNING_AFTER", "999")) else 1)
elif name == "file":
    print("Mach-O 64-bit executable " + os.environ.get("TEST_ARCH", "arm64"))
elif name == "codesign":
    count_file = root / "codesign-count"
    count = int(count_file.read_text()) + 1 if count_file.exists() else 1
    count_file.write_text(str(count))
    sys.exit(1 if count >= int(os.environ.get("TEST_SIGNATURE_FAIL_AFTER", "999")) else 0)
elif name == "mv":
    source = pathlib.Path(args[0])
    if os.environ.get("TEST_ROLLBACK_FAIL") == "1" and source.name == "previous.app":
        sys.exit(1)
    if os.environ.get("TEST_ACTIVATION_FAIL") == "1" and source.name == "OpenNoType.app" and source.parent.name.startswith((".opennotype-install.", ".opennotype-backup.")):
        sys.exit(1)
    sys.exit(subprocess.call(["/bin/mv", *args]))
else:
    raise AssertionError(name)
'''


@unittest.skipUnless(sys.platform == "darwin", "native macOS installer tools required")
class InstallReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="opennotype-installer-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.destination = self.root / "Applications"
        self.destination.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("sysctl", "sw_vers", "uname", "curl", "pgrep", "file", "codesign", "mv"):
            stub = self.bin / name
            stub.write_text(f"#!{sys.executable}\n" + STUB)
            stub.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin",
                    "INSTALL_TEST_ROOT": str(self.root), "INSTALL_TEST_DESTINATION": str(self.destination),
                    "TMPDIR": str(self.root)}
        self.make_release()

    def make_release(self, bundle_id="app.opennotype.mac", min_os="14.0", bad_sha=False, tag="v0.2.0", build="12"):
        app = self.root / "fixture" / "OpenNoType.app"
        (app / "Contents" / "MacOS").mkdir(parents=True, exist_ok=True)
        (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle_id, "CFBundleExecutable": "OpenNoType",
            "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": build, "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": min_os}))
        executable = app / "Contents" / "MacOS" / "OpenNoType"
        executable.write_text("synthetic executable — never launched\n")
        executable.chmod(0o755)
        archive = self.root / "release.zip"
        archive.unlink(missing_ok=True)
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True)
        digest = "0" * 64 if bad_sha else hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.root / "checksum").write_text(f"{digest}  {ZIP_NAME}\n")
        self.release = {"tag_name": tag, "draft": False, "prerelease": False,
                        "assets": [{"name": name, "browser_download_url": f"{BASE}/{name}"}
                                   for name in (ZIP_NAME, f"{ZIP_NAME}.sha256")]}
        self.write_metadata()

    def write_metadata(self):
        (self.root / "release.json").write_text(json.dumps(self.release))

    def existing_app(self, bundle_id="app.opennotype.mac", version="0.1.9", build="10"):
        app = self.destination / "OpenNoType.app"
        (app / "Contents").mkdir(parents=True)
        (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle_id, "CFBundleShortVersionString": version, "CFBundleVersion": build}))
        (app / "previous-marker").write_text("old app")
        return app

    def run_install(self, *flags, **overrides):
        return subprocess.run(["/bin/bash", str(INSTALLER), "--destination", str(self.destination), *flags],
                              env={**self.env, **overrides}, text=True, capture_output=True, timeout=30)

    def assert_old_preserved(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.destination / "OpenNoType.app" / "previous-marker").read_text(), "old app")
        self.assertFalse(list(self.destination.glob(".opennotype-install.*")))
        self.assertFalse(list(self.destination.glob(".opennotype-backup.*")))

    def test_success_preserves_private_previous_bundle_until_first_launch_is_checked(self):
        self.existing_app()
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list(self.destination.glob(".opennotype-backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o700)
        self.assertEqual((backups[0] / "previous.app" / "previous-marker").read_text(), "old app")
        self.assertIn(str(backups[0] / "previous.app"), result.stdout)
        self.assertIn("첫 실행", result.stdout)

    def test_success_can_explicitly_discard_previous_bundle_backup(self):
        self.existing_app()
        result = self.run_install("--discard-backup")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(list(self.destination.glob(".opennotype-backup.*")))
        self.assertFalse(list(self.destination.glob(".opennotype-install.*")))

    def test_first_install_has_no_previous_bundle_backup(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(list(self.destination.glob(".opennotype-backup.*")))
        self.assertFalse(list(self.destination.glob(".opennotype-install.*")))

    def test_app_replaced_during_staging_is_not_overwritten(self):
        self.existing_app()
        result = self.run_install(TEST_REPLACE_APP_AFTER="3")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("기존 앱이 바뀌었습니다", result.stderr)
        self.assertEqual((self.destination / "OpenNoType.app" / "external-marker").read_text(), "external replacement")
        self.assertEqual((self.root / "externally-moved.app" / "previous-marker").read_text(), "old app")
        self.assertFalse(list(self.destination.glob(".opennotype-backup.*")))
        calls = [json.loads(row) for row in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertFalse(any(name == "mv" for name, _ in calls))

    def test_rollback_failure_retains_private_backup_and_reports_location(self):
        self.existing_app()
        result = self.run_install(TEST_SIGNATURE_FAIL_AFTER="3", TEST_ROLLBACK_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        backups = list(self.destination.glob(".opennotype-backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o700)
        self.assertEqual((backups[0] / "previous.app" / "previous-marker").read_text(), "old app")
        self.assertIn(str(backups[0] / "previous.app"), result.stderr)

    def test_symlink_destination_is_refused_without_downloading(self):
        real_destination = self.root / "RealApplications"
        self.destination.rename(real_destination)
        self.destination.symlink_to(real_destination, target_is_directory=True)
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("심볼릭 링크", result.stderr)
        calls_path = self.root / "calls.jsonl"
        self.assertFalse(calls_path.exists() and any(json.loads(row)[0] == "curl" for row in calls_path.read_text().splitlines()))

    def test_verify_only_downloads_and_checks_without_destination_write(self):
        self.existing_app()
        result = self.run_install("--verify-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.destination / "OpenNoType.app" / "previous-marker").exists())
        calls = [json.loads(row) for row in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertEqual(sum(name == "curl" for name, _ in calls), 3)
        self.assertFalse(any(name in ("pgrep", "mv") for name, _ in calls))

    def test_rosetta_host_install_preserves_data_and_real_download_quarantine(self):
        self.existing_app()
        data = self.root / "synthetic-user-data"
        data.write_text("settings and history")
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        app = self.destination / "OpenNoType.app"
        self.assertFalse((app / "previous-marker").exists())
        self.assertEqual(data.read_text(), "settings and history")
        quarantine = subprocess.check_output(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(app)], text=True)
        self.assertTrue(quarantine.strip())
        # Read our fixture's native metadata, without Apple Events or UI access.
        script = r'''
ObjC.import("Foundation");ObjC.import("CoreServices");
function run(argv) {
    var value=Ref(),error=Ref();
    if (!$.NSURL.fileURLWithPath(argv[0]).getResourceValueForKeyError(value,$.NSURLQuarantinePropertiesKey,error)) throw Error("missing metadata");
    function get(key) { return ObjC.unwrap(value[0].objectForKey(ObjC.castRefToObject(key))); }
    return JSON.stringify([get($.kLSQuarantineAgentNameKey),get($.kLSQuarantineTypeKey)]);
}
'''
        native = subprocess.run(["/usr/bin/osascript", "-l", "JavaScript", "-", str(app)],
                                input=script, text=True, capture_output=True, check=True)
        self.assertEqual(json.loads(native.stdout), ["OpenNoType Installer", "LSQuarantineTypeOtherDownload"])

    def test_checksum_rejection_preserves_old_app(self):
        self.existing_app()
        self.make_release(bad_sha=True)
        result = self.run_install()
        self.assert_old_preserved(result)
        self.assertIn("SHA-256", result.stderr)

    def test_bundle_identity_rejection_preserves_old_app(self):
        self.existing_app()
        self.make_release(bundle_id="unrelated.bundle")
        self.assert_old_preserved(self.run_install())

    def test_malformed_release_build_is_refused_before_replacement(self):
        self.existing_app()
        self.make_release(build="invalid")
        result = self.run_install()
        self.assert_old_preserved(result)
        self.assertIn("build 번호", result.stderr)

    def test_wrong_architecture_rejection_preserves_old_app(self):
        self.existing_app()
        self.assert_old_preserved(self.run_install(TEST_ARCH="x86_64"))

    def test_signature_rejection_preserves_old_app(self):
        self.existing_app()
        self.assert_old_preserved(self.run_install(TEST_SIGNATURE_FAIL_AFTER="1"))

    def test_app_launch_during_staging_aborts_before_old_bundle_move(self):
        self.existing_app()
        result = self.run_install(TEST_RUNNING_AFTER="3")
        self.assert_old_preserved(result)
        self.assertIn("앱 준비 중", result.stderr)
        self.assertFalse(any(json.loads(row)[0] == "mv" for row in (self.root / "calls.jsonl").read_text().splitlines()))

    def test_activation_failure_rolls_back_old_app(self):
        self.existing_app()
        result = self.run_install(TEST_ACTIVATION_FAIL="1")
        self.assert_old_preserved(result)
        self.assertIn("이전 앱으로 되돌렸습니다", result.stderr)

    def test_final_validation_failure_rolls_back_old_app(self):
        self.existing_app()
        result = self.run_install(TEST_SIGNATURE_FAIL_AFTER="3")
        self.assert_old_preserved(result)
        self.assertIn("이전 앱으로 되돌렸습니다", result.stderr)

    def test_running_app_refused_before_download(self):
        result = self.run_install(TEST_RUNNING_AFTER="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(json.loads(row)[0] == "curl" for row in (self.root / "calls.jsonl").read_text().splitlines()))

    def test_missing_destination_gives_user_applications_instruction(self):
        self.destination.rmdir()
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('--destination "$HOME/Applications"', result.stderr)
        self.assertFalse(self.destination.exists())

    def test_rejects_intel_and_old_macos_before_download(self):
        for override in ({"TEST_ARM64": "0"}, {"TEST_OS_VERSION": "13.7"}):
            with self.subTest(override=override):
                result = self.run_install(**override)
                self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(json.loads(row)[0] == "curl" for row in (self.root / "calls.jsonl").read_text().splitlines()))

    def test_unrelated_existing_app_is_never_replaced(self):
        self.existing_app(bundle_id="other.app")
        self.assert_old_preserved(self.run_install())

    def test_newer_version_is_never_downgraded_to_public_release(self):
        self.existing_app(version="0.2.1", build="13")
        result = self.run_install()
        self.assert_old_preserved(result)
        self.assertIn("이전 버전으로 내리지 않았습니다", result.stderr)

    def test_same_version_newer_build_is_never_downgraded(self):
        self.existing_app(version="0.2.0", build="13")
        self.assert_old_preserved(self.run_install())

    def test_release_metadata_cannot_redirect_download_to_another_owner(self):
        self.existing_app()
        self.release["assets"][0]["browser_download_url"] = "https://github.com/other/repo/releases/download/v0.2.0/test.zip"
        self.write_metadata()
        self.assert_old_preserved(self.run_install())


if __name__ == "__main__":
    unittest.main()
