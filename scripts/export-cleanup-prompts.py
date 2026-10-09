#!/usr/bin/env python3
"""Compile actual prompt sources from a Git commit or the working tree; no API/key access."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

SOURCES = ["Sources/OpenNoTypeCore/Localization.swift", "Sources/OpenNoTypeCore/Models.swift", "Sources/OpenNoTypeCore/AI/JevRepairIssue.swift", "Sources/OpenNoTypeCore/AI/ProviderDefaults.swift",
           "Sources/OpenNoTypeCore/AI/WritingProfile.swift", "Sources/OpenNoTypeCore/AI/DictionaryHints.swift",
           "Sources/OpenNoTypeCore/AI/ProcessingPrompt.swift"]
OPTIONAL = ["Sources/OpenNoTypeCore/AI/DictationCleanupInstructions.swift",
            "Sources/OpenNoTypeCore/AI/DictationExpression.swift",
            "Sources/OpenNoTypeCore/AI/DictationOutputLanguage.swift",
            "Sources/OpenNoTypeCore/AI/NativeTranslationInstructions.swift",
            "Sources/OpenNoTypeCore/AI/ProtectedLiteralPatterns.swift",
            "Sources/OpenNoTypeCore/AI/TranslationOutputGuard.swift",
            "Sources/OpenNoTypeCore/AI/TranslationRefinement.swift",
            "Sources/OpenNoTypeCore/AI/TranslationRefinementInstructions.swift",
            "Sources/OpenNoTypeCore/AI/PromptComposition.swift",
            "Sources/OpenNoTypeCore/AI/PromptCompositionSegmentResponse.swift"]
HARNESS = r'''
import Foundation
import CryptoKit

let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fixtureData = try Data(contentsOf: fixtureURL)
let document = try JSONSerialization.jsonObject(with: fixtureData) as! [String: Any]
let cases = document["cases"] as! [[String: Any]]
let output = try cases.map { fixture -> [String: Any] in
    let profileData = try JSONSerialization.data(withJSONObject: fixture["writing_profile"] as! [String: Any])
    let profile = try JSONDecoder().decode(WritingProfile.self, from: profileData)
    let dictionary = (fixture["dictionary"] as? [[String: String]] ?? []).map {
        DictionaryEntry(spoken: $0["spoken"]!, written: $0["written"]!)
    }
    let request = ProcessingRequest(mode: InputMode(rawValue: fixture["mode"] as! String)!,
        transcript: fixture["stt_input"] as! String,
        selectedText: fixture["selected_text"] as? String,
        context: fixture["cursor_context"] as? String,
        dictionary: dictionary,
        targetLanguage: fixture["target_language"] as? String ?? "English (United States)",
        writingProfile: profile)
    let prompt = try ProcessingPrompt.build(request)
    let hash = SHA256.hash(data: Data(prompt.instructions.utf8)).map { String(format: "%02x", $0) }.joined()
    return ["fixture": fixture, "instructions": prompt.instructions, "input": prompt.input,
            "instructions_sha256": hash]
}
try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .withoutEscapingSlashes])
    .write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
'''

# Historical revision exports keep the API that existed at that revision. Working-tree
# exports also exercise the controlled output setting, including expression isolation.
TRANSLATION_HARNESS = HARNESS.replace(
    '        writingProfile: profile)',
    '        outputLanguage: DictationOutputLanguage(rawValue: fixture["output_language"] as? String ?? "original")!,\n'
    '        writingProfile: profile)')


def export(root, fixture, output, revision=None):
    ref = subprocess.check_output(["git", "rev-parse", "--verify", "--end-of-options", revision + "^{commit}"],
                                  cwd=root, text=True).strip() if revision else None
    hashes = {}
    with tempfile.TemporaryDirectory(prefix="opennotype-prompt-export-") as scratch:
        scratch = Path(scratch)
        paths = []
        for source in SOURCES + OPTIONAL:
            if ref:
                result = subprocess.run(["git", "show", f"{ref}:{source}"], cwd=root, capture_output=True)
                if result.returncode and source in OPTIONAL:
                    continue
                result.check_returncode()
                data = result.stdout
            else:
                path = root / source
                if source in OPTIONAL and not path.exists():
                    continue
                data = path.read_bytes()
            target = scratch / Path(source).name
            target.write_bytes(data)
            paths.append(str(target))
            hashes[source] = hashlib.sha256(data).hexdigest()
        main = scratch / "main.swift"
        main.write_text(TRANSLATION_HARNESS if OPTIONAL[2] in hashes else HARNESS)
        binary = scratch / "export-prompts"
        subprocess.run(["swiftc", "-swift-version", "5", *paths, str(main), "-o", str(binary)], check=True)
        result = scratch / "cases.json"
        subprocess.run([str(binary), str(fixture), str(result)], check=True)
        cases = json.loads(result.read_bytes())
    document = {"schema_version": 1, "status": "synthetic_fixture_prompts_not_live_model_results",
                "fixture_sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
                "prompt_source_sha256": hashes[SOURCES[-1]], "source_sha256": hashes,
                "source_ref": ref or "working_tree", "cases": cases}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n")
    print(f"Exported {len(cases)} actual prompt requests; max instructions {max(len(c['instructions'].encode()) for c in cases)} UTF-8 bytes; {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", help="Exact Git revision; omit for current source files")
    parser.add_argument("--fixtures", default="docs/fixtures/faithful-cleanup.json")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    export(root, Path(args.fixtures).resolve(), Path(args.output).resolve(), args.ref)
