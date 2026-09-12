#!/usr/bin/env python3
"""Prepare a synthetic Sparkle 2.9.6 update; --execute opts into localhost and test-app launch.

No production app, release archive, credentials, Keychain, or user history is used.
The known RFC 8032 test seed below is public test data, NEVER a release signing key.
"""
from __future__ import annotations
import argparse
import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PUBLIC = base64.b64encode(bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")).decode()
SEED = base64.b64encode(bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"))
NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def run(command: list[str], directory: Path, *, source: bytes | None = None) -> str:
    result = subprocess.run(command, input=source, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with (directory / "preparation.log").open("ab") as log:
        log.write(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name} failed; see preparation.log")
    return result.stdout.decode()


def read_info(app: Path) -> dict:
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sign_bundle(app: Path, directory: Path) -> None:
    framework = app / "Contents/Frameworks/Sparkle.framework"
    if framework.exists():
        base = framework / "Versions/Current"
        for relative in ("XPCServices/Installer.xpc", "XPCServices/Downloader.xpc", "Autoupdate", "Updater.app"):
            arguments = ["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none"]
            if relative.endswith("Downloader.xpc"):
                arguments += ["--preserve-metadata=entitlements"]
            run(arguments + [str(base / relative)], directory)
        run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(framework)], directory)
    run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(app)], directory)
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], directory)


def prepare(directory: Path, artifact: Path, port: int, tamper: bool) -> dict:
    framework = artifact / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    version = plistlib.loads((framework / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    if version != "2.9.6":
        raise RuntimeError("This harness was written against Sparkle 2.9.6; re-review before changing versions")
    suffix = uuid.uuid4().hex
    prefix = f"app.opennotype.sparkle-harness.{suffix}"
    feed_url = f"http://127.0.0.1:{port}/appcast.xml"
    info = {"CFBundleName": "Synthetic Sparkle Target", "CFBundlePackageType": "APPL",
            "CFBundleIdentifier": prefix + ".host", "CFBundleExecutable": "Target",
            "LSMinimumSystemVersion": "14.0", "LSUIElement": True,
            "SUFeedURL": feed_url, "SUPublicEDKey": PUBLIC,
            "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False,
            "SUSendProfileInfo": False, "SUShowReleaseNotes": False,
            "SUVerifyUpdateBeforeExtraction": True}
    for name, build in (("Target.app", "1"), ("Candidate.app", "2")):
        app = directory / name
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Resources").mkdir()
        (app / "Contents/Frameworks").mkdir()
        values = info | {"CFBundleVersion": build, "CFBundleShortVersionString": f"1.0.{build}"}
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(values))
        (app / "Contents/Resources/payload.txt").write_text(f"synthetic-build-{build}\n")
        marker = json.dumps(str(directory / "UNEXPECTED-TARGET-EXECUTION"))
        source = f'#include <stdio.h>\nint main(void) {{ FILE *f=fopen({marker},"w"); if(f) {{fputs("target unexpectedly ran",f); fclose(f);}} return 77; }}\n'
        run(["/usr/bin/clang", "-arch", "arm64", "-mmacosx-version-min=14.0", "-x", "c", "-",
             "-o", str(app / "Contents/MacOS/Target")], directory, source=source.encode())
        run(["/usr/bin/ditto", str(framework), str(app / "Contents/Frameworks/Sparkle.framework")], directory)
        sign_bundle(app, directory)

    driver = directory / "Driver.app"
    (driver / "Contents/MacOS").mkdir(parents=True)
    (driver / "Contents/Frameworks").mkdir()
    driver_info = {"CFBundleName": "Synthetic Sparkle Driver", "CFBundlePackageType": "APPL",
                   "CFBundleIdentifier": prefix + ".driver", "CFBundleExecutable": "HarnessDriver",
                   "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0.0", "LSMinimumSystemVersion": "14.0",
                   "LSUIElement": True, "NSPrincipalClass": "NSApplication", "HarnessRoot": str(directory),
                   "HarnessHostID": prefix + ".host", "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}
    (driver / "Contents/Info.plist").write_bytes(plistlib.dumps(driver_info))
    run(["/usr/bin/swiftc", "-parse-as-library", "-target", "arm64-apple-macosx14.0", "-F", str(framework.parent),
         "-framework", "Sparkle", "-framework", "AppKit", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
         str(HERE / "Driver.swift"), "-o", str(driver / "Contents/MacOS/HarnessDriver")], directory)
    run(["/usr/bin/ditto", str(framework), str(driver / "Contents/Frameworks/Sparkle.framework")], directory)
    sign_bundle(driver, directory)
    served = directory / "served"
    served.mkdir()
    archive = served / "Target-2.zip"
    # Sparkle matches the incoming host bundle ID and installs at Target.app.
    run(["/usr/bin/ditto", "-c", "-k", "--keepParent", str(directory / "Candidate.app"), str(archive)], directory)
    key = directory / "public-rfc8032-test-seed"
    descriptor = os.open(key, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, "wb") as output:
        output.write(SEED)
    try:
        signature = run([str(artifact / "bin/sign_update"), "--ed-key-file", str(key), "-p", str(archive)], directory).strip()
    finally:
        key.unlink()  # The published test vector has no purpose after creating the fixture signature.
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise RuntimeError("sign_update did not return a signature")
    signed_digest = digest(archive)
    if tamper:
        with archive.open("ab") as output:
            output.write(b"intentional-post-signature-mutation")
    ET.register_namespace("sparkle", NAMESPACE)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Synthetic Sparkle harness"
    item = ET.SubElement(channel, "item")
    for name, value in (("version", "2"), ("shortVersionString", "1.0.2"), ("minimumSystemVersion", "14.0"), ("hardwareRequirements", "arm64")):
        ET.SubElement(item, f"{{{NAMESPACE}}}{name}").text = value
    ET.SubElement(item, "enclosure", {"url": f"http://127.0.0.1:{port}/Target-2.zip",
                  "length": str(archive.stat().st_size), "type": "application/octet-stream",
                  f"{{{NAMESPACE}}}edSignature": signature, f"{{{NAMESPACE}}}os": "macos"})
    (served / "appcast.xml").write_bytes(ET.tostring(rss, encoding="utf-8", xml_declaration=True))
    metadata = {"root": str(directory), "sparkle_version": version, "host_bundle_id": prefix + ".host",
                "driver_bundle_id": prefix + ".driver", "feed_url": feed_url, "tampered": tamper,
                "signed_zip_sha256": signed_digest, "served_zip_sha256": digest(archive),
                "candidate_executable_sha256": digest(directory / "Candidate.app/Contents/MacOS/Target"),
                "driver_executable_sha256": digest(driver / "Contents/MacOS/HarnessDriver"),
                "production_artifact_tested": False}
    (directory / "prepared.json").write_text(json.dumps(metadata, indent=2) + "\n")
    return metadata


def handler_for(directory: Path):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path not in ("/appcast.xml", "/Target-2.zip"):
                self.send_error(404)
                return
            data = (directory / "served" / path[1:]).read_bytes()
            with (directory / "http-requests.jsonl").open("a") as log:
                log.write(json.dumps({"path": path, "bytes": len(data), "time": time.time()}) + "\n")
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Content-Type", "application/xml" if path.endswith("xml") else "application/zip")
            self.end_headers()
            self.wfile.write(data)
        def log_message(self, *args):
            pass
    return Handler


def execute(directory: Path, metadata: dict, server, timeout: int) -> dict:
    server.harness_started = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    run(["/usr/bin/open", "-n", str(directory / "Driver.app")], directory)
    deadline = time.monotonic() + timeout
    result_path = directory / "driver-result.json"
    while not result_path.exists() and time.monotonic() < deadline:
        time.sleep(0.5)
    if not result_path.exists():
        raise RuntimeError("Harness timed out; only the isolated driver may remain running. No production process was touched")
    result = json.loads(result_path.read_text())
    events = [json.loads(line) for line in (directory / "events.jsonl").read_text().splitlines()]
    launches = [event for event in events if event["event"] == "driver-launched"]
    host = read_info(directory / "Target.app")
    require_target_idle = not (directory / "UNEXPECTED-TARGET-EXECUTION").exists()
    unchanged_driver = digest(directory / "Driver.app/Contents/MacOS/HarnessDriver") == metadata["driver_executable_sha256"]
    requests = [json.loads(line) for line in (directory / "http-requests.jsonl").read_text().splitlines()]
    downloaded = any(item["path"] == "/Target-2.zip" for item in requests)
    if metadata["tampered"]:
        # Sparkle 2.9.6 uses SUValidationError (3002) for an EdDSA mismatch.
        # Check its non-localized verifier reason as well, not just a generic install failure.
        signature_error = any(error.get("domain") == "SUSparkleErrorDomain" and error.get("code") == 3002
                              and error.get("description", "").startswith("EdDSA signature does not match.")
                              for error in result.get("error_chain", []))
        passed = (result["outcome"] == "update-rejected" and host["CFBundleVersion"] == "1"
                  and signature_error
                  and require_target_idle and unchanged_driver and downloaded)
    else:
        passed = (result["outcome"] == "relaunched-with-updated-target" and host["CFBundleVersion"] == "2"
                  and len(launches) == 2 and launches[0]["pid"] != launches[1]["pid"]
                  and any(event["event"] == "sparkle-will-install" for event in events)
                  and any(event["event"] == "driver-termination-requested" for event in events)
                  and (directory / "Target.app/Contents/Resources/payload.txt").read_text() == "synthetic-build-2\n"
                  and digest(directory / "Target.app/Contents/MacOS/Target") == metadata["candidate_executable_sha256"]
                  and require_target_idle and unchanged_driver and downloaded)
    report = metadata | {"passed": passed, "result": result, "target_build": host["CFBundleVersion"],
                         "driver_launches": launches, "target_never_launched": require_target_idle,
                         "driver_binary_unchanged": unchanged_driver, "download_observed": downloaded}
    (directory / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def cleanup_test_state(directory: Path, metadata: dict) -> dict:
    """Only the newly generated identifiers and the PIDs recorded by this driver."""
    events_path = directory / "events.jsonl"
    events = [json.loads(line) for line in events_path.read_text().splitlines()] if events_path.exists() else []
    pids = {event["pid"] for event in events if event["event"] == "driver-launched"}
    deadline = time.monotonic() + 10
    remaining = set(pids)
    while remaining and time.monotonic() < deadline:
        for pid in tuple(remaining):
            try:
                os.kill(pid, 0)  # Existence check only: never terminate another process.
            except ProcessLookupError:
                remaining.remove(pid)
        if remaining:
            time.sleep(0.2)
    cleared = []
    if not remaining:
        for field in ("host_bundle_id", "driver_bundle_id"):
            identifier = metadata[field]
            if not re.fullmatch(r"app\.opennotype\.sparkle-harness\.[0-9a-f]{32}\.(host|driver)", identifier):
                raise RuntimeError("Refusing to clean a non-harness identifier")
            subprocess.run(["/usr/bin/defaults", "delete", identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            cache = Path.home() / "Library/Caches" / identifier
            if cache.is_symlink():
                raise RuntimeError("Refusing to clean a symlinked harness cache")
            if cache.is_dir():
                shutil.rmtree(cache)
            cleared.append(identifier)
    result = {"driver_pids_exited": sorted(pids - remaining), "remaining_driver_pids": sorted(remaining),
              "cleared_synthetic_domains": cleared, "evidence_retained": str(directory)}
    (directory / "cleanup.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true", help="Start only a loopback server and the generated synthetic driver")
    parser.add_argument("--tamper", action="store_true", help="Append bytes after signing and require Sparkle to reject them")
    parser.add_argument("--sparkle-artifact", type=Path, default=ROOT / ".build/artifacts/sparkle/Sparkle")
    parser.add_argument("--timeout-seconds", type=int, default=180)
    args = parser.parse_args()
    if sys.platform != "darwin" or not 30 <= args.timeout_seconds <= 300:
        parser.error("macOS and a 30..300 second timeout are required")
    directory = Path(tempfile.mkdtemp(prefix="opennotype-sparkle-harness-")).resolve()
    print(f"Harness evidence: {directory}", flush=True)
    server = None
    try:
        # Preparation without --execute never binds a socket or launches an app.
        if args.execute:
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler_for(directory))
        metadata = prepare(directory, args.sparkle_artifact.resolve(), server.server_port if server else 8765, args.tamper)
        if not args.execute:
            print("Prepared only: no server, no app launch, no update was executed.")
            return 0
        report = execute(directory, metadata, server, args.timeout_seconds)
        cleanup = cleanup_test_state(directory, metadata)
        if cleanup["remaining_driver_pids"]:
            report["passed"] = False
        report["cleanup"] = cleanup
        (directory / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"passed": report["passed"], "outcome": report["result"]["outcome"],
                          "target_build": report["target_build"], "production_artifact_tested": False}))
        return 0 if report["passed"] else 1
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Harness failed: {error}", file=sys.stderr)
        return 1
    finally:
        if server:
            if getattr(server, "harness_started", False):
                server.shutdown()
            server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())
