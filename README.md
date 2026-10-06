# OpenNoType

**Speak naturally. Type in your own words. Bring your own API key.**

[한국어 안내](README.ko.md) · [Verification status](docs/verification.md) · [License](LICENSE)

| Status | Version | Scope |
| --- | --- | --- |
| Public download | [v0.1.26 (28)](https://github.com/techjuicelab/opennotype/releases/tag/v0.1.26) | First-phase community release; its source is on `main`. Ad-hoc app signing and Sparkle Ed25519 updates, without Developer ID or Apple notarization. |
| Next version in development | **0.2.2** | Separate [`codex/native-translation-0.2.2` branch](https://github.com/techjuicelab/opennotype/tree/codex/native-translation-0.2.2); not publicly released. |

**The installation and feature guide below describes the public v0.1.26 release.** The experimental 0.2.2 features are developed separately and are not included in this download. See [update operations](docs/updates.md) for the public channel and installation limits.

**Development 0.2.2:** Dictation can output English, Japanese, or Korean through the usual dictation shortcut, with Keep spoken language as the default. Translation asks the selected text model to preserve meaning and tone while leaving summary and creative settings out. Work on phrasing and sentence flow continues; the recorded 0.2.1 measurements do not establish 0.2.2 quality. Results may still contain meaning or wording errors; real microphone and human native-speaker validation are incomplete. This feature is not included in the public v0.1.26 download. See [translation setup and validation scope](docs/native-translation.md).

OpenNoType is an MIT-licensed macOS voice-input app. It records when you ask, transcribes your speech, asks your chosen AI provider to remove fillers and clear false starts, and inserts the finished text at your cursor. The aim is to preserve your meaning, tone, and mixed-language spelling. Dictation restores confidently recognized technical names to official spellings such as `OpenRouter` and `1Password`, while preserving ordinary Korean and explicit literal instructions.

**Public community release:** v0.1.26 contains the first-phase feature set, including dictation-expression previews, optional Jev review and repair, and input, learning, and storage reliability fixes. Synthetic text cleanup has been exercised with a live provider; natural speech quality and the complete nine-app compatibility matrix still require end-to-end validation. New installs use English. English and 한국어 are available in Settings → Mac & general → App language; existing Korean installs keep Korean. Interface language does not change dictation or the translation target.

Earlier prompt comparisons and history-reprocessing checks are documented in the [Typeless comparison](docs/typeless-comparison.md), [implementation report](docs/reviews/2026-09-12/typeless-integration.md), and [synthetic live comparison](docs/reviews/2026-09-12/faithful-cleanup-live-comparison.md). Those small synthetic samples do not establish general speech quality or superiority over another app.

The **[0.1.26 download](https://github.com/techjuicelab/opennotype/releases/tag/v0.1.26)** is published as a **Community release — not notarized by Apple**, using ad-hoc app signing and Ed25519-signed updates. Anonymous downloads, checksums, signatures, and the latest update feed were verified. Existing development installs without a feed and public key need one manual replacement. See the [0.1.26 release verification](docs/reviews/2026-10-05/community-release-0.1.26.md) and [first-install guide](docs/updates.md), including [Apple's per-app opening instructions](https://support.apple.com/102445).

## Features in the public 0.1.26 release

- English and Korean interfaces, with English for new installs and preserved language choices on upgrade.
- Dictation, translation, and spoken edits to selected text.
- General-purpose transcription references, contextual recognition repair, and natural sentence cleanup. See [examples and limits](docs/dictation-baseline.md).
- Per-app writing format and tone, preserving spoken register by default.
- Six dictation wording directions with **0–100 AI editing strength**, fixed example previews, and explicit application from the preview. Current dictation at strength 0 remains the default. See [directions and limits](docs/dictation-expression.md).
- 20 affordable OpenRouter text models and two Groq models with input/output reference prices and a verification date. [Model comparison](docs/text-models.md).
- Optional experimental [Jev review and repair](docs/jev-review.md): use the existing OpenRouter key or a separate TypeSafe key, review after typing, protect before typing, or generate one repair with the current text model and recheck it before typing. Automatic review is off by default; requests add API costs and do not guarantee accuracy.
- Optional Jev error-pattern learning: remember predefined categories resolved by a repair that passes recheck, scoped to the text provider and model. Learning is off by default, stores no past sentences or repair text, and does not train the model itself.
- Explicit Jev spelling review with confirmed dictionary saving and undo, alternatives for comparison/copying, and text-model comparison using approved examples. Suggestions and recommended model changes require your choice; saving a dictionary suggestion calls no API and leaves already typed text unchanged.
- Configurable global shortcuts and a floating recording bar.
- Final text insertion with focus checks and a clipboard fallback. The app does not press Enter to send a message.
- Up to nine minutes of recording, with a countdown during the final minute.
- Personal spelling dictionary: manual editing, optional limited correction learning, undoing the latest learned entry, and JSON import/export.
- Encrypted local history, configurable retention, search, original/result comparison and copying, manual dictation/translation reprocessing, and deletion.
- Model-specific usage: requests, audio length, tokens, daily activity, and separately labeled reported/estimated/unavailable USD costs. See [accounting rules](docs/usage.md).
- Encrypted failed recordings with a 24-hour expiry and retries using the original or current settings. Retrying a selected-text edit asks you to supply the original text again.
- Optional local transcription and an experimental enrolled-speaker filter.

Automatic insertion pastes with ⌘V first in every app: keyboard paste reaches everything that accepts typing (terminals, Electron editors, note apps, browsers), whereas many apps acknowledge an Accessibility write without showing it. A direct Accessibility write is used only when the clipboard cannot be preserved, key events cannot be built, or the captured app cannot be brought to the front, and it never follows a paste that was already posted. Electron-based editors, browsers and terminals use paste only, with no Accessibility fallback. The clipboard contents used for pasting are restored once the insertion has been checked and are marked as transient so clipboard managers do not record them. Text that could not be submitted is shown for manual copying; submitted but unconfirmed text is reported with a quiet notice.

If another app takes focus during processing, OpenNoType first returns to the captured app. A spoken edit is submitted only after rechecking the original field, its complete text, and the selection range immediately before insertion. Changes or unreadable state block automatic insertion. Dictation and translation may paste into a different text field if you moved the cursor within the same app.

Settings → Input & shortcuts compares stored bindings from known running apps (ChatGPT and notype) and unambiguous simple Karabiner rules. A saved overlap is not proof that an app handled the actual keystroke. Other overlaps may appear as another app coming to the front when you press the shortcut. Change one of the two.

Translation targets include Korean, English, Japanese, and simplified/traditional Chinese. Korean–English quality is the first evaluation priority; listing a language does not mean its quality has been validated.

## Use your own provider

| Your API key | Speech-to-text | Text cleanup, translation, and editing |
| --- | --- | --- |
| OpenAI | Direct OpenAI transcription request | Direct OpenAI request |
| Groq | Direct Groq transcription request | Direct Groq request |
| OpenRouter | Request through OpenRouter to a model provider | Request through OpenRouter to a model provider |
| Claude / Anthropic | No speech API; select local transcription or another service | Direct Anthropic request |

Speech recognition and text processing can use different providers, such as **Groq speech + OpenRouter text**. Save a key for each selected service; using one service for both stages shares its key. Claude can process text from another speech API or local transcription. Local transcription requires no speech API key.

OpenRouter is an intermediary: the actual model provider may vary for the same model. Its transcription endpoint does not apply chat routing controls such as provider pinning or fallback restrictions. This app therefore does not guarantee a fixed upstream transcription provider. See the [official OpenRouter transcription guide](https://openrouter.ai/blog/tutorials/transcription-on-openrouter/).

For Groq speech, open **Settings → AI connection → Speech recognition**, choose Groq, and save its key. Choose the text provider, model, and any separate key under **Text processing**. Menus include Whisper Large v3 Turbo / Large v3 and GPT OSS 120B / 20B, with custom model IDs available. These are bundled choices, not an account-specific access check. Switching providers preserves each provider's key and model settings.

There is no OpenNoType account or application backend. You need an API account with model access and available credit. Provider charges and model availability are controlled by the provider; a ChatGPT or Claude chat subscription is separate from API billing. Text processing still uses the selected cloud API when transcription is local.

Default model identifiers are editable in the app. See the [provider implementation and limits](docs/ai-providers.md) before changing them.

## Install the app

Supported: **Apple Silicon M1 or later, macOS 14 or later**. Download the **[v0.1.26 DMG](https://github.com/techjuicelab/opennotype/releases/download/v0.1.26/OpenNoType-0.1.26.dmg)**, copy `OpenNoType.app` to **Applications**, and launch it. The [release page](https://github.com/techjuicelab/opennotype/releases/tag/v0.1.26) also provides the ZIP, checksums, and release notes. Installing a release does not require Xcode, Swift, or Homebrew. Cloud transcription needs no local model download.

The current public release is **Community — not notarized by Apple**. If macOS blocks opening, follow [Apple's per-app instructions](https://support.apple.com/102445). Each Mac needs the selected API keys and Microphone / Accessibility permission. A replaced ad-hoc build may ask for Keychain authentication again.

See the [standalone verified installer and first-run guide](docs/mac-installation.md), [0.1.26 public-package verification](docs/reviews/2026-10-05/community-release-0.1.26.md), and [earlier new-Mac findings and verification scope](docs/reviews/2026-10-01/macbook-installation.md).

## Developer build and run

The first target is **macOS 14 or later on Apple Silicon, M1 or later**. Intel Mac, Windows, iPhone, and Android builds are not provided.

Install Xcode or its command-line developer tools with Swift 6. The build script compile-checks SwiftUI and Observation against the selected SDK. If the default SDK fails, it checks an installed 26.5 SDK; an explicit `MACOS_SDK_PATH` is never replaced. Running the full `swift test` suite requires Xcode with XCTest. From a checkout of this repository:

```sh
./scripts/build-app.sh
open build/OpenNoType.app
```

The script builds an arm64 app bundle and applies a local ad-hoc development signature. It does not produce a Developer ID-signed or notarized public release. To build an optimized local bundle:

```sh
CONFIGURATION=release ./scripts/build-app.sh
```

On first launch:

1. Open **Settings → AI connection / 설정 → AI 연결**, select providers and models separately for speech and text, and save the required API keys in macOS Keychain. A saved key is not a verified connection; edited keys must be saved before use.
2. Grant **Microphone** and **Accessibility** access. If microphone access was denied, use the app's button to open System Settings. Recording does not start without Accessibility access.
3. If you choose local transcription, open **Voice models / 음성 모델** and download the model once. The home screen shows required model and voice-profile readiness.
4. Open **Home → Input practice / 시작하기 → 입력 연습**, focus another app's text field, and press the dictation shortcut. This inserts a fixed sentence without recording or calling an API.
5. Focus the field you want to write in and use a shortcut to record.

| Action | Default shortcut |
| --- | --- |
| Dictate | `⌥ Space` |
| Translate | `⌥ ⇧ Space` |
| Edit selected text | `⌃ ⌥ Space` |

Press the shortcut again to finish recording. Select the original text before starting a spoken edit. Change conflicting shortcuts in Settings.

Open **Settings** with **⌘,**. Settings are grouped into AI connection, Input & shortcuts, Privacy, and Mac & general. The home screen identifies the active speech and text models; the menu bar also links directly to usage.

In **Settings → Input & shortcuts → Dictation expression**, choose **Current dictation**, **Concise**, **Key-point summary**, **Clearer**, **More detailed**, or **Creative wording**, then adjust editing strength from 0 to 100 in steps of 5. Current dictation or strength 0 retains the default cleanup. **Compare examples…** shows fixed synthetic examples without recording, network traffic, or API calls; browsing, closing, or pressing Escape leaves your setting unchanged. Choose **Use [direction]** to apply it. The examples illustrate wording directions, not guaranteed model results. Changes take effect with your next dictation, while translation and selected-text editing keep their existing behavior. Wording changes still ask the model to preserve facts, conditions, negation, and intent; strength is not an accuracy score.

In **Settings → AI connection → Jev text review · Experimental**, select a connection and review mode. Automatic review and repair apply only to dictation; translation and selected-text editing results support explicit review. **Repair before typing** performs at most one repair generation followed by a Jev recheck; unresolved results, failures, timeouts, unavailable keys, or unknown/excess reference costs hold automatic insertion. Its additional-cost reservation must fit within **US$0.05 at reference prices**, which is not a provider billing guarantee. The older **Protect before typing** mode can insert the original result when review fails or times out, with an incomplete-review notice. **Review after typing** does not replace text already entered. Error-pattern learning is a separate choice. **Alternative model and comparison** lets you request alternatives or compare 2–3 models using 1–5 source/approved-answer pairs, then explicitly apply a recommendation. See [Jev modes, data, costs, and limits](docs/jev-review.md).

Open **Usage / 사용량** to filter by period and provider. Statistics begin with requests made after collection is enabled on this Mac; previous history and usage outside this app are not imported. Collection is enabled by default and can be disabled independently of text history under **Settings → Privacy**. Statistics contain numeric/model metadata only, are encrypted locally, and retain the latest 10,000 requests. Estimated USD amounts may differ from the provider's bill; unavailable amounts are never shown as zero.

## Local models and speaker filtering

The default multilingual Whisper Large v3 model downloads approximately **627 MB** of model weights. Tokenizers and device-specific Core ML caches need additional space. The first model preparation may take time after the download has finished. Model downloads begin with an explicit preparation action.

When files for a selected local feature already exist, startup or first use prepares them from the local cache only. Missing or corrupt files never trigger an automatic download; use the Voice models screen to download or prepare them explicitly. Preparation can be cancelled. A Core ML load may not stop immediately, but a cancelled preparation's late result is not applied to the UI.

The experimental speaker filter downloads approximately **14 MB** of segmentation and speaker-embedding models. It is **off by default** and requires a separate voice enrollment. The enrollment recording is deleted; a 256-dimensional voice profile is stored locally in the encrypted vault.

The filter tries to retain isolated segments that match the enrolled voice. **It does not separate overlapping voices.** Other people or TV speech may remain, and your own speech may be discarded. Synthetic-voice checks exercise the implementation, but real users, TV playback, and overlapping speakers have not been validated. It is not an identity-authentication feature.

See [local audio implementation and evidence](docs/local-audio.md).

## What leaves your Mac

| Data | Handling |
| --- | --- |
| API keys | Stored in macOS Keychain; sent to the selected provider for authentication. |
| Recorded speech | Sent to the selected speech provider when cloud transcription is enabled. Optional Jev-assisted audio re-recognition sends it to that speech provider once more using another supported model; Jev receives only the transcripts. Local transcription runs on the Mac. |
| Transcript and spelling dictionary | Sent to the selected text provider for cleanup, translation, or editing. |
| Selected original text | Sent for a spoken edit; not stored as a separate original-selection or cursor-context record. |
| Cursor context | Off by default, enabled per app; at most 1,000 preceding characters are sent. Context is not saved in history. |
| Writing profile and dictation expression | Selected format/tone values and, when active, dictation direction/strength accompany text processing. Jev also receives the expression settings used to generate the result. The name or bundle identifier of the app you are writing in is never sent. |
| Jev review, repairs, and alternatives | When requested or enabled, the source, result, and up to four locally selected spelling/name candidates go to TypeSafe directly or through OpenRouter. Selected-text editing review also includes the original selected text and edit instruction; translation review includes the target language. Repair/alternative generation sends the source, existing result, and relevant dictionary hints to the selected text provider, followed by Jev recheck; repairs also send predefined review categories. Jev receives no audio or surrounding app context. Diagnostics and repair/alternative previews stay in memory; source/final-result history follows the existing retention setting. |
| Jev model-comparison examples | Explicitly submitted sources go to the selected text provider. Approved answers and generated results go to Jev for comparison; approved answers are not sent to the generation models. Comparison cases and previews stay in memory; additional requests incur API costs. |
| Jev learned error categories | Optional learning stores only predefined resolved categories, encrypted locally per text provider/model. Those categories become reminders in later cleanup requests to the same provider/model. No past source sentences or repair text are stored in the learning data. Turning off or clearing all history also clears these categories. |
| Jev approved names | Names you explicitly register are kept in ordinary local preferences; only locally selected candidates are sent for name review. Saving a spelling mapping uses the encrypted dictionary and requires confirmation. |
| Speech hints | Up to 24 personal dictionary spellings (plus seven fixed development terms under the development profile) are sent to the cloud speech provider as a transcript-style prompt. OpenAI models that accept context (`gpt-transcribe`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`) also receive fixed reference sentences and a one-line situation hint. Local Whisper never sends anything. |
| History | Original transcript, final text, and the writing profile used for dictation are encrypted locally; the default retention is 30 days, with an option to keep until manually deleted. Recording new history can be disabled separately. |
| Usage statistics | Request/model metadata, tokens, audio length, and cost are encrypted locally, independently of text history. Latest 10,000 requests; no prompts, transcripts, raw audio, or API keys in statistics. |
| Failed recordings | Each audio file is encrypted separately and expires after 24 hours. New saves are limited to 25 MB per recording and 100 MB total, including encryption overhead. Purged once a minute while running, on startup, and on storage access. Cleanup resumes at the next launch when the app was closed. |
| Successful and enrollment recordings | Temporary recordings are deleted after their processing/enrollment path completes. |
| Speaker profile | Kept in the encrypted local vault until deleted in the app. |
| Exported dictionary JSON | A user-selected, unencrypted file containing the exported spelling entries. |

Correction learning observes only the text just inserted by the app, for a limited window while the same field remains focused. It does not install a general keyboard logger. Larger or uncertain corrections are shown for review instead of automatically saving a full sentence as a dictionary entry.

Automatic learning is limited to casing changes, narrow spelling corrections of names with internal capitals such as `OpenAI`, and a single internal digit misrecognized in an uppercase name (`GR5Q` → `GROQ`). Ordinary word substitutions such as `Cat` → `Car` and arbitrary Hangul↔Latin changes are not automatically registered. **Review spelling / 표기 확인하고 등록** only prefills the dictionary editor; you must inspect and save the entry. Shared Korean particles and unchanged leading or trailing digits are excluded: `아이폰15` → `iPhone15` proposes `아이폰` → `iPhone` for review. Version, date, amount, and Hangul-to-Hangul name changes require manual registration.

After confirmed dictation insertion, corrections are observed in the same focused field for up to 30 seconds. Eligible edits must remain stable for about three seconds. Apps where insertion or edits cannot be read require manual registration. Automatic learning can be disabled separately from history: this stops new correction observation and registration while retaining the existing dictionary. The latest automatic change can be undone during the same app session; an entry changed afterwards is not overwritten by undo. When history is enabled, the latest review candidate is encrypted locally and follows the history retention period.

Local files use AES-GCM encryption with a random key in Keychain. If the key is missing or data fails authentication, the store returns an error and preserves the existing files. Keep the corresponding Keychain key with any data you intend to restore.

Text/dictionary metadata and failed audio use separate encrypted files, so ordinary history queries do not read every recording. The previous storage format is migrated by writing and validating live audio files before replacing the metadata. A failed migration retains the previous vault. Existing recordings are not discarded to meet the new quota during migration; exceeding it blocks new saves until recordings are deleted or expire.

**Retry with the same settings / 같은 설정으로 다시 처리** preserves the recording's provider, models, transcription path, filter, and translation language. **Recover with current settings / 현재 설정으로 복구** uses the current values after confirmation, allowing recovery from an unavailable model or a filter problem. Both paths use the current dictionary and the recording's original writing profile, preserve the original expiry, delete successfully retried audio, and show the result for copying instead of inserting it automatically.

These local storage rules do not replace the chosen provider's retention, training, or security policies.

## Development and verification

```sh
scripts/macos-preflight.sh --tests
swift test --sdk "$(scripts/macos-preflight.sh --print-sdk)"
scripts/build-app.sh
```

The normal tests do not require paid API keys. Provider tests use an in-process test transport; encrypted-storage tests use an isolated key backend rather than a real user's Keychain. Downloading and running the local model is an explicit integration test described in [verification](docs/verification.md).

Version-specific live synthetic provider and Jev checks, focused insertion checks, and development build/signature checks are recorded in [verification](docs/verification.md). Dictation-expression directions have [synthetic evaluation evidence and limits](docs/dictation-expression.md); the [0.1.26 example-preview report](docs/reviews/2026-10-03/expression-example-preview.md) records the fixed previews and explicit-apply behavior. These checks do not establish natural-speech quality, reliable Jev repair/learning across arbitrary text, or the complete nine-app matrix. The [0.1.26 release report](docs/reviews/2026-10-05/community-release-0.1.26.md) separately records public package and update-feed verification.

Please include the app version, macOS version, hardware, provider/model names, and reproducible steps with an issue. Use short synthetic examples. Do not post API keys, private recordings, or private text.

## Release status and roadmap

- Community distribution uses ad-hoc app signing and Sparkle Ed25519 signatures, without Developer ID or Apple notarization. A separate notarized mode remains available when Apple credentials are configured; notarization failures never fall back automatically.
- Version 0.1.26 (28) is publicly available with a verified Sparkle feed. Existing development builds without a feed and public key require one manual installation. Synthetic Sparkle replacement and tamper rejection passed; automatic production app updates through Sparkle and preservation of permissions and Keychain access remain unverified. See [update operations](docs/updates.md).
- `main` contains the 0.1.26 release source. Version 0.2.2 is being developed on a separate branch and is not included in the public download.
- Synthetic live API checks exist; natural-speech testing across providers and the complete nine-app interaction matrix remain incomplete. Jev diagnoses, repairs, and learned reminders do not guarantee correctness.
- Real voice enrollment, TV exclusion, overlap behavior, and natural translation need evaluation.
- Windows, iPhone, and Android are future targets with no released implementation. Their permissions and input workflows need platform-specific work.
- General-purpose “ask anything” and web search are outside this first version.

Public packages are built by [scripts/package-release.sh](scripts/package-release.sh) and published only after release-workflow validation. See the [0.1.26 release report](docs/reviews/2026-10-05/community-release-0.1.26.md) for the checks performed on this download.

## License and acknowledgements

OpenNoType source code is licensed under [MIT](LICENSE). Third-party code and downloaded model weights retain their own licenses. Whisper model weights are labeled MIT upstream; the optional speaker models require CC BY 4.0 attribution. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the dependency inventory, model attribution, and license texts.
