"""Offline release gates using synthetic metadata; no real signing keys or API."""
import base64
import importlib.util
import json
import plistlib
from pathlib import Path
import tempfile
import unittest
import zipfile
from unittest import mock

SPEC = importlib.util.spec_from_file_location("release_preflight", Path(__file__).with_name("release-preflight.py"))
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


def info(version="0.2.0", build="11"):
    return {"CFBundleIdentifier": "app.opennotype.mac", "CFBundleShortVersionString": version,
            "CFBundleVersion": build}


def metadata(version="0.1.9", build=10):
    return {"version": version, "tag": f"v{version}", "build": build,
            "zip_file": f"OpenNoType-{version}.zip", "zip_sha256": "a" * 64,
            "length": 123, "signature": base64.b64encode(bytes(64)).decode(),
            "public_key": base64.b64encode(bytes(32)).decode(), "feed_url": release.FEED_URL,
            "download_url": f"https://github.com/{release.REPOSITORY}/releases/download/v{version}/OpenNoType-{version}.zip",
            "release_notes_url": f"https://github.com/{release.REPOSITORY}/releases/tag/v{version}",
            "min_os": "14.0.0", "arch": "arm64", "distribution": "notarized"}


def previous(tag="v0.1.9", identifier=1, draft=False, prerelease=False):
    return {"tag_name": tag, "id": identifier, "draft": draft, "prerelease": prerelease,
            "assets": [{"name": "release-metadata.json", "id": 9}]}


class ReleasePreflightTests(unittest.TestCase):
    def test_only_canonical_stable_tag_matches_bundle(self):
        self.assertEqual(release.validate_identity(info(), "v0.2.0"), ("0.2.0", 11))
        for tag in ("0.2.0", "v0.2.1", "v0.2.0-beta", "v0.2.0+12", "v00.2.0"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.validate_identity(info(), tag)

    def test_rejects_nonstable_bundle_versions(self):
        for version in ("0.2", "01.2.3", "1.2.3-beta", "1.2.3+4", "1.2.3\n", None):
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.validate_identity(info(version=version), f"v{version}")

    def test_build_is_positive_decimal_and_bundle_identity_is_fixed(self):
        for build in ("0", "-1", "01", "1.2", "a", None, 12):
            with self.subTest(build=build), self.assertRaises(ValueError):
                release.validate_identity(info(build=build), "v0.2.0")
        changed = info()
        changed["CFBundleIdentifier"] = "other.app"
        with self.assertRaises(ValueError):
            release.validate_identity(changed, "v0.2.0")

    def test_bootstrap_needs_no_fake_previous_release(self):
        read = mock.Mock(side_effect=AssertionError("no assets exist"))
        release.validate_previous_releases([], "0.2.0", 11, read)
        read.assert_not_called()

    def test_version_and_build_must_both_increase(self):
        release.validate_previous_releases([previous()], "0.2.0", 11, lambda _: metadata())
        for version, build in (("0.1.8", 11), ("0.1.9", 11), ("0.2.0", 10), ("0.2.0", 9)):
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                release.validate_previous_releases([previous()], version, build, lambda _: metadata())

    def test_all_published_releases_checked_not_only_latest(self):
        history = [previous(), previous("v1.0.0", identifier=2)]
        with self.assertRaisesRegex(ValueError, "downgrade"):
            release.validate_previous_releases(history, "0.2.0", 100, lambda _: metadata())

    def test_unrelated_prereleases_and_drafts_do_not_become_stable_baseline(self):
        history = [previous("v5.0.0", draft=True), previous("v3.0.0-beta", prerelease=True)]
        release.validate_previous_releases(history, "0.2.0", 11, mock.Mock(side_effect=AssertionError))

    def test_published_unknown_tag_or_missing_metadata_fails_closed(self):
        for old in (previous("nightly"), {**previous(), "assets": []}):
            with self.subTest(old=old), self.assertRaises(ValueError):
                release.validate_previous_releases([old], "0.2.0", 11, lambda _: metadata())

    def test_candidate_release_never_overwritten_and_only_owned_draft_allowed(self):
        for draft in (False, True):
            with self.subTest(draft=draft), self.assertRaises(ValueError):
                release.validate_previous_releases([previous("v0.2.0", draft=draft)], "0.2.0", 11, lambda _: metadata())
        owned = previous("v0.2.0", draft=True)
        release.validate_previous_releases([owned], "0.2.0", 11, lambda _: metadata(), allow_draft_id=1)
        for changed in ({**owned, "id": 2}, {**owned, "draft": False}, {**owned, "prerelease": True}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                release.validate_previous_releases([changed], "0.2.0", 11, lambda _: metadata(), allow_draft_id=1)

    def test_previous_metadata_must_match_its_actual_release(self):
        for changed in ({**metadata(), "tag": "v9.0.0"}, {**metadata(), "version": "9.0.0"},
                        {**metadata(), "feed_url": "https://example.com/appcast.xml"}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                release.validate_previous_releases([previous()], "0.2.0", 11, lambda _: changed)

    def test_metadata_download_url_requires_the_exact_repository_tag_and_filename(self):
        canonical = metadata()["download_url"]
        changed_urls = (None, "", canonical.replace("github.com", "example.invalid"),
                        canonical.replace("/v0.1.9/", "/v0.1.8/"),
                        canonical.replace("/download/v0.1.9/", "/latest/download/"),
                        canonical.replace("OpenNoType-0.1.9.zip", "OpenNoType-0.1.8.zip"),
                        canonical + "?redirect=1")
        for url in changed_urls:
            with self.subTest(url=url), self.assertRaisesRegex(ValueError, "Metadata download URL"):
                release.validate_metadata(metadata() | {"download_url": url}, "0.1.9", 10)

    def test_metadata_release_notes_url_requires_the_exact_tag(self):
        canonical = metadata()["release_notes_url"]
        changed_urls = (None, "", canonical.replace("github.com", "example.invalid"),
                        canonical.replace("/v0.1.9", "/v0.1.8"),
                        canonical.replace("/tag/v0.1.9", "/latest"), canonical + "#other")
        for url in changed_urls:
            with self.subTest(url=url), self.assertRaisesRegex(ValueError, "Metadata release notes URL"):
                release.validate_metadata(metadata() | {"release_notes_url": url}, "0.1.9", 10)

    def make_artifacts(self, directory, distribution="notarized"):
        value = metadata("0.2.0", 11)
        value["distribution"] = distribution
        for suffix in ("zip", "dmg"):
            filename = f"OpenNoType-0.2.0.{suffix}"
            path = directory / filename
            if suffix == "zip":
                app_info = info() | {"OpenNoTypeDistribution": distribution,
                    "SUPublicEDKey": value["public_key"], "SUFeedURL": value["feed_url"],
                    "LSMinimumSystemVersion": value["min_os"]}
                with zipfile.ZipFile(path, "w") as handle:
                    handle.writestr("OpenNoType.app/Contents/Info.plist", plistlib.dumps(app_info))
            else:
                path.write_bytes(b"synthetic public artifact " + suffix.encode())
            (directory / f"{filename}.sha256").write_text(f"{release.sha256(path)}  {filename}\n")
        archive = directory / value["zip_file"]
        value.update(length=archive.stat().st_size, zip_sha256=release.sha256(archive))
        (directory / "release-metadata.json").write_text(json.dumps(value))
        (directory / "appcast.xml").write_text(f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<title>{"커뮤니티 배포 (Apple 미공증)" if distribution == "community" else "OpenNoType 0.2.0"}</title>
<sparkle:version>11</sparkle:version><sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
<sparkle:releaseNotesLink>{value['release_notes_url']}</sparkle:releaseNotesLink>
<enclosure url="https://github.com/{release.REPOSITORY}/releases/download/v0.2.0/{archive.name}" type="application/octet-stream" length="{value['length']}" sparkle:edSignature="{value['signature']}" />
</item></channel></rss>''')
        return value

    def test_verified_artifacts_match_manifest_and_appcast(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            expected = self.make_artifacts(directory)
            self.assertEqual(release.validate_artifacts(directory, "0.2.0", 11), expected)

    def test_appcast_release_notes_link_cannot_drift_from_the_canonical_tag(self):
        canonical = metadata("0.2.0", 11)["release_notes_url"]
        changed_urls = ("", canonical.replace("github.com", "example.invalid"),
                        canonical.replace("/v0.2.0", "/v0.1.9"), canonical + "?other=1")
        for url in changed_urls:
            with self.subTest(url=url), tempfile.TemporaryDirectory() as folder:
                directory = Path(folder)
                self.make_artifacts(directory, "community")
                path = directory / "appcast.xml"
                path.write_text(path.read_text().replace(
                    f"<sparkle:releaseNotesLink>{canonical}</sparkle:releaseNotesLink>",
                    f"<sparkle:releaseNotesLink>{url}</sparkle:releaseNotesLink>" if url else ""))
                with self.assertRaisesRegex(ValueError, "Appcast release notes link"):
                    release.validate_artifacts(directory, "0.2.0", 11, "community")

    def test_community_metadata_must_match_mode_and_signed_app_field(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            expected = self.make_artifacts(directory, "community")
            self.assertEqual(release.validate_artifacts(directory, "0.2.0", 11, "community"), expected)
            with self.assertRaisesRegex(ValueError, "selected signing mode"):
                release.validate_artifacts(directory, "0.2.0", 11, "notarized")
            expected["distribution"] = "notarized"
            (directory / "release-metadata.json").write_text(json.dumps(expected))
            with self.assertRaisesRegex(ValueError, "ZIP app distribution"):
                release.validate_artifacts(directory, "0.2.0", 11, "notarized")

    def test_community_appcast_must_disclose_distribution(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            self.make_artifacts(directory, "community")
            path = directory / "appcast.xml"
            path.write_text(path.read_text().replace("커뮤니티 배포 (Apple 미공증)", "OpenNoType"))
            with self.assertRaisesRegex(ValueError, "visibly identify"):
                release.validate_artifacts(directory, "0.2.0", 11, "community")

    def test_missing_or_unknown_distribution_fails(self):
        for distribution in (None, "", "development", "Community"):
            with self.subTest(distribution=distribution), self.assertRaisesRegex(ValueError, "distribution"):
                release.validate_metadata(metadata() | {"distribution": distribution}, "0.1.9", 10)

    def test_changed_zip_bytes_rejected_even_when_same_length(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            self.make_artifacts(directory)
            archive = directory / "OpenNoType-0.2.0.zip"
            archive.write_bytes(b"x" * archive.stat().st_size)
            with self.assertRaisesRegex(ValueError, "digest"):
                release.validate_artifacts(directory, "0.2.0", 11)

    def test_changed_dmg_and_missing_or_extra_files_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            self.make_artifacts(directory)
            (directory / "OpenNoType-0.2.0.dmg").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "checksum"):
                release.validate_artifacts(directory, "0.2.0", 11)
            self.make_artifacts(directory)
            (directory / "private.key").write_text("synthetic unexpected artifact")
            with self.assertRaisesRegex(ValueError, "unexpected"):
                release.validate_artifacts(directory, "0.2.0", 11)
            (directory / "private.key").unlink()
            (directory / "appcast.xml").unlink()
            with self.assertRaisesRegex(ValueError, "unexpected"):
                release.validate_artifacts(directory, "0.2.0", 11)

    def test_appcast_version_url_signature_and_channel_cannot_drift(self):
        changes = (("<sparkle:version>11", "<sparkle:version>12"),
                   ("releases/download/v0.2.0", "releases/latest/download"),
                   ("0.2.0</sparkle:shortVersionString>", "0.2.1</sparkle:shortVersionString>"),
                   ("arm64</sparkle:hardwareRequirements>", "x86_64</sparkle:hardwareRequirements>"),
                   ("</item>", "<sparkle:channel>beta</sparkle:channel></item>"),
                   ("sparkle:edSignature=", "removedSignature="))
        for before, after in changes:
            with self.subTest(before=before), tempfile.TemporaryDirectory() as folder:
                directory = Path(folder)
                self.make_artifacts(directory)
                path = directory / "appcast.xml"
                path.write_text(path.read_text().replace(before, after))
                with self.assertRaises(ValueError):
                    release.validate_artifacts(directory, "0.2.0", 11)

    def test_malformed_signature_and_public_key_rejected(self):
        for field in ("signature", "public_key"):
            for value in ("", "bad", base64.b64encode(b"short").decode()):
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    release.validate_metadata({**metadata(), field: value}, "0.1.9", 10)

    def test_git_must_match_tag_and_main_before_history_is_checked(self):
        with mock.patch.object(release, "run_read", side_effect=[b"sha1", b"sha2"]):
            with self.assertRaisesRegex(ValueError, "exactly match"):
                release.validate_git("v0.2.0", "0.2.0", 11)
        with mock.patch.object(release, "run_read", side_effect=[b"sha", b"sha", ValueError("not on main")]):
            with self.assertRaisesRegex(ValueError, "not on main"):
                release.validate_git("v0.2.0", "0.2.0", 11)

    def test_build_must_exceed_older_tag_even_if_unpublished(self):
        responses = [b"sha", b"sha", b"", b"v0.1.9\nv0.2.0\nv1.0.0-beta", plistlib.dumps(info("0.1.9", "12"))]
        with mock.patch.object(release, "run_read", side_effect=responses):
            with self.assertRaisesRegex(ValueError, "older tag"):
                release.validate_git("v0.2.0", "0.2.0", 11)

    def test_remote_lists_every_page_and_reads_only_same_repository_asset_ids(self):
        calls = []
        def fake(command):
            calls.append(command)
            if "--paginate" in command:
                return json.dumps([[previous()]]).encode()
            return json.dumps(metadata()).encode()
        with mock.patch.object(release, "run_read", side_effect=fake):
            release.check_remote("0.2.0", 11, None)
        self.assertIn("--slurp", calls[0])
        self.assertEqual(calls[1][-1], f"repos/{release.REPOSITORY}/releases/assets/9")
        self.assertFalse(any("POST" in command or "PATCH" in command for command in calls))


if __name__ == "__main__":
    unittest.main()
