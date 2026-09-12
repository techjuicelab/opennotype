"""Exercise the CI importer with a disposable self-signed identity, never user credentials."""
import os
from pathlib import Path
import secrets
import shlex
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.uname().sysname == "Darwin", "Requires macOS Security.framework")
class CertificateImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="opennotype-certificate-test-")
        cls.root = Path(cls.scratch.name)
        cls.binary = cls.root / "import-certificate"
        subprocess.run(["swiftc", "-suppress-warnings", str(Path(__file__).with_name("import-release-certificate.swift")),
                        "-o", str(cls.binary)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def setUp(self):
        self.private = Path(tempfile.mkdtemp(dir=self.root))
        self.keychain = self.private / "release.keychain-db"
        self.identity = "Developer ID Application: OpenNoType CI Fixture (TESTONLY)"
        self.password = secrets.token_urlsafe(24)
        self.env = dict(os.environ, RUNNER_TEMP=str(self.root),
                        RELEASE_KEYCHAIN_PATH=str(self.keychain), P12_FILE=str(self.private / "certificate.p12"),
                        P12_PASSWORD=self.password, DEVELOPER_ID_APPLICATION=self.identity)
        configuration = self.private / "certificate.cnf"
        configuration.write_text("[req]\ndistinguished_name = dn\n[dn]\n"
                                 "[signing]\nbasicConstraints = critical,CA:FALSE\n"
                                 "keyUsage = critical,digitalSignature\nextendedKeyUsage = codeSigning\n")
        old_mask = os.umask(0o077)
        try:
            subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                            "-keyout", str(self.private / "key.pem"), "-out", str(self.private / "cert.pem"),
                            "-days", "1", "-subj", "/CN=" + self.identity,
                            "-config", str(configuration), "-extensions", "signing"], check=True, capture_output=True)
            subprocess.run(["/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(self.private / "key.pem"),
                            "-in", str(self.private / "cert.pem"), "-out", self.env["P12_FILE"],
                            "-passout", "env:P12_PASSWORD"], env=self.env, check=True, capture_output=True)
        finally:
            os.umask(old_mask)

    def tearDown(self):
        if self.keychain.exists():
            subprocess.run(["/usr/bin/security", "delete-keychain", str(self.keychain)], capture_output=True)
        shutil.rmtree(self.private)

    def run_import(self, **overrides):
        return subprocess.run([str(self.binary)], env=dict(self.env, **overrides), capture_output=True, timeout=20)

    def test_import_and_unattended_codesign_use_only_temporary_keychain(self):
        result = self.run_import()
        self.assertEqual(result.returncode, 0, "Test identity import failed")
        self.assertTrue(self.keychain.exists())
        self.assertEqual(self.keychain.stat().st_mode & 0o777, 0o600)
        subprocess.run(["/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,apple:",
                        "-s", "-k", "", str(self.keychain)], check=True, capture_output=True)
        executable = self.private / "fixture"
        shutil.copyfile("/usr/bin/true", executable)
        executable.chmod(0o700)
        # codesign resolves identities through the search list even with --keychain.
        # Mirror CI, then restore the user's list; never alter certificate trust.
        previous = subprocess.run(["/usr/bin/security", "list-keychains", "-d", "user"],
                                  check=True, capture_output=True, text=True)
        keychains = shlex.split(previous.stdout)
        try:
            subprocess.run(["/usr/bin/security", "list-keychains", "-d", "user", "-s", str(self.keychain)],
                           check=True, capture_output=True)
            result = subprocess.run(["/usr/bin/codesign", "--force", "--timestamp=none", "--keychain",
                                     str(self.keychain), "--sign", self.identity, str(executable)],
                                    capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, "Unattended fixture signing failed")
            subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(executable)], check=True, capture_output=True)
        finally:
            subprocess.run(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *keychains],
                           check=True, capture_output=True)

    def test_wrong_password_leaves_no_keychain_and_does_not_echo_password(self):
        wrong = secrets.token_urlsafe(24)
        result = self.run_import(P12_PASSWORD=wrong)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.keychain.exists())
        self.assertNotIn(wrong.encode(), result.stdout + result.stderr)
        self.assertNotIn(self.password.encode(), result.stdout + result.stderr)

    def test_wrong_identity_is_rejected_and_import_is_removed(self):
        result = self.run_import(DEVELOPER_ID_APPLICATION="Developer ID Application: Different (TESTONLY)")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.keychain.exists())

    def test_publicly_readable_p12_is_rejected_before_keychain_creation(self):
        Path(self.env["P12_FILE"]).chmod(0o644)
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.keychain.exists())

    def test_destination_outside_private_runner_directory_is_rejected(self):
        result = self.run_import(RELEASE_KEYCHAIN_PATH=str(self.root / "outside.keychain-db"))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "outside.keychain-db").exists())


if __name__ == "__main__":
    unittest.main()
