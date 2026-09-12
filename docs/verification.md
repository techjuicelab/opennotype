# Verification status and release checks

This document separates implemented behavior, reproducible automated checks, and validation that still needs a real user or service. It is not a product-quality certification. Snapshot date: **2026-09-12**.

## Faithful cleanup improvement branch (0.1.8)

The [2026-09-12 implementation report](reviews/2026-09-12/faithful-cleanup-implementation.md) records the isolated `codex/typeless-faithful-cleanup` worktree and its preserved 0.1.7 baseline. `git pull --ff-only` completed before work; the remote was already current, while local committed and uncommitted improvements were preserved separately.

The shared dictation/translation prompt now distinguishes accidental duplication from distinct information, carries details forward across restarts, narrows self-correction scope, and resolves the dictionary/literal priority conflict. This uses the existing single text request; it adds no runtime regex deletion, second verification call or automatic raw-transcript fallback.

Full suite: **278 discovered, 276 passed, 2 opt-in model tests skipped, 0 failures**. The 32-case synthetic specification was independently reviewed, and before/after production prompt exports retain identical fixture/input data. The **0.1.8 (9)** development app build and strict codesign verification passed. New paid-provider comparison, natural speech and Typeless app reproduction were not run; these tests do not establish semantic quality or loss-free cleanup.

The comparison runner's **20 offline tests passed**. Its default dry-run reads no API key and makes no network calls; selected synthetic cases have a cost reservation below US$0.10. Final review also resolved an example-language conflict with translation and clarified the permitted use of dictionary spelling hints.

## All-app insertion and predecessor conflict (0.1.7)

The [all-app insertion report](reviews/2026-09-11/all-apps-insertion.md) records the current **0.1.7 (8)** implementation. Keyboard paste is now the first route for every app, with a direct Accessibility write only when the paste route itself is unavailable and never after a posted paste; Electron/Chromium apps and terminals stay paste-only. Paste-only targets are acknowledged by a "changed and contains the text" check because Chromium exposes placeholder text through AXValue. Focus resting on a button or similar blocks the paste with an explanation, apps that expose no focused element are still pasted into, clipboard items are marked transient for clipboard managers, and the predecessor app notype (`space.techjuicelab.notype`) is reported as a shortcut conflict at launch, on each recording start, and whenever it launches or quits.

Current full suite: **275 discovered, 273 passed, 2 opt-in model integration tests skipped, 0 failures**. The local development build and strict codesign verification passed. Live checks with the recording-free input test: TextEdit, Notes, Ghostty, a Chrome textarea and the Claude desktop composer all reported `confirmed.paste`; Zed received the text (verified from the saved file) but reports `submittedUnverified.paste` because it exposes no accessibility value. Obsidian, Notion and messenger apps were not exercised. Public signing/notarization and real provider testing remain separate checks.

## Usage and settings UI (0.1.6)

The [usage and UI report](reviews/2026-09-10/usage-ui.md) records the current **0.1.6 (7)** implementation. It adds per-model requests, tokens, audio length and clearly separated reported/estimated/unavailable costs, encrypted independently of result history. Settings are split into four sections, with active-model summaries, macOS permission guidance, usage navigation and `⌘,`. [Accounting rules and official price sources](usage.md) define the scope and exclusions.

Current full suite: **265 discovered, 263 passed, 2 opt-in model integration tests skipped, 0 failures**. The 55 new usage tests cover provider responses, pricing/cache semantics, storage/reset races, AppModel flows and period/model presentation. [Test log](reviews/2026-09-10/usage-evidence/swift-test.log). The local app build, strict codesign verification and optimized release compilation passed.

A separately identified debug app with synthetic data was checked through native accessibility and screenshots in light/dark mode, at the default window size and minimum content size. Local and OpenRouter filters, zero versus unknown cost, and request expansion were exercised. The preview reads no real key, preferences or vault and rejects network requests. This is UI validation, not paid-provider or billing reconciliation evidence.

The previous 0.1.5 native app was accessible before this update, with its saved Groq model choices visible. After an encrypted backup, the 0.1.6 relaunch reached a macOS authentication wait. Post-authentication settings navigation and the real empty usage view are pending. Actual paid usage, natural voice, external-app insertion, public signing/notarization and the nine-app matrix remain separate checks.

## Reliability and recovery improvements (0.1.5)

The [2026-09-10 implementation report](reviews/2026-09-10/improvements.md) supersedes earlier insertion, learning, retry, and storage behavior below. The earlier sections are historical records, not the current delivery contract. The starting checkout was committed as `aa56f8a` before improvements.

- Rewrite revalidates the original application, element, full value, and UTF-16 selection before dispatch. Capture rejects inconsistent foreground/PID observations. An accepted or ambiguous AX write is never automatically followed by a paste after timeout. Existing paste-first targets remain paste-first.
- Automatic learning is limited to conservative spelling corrections; arbitrary cross-script and ordinary-word replacements require explicit review. Learning can be disabled and its last change undone without overwriting later manual edits.
- Recovery offers recorded or current settings with explicit destination/model/filter/language information. Capture and preparation own a generation before suspending; processing retains the starting configuration and dictionary. Blank model settings resolve to the same defaults in UI and actual requests.
- Enabled local features automatically prepare existing model/tokenizer caches without downloads. Explicit prepare/download actions remain available with cancellation. The Claude-required local mode is displayed as enabled.
- Failed audio now uses individual authenticated encrypted files and small metadata snapshots. Atomic dictionary/history mutations replace stale-array saves. Version 1 migration, repeated interrupted migration, staged-file recovery, quota, expiry, and post-commit deletion recovery have regression coverage. **Old version-1-only binaries cannot read the new internal version 2 vault.** An encrypted local backup was preserved before launching this build; it is not part of Git.
- OpenRouter STT no longer sends unsupported routing restrictions; the UI explains its upstream routing boundary. Permission recovery, actual login-item status, malformed hotkey recovery, per-page scroll reset, processing stages, and recorder-failure handling were also improved.

The 0.1.5 `swift test` snapshot: **210 discovered, 208 passed, 2 opt-in model tests skipped, 0 failures**. The [full log](reviews/2026-09-10/evidence/swift-test.log) includes nine AppModel flow tests with isolated recording, HTTP, storage, and system boundaries. macOS emitted CoreData/XPC diagnostics, without assertion failures.

Separately, `OPENNOTYPE_RUN_CACHED_AUDIO_INTEGRATION=1 swift test --filter LocalAudioTests/testOptInCachedLocalTranscriptionIntegration` passed: cached Whisper preparation plus a Yuna Korean synthetic utterance in **74.268 seconds**, with no microphone, model download, or paid API. The [log](reviews/2026-09-10/evidence/cached-local-integration.log) records the output; this is not a natural-speech quality benchmark.

An isolated optimized benchmark with three synthetic nine-minute recordings reduced snapshot time from 0.370–0.374 seconds to **0.000431–0.000653 seconds** and workload peak RSS from about 1,015 MB to **116.9 MB**. This is a storage workload, not whole-app memory or end-to-end dictation latency. See [reproduction and original logs](reviews/2026-09-10/evidence/README.md).

The 0.1.5 report recorded `build/OpenNoType.app` as **0.1.5 (6)**, signed with the existing `TechJuice Local Code Signing` identity and verified by the packaging script's strict codesign check. At that snapshot, native relaunch was waiting for the user's macOS authentication prompt. The 0.1.6 section above records the later launch checks; live target-app insertion remains a separate check. Public release signing/notarization, natural voice and real provider testing, and the nine-app matrix remain separate open checks.

## Review of the profile, branding, and Groq changes (0.1.4)

A multi-lens review of everything after 0.1.2 (writing profiles, branding, the Groq provider, and digit-aware correction learning) was applied on 2026-09-09. Changes in this revision:

- Whisper-family speech models (Groq Whisper, OpenAI `whisper-1`, local WhisperKit, unlisted models) now receive a transcript-style prompt in the audio's language: personal and profile vocabulary followed by the one-line Korean context, packed within an estimated 224 tokens. English instruction text, JSON wrapping, and the complete example sentences are no longer sent to these models, because Whisper treats the prompt as previous text and can echo whole sentences into silent recordings. Context-following OpenAI models (`gpt-transcribe`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`) keep the full reference prompt.
- Custom model identifiers are trimmed before use, a cleared field falls back to the provider default, and a retry never reuses a blank model saved by an older build.
- Preferences decode field by field: an unknown provider or profile value from a newer build falls back to its default without discarding the other settings. Provider values that an older build does not recognise decode as the default provider instead of making the encrypted vault unreadable.
- Correction learning again learns Hangul↔Latin spellings when digits are attached to the word (`아이폰15` → `iPhone15`); numbers themselves are never learned.
- A missing app icon resource falls back to a system symbol instead of terminating the app; the packaged app no longer ships a duplicate icon bundle.
- The provider order in Settings (OpenAI · Groq · OpenRouter · Claude) matches the copy, the privacy tables list writing profiles and speech hints, and the real-provider checklist has a Groq row. The redirect-rejection test now drives the session's redirect delegate.

`swift test` on 2026-09-09 after these changes: **166 discovered tests, 165 passed, 1 opt-in model test skipped, 0 failures**. Real Groq API calls, live audio, and the silence/noise control for speech hints remain pending.

## Dictation quality baseline and app profiles (0.1.3)

The additional interview is recorded in [requirements](requirements.md) and the [baseline examples](dictation-baseline.md). The first revision keeps existing model defaults, adds bounded STT references and development vocabulary, permits contextual recognition repair and natural grammar reconstruction, and selects writing format/tone from the app captured at recording start. Spoken register remains the default; voice-edit instructions take precedence over automatic profiles.

Automated validation on 2026-09-09: **140 discovered tests, 139 passed, 1 opt-in model test skipped, 0 failures**. Tests cover request serialization/model capability gating, invalid vocabulary exclusion, profile/mode boundaries, legacy preferences and failure-record decoding, and the encrypted-store snapshot with expiry/concurrency/tamper checks. The full log is local-only at `build/quality-tests.log`.

The storage refresh now uses one authenticated transaction instead of four. Filtered PCM is passed directly to local STT. New timing diagnostics separate audio preparation, STT, text processing, insertion acknowledgement, and storage refresh. These are implemented reductions/measurements, not measured end-to-end speed gains.

The [16 semantic fixtures](fixtures/dictation-quality.json) remain human-authored specifications. Natural voice accuracy, unspoken-example leakage, live API compatibility, translation naturalness, and same-audio model comparisons are pending. No paid API or personal audio was used for this revision's automated verification.

Final local artifact: `build/OpenNoType.app`, version **0.1.3 (4)**, signed with the existing `TechJuice Local Code Signing` identity and passed `codesign --verify --deep --strict`. Native UI verification launched this build with the existing OpenAI key and permissions available; no new Keychain prompt appeared in this run. Settings displayed app-specific defaults, a temporary Antigravity polite-tone selection took effect, and reset restored preserve-tone. After final relaunch, Codex was displayed under its correct product name, all default tones remained preserve, and surrounding-context access remained disabled. These checks did not record audio, call a paid API, or re-test external text insertion.

## Earlier recorded evidence

Final local suite on 2026-09-09 for 0.1.2: **118 discovered tests, 117 passed, 1 opt-in model test skipped, 0 failures**. The complete application built and its local development signature passed `codesign --verify --deep --strict`. This is not Developer ID notarization. macOS emitted CoreData/XPC diagnostics during the clipboard tests; all clipboard assertions passed.

Native UI smoke checks confirmed initial app launch, navigation through settings/model/recovery screens, and encrypted dictionary add/edit/save with the synthetic `웨더 → weather` example. Relaunching the newly signed development build reached a macOS Keychain confirmation requiring the user's local interaction; the updated build's post-confirmation UI and restart persistence are still pending. No real microphone recording or paid API was used.

| Area | Evidence | What it establishes | What it does not establish |
| --- | --- | --- | --- |
| Encrypted storage and dictionary learning | 29 focused tests passed in an isolated Swift package using the production storage/domain source and an in-memory key backend | AES-GCM round trips; tampered/truncated data and wrong/missing keys fail closed; expiry, forever-retention, and scoped deletion; single-word learning rules | A signed release's Keychain prompts, restoration on another Mac, or real correction observation in external apps |
| AI provider contracts | `AIProviderClientTests` in the full suite (OpenAI, Groq, OpenRouter, Claude request shapes; see the [provider report](ai-providers.md)) | Request shapes, response validation, cancellation, limited retries, and exclusion of provider error bodies | Actual account access, billing, end-to-end model output, or translation quality |
| Local transcription | WhisperKit 1.1.0 ran the final `LocalTranscriber` path with an `API` dictionary hint: one Yuna Korean fixture in 1.201 seconds and one Samantha English fixture in 1.032 seconds; see the [local-audio report](local-audio.md) | Runtime model loading and these two separate synthetic fixtures | Natural human speech accuracy, accents, long-form completeness, or mixed languages within one utterance |
| Speaker enrollment/filter | Synthetic-voice checks produced a 256-dimensional profile, accepted a separate sample of the enrolled synthetic voice, rejected a different synthetic voice, and deleted the enrollment file/profile | The neural enrollment/matching/deletion code path ran | Human voice identification, TV exclusion, replay resistance, overlap separation, or calibrated thresholds |
| macOS UI | Initial launch, settings/model/recovery navigation, and dictionary add/edit/save checked through the running native UI | These specific interaction paths ran | All buttons, permissions, hotkeys, final-build post-Keychain restart, or target-app insertion working end to end |
| Input and temporary audio safeguards | 45 platform insertion/clipboard/feedback/shortcut-overlap tests, 2 recording-boundary tests, and 12 isolated temporary-file tests are included in the final suite | UTF-16 ranges, delivery routing and acknowledgement, cancellation and clipboard ownership, 480/540-second policy, private file permissions, direct retry writes, and scoped dead-process cleanup | Real target-app insertion, physical microphone duration, or cleanup while the app is not running |
| Public release | Local build and release-packaging scripts exist | Reproducible entry points are available | Developer ID signing, notarization, Gatekeeper acceptance, a published release, or a functioning update feed |

Full-suite results must be taken from the current checkout's `swift test` output. Focused test counts above are not a combined whole-app result. Ordinary `swift test` skips both opt-in model integration tests unless explicitly enabled. The cached-only integration was separately run for 0.1.5 as recorded above.

The final local-audio benchmark ran on an Apple M2 Max with 32 GB RAM, macOS 26.6.2, and Swift 6.3.3. Model preparation took 71.636 seconds with weights already cached; the two transcription times exclude that preparation. This is not an M1 or macOS 14 runtime validation.

## Reproduce automated checks

### Insertion failure: focus theft and strict acknowledgement (0.1.2)

The original diagnosis recorded a saved ChatGPT chat-bar shortcut matching ⌥Space and treated it as the reproduced cause. A saved binding alone does not establish which app handled the user's shortcut; the subsequent investigation reported that ChatGPT Classic was not running. Treat that shortcut explanation as an earlier hypothesis, not confirmed attribution.

The insertion defect was an accessibility write returning success without a visible field change in Electron targets, followed by strict acknowledgement failure and automatic activation of the OpenNoType manager. The user reported working insertion after the broader paste-first and outcome-feedback fixes. The changes below describe that implementation; the quality/profile revision does not alter its paste or clipboard policies.

Changes:

- Insertion re-activates the captured app before pasting (`NSRunningApplication.activate`, then macOS 14 cooperative hand-off) and only gives up when the app has quit or cannot be brought forward. Direct accessibility writes still target the captured element when the app is not in front.
- An accessibility snapshot (readable value and selection range) is no longer required. Without it, keyboard paste is used directly, and acknowledgement accepts any readable value that changed and contains the result.
- Chromium-based apps (Electron shells and Chromium browsers, detected by a `Contents/Frameworks` entry named `Electron Framework…` or containing `Chrom`) and known GPU-rendered terminals use keyboard paste directly; the explicit list covers Antigravity, Codex, VS Code, Terminal, iTerm2, Ghostty, Warp, Alacritty, kitty, WezTerm, Slack, Discord, Chrome, Chromium, Brave, Edge, Arc, Vivaldi, and Opera.
- An accessibility write that reports success (or a messaging timeout) but leaves value **and** selection byte-for-byte unchanged after one second is treated as dropped and falls back to one keyboard paste. Any other unacknowledged write is left alone, and a field that changed after an unacknowledged write is never pasted into, to avoid duplicate text.
- If the caret moved to another text field of the same app during processing, paste goes to that field and is verified there; focus on a non-text element blocks the paste.
- Clipboard snapshotting is best-effort: secondary representations that cannot be read or exceed 32 MB are skipped, but an item that would lose every representation, an unreadable populated pasteboard, or a copy that races the snapshot refuses the paste so the clipboard is never replaced by nothing.
- Submitted-but-unacknowledged delivery is a quiet notice and never activates the manager window; the floating bar shows the outcome for a few seconds. Only a delivery that never reached the target app opens the window with the result. A retry from 다시 처리 keeps the neutral “copy the result” notice.
- Recording fails fast with guidance when Accessibility is not granted, secure keyboard entry is active, a password field is focused, or OpenNoType itself is in front. The input test also requires Accessibility.
- Settings → 단축키 lists overlaps with known running apps (currently ChatGPT’s stored chat-bar shortcut). When another app comes to the front right after the shortcut fires, the floating bar names it, the window keeps a notice, and a later `targetChanged` error is prefixed with that app.
- Insertion emits fixed diagnostic codes to the unified log at default level; read them live with `log stream --predicate 'subsystem == "app.opennotype.mac"'` (on the development Mac `log show` did not return them afterwards). No text or clipboard data is logged.

### Diagnosing text insertion (0.1.1, superseded by 0.1.2 above)

Settings → **입력 문제 확인** can insert the fixed sentence `OpenNoType 입력 테스트입니다.` through the production insertion path without recording, calling a provider, saving history, or sending Enter. Arm the test and press the dictation shortcut in a disposable empty field, or use the five-second button and switch to the field. A pending test can be cancelled in Settings; translation and editing shortcuts cancel it before starting their normal mode.

The on-screen diagnostic contains app bundle ID, accessibility role/status, snapshot/focus checks, insertion route, clipboard transaction status, and delivery outcome. It excludes dictated text, field contents, selection contents, window titles, clipboard representations, and API keys. It is held in memory only. Read it without copying private field contents into a bug report.

The initial failure was reproduced using the physical shortcut in Antigravity: permissions, captured value/range, focus, and unchanged-field checks all passed; `AXSelectedText` was writable and returned success, but the field remained unchanged until verification timed out. The old fallback then opened the manager window; `WindowGroup` created another window each time.

That 0.1.1 attempt chose keyboard paste **before** attempting AX writes for the exact Antigravity and Codex bundle IDs only, kept the exact value/selection checks, and still opened the manager window for every unconfirmed delivery; it did not resolve the report (the user’s attempts were in Claude desktop, Codex, and Antigravity). The 0.1.2 section above describes the current behaviour. The manager has one `Window` since 0.1.1.

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
| Groq cloud path | One Groq key serves `/openai/v1/audio/transcriptions` and `/openai/v1/chat/completions`; GPT OSS returns the strict JSON schema and another model returns JSON mode; the 10-second minimum audio billing is understood |
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
