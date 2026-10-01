"""Compiler/toolchain doubles verify SDK selection without changing xcode-select."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PREFLIGHT = Path(__file__).with_name("macos-preflight.sh").resolve()
STUB = r'''
import json, os, pathlib, sys
args = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
root = pathlib.Path(os.environ["SDK_TEST_ROOT"])
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps([name, args]) + "\n")
if name == "xcrun":
    print(root / "SDKs" / "MacOSX27.0.sdk")
elif name == "xcode-select":
    print(root / "Developer")
elif args == ["--version"]:
    print("Apple Swift version " + os.environ.get("TEST_SWIFT_VERSION", "6.4"))
else:
    sdk = pathlib.Path(args[args.index("-sdk") + 1]).name
    test = any(arg.endswith("/xctest.swift") for arg in args)
    fail = (os.environ.get("TEST_XCTEST", "fail") == "fail") if test else sdk in os.environ.get("TEST_FAIL_SDKS", "MacOSX27.0.sdk").split(",")
    if fail:
        print("error: no such module 'XCTest'" if test else "error: plugin for module 'SwiftUIMacros' not found", file=sys.stderr)
        sys.exit(1)
    pathlib.Path(args[args.index("-o") + 1]).write_bytes(b"synthetic compiler output")
'''


class MacOSPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="opennotype-preflight-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.default = self.root / "SDKs" / "MacOSX27.0.sdk"
        self.fallback = self.root / "SDKs" / "MacOSX26.5.sdk"
        self.default.mkdir(parents=True)
        self.fallback.mkdir()
        (self.root / "Developer").mkdir()
        for name in ("swiftc", "xcrun", "xcode-select"):
            path = self.bin / name
            path.write_text(f"#!{sys.executable}\n" + STUB)
            path.chmod(0o755)
        # Do not inherit a caller's explicit SDK into default-selection tests.
        self.env = {key: value for key, value in os.environ.items() if key != "MACOS_SDK_PATH"}
        self.env.update({"PATH": f"{self.bin}:/usr/bin:/bin", "SDK_TEST_ROOT": str(self.root), "TMPDIR": str(self.root)})

    def run_preflight(self, *flags, **overrides):
        return subprocess.run(["/bin/bash", str(PREFLIGHT), *flags], env={**self.env, **overrides},
                              text=True, capture_output=True, timeout=20)

    def calls(self):
        return [json.loads(row) for row in (self.root / "calls.jsonl").read_text().splitlines()]

    def test_failed_default_uses_only_actually_compiling_fallback(self):
        result = self.run_preflight("--print-sdk")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.fallback))
        compilations = [args for name, args in self.calls() if name == "swiftc" and "-sdk" in args]
        self.assertEqual([args[args.index("-sdk") + 1] for args in compilations],
                         [str(self.default), str(self.fallback), str(self.fallback)])
        self.assertIn("XCTest", result.stderr)

    def test_working_default_is_kept_without_fallback_probe(self):
        result = self.run_preflight("--print-sdk", TEST_FAIL_SDKS="", TEST_XCTEST="pass")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.default))
        self.assertFalse(any(str(self.fallback) in args for _, args in self.calls()))

    def test_explicit_broken_sdk_does_not_silently_fallback(self):
        result = self.run_preflight("--print-sdk", MACOS_SDK_PATH=str(self.default))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("명시했으므로", result.stderr)
        self.assertFalse(any(str(self.fallback) in args for _, args in self.calls()))

    def test_explicit_working_sdk_is_used(self):
        result = self.run_preflight("--print-sdk", MACOS_SDK_PATH=str(self.fallback))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.fallback))
        self.assertFalse(any(name == "xcrun" for name, _ in self.calls()))

    def test_test_mode_fails_when_xctest_import_fails(self):
        result = self.run_preflight("--tests")
        self.assertEqual(result.returncode, 2)
        self.assertIn("전체 Xcode", result.stderr)
        self.assertNotIn("전체 테스트 실행", result.stdout)

    def test_test_mode_compile_success_is_not_a_test_run_claim(self):
        result = self.run_preflight("--tests", TEST_XCTEST="pass")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("전체 테스트 실행은 별도", result.stdout)

    def test_no_compiling_sdk_fails_before_xctest(self):
        result = self.run_preflight(TEST_FAIL_SDKS="MacOSX27.0.sdk,MacOSX26.5.sdk")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(any(any(arg.endswith("/xctest.swift") for arg in args) for _, args in self.calls()))

    def test_full_xcode_xctest_framework_search_path_is_supplied(self):
        frameworks = self.root / "Developer" / "Platforms" / "MacOSX.platform" / "Developer" / "Library" / "Frameworks"
        frameworks.mkdir(parents=True)
        result = self.run_preflight("--tests", TEST_XCTEST="pass")
        self.assertEqual(result.returncode, 0, result.stderr)
        test_args = next(args for name, args in self.calls() if name == "swiftc" and any(arg.endswith("/xctest.swift") for arg in args))
        self.assertEqual(test_args[test_args.index("-F") + 1], str(frameworks))

    def test_swift_five_is_rejected_before_sdk_probe(self):
        result = self.run_preflight(TEST_SWIFT_VERSION="5.10")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Swift 6", result.stderr)
        self.assertFalse(any("-sdk" in args for _, args in self.calls()))


if __name__ == "__main__":
    unittest.main()
