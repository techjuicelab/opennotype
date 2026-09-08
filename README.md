# OpenNoType

**Speak naturally. Type in your own words. Bring your own API key.**

[한국어 안내](README.ko.md) · [Verification status](docs/verification.md) · [License](LICENSE)

OpenNoType is an MIT-licensed macOS voice-input app. It records when you ask, transcribes your speech, asks your chosen AI provider to remove fillers and clear false starts, and inserts the finished text at your cursor. The aim is to preserve your meaning, tone, and mixed-language spelling.

**Development preview:** this is a source-buildable implementation, not a completed production release or a claim of feature parity with another product. Paid API calls, natural speech quality, and the nine-app compatibility matrix still require end-to-end validation. The interface is currently in Korean.

## What is implemented

- Dictation, translation, and spoken edits to selected text.
- Configurable global shortcuts and a floating recording bar.
- Final text insertion with focus checks and a clipboard fallback. The app does not press Enter to send a message.
- Up to nine minutes of recording, with a countdown during the final minute.
- Personal spelling dictionary: manual editing, limited correction learning, and JSON import/export.
- Encrypted local history, configurable retention, search, copying, and deletion.
- Encrypted failed recordings with a 24-hour expiry and a retry screen. Retrying a selected-text edit asks you to supply the original text again.
- Optional local transcription and an experimental enrolled-speaker filter.

Automatic insertion requires the input field to expose its text and selection through macOS Accessibility. If those details are unavailable or focus changes during processing, the app presents the result for manual copying and pasting.

Translation targets include Korean, English, Japanese, and simplified/traditional Chinese. Korean–English quality is the first evaluation priority; listing a language does not mean its quality has been validated.

## Use your own provider

| Your API key | Speech-to-text | Text cleanup, translation, and editing |
| --- | --- | --- |
| OpenAI | Direct OpenAI transcription request | Direct OpenAI request |
| OpenRouter | Direct OpenRouter transcription request | Direct OpenRouter request |
| Claude / Anthropic | Local Whisper model on your Mac | Direct Anthropic request |

An OpenAI or OpenRouter key is used for both cloud stages. Claude uses local transcription first, so a separate speech API key is not needed. Local transcription can also be enabled for the other providers.

There is no OpenNoType account or application backend. You need an API account with model access and available credit. Provider charges and model availability are controlled by the provider; a ChatGPT or Claude chat subscription is separate from API billing. Text processing still uses the selected cloud API when transcription is local.

Default model identifiers are editable in the app. See the [provider implementation and limits](docs/ai-providers.md) before changing them.

## Build and run

The first target is **macOS 14 or later on Apple Silicon, M1 or later**. Intel Mac, Windows, iPhone, and Android builds are not provided.

Install Xcode or its command-line developer tools with Swift 6. The recorded development toolchain is Swift 6.3.3. From a checkout of this repository:

```sh
./scripts/build-app.sh
open build/OpenNoType.app
```

The script builds an arm64 app bundle and applies a local ad-hoc development signature. It does not produce a Developer ID-signed or notarized public release. To build an optimized local bundle:

```sh
CONFIGURATION=release ./scripts/build-app.sh
```

On first launch:

1. Open **Settings / 설정**, select a provider, and save your API key. Keys are stored in macOS Keychain.
2. Grant **Microphone** and **Accessibility** access when requested. Accessibility is used to insert text into another app.
3. For Claude, open **Voice models / 음성 모델** and prepare the local transcription model.
4. Click a text field in the app you want to write in, then use a shortcut.

| Action | Default shortcut |
| --- | --- |
| Dictate | `⌥ Space` |
| Translate | `⌥ ⇧ Space` |
| Edit selected text | `⌃ ⌥ Space` |

Press the shortcut again to finish recording. Select the original text before starting a spoken edit. Change conflicting shortcuts in Settings.

## Local models and speaker filtering

The default multilingual Whisper Large v3 model downloads approximately **627 MB** of model weights. Tokenizers and device-specific Core ML caches need additional space. The first model preparation may take time after the download has finished. Model downloads begin with an explicit preparation action.

The experimental speaker filter downloads approximately **14 MB** of segmentation and speaker-embedding models. It is **off by default** and requires a separate voice enrollment. The enrollment recording is deleted; a 256-dimensional voice profile is stored locally in the encrypted vault.

The filter tries to retain isolated segments that match the enrolled voice. **It does not separate overlapping voices.** Other people or TV speech may remain, and your own speech may be discarded. Synthetic-voice checks exercise the implementation, but real users, TV playback, and overlapping speakers have not been validated. It is not an identity-authentication feature.

See [local audio implementation and evidence](docs/local-audio.md).

## What leaves your Mac

| Data | Handling |
| --- | --- |
| API keys | Stored in macOS Keychain; sent to the selected provider for authentication. |
| Recorded speech | Sent to the selected speech provider when cloud transcription is enabled. Local transcription runs on the Mac. |
| Transcript and spelling dictionary | Sent to the selected text provider for cleanup, translation, or editing. |
| Selected original text | Sent for a spoken edit; not stored as a separate original-selection or cursor-context record. |
| Cursor context | Off by default, enabled per app; at most 1,000 preceding characters are sent. Context is not saved in history. |
| History | Original transcript and final text are encrypted locally; the default retention is 30 days, with an option to keep until manually deleted. Recording new history can be disabled separately. |
| Failed recordings | Encrypted locally; expire after 24 hours. Purged once a minute while running, on startup, and on storage access. If the app is closed, cleanup resumes at its next launch. |
| Successful and enrollment recordings | Temporary recordings are deleted after their processing/enrollment path completes. |
| Speaker profile | Kept in the encrypted local vault until deleted in the app. |
| Exported dictionary JSON | A user-selected, unencrypted file containing the exported spelling entries. |

Correction learning observes only the text just inserted by the app, for a limited window while the same field remains focused. It does not install a general keyboard logger. Larger or uncertain corrections are shown for review instead of automatically saving a full sentence as a dictionary entry.

Automatic learning currently covers Hangul↔Latin spelling changes and some Latin spelling corrections with a name or identifier signal. Hangul-to-Hangul name corrections require manual registration. In an initially empty field, only a single-word correction is observed; larger edits are not collected. When history is enabled, the latest review candidate is encrypted locally and follows the history retention period.

Local files use AES-GCM encryption with a random key in Keychain. If the key is missing or data fails authentication, the store returns an error and preserves the existing files. Keep the corresponding Keychain key with any data you intend to restore.

These local storage rules do not replace the chosen provider's retention, training, or security policies.

## Development and verification

```sh
swift test
swift build --product OpenNoType
```

The normal tests do not require paid API keys. Provider tests use an in-process test transport; encrypted-storage tests use an isolated key backend rather than a real user's Keychain. Downloading and running the local model is an explicit integration test described in [verification](docs/verification.md).

Please include the app version, macOS version, hardware, provider/model names, and reproducible steps with an issue. Use short synthetic examples. Do not post API keys, private recordings, or private text.

## Release status and roadmap

- Developer ID signing and notarization are not complete.
- Sparkle is integrated, but the production update feed and signing key are not configured. Automatic updates are therefore inactive in the development build.
- Real paid-provider runs and the nine-app interaction matrix remain incomplete.
- Real voice enrollment, TV exclusion, overlap behavior, and natural translation need evaluation.
- Windows, iPhone, and Android are future targets with no released implementation. Their permissions and input workflows need platform-specific work.
- General-purpose “ask anything” and web search are outside this first version.

The public-release packaging script is [scripts/package-release.sh](scripts/package-release.sh). Its existence is not evidence that a signed release has been produced.

## License and acknowledgements

OpenNoType source code is licensed under [MIT](LICENSE). Third-party code and downloaded model weights retain their own licenses. Whisper model weights are labeled MIT upstream; the optional speaker models require CC BY 4.0 attribution. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the dependency inventory, model attribution, and license texts.
