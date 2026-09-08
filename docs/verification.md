# Verification status and release checks

This document separates implemented behavior, reproducible automated checks, and validation that still needs a real user or service. It is not a product-quality certification. Snapshot date: **2026-09-09**.

## Recorded evidence

Final local suite on 2026-09-09: **86 discovered tests, 85 passed, 1 opt-in model test skipped, 0 failures**. The complete application built and its local development signature passed `codesign --verify --deep --strict`. This is not Developer ID notarization. macOS emitted CoreData/XPC diagnostics during the clipboard tests; all clipboard assertions passed.

Native UI smoke checks confirmed initial app launch, navigation through settings/model/recovery screens, and encrypted dictionary add/edit/save with the synthetic `웨더 → weather` example. Relaunching the newly signed development build reached a macOS Keychain confirmation requiring the user's local interaction; the updated build's post-confirmation UI and restart persistence are still pending. No real microphone recording or paid API was used.

| Area | Evidence | What it establishes | What it does not establish |
| --- | --- | --- | --- |
| Encrypted storage and dictionary learning | 29 focused tests passed in an isolated Swift package using the production storage/domain source and an in-memory key backend | AES-GCM round trips; tampered/truncated data and wrong/missing keys fail closed; expiry, forever-retention, and scoped deletion; single-word learning rules | A signed release's Keychain prompts, restoration on another Mac, or real correction observation in external apps |
| AI provider contracts | 16 focused tests recorded in the [provider report](ai-providers.md) | Request shapes, response validation, cancellation, limited retries, and exclusion of provider error bodies | Actual account access, billing, end-to-end model output, or translation quality |
| Local transcription | WhisperKit 1.1.0 ran the final `LocalTranscriber` path with an `API` dictionary hint: one Yuna Korean fixture in 1.201 seconds and one Samantha English fixture in 1.032 seconds; see the [local-audio report](local-audio.md) | Runtime model loading and these two separate synthetic fixtures | Natural human speech accuracy, accents, long-form completeness, or mixed languages within one utterance |
| Speaker enrollment/filter | Synthetic-voice checks produced a 256-dimensional profile, accepted a separate sample of the enrolled synthetic voice, rejected a different synthetic voice, and deleted the enrollment file/profile | The neural enrollment/matching/deletion code path ran | Human voice identification, TV exclusion, replay resistance, overlap separation, or calibrated thresholds |
| macOS UI | Initial launch, settings/model/recovery navigation, and dictionary add/edit/save checked through the running native UI | These specific interaction paths ran | All buttons, permissions, hotkeys, final-build post-Keychain restart, or target-app insertion working end to end |
| Input and temporary audio safeguards | 13 platform input/clipboard tests, 2 recording-boundary tests, and 12 isolated temporary-file tests are included in the final suite | UTF-16 ranges, cancellation and clipboard ownership, 480/540-second policy, private file permissions, direct retry writes, and scoped dead-process cleanup | Real target-app insertion, physical microphone duration, or cleanup while the app is not running |
| Public release | Local build and release-packaging scripts exist | Reproducible entry points are available | Developer ID signing, notarization, Gatekeeper acceptance, a published release, or a functioning update feed |

Full-suite results must be taken from the current checkout's `swift test` output. Focused test counts above are not a combined whole-app result. Ordinary `swift test` skips the model-download integration test unless explicitly enabled.

The final local-audio benchmark ran on an Apple M2 Max with 32 GB RAM, macOS 26.6.2, and Swift 6.3.3. Model preparation took 71.636 seconds with weights already cached; the two transcription times exclude that preparation. This is not an M1 or macOS 14 runtime validation.

## Reproduce automated checks

Run from the repository root on an Apple Silicon Mac with the Swift developer toolchain installed:

```sh
swift test
swift build --product OpenNoType
./scripts/build-app.sh
```

Useful focused checks:

```sh
swift test --filter StorageTests
swift test --filter DictionaryTests
swift test --filter AI
swift test --filter LocalAudioTests
```

These checks must not read, replace, or reset a real user's API key. The storage tests inject a separate key backend. Provider transport tests do not send traffic to paid endpoints.

The following test explicitly downloads roughly 627 MB of model weights, creates temporary synthetic speech with macOS `say`, and runs local transcription:

```sh
OPENNOTYPE_RUN_LOCAL_AUDIO_INTEGRATION=1 swift test --filter LocalAudioTests/testOptInLocalTranscriptionIntegration
```

Model loading and device-specific preparation can take longer on the first run. Record toolchain, macOS, hardware, model identity, cache state, input length, and elapsed time before comparing performance. Synthetic input must be labeled as synthetic in any published result.

## Real-provider acceptance checks — pending

Use an explicitly supplied test API key and non-private speech. Record provider and exact model identifiers. A public model listing or HTTP success alone is not a pass.

| Case | Acceptance condition |
| --- | --- |
| OpenAI cloud path | Recorded audio → transcription → cleaned text → expected insertion, using the user's OpenAI key |
| OpenRouter cloud path | Dedicated transcription request and text request both succeed with one OpenRouter key; no unexpected provider fallback |
| Claude path | Local transcription → Anthropic text processing succeeds without a second speech-service key |
| False start | A clear final correction replaces the abandoned choice, with names, numbers, dates, and negation otherwise preserved |
| Unresolved thought | Uncertainty remains when the speaker has not made a final decision |
| Mixed scripts | Intended `weather`, `rain`, and `API` spelling survives Korean-containing speech where appropriate |
| Translation | A bilingual reviewer checks intended meaning, register, nuance, and naturalness; Korean↔English first |
| Spoken edit | Only the selected original text changes according to the spoken instruction |
| Long recordings | Check 8-minute warning, 9-minute stop, and complete output near the duration limit |
| Provider failure | Unauthorized, insufficient-credit, rate-limit, timeout, refusal, and malformed/incomplete output produce a recoverable error without inserting a fabricated result |
| Retry | Uses the recording's saved processing configuration, keeps the original expiry, deletes successful retry audio, and never auto-sends a message |
| Cancellation | Cancelling during recording, model work, or network work prevents subsequent insertion from that job |

## Target-app interaction matrix — pending

No row below is a completed end-to-end pass. Mark a cell only after interacting with the actual application and inspecting the result.

| App | Hotkey / recording | Dictation | Translation | Selection edit | Focus / clipboard / retry |
| --- | --- | --- | --- | --- | --- |
| Claude | Pending | Pending | Pending | Pending | Pending |
| Codex | Pending | Pending | Pending | Pending | Pending |
| Antigravity | Pending | Pending | Pending | Pending | Pending |
| KakaoTalk | Pending | Pending | Pending | Pending | Pending |
| Telegram | Pending | Pending | Pending | Pending | Pending |
| Discord | Pending | Pending | Pending | Pending | Pending |
| Apple Notes | Pending | Pending | Pending | Pending | Pending |
| Notion | Pending | Pending | Pending | Pending | Pending |
| Obsidian | Pending | Pending | Pending | Pending | Pending |

For every app: capture the insertion position, start/stop with each shortcut, change focus during processing, try a selected-text edit, verify clipboard preservation, and verify that Enter is not sent. Check a normal field and the app's supported rich-text surface separately. Do not use a password or other sensitive field as test content.

## Privacy and local-data acceptance checks

- Grant, deny, and revoke microphone/accessibility access. Confirm the UI reflects the state and does not claim permission it lacks.
- Verify that context collection starts off, is enabled per app, is bounded to 1,000 preceding characters, excludes secure inputs, and is not persisted in history.
- Observe only a just-inserted result while the same input remains focused. Edits elsewhere must not become learned dictionary entries.
- Confirm the dictionary's add/edit/delete/import/export controls against reopened encrypted data. JSON exports are intentionally unencrypted.
- Turn history off, change retention, delete one record, and confirm whole-history deletion. Repeat after reopening the app.
- Inspect the success, cancellation, failed-recording, retry, and enrollment paths for temporary audio cleanup. Failed recordings expire after 24 hours; cleanup runs every minute while running, on startup, and on storage access. It does not run while the app is closed. Recognized temporary WAV files belonging to an exited process are cleaned at the next startup; unknown files and links are preserved.
- Test missing keys, a locked/unavailable Keychain, and corrupted files. Preserve the original encrypted data and show an error instead of resetting the store.
- Confirm model downloads occur only after an explicit preparation action. Local speech inference must not upload audio to the model host.

At the storage API boundary, history retention means `-1` for keep until manually deleted, `0` for retain no history, and a positive integer for a day-based cutoff. Values below `-1` are invalid. These rules also apply to stored learning candidates. Failed-audio expiry remains 24 hours regardless of history retention. The UI's option to disable new history is separate from the retention period for records that already exist.

## Human speaker evaluation — pending

The speaker filter remains experimental and off by default. Enrollment success is not an accuracy result.

Evaluate the enrolled person alone, another person alone, alternating speakers, TV-only playback, the user with TV playback, overlapping voices, a changed microphone, and a quiet/reverberant room. Record accepted/discarded intervals and listen to the retained audio. Measure both leaked non-user speech and lost user speech.

The implementation does not perform source separation. If overlapping speech is detected, it rejects the candidate segment; undetected overlap can remain. Do not publish “TV removed,” “only your voice,” or “overlap supported” without evidence matching that claim.

## Public-release acceptance checks — pending

- Build the exact tagged source and preserve dependency/model attribution.
- Use a real Developer ID Application identity, sign nested components, notarize, and staple the app and distributable.
- Verify installation and Gatekeeper behavior on a separate Mac, including microphone/accessibility and Keychain behavior after an update.
- Configure a real HTTPS Sparkle feed and matching public signing key; verify an update from a previous installed version.
- Publish checksums and verify the downloaded artifact, rather than just the local build.
- Finish the real-provider and application matrix above before claiming broad daily-use compatibility.

The source [release script](../scripts/package-release.sh) requires external signing/notarization credentials; see the [release guide](releasing.md). These credentials and update-signing private keys must never be committed. The current development Info.plist has no production update feed or update public key.
