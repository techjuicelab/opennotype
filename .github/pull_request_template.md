## Summary / 요약

<!-- What changes, and why. Link the related issue if there is one. -->

## Verification / 검증

<!-- Delete the lines that do not apply and paste the result counts. -->
- [ ] `swift test` (or the macOS CI run)
- [ ] `SPARKLE_TEST_ARTIFACT_DIR="$PWD/.build/artifacts/sparkle/Sparkle" python3 -m unittest discover -s scripts -p 'test*.py'`
- [ ] `scripts/build-app.sh`

Not verified / 검증하지 않은 범위:
<!-- Keep synthetic checks separate from natural speech, real microphones, human translation review and real target apps. A passing build is not proof that typing works in every app. -->

## Checklist / 확인

- [ ] Contract or state-transition tests cover the change.
- [ ] No API keys, recordings, private text or provider response bodies in code, tests, docs or logs.
- [ ] Dictation still preserves uncertainty, explicit corrections, numbers, names, negation and mixed scripts.
- [ ] User-facing text is updated in both English and Korean, and docs describe the new behavior.
