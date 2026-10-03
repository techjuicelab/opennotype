# Dictation expression examples · 0.1.26 (28)

Settings → Input & shortcuts → Dictation expression now offers **Compare examples…** beside the wording picker. A separate comparison sheet keeps the settings page short and lets users browse all six directions before applying one.

- The same synthetic speech is shown alongside each direction's prewritten result. Korean and English examples preserve names, numbers, timing, requests and negation while making the wording differences visible.
- Browsing and closing the sheet only change local preview state. **Use [direction]** is the sole action that changes the saved expression setting.
- Applying Current dictation sets strength to zero. Other directions retain an existing nonzero strength, or start at 40 when the previous strength is zero. The proposed strength is shown before applying.
- The result pane scrolls independently; direction choices and the apply action remain visible. Close and Escape dismiss the comparison without applying.
- Examples do not record audio, inspect history or call any API. They illustrate direction rather than promising the result of an actual recording or a particular editing strength.

The existing dictation prompt, provider/model selection, Jev review settings, translation and selected-text editing are unchanged.

Validation before commit: release app build and strict code-signature verification passed. Independent code review checked preview-only selection, explicit apply, dismissal, zero-strength behavior, both languages and the absence of API work.
