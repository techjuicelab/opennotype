# Security

OpenNoType is pre-release software. Do not put API keys, personal recordings, private transcripts, or Keychain exports in an issue or pull request.

Report a suspected vulnerability privately with GitHub's [private vulnerability reporting](https://github.com/techjuicelab/opennotype/security/advisories/new). Only the maintainers can read the report. Do not put exploit details or private data in a public issue, pull request, or discussion.

## Data boundaries

- API keys live in macOS Keychain and are never included in app preferences or the repository.
- Text history, dictionary, speaker profile and failed recordings use an authenticated, encrypted local vault.
- Only explicitly enabled application context is sent to the selected provider. Context is not stored in history or recovery records.
- Network requests use HTTPS and do not redirect authentication to another host.
- Public model downloads are separate from voice uploads. Local model inference runs on the Mac.
- A published update requires authenticated Sparkle signatures and a notarized Developer ID app. Development builds do not enable an unconfigured update feed.

Provider retention policies are separate from OpenNoType's local retention settings. Speech matching is not an authentication mechanism.
