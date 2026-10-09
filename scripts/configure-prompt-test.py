#!/usr/bin/env python3
"""Apply isolated Prompt Test identity, version, and provenance to a staged app."""

import argparse
from datetime import datetime
import json
from pathlib import Path
import plistlib
import re


def configure_prompt_test(
    app_path: Path,
    version_path: Path,
    source_commit: str,
    source_dirty: bool,
    built_at: str,
) -> None:
    version = plistlib.loads(version_path.read_bytes())
    if not isinstance(version, dict) or set(version) != {
        "CFBundleShortVersionString", "CFBundleVersion"
    }:
        raise ValueError("Expected only the test version and build number.")
    short_version = version["CFBundleShortVersionString"]
    build_number = version["CFBundleVersion"]
    component = r"(?:0|[1-9][0-9]*)"
    if not isinstance(short_version, str) or not re.fullmatch(
        rf"{component}\.{component}\.{component}", short_version
    ):
        raise ValueError("The test version must contain three numeric components.")
    if not isinstance(build_number, str) or not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise ValueError("The test build number must be a positive integer string.")
    if not isinstance(source_commit, str) or not re.fullmatch(
        r"(?:[0-9a-f]{40}|[0-9a-f]{64})", source_commit
    ):
        raise ValueError("Could not identify the test source commit.")
    if type(source_dirty) is not bool:
        raise ValueError("The test source dirty flag must be a boolean.")
    if not isinstance(built_at, str) or not re.fullmatch(
        r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", built_at
    ):
        raise ValueError("The test build time must use UTC ISO 8601.")
    datetime.strptime(built_at, "%Y-%m-%dT%H:%M:%SZ")

    info_path = app_path / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    if info.get("CFBundleIdentifier") != "app.opennotype.mac" or info.get("CFBundleExecutable") != "OpenNoType":
        raise ValueError("Expected a freshly built OpenNoType app bundle.")
    info.update({
        "CFBundleIdentifier": "app.opennotype.prompt-test",
        "CFBundleName": "OpenNoType Prompt Test",
        "CFBundleDisplayName": "OpenNoType Prompt Test",
        **version,
        "OpenNoTypeTestSourceCommit": source_commit,
        "OpenNoTypeTestSourceDirty": source_dirty,
        "OpenNoTypeTestBuiltAt": built_at,
        "SUEnableAutomaticChecks": False,
        "SUAutomaticallyUpdate": False,
    })
    for key in list(info):
        if key in ("SUFeedURL", "SUPublicEDKey", "OpenNoTypeDistribution") or key.startswith("OpenNoTypePreview"):
            del info[key]
    messages = {
        "en": {
            "NSMicrophoneUsageDescription": "OpenNoType Prompt Test uses the microphone to turn your speech into text and enroll your voice.",
            "NSSpeechRecognitionUsageDescription": "OpenNoType Prompt Test converts speech to text on this Mac.",
        },
        "ko": {
            "NSMicrophoneUsageDescription": "OpenNoType Prompt Test에서 말씀하신 내용을 글로 입력하고 내 목소리를 등록하기 위해 마이크를 사용합니다.",
            "NSSpeechRecognitionUsageDescription": "OpenNoType Prompt Test에서 기기의 음성을 글로 변환합니다.",
        },
    }
    info.update(messages["en"])

    # Validate every localization before changing any of the staged files.
    localized_strings = {}
    for language, values in messages.items():
        strings_path = app_path / "Contents/Resources" / f"{language}.lproj/InfoPlist.strings"
        text = strings_path.read_text(encoding="utf-8")
        for key, value in values.items():
            pattern = r'^"' + re.escape(key) + r'"\s*=\s*"(?:\\.|[^"\\])*"\s*;'
            replacement = json.dumps(key) + " = " + json.dumps(value, ensure_ascii=False) + ";"
            text, count = re.subn(pattern, lambda match: replacement, text, flags=re.MULTILINE)
            if count != 1:
                raise ValueError(f"Expected one localized {key} in {language}.")
        localized_strings[strings_path] = text

    info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    for strings_path, text in localized_strings.items():
        strings_path.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("version", type=Path)
    parser.add_argument("commit")
    parser.add_argument("dirty", choices=("true", "false"))
    parser.add_argument("built_at")
    args = parser.parse_args()
    configure_prompt_test(args.app, args.version, args.commit, args.dirty == "true", args.built_at)


if __name__ == "__main__":
    main()
