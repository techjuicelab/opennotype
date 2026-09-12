#!/usr/bin/env python3
"""Configure public update settings and validate/sign a final community or notarized release ZIP.

Private keys enter only through SPARKLE_PRIVATE_KEY_FILE (a runtime 0600 file).
Sparkle 2.9's own generate_appcast and sign_update --verify are used; CryptoKit
independently verifies with the public key actually embedded in the update app.
No network, Keychain lookup, certificate signing, or notarization occurs here.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
from urllib.parse import urlsplit

REPOSITORY_URL = "https://github.com/techjuicelab/opennotype"
FEED_URL = REPOSITORY_URL + "/releases/latest/download/appcast.xml"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NS = {"sparkle": SPARKLE_NS}
ET.register_namespace("sparkle", SPARKLE_NS)
ROOT = Path(__file__).resolve().parent.parent


class ReleaseError(ValueError):
    """A safe-to-display release validation failure (never include private data)."""


def signing_mode(env: dict) -> str:
    mode = env.get("RELEASE_SIGNING_MODE", "notarized")
    if mode not in ("community", "notarized"):
        raise ReleaseError("RELEASE_SIGNING_MODE must be community or notarized.")
    return mode


def distribution_from_info(info: dict, expected: str) -> str:
    distribution = info.get("OpenNoTypeDistribution")
    if distribution not in ("community", "notarized") or distribution != expected:
        raise ReleaseError("The app's OpenNoTypeDistribution must match the selected release signing mode.")
    return distribution


def canonical_base64(value: str, size: int, label: str) -> bytes:
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, TypeError):
        raise ReleaseError(f"{label} must be canonical base64 for {size} bytes.") from None
    if len(decoded) != size or base64.b64encode(decoded).decode("ascii") != value:
        raise ReleaseError(f"{label} must be canonical base64 for {size} bytes.")
    return decoded


def validate_public_key(value: str) -> str:
    if canonical_base64(value, 32, "SUPublicEDKey") == bytes(32):
        raise ReleaseError("SUPublicEDKey cannot be an all-zero placeholder.")
    return value


def validate_feed_url(value: str, *, release: bool) -> str:
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except (ValueError, TypeError):
        raise ReleaseError("SUFeedURL must be a valid HTTPS URL.") from None
    if (not isinstance(value, str) or any(ord(c) <= 32 or ord(c) == 127 for c in value)
            or parsed.scheme != "https" or not parsed.hostname
            or parsed.username is not None or parsed.password is not None
            or parsed.fragment or "\\" in value
            or not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", parsed.hostname)
            or (port is not None and not 1 <= port <= 65535)):
        raise ReleaseError("SUFeedURL must be an HTTPS URL without credentials, fragments, or whitespace.")
    if value != FEED_URL:
        raise ReleaseError("Update builds must use the canonical GitHub Releases appcast URL.")
    return value


def read_plist(path: Path) -> dict:
    try:
        result = plistlib.loads(path.read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException):
        raise ReleaseError(f"Cannot read a valid plist: {path.name}") from None
    if not isinstance(result, dict):
        raise ReleaseError(f"Expected a plist dictionary: {path.name}")
    return result


def release_identity(info: dict, tag: str | None = None) -> dict:
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    if not isinstance(version, str) or not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ReleaseError("CFBundleShortVersionString must be a numeric major.minor.patch version.")
    if not isinstance(build, str) or not re.fullmatch(r"[1-9][0-9]*", build):
        raise ReleaseError("CFBundleVersion must be a positive integer string.")
    if tag is not None and tag != f"v{version}":
        raise ReleaseError("RELEASE_TAG must equal vCFBundleShortVersionString.")
    if info.get("LSMinimumSystemVersion") != "14.0":
        raise ReleaseError("This release channel requires LSMinimumSystemVersion 14.0.")
    if info.get("CFBundleIdentifier") != "app.opennotype.mac" or info.get("CFBundleExecutable") != "OpenNoType":
        raise ReleaseError("Expected the OpenNoType application bundle.")
    return {"version": version, "build": int(build), "tag": f"v{version}", "min_os": "14.0", "arch": "arm64"}


def update_settings(channel: dict, env: dict, *, release: bool) -> dict:
    # Explicit overrides are a pair. An empty or half-specified override is an
    # operator error, while a checked-in channel awaiting its key is a valid dev setup.
    overridden = "SPARKLE_FEED_URL" in env or "SPARKLE_PUBLIC_ED_KEY" in env
    if overridden:
        feed = env.get("SPARKLE_FEED_URL", "")
        key = env.get("SPARKLE_PUBLIC_ED_KEY", "")
        if not feed or not key:
            raise ReleaseError("SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY overrides must both be nonempty.")
    else:
        feed = channel.get("SUFeedURL", "")
        key = channel.get("SUPublicEDKey", "")
    if feed:
        validate_feed_url(feed, release=release)
    if not key:
        if release:
            raise ReleaseError("Public releases require a configured SUPublicEDKey.")
        return {}
    validate_public_key(key)
    validate_feed_url(feed, release=release)
    return {"SUFeedURL": feed, "SUPublicEDKey": key,
            "SUEnableAutomaticChecks": True, "SUAutomaticallyUpdate": False}


def configure(info_path: Path, channel_path: Path, env: dict, *, release: bool, tag: str | None, write: bool) -> dict:
    if release and not tag:
        raise ReleaseError("RELEASE_TAG is required for public releases.")
    info = read_plist(info_path)
    identity = release_identity(info, tag)
    channel = read_plist(channel_path)
    settings = update_settings(channel, env, release=release)
    for key in ("SUFeedURL", "SUPublicEDKey", "SUEnableAutomaticChecks", "SUAutomaticallyUpdate"):
        info.pop(key, None)
    info.update(settings)
    info.pop("OpenNoTypeDistribution", None)
    if release:
        distribution = signing_mode(env)
        info["OpenNoTypeDistribution"] = distribution
        identity["distribution"] = distribution
    if write:
        info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    return identity | {"updates_enabled": bool(settings)}


def validate_private_key_file(path: Path) -> None:
    """Accept Sparkle's 32-byte seed or legacy 96-byte export, never print either."""
    try:
        if path.is_symlink():
            raise ReleaseError("SPARKLE_PRIVATE_KEY_FILE must not be a symlink.")
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as handle:
            status = os.fstat(handle.fileno())
            if not stat.S_ISREG(status.st_mode) or stat.S_IMODE(status.st_mode) != 0o600 or status.st_uid != os.getuid():
                raise ReleaseError("SPARKLE_PRIVATE_KEY_FILE must be an owned regular file with mode 0600.")
            data = handle.read(1025)
        if len(data) > 1024:
            raise ReleaseError("SPARKLE_PRIVATE_KEY_FILE has an invalid key format.")
        encoded = data.decode("ascii").strip()
        decoded = base64.b64decode(encoded, validate=True)
        if len(decoded) not in (32, 96) or base64.b64encode(decoded).decode("ascii") != encoded:
            raise ValueError()
    except ReleaseError:
        raise
    except (OSError, ValueError, UnicodeError):
        raise ReleaseError("SPARKLE_PRIVATE_KEY_FILE is unreadable or has an invalid key format.") from None


def run_tool(arguments: list[str], label: str, *, include_stderr: bool = False) -> str:
    # Sparkle's malformed-key error can echo the key. Never forward tool output
    # on failure or include subprocess exceptions/arguments in diagnostics.
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, check=False)
    except OSError:
        raise ReleaseError(f"{label} could not be started.") from None
    if result.returncode != 0:
        raise ReleaseError(f"{label} failed; private signing-tool diagnostics are suppressed.")
    return result.stdout + (result.stderr if include_stderr else "")


def validate_signing_details(details: str, distribution: str) -> None:
    lines = details.splitlines()
    ad_hoc = "Signature=adhoc" in lines
    if distribution == "community":
        if not ad_hoc:
            raise ReleaseError("Community artifacts must have an actual ad-hoc code signature.")
        flags = re.search(r"\bflags=0x([0-9a-fA-F]+)", details)
        if flags and int(flags.group(1), 16) & 0x10000:
            raise ReleaseError("Community artifacts must not enable hardened runtime library validation without a Team ID.")
    elif distribution == "notarized":
        if ad_hoc or not any(line.startswith("Authority=Developer ID Application: ") for line in lines):
            raise ReleaseError("Notarized artifacts require an actual Developer ID Application signature.")
    else:
        raise ReleaseError("Unknown release distribution.")


def validate_code_signing(path: Path, distribution: str) -> None:
    run_tool(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(path)], "Code signature validation")
    details = run_tool(["/usr/bin/codesign", "--display", "--verbose=4", str(path)],
                       "Code signing identity inspection", include_stderr=True)
    validate_signing_details(details, distribution)


def sparkle_tools(project_root: Path, app: Path) -> tuple[Path, Path]:
    artifact = project_root / ".build/artifacts/sparkle/Sparkle"
    try:
        pins = json.loads((project_root / "Package.resolved").read_text())["pins"]
        pinned = next(pin["state"]["version"] for pin in pins if pin["identity"] == "sparkle")
    except (OSError, ValueError, KeyError, StopIteration):
        raise ReleaseError("Package.resolved must pin the Sparkle version used for release tools.") from None
    source_info = read_plist(artifact / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Resources/Info.plist")
    bundled_info = read_plist(app / "Contents/Frameworks/Sparkle.framework/Resources/Info.plist")
    if source_info.get("CFBundleShortVersionString") != pinned or any(
        bundled_info.get(key) != source_info.get(key) for key in ("CFBundleShortVersionString", "CFBundleVersion")
    ):
        raise ReleaseError("The bundled framework and local Sparkle release tools must match Package.resolved.")
    result = tuple(artifact / "bin" / name for name in ("generate_appcast", "sign_update"))
    for tool in result:
        if not tool.is_file() or not os.access(tool, os.X_OK) or tool.resolve().parent != (artifact / "bin").resolve():
            raise ReleaseError("Expected executable Sparkle tools in the resolved local artifact's bin directory.")
    return result


def fingerprint(path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    length = 0
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
            length += len(block)
    if length <= 0:
        raise ReleaseError("The release archive is empty.")
    return length, digest.hexdigest()


def assert_unchanged(path: Path, expected: tuple[int, str]) -> None:
    if fingerprint(path) != expected:
        raise ReleaseError("The release archive changed after signing began; no appcast can be published.")


def validate_archive_info(archive: Path, app_info: dict) -> None:
    name = "OpenNoType.app/Contents/Info.plist"
    try:
        with zipfile.ZipFile(archive) as handle:
            matches = [entry for entry in handle.infolist() if entry.filename == name]
            if len(matches) != 1 or matches[0].file_size > 1024 * 1024:
                raise ReleaseError("The ZIP must contain exactly one OpenNoType Info.plist.")
            if plistlib.loads(handle.read(matches[0])) != app_info:
                raise ReleaseError("The ZIP's bundled settings differ from the signed app.")
    except (OSError, ValueError, zipfile.BadZipFile, plistlib.InvalidFileException):
        raise ReleaseError("Cannot validate the final ZIP's application metadata.") from None


def validate_generated_feed(data: bytes, metadata: dict) -> str:
    try:
        tree = ET.fromstring(data)
    except ET.ParseError:
        raise ReleaseError("Sparkle did not generate valid appcast XML.") from None
    items = tree.findall("./channel/item")
    if len(items) != 1 or len(items[0].findall("enclosure")) != 1:
        raise ReleaseError("Expected exactly one full update in the generated appcast.")
    item = items[0]
    for key, value in (("version", str(metadata["build"])), ("shortVersionString", metadata["version"]),
                       ("minimumSystemVersion", metadata["min_os"]), ("hardwareRequirements", metadata["arch"])):
        if item.findtext(f"sparkle:{key}", namespaces=NS) != value:
            raise ReleaseError(f"Generated appcast {key} differs from the final app.")
    enclosure = item.find("enclosure")
    if enclosure.get("url") != metadata["download_url"] or enclosure.get("length") != str(metadata["length"]):
        raise ReleaseError("Generated appcast URL or length differs from the final ZIP.")
    signature = enclosure.get(f"{{{SPARKLE_NS}}}edSignature", "")
    canonical_base64(signature, 64, "Sparkle signature")
    return signature


def appcast_xml(metadata: dict, *, title: str = "OpenNoType") -> bytes:
    """A single immutable full update. XML serializers perform all escaping."""
    canonical_base64(metadata["signature"], 64, "Sparkle signature")
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = f"{title} updates"
    ET.SubElement(channel, "link").text = REPOSITORY_URL
    ET.SubElement(channel, "description").text = f"{title} for macOS"
    ET.SubElement(channel, "language").text = "ko"
    item = ET.SubElement(channel, "item")
    community = metadata.get("distribution") == "community"
    suffix = " · 커뮤니티 배포 (Apple 미공증)" if community else ""
    ET.SubElement(item, "title").text = f"{title} {metadata['version']}{suffix}"
    if community:
        ET.SubElement(item, "description").text = "이 버전은 Apple Developer ID 서명과 공증 없이 제공되는 커뮤니티 배포입니다. 업데이트 파일의 무결성은 Sparkle 서명으로 검증합니다."
    ET.SubElement(item, "pubDate").text = metadata["published_at"]
    for key, value in (("version", str(metadata["build"])), ("shortVersionString", metadata["version"]),
                       ("minimumSystemVersion", metadata["min_os"]), ("hardwareRequirements", metadata["arch"]),
                       ("releaseNotesLink", metadata["release_notes_url"])):
        ET.SubElement(item, f"{{{SPARKLE_NS}}}{key}").text = value
    ET.SubElement(item, "enclosure", {"url": metadata["download_url"], "length": str(metadata["length"]),
        "type": "application/octet-stream", f"{{{SPARKLE_NS}}}edSignature": metadata["signature"],
        f"{{{SPARKLE_NS}}}os": "macos"})
    ET.indent(rss, space="  ")
    return ET.tostring(rss, encoding="utf-8", xml_declaration=True) + b"\n"


def atomic_write(path: Path, data: bytes) -> None:
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as handle:
        temporary = Path(handle.name)
        try:
            handle.write(data)
            handle.flush()
            os.fchmod(handle.fileno(), 0o644)
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    os.replace(temporary, path)


def generate(app: Path, archive: Path, output_dir: Path, tag: str, private_key_file: Path, project_root: Path = ROOT, *, distribution: str | None = None) -> dict:
    info = read_plist(app / "Contents/Info.plist")
    metadata = release_identity(info, tag)
    mode = signing_mode(os.environ) if distribution is None else signing_mode({"RELEASE_SIGNING_MODE": distribution})
    metadata["distribution"] = distribution_from_info(info, mode)
    validate_code_signing(app, mode)
    metadata["public_key"] = validate_public_key(info.get("SUPublicEDKey", ""))
    metadata["feed_url"] = validate_feed_url(info.get("SUFeedURL", ""), release=True)
    if info.get("SUEnableAutomaticChecks") is not True or info.get("SUAutomaticallyUpdate") is not False:
        raise ReleaseError("Public releases must enable checks and keep automatic installation disabled by default.")
    expected_name = f"OpenNoType-{metadata['version']}.zip"
    if archive.name != expected_name or not archive.is_file() or archive.is_symlink():
        raise ReleaseError("The final archive must be named OpenNoType-VERSION.zip and be a regular file.")
    validate_private_key_file(private_key_file)
    generator, verifier = sparkle_tools(project_root, app)
    if run_tool(["/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/OpenNoType")], "Architecture validation").strip() != "arm64":
        raise ReleaseError("The release application must contain only the arm64 architecture.")
    validate_archive_info(archive, info)
    boundary = fingerprint(archive)
    metadata.update(zip_file=archive.name, length=boundary[0], zip_sha256=boundary[1],
        download_url=f"{REPOSITORY_URL}/releases/download/{tag}/{archive.name}",
        release_notes_url=f"{REPOSITORY_URL}/releases/tag/{tag}",
        published_at=format_datetime(datetime.now(timezone.utc), usegmt=True))
    output_dir.mkdir(parents=True, exist_ok=True)
    # Isolate generate_appcast from old releases/deltas and an old appcast. It
    # signs the ZIP while deriving version, OS, and arm64 requirements from it.
    with tempfile.TemporaryDirectory(prefix="opennotype-appcast-") as temporary:
        staging = Path(temporary)
        staged_archive = staging / archive.name
        shutil.copyfile(archive, staged_archive)
        assert_unchanged(staged_archive, boundary)
        generated = staging / "appcast.xml"
        run_tool([str(generator), "--ed-key-file", str(private_key_file),
                  "--download-url-prefix", f"{REPOSITORY_URL}/releases/download/{tag}/",
                  "--maximum-deltas", "0", "--maximum-versions", "1", "--versions", str(metadata["build"]),
                  "--link", metadata["release_notes_url"], "-o", str(generated), str(staging)], "Sparkle appcast generation")
        metadata["signature"] = validate_generated_feed(generated.read_bytes(), metadata)
        assert_unchanged(staged_archive, boundary)
    assert_unchanged(archive, boundary)
    # sign_update verifies against the private export's derived public key.
    # CryptoKit then verifies against the app's actual public key: both must pass.
    validate_private_key_file(private_key_file)
    run_tool([str(verifier), "--ed-key-file", str(private_key_file), "--verify", str(archive), metadata["signature"]],
             "Sparkle archive signature verification")
    run_tool(["/usr/bin/swift", str(project_root / "scripts/verify-update-signature.swift"), str(archive),
              metadata["public_key"], metadata["signature"]], "Bundled public-key signature verification")
    assert_unchanged(archive, boundary)
    xml = appcast_xml(metadata)
    # Reparse our serialized feed too; this catches accidental length/URL changes.
    if validate_generated_feed(xml, metadata) != metadata["signature"]:
        raise ReleaseError("The final appcast signature differs from the verified archive.")
    atomic_write(output_dir / "appcast.xml", xml)
    atomic_write(output_dir / f"{archive.name}.sha256", f"{boundary[1]}  {archive.name}\n".encode())
    atomic_write(output_dir / "release-metadata.json", (json.dumps(metadata, indent=2, ensure_ascii=False) + "\n").encode())
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    config = sub.add_parser("configure", help="Validate or inject public update settings into an unsigned plist")
    config.add_argument("--info-plist", type=Path, required=True)
    config.add_argument("--channel-plist", type=Path, default=ROOT / "Resources/UpdateChannel.plist")
    config.add_argument("--release", action="store_true")
    config.add_argument("--tag", default=os.environ.get("RELEASE_TAG"))
    config.add_argument("--write", action="store_true")
    sub.add_parser("validate-key-file", help="Validate the runtime key file without printing its contents")
    signing = sub.add_parser("validate-signing", help="Verify the actual code signature for the declared distribution")
    signing.add_argument("--path", type=Path, required=True)
    signing.add_argument("--distribution", choices=("community", "notarized"), required=True)
    gen = sub.add_parser("generate", help="Sign and verify the final ZIP, then emit the appcast and public metadata")
    gen.add_argument("--app", type=Path, required=True)
    gen.add_argument("--zip", type=Path, required=True)
    gen.add_argument("--output-dir", type=Path, required=True)
    gen.add_argument("--tag", default=os.environ.get("RELEASE_TAG"))
    args = parser.parse_args()
    try:
        if args.command == "configure":
            configure(args.info_plist, args.channel_plist, dict(os.environ), release=args.release, tag=args.tag, write=args.write)
        elif args.command == "validate-signing":
            validate_code_signing(args.path, args.distribution)
        else:
            key_path = os.environ.get("SPARKLE_PRIVATE_KEY_FILE")
            if not key_path or key_path == "-":
                raise ReleaseError("SPARKLE_PRIVATE_KEY_FILE must name a runtime 0600 key file.")
            key_file = Path(key_path).absolute()
            if args.command == "validate-key-file":
                validate_private_key_file(key_file)
            else:
                if not args.tag:
                    raise ReleaseError("RELEASE_TAG is required for public releases.")
                generate(args.app.absolute(), args.zip.absolute(), args.output_dir.absolute(), args.tag, key_file)
    except ReleaseError as error:
        print(f"Release validation failed: {error}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError):
        # Do not expose a path or a third-party exception containing key material.
        print("Release validation failed: unable to process release files.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
