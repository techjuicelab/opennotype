#!/usr/bin/env python3
"""Read-only stable-release gates; never creates a tag, release, or secret."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import plistlib
import re
import subprocess
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

REPOSITORY = "techjuicelab/opennotype"
FEED_URL = f"https://github.com/{REPOSITORY}/releases/latest/download/appcast.xml"
SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def version_tuple(version: str) -> tuple[int, int, int]:
    require(isinstance(version, str) and SEMVER.fullmatch(version) is not None,
            "Only stable x.y.z versions without leading zeroes are allowed")
    return tuple(int(part) for part in version.split("."))


def positive_build(value: object) -> int:
    require(isinstance(value, str) and re.fullmatch(r"[1-9][0-9]*", value) is not None,
            "CFBundleVersion/build must be a positive decimal string")
    return int(value)


def validate_identity(info: dict, tag: str) -> tuple[str, int]:
    version = info.get("CFBundleShortVersionString")
    version_tuple(version)
    require(tag == f"v{version}", "Release tag and CFBundleShortVersionString differ")
    require(info.get("CFBundleIdentifier") == "app.opennotype.mac", "Unexpected bundle identifier")
    return version, positive_build(info.get("CFBundleVersion"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_metadata(metadata: dict, version: str, build: int) -> None:
    require(metadata.get("version") == version and metadata.get("tag") == f"v{version}",
            "Release metadata version/tag mismatch")
    require(positive_build(str(metadata.get("build"))) == build, "Release metadata build mismatch")
    require(metadata.get("zip_file") == f"OpenNoType-{version}.zip", "Unexpected ZIP filename")
    require(metadata.get("feed_url") == FEED_URL, "Unexpected stable feed URL")
    require(metadata.get("download_url") ==
            f"https://github.com/{REPOSITORY}/releases/download/v{version}/OpenNoType-{version}.zip",
            "Metadata download URL is not the immutable version URL")
    require(metadata.get("release_notes_url") == f"https://github.com/{REPOSITORY}/releases/tag/v{version}",
            "Metadata release notes URL is not the immutable tag URL")
    require(metadata.get("arch") == "arm64", "Unexpected release architecture")
    require(metadata.get("distribution") in ("community", "notarized"), "Missing or invalid release distribution")
    require(isinstance(metadata.get("min_os"), str) and
            re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", metadata["min_os"]) is not None,
            "Invalid minimum macOS version")
    require(re.fullmatch(r"[0-9a-f]{64}", str(metadata.get("zip_sha256"))) is not None,
            "Invalid ZIP SHA-256")
    require(isinstance(metadata.get("length"), int) and metadata["length"] > 0, "Invalid ZIP length")
    for field, size in (("public_key", 32), ("signature", 64)):
        value = metadata.get(field, "")
        try:
            decoded = base64.b64decode(value, validate=True)
        except (ValueError, TypeError) as error:
            raise ValueError(f"Invalid {field}") from error
        require(len(decoded) == size and base64.b64encode(decoded).decode() == value,
                f"Invalid canonical {field}")


def validate_archive_distribution(archive: Path, metadata: dict) -> None:
    # The display type comes from the signed application too. Editing only the
    # public JSON must not turn a community build into a notarized claim.
    try:
        with zipfile.ZipFile(archive) as handle:
            entries = [item for item in handle.infolist() if item.filename == "OpenNoType.app/Contents/Info.plist"]
            require(len(entries) == 1 and entries[0].file_size <= 1024 * 1024, "Expected exactly one bounded app Info.plist")
            app_info = plistlib.loads(handle.read(entries[0]))
    except (OSError, zipfile.BadZipFile, plistlib.InvalidFileException):
        raise ValueError("Cannot read release app metadata from ZIP") from None
    require(validate_identity(app_info, metadata["tag"]) == (metadata["version"], int(metadata["build"])), "ZIP app version/build differs")
    require(app_info.get("OpenNoTypeDistribution") == metadata["distribution"], "ZIP app distribution differs from release metadata")
    require(app_info.get("SUPublicEDKey") == metadata["public_key"] and app_info.get("SUFeedURL") == metadata["feed_url"],
            "ZIP app update channel differs from release metadata")
    require(app_info.get("LSMinimumSystemVersion") == metadata["min_os"], "ZIP app minimum OS differs")


def validate_artifacts(directory: Path, version: str, build: int, distribution: str | None = None) -> dict:
    names = {f"OpenNoType-{version}.zip", f"OpenNoType-{version}.dmg",
             f"OpenNoType-{version}.zip.sha256", f"OpenNoType-{version}.dmg.sha256",
             "appcast.xml", "release-metadata.json"}
    require(directory.is_dir(), "Artifact directory is missing")
    require({path.name for path in directory.iterdir()} == names, "Missing or unexpected release artifacts")
    require(all((directory / name).is_file() and not (directory / name).is_symlink() for name in names),
            "Artifacts must be regular files")
    metadata = json.loads((directory / "release-metadata.json").read_text())
    validate_metadata(metadata, version, build)
    if distribution is not None:
        require(distribution in ("community", "notarized"), "Invalid selected release distribution")
        require(metadata["distribution"] == distribution, "Release distribution differs from the selected signing mode")
    archive = directory / metadata["zip_file"]
    require(archive.stat().st_size == metadata["length"], "ZIP length differs from signed metadata")
    require(sha256(archive) == metadata["zip_sha256"], "ZIP digest differs from signed metadata")
    for suffix in ("zip", "dmg"):
        filename = f"OpenNoType-{version}.{suffix}"
        checksum = (directory / f"{filename}.sha256").read_text().strip().split()
        require(len(checksum) == 2 and checksum[0] == sha256(directory / filename)
                and checksum[1] in (filename, f"*{filename}"), "Invalid portable artifact checksum")
    validate_archive_distribution(archive, metadata)
    tree = ET.parse(directory / "appcast.xml")
    items = tree.findall("./channel/item")
    require(len(items) == 1, "Stable appcast must contain exactly the candidate release")
    item = items[0]
    if metadata["distribution"] == "community":
        require("커뮤니티" in item.findtext("title", "") and "미공증" in item.findtext("title", ""),
                "Community appcast must visibly identify the unnotarized release")
    enclosure = item.find("enclosure")
    require(enclosure is not None, "Missing appcast enclosure")
    require(item.findtext(f"{SPARKLE}version") == str(build), "Appcast build differs")
    require(item.findtext(f"{SPARKLE}shortVersionString") == version, "Appcast version differs")
    require(item.findtext(f"{SPARKLE}minimumSystemVersion") == metadata.get("min_os"), "Appcast minimum OS differs")
    require(item.findtext(f"{SPARKLE}hardwareRequirements") == metadata["arch"], "Appcast architecture differs")
    require(item.findtext(f"{SPARKLE}releaseNotesLink") == metadata["release_notes_url"],
            "Appcast release notes link is not the immutable tag URL")
    require(item.find(f"{SPARKLE}channel") is None, "Prerelease appcast channels are forbidden")
    expected_url = f"https://github.com/{REPOSITORY}/releases/download/v{version}/{archive.name}"
    require(enclosure.get("url") == expected_url, "Appcast enclosure is not the immutable version URL")
    require(enclosure.get("type") == "application/octet-stream", "Unexpected appcast enclosure type")
    require(enclosure.get("length") == str(metadata["length"]), "Appcast length differs")
    require(enclosure.get(f"{SPARKLE}edSignature") == metadata["signature"], "Appcast signature differs")
    return metadata


def run_read(command: list[str]) -> bytes:
    result = subprocess.run(command, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result.returncode == 0, f"Read-only command failed: {command[0]}")
    return result.stdout


def validate_git(tag: str, version: str, build: int) -> None:
    head = run_read(["git", "rev-parse", "HEAD"]).strip()
    tagged = run_read(["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"]).strip()
    require(head == tagged, "Checkout must exactly match the existing release tag")
    run_read(["git", "merge-base", "--is-ancestor", "HEAD", "origin/main"])
    tags = run_read(["git", "tag", "--list", "v*"]).decode().splitlines()
    for older in tags:
        if not SEMVER.fullmatch(older[1:]) or version_tuple(older[1:]) >= version_tuple(version):
            continue
        raw = run_read(["git", "show", f"refs/tags/{older}:Resources/Info.plist"])
        old_info = plistlib.loads(raw)
        _, old_build = validate_identity(old_info, older)
        require(build > old_build, f"Build must increase beyond older tag {older}")


def validate_previous_releases(releases: list[dict], version: str, build: int,
                               read_metadata, allow_draft_id: int | None = None) -> None:
    for release in releases:
        tag = release.get("tag_name", "")
        if tag == f"v{version}":
            require(release.get("draft") is True and allow_draft_id is not None
                    and release.get("id") == allow_draft_id and release.get("prerelease") is False,
                    "Candidate release already exists; never overwrite an existing release")
            continue
        if release.get("draft") or release.get("prerelease"):
            continue
        require(isinstance(tag, str) and tag.startswith("v"), "Published release has an unsupported tag")
        old_version = tag[1:]
        require(version_tuple(version) > version_tuple(old_version),
                f"Candidate would downgrade or duplicate published release {tag}")
        matching = [asset for asset in release.get("assets", []) if asset.get("name") == "release-metadata.json"]
        require(len(matching) == 1, f"Published release {tag} lacks trustworthy build metadata")
        metadata = read_metadata(matching[0])
        old_build = positive_build(str(metadata.get("build")))
        validate_metadata(metadata, old_version, old_build)
        require(build > old_build, f"Build must increase beyond published release {tag}")


def check_remote(version: str, build: int, allow_draft_id: int | None) -> None:
    pages = json.loads(run_read(["gh", "api", "--paginate", "--slurp",
                                f"repos/{REPOSITORY}/releases?per_page=100"]))
    require(isinstance(pages, list) and all(isinstance(page, list) for page in pages), "Invalid releases response")
    releases = [release for page in pages for release in page]

    def read_metadata(asset: dict) -> dict:
        asset_id = asset.get("id")
        require(isinstance(asset_id, int) and asset_id > 0, "Invalid metadata asset ID")
        raw = run_read(["gh", "api", "-H", "Accept: application/octet-stream",
                        f"repos/{REPOSITORY}/releases/assets/{asset_id}"])
        return json.loads(raw)

    validate_previous_releases(releases, version, build, read_metadata, allow_draft_id)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--info", type=Path, default=Path("Resources/Info.plist"))
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--distribution", choices=("community", "notarized"),
                        default=os.environ.get("RELEASE_SIGNING_MODE", "notarized"))
    parser.add_argument("--check-git", action="store_true")
    parser.add_argument("--check-remote", action="store_true")
    parser.add_argument("--allow-draft-id", type=int)
    args = parser.parse_args()
    try:
        require(args.distribution in ("community", "notarized"), "Invalid selected release distribution")
        require(args.repository == REPOSITORY, "Release workflow is restricted to the canonical repository")
        version, build = validate_identity(plistlib.loads(args.info.read_bytes()), args.tag)
        if args.check_git:
            validate_git(args.tag, version, build)
        if args.artifacts:
            validate_artifacts(args.artifacts, version, build, args.distribution)
        if args.check_remote:
            check_remote(version, build, args.allow_draft_id)
        print(f"Stable release gates passed: {args.tag} (build {build})")
        return 0
    except (ValueError, OSError, KeyError, TypeError, ET.ParseError) as error:
        parser.exit(1, f"Release preflight failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
