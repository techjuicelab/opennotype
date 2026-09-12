# OpenNoType

**Speak naturally. Type in your own words. Bring your own API key.**

[한국어 안내](README.ko.md) · [Verification status](docs/verification.md) · [License](LICENSE)

OpenNoType is an MIT-licensed macOS voice-input app. It records when you ask, transcribes your speech, asks your chosen AI provider to remove fillers and clear false starts, and inserts the finished text at your cursor. The aim is to preserve your meaning, tone, and mixed-language spelling.

**Development preview:** this is a source-buildable implementation, not a completed production release or a claim of feature parity with another product. Paid API calls, natural speech quality, and the nine-app compatibility matrix still require end-to-end validation. The interface is currently in Korean.

## What is implemented

- Dictation, translation, and spoken edits to selected text.
- General-purpose transcription references, contextual recognition repair, and natural sentence cleanup. See [examples and limits](docs/dictation-baseline.md).
- Per-app writing format and tone, preserving spoken register by default.
- Configurable global shortcuts and a floating recording bar.
- Final text insertion with focus checks and a clipboard fallback. The app does not press Enter to send a message.
- Up to nine minutes of recording, with a countdown during the final minute.
- Personal spelling dictionary: manual editing, optional limited correction learning, undoing the latest learned entry, and JSON import/export.
- Encrypted local history, configurable retention, search, copying, and deletion.
- Model-specific usage: requests, audio length, tokens, daily activity, and separately labeled reported/estimated/unavailable USD costs. See [accounting rules](docs/usage.md).
- Encrypted failed recordings with a 24-hour expiry and retries using the original or current settings. Retrying a selected-text edit asks you to supply the original text again.
- Optional local transcription and an experimental enrolled-speaker filter.

Automatic insertion pastes with ⌘V first in every app: keyboard paste reaches everything that accepts typing (terminals, Electron editors, note apps, browsers), whereas many apps acknowledge an Accessibility write without showing it. A direct Accessibility write is used only when the clipboard cannot be preserved, key events cannot be built, or the captured app cannot be brought to the front, and it never follows a paste that was already posted. Electron-based editors, browsers and terminals use paste only, with no Accessibility fallback. The clipboard contents used for pasting are restored once the insertion has been checked and are marked as transient so clipboard managers do not record them. Text that could not be submitted is shown for manual copying; submitted but unconfirmed text is reported with a quiet notice.

If another app takes focus during processing, OpenNoType first returns to the captured app. A spoken edit is submitted only after rechecking the original field, its complete text, and the selection range immediately before insertion. Changes or unreadable state block automatic insertion. Dictation and translation may paste into a different text field if you moved the cursor within the same app.

Settings → Input & shortcuts warns when a known running app stores the same shortcut (currently the ChatGPT chat bar on ⌥Space). Other overlaps may appear as another app coming to the front when you press the shortcut. Change one of the two.

Translation targets include Korean, English, Japanese, and simplified/traditional Chinese. Korean–English quality is the first evaluation priority; listing a language does not mean its quality has been validated.

## Use your own provider

| Your API key | Speech-to-text | Text cleanup, translation, and editing |
| --- | --- | --- |
| OpenAI | Direct OpenAI transcription request | Direct OpenAI request |
| Groq | Direct Groq transcription request | Direct Groq request |
| OpenRouter | Request through OpenRouter to a model provider | Request through OpenRouter to a model provider |
| Claude / Anthropic | Local Whisper model on your Mac | Direct Anthropic request |

An OpenAI, Groq, or OpenRouter key is used for both cloud stages. Claude uses local transcription first, so a separate speech API key is not needed. Local transcription can also be enabled for the other providers.

OpenRouter is an intermediary: the actual model provider may vary for the same model. Its transcription endpoint does not apply chat routing controls such as provider pinning or fallback restrictions. This app therefore does not guarantee a fixed upstream transcription provider. See the [official OpenRouter transcription guide](https://openrouter.ai/blog/tutorials/transcription-on-openrouter/).

For Groq, open **Settings → AI connection → Groq**, save your key, and select speech and text models separately. Menus include Whisper Large v3 Turbo / Large v3 and GPT OSS 120B / 20B, with custom model IDs available. These are bundled choices, not an account-specific access check. Switching providers preserves each provider's key and model settings.

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

1. Open **Settings / 설정**, select a provider, and save your API key in macOS Keychain. A saved key is not a verified connection; edited keys must be saved before use.
2. Grant **Microphone** and **Accessibility** access. If microphone access was denied, use the app's button to open System Settings. Recording does not start without Accessibility access.
3. For Claude or optional local transcription, open **Voice models / 음성 모델** and download the model once. The home screen shows required model and voice-profile readiness.
4. Open **Home → Input practice / 시작하기 → 입력 연습**, focus another app's text field, and press the dictation shortcut. This inserts a fixed sentence without recording or calling an API.
5. Focus the field you want to write in and use a shortcut to record.

| Action | Default shortcut |
| --- | --- |
| Dictate | `⌥ Space` |
| Translate | `⌥ ⇧ Space` |
| Edit selected text | `⌃ ⌥ Space` |

Press the shortcut again to finish recording. Select the original text before starting a spoken edit. Change conflicting shortcuts in Settings.

Open **Settings** with **⌘,**. Settings are grouped into AI connection, Input & shortcuts, Privacy, and Mac & general. The home screen identifies the active speech and text models; the menu bar also links directly to usage.

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
| Recorded speech | Sent to the selected speech provider when cloud transcription is enabled. Local transcription runs on the Mac. |
| Transcript and spelling dictionary | Sent to the selected text provider for cleanup, translation, or editing. |
| Selected original text | Sent for a spoken edit; not stored as a separate original-selection or cursor-context record. |
| Cursor context | Off by default, enabled per app; at most 1,000 preceding characters are sent. Context is not saved in history. |
| Writing profile | Only the selected format and tone values (for example `development` / `preserve`) accompany the text request. The name or bundle identifier of the app you are writing in is never sent. |
| Speech hints | Up to 24 personal dictionary spellings (plus seven fixed development terms under the development profile) are sent to the cloud speech provider as a transcript-style prompt. OpenAI models that accept context (`gpt-transcribe`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`) also receive fixed reference sentences and a one-line situation hint. Local Whisper never sends anything. |
| History | Original transcript and final text are encrypted locally; the default retention is 30 days, with an option to keep until manually deleted. Recording new history can be disabled separately. |
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
