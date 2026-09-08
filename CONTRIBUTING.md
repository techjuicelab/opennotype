# Contributing

OpenNoType targets Apple Silicon and macOS 14 or later. Build with Xcode 26 and Swift Package Manager.

```sh
swift test
scripts/build-app.sh
```

Keep platform interaction in `Sources/OpenNoType/Platform`, AI contracts in `OpenNoTypeCore/AI`, and local inference in `OpenNoTypeCore/LocalAudio`. Do not add a central account service or embed provider credentials.

Changes to dictation must preserve uncertainty, explicit corrections, numbers, names, negation, and mixed scripts. Translation should preserve intent and register while using idiomatic target-language phrasing.

Include relevant contract or state-transition tests. Clearly distinguish synthetic audio checks from natural speech, human translation review, and interaction with real target apps. Never label a build as passing all applications merely because it compiles.

Downloaded model weights are not committed. Preserve the separate license and attribution of every model and dependency.
