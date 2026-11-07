# Changelog

## Unreleased

- iPhone app (iOS 17+): script picker as the home screen, a recording view with a prompter band under the Dynamic Island, and the front-camera preview scaled into the rest of the screen. 3 lines in portrait, 5 in landscape; width and height are adjustable per orientation.
- iPhone video: 16:9 or 4:3, resolution and frame rate, codec, color, HDR, stabilization, torch, exposure and focus locks. Starts on the front camera, 16:9, 4K, 30 fps. Saved to Photos.
- Voice following: spoken numbers now match whether the recognizer writes digits or words; the next expected word moves the cursor at once; cost per update no longer grows with the length of the recording.
- Voice following: when you scroll to a different part, speaking the words on screen moves the reading position there.
- Voice following on iPhone: recognition survives notifications and audio interruptions; camera audio feeds the on-device engine; script words are given to the recognizer as hints.
- Project layout: shared code in `Shared/`, Mac app in `macOS/`, iPhone app in `iOS/`. The Mac build script is now `macOS/build.sh`.

## 1.0.2

- Language list: every language Apple offers for one-click offline download is offered, with regional variants (31 entries including Turkish). German, Italian, Korean and others are now available.
- Removed the Keyboard settings redirect and the Dictation instructions.
- Arabic, Hindi, Russian and Indonesian are no longer offered, because Apple has no one-click offline download for them. Scripts already saved in those languages still open.
- Turkish has no one-click download. It works on device when macOS has its Dictation model, and online otherwise.

## 1.0.1

- Fixed: Cut, Copy, Paste, Select All, Undo and Redo did not work in the script editor. The app now has a standard Edit menu.
- Language list shows only the languages this Mac can use, with each one's offline status.
- Spanish, French, Portuguese, Japanese and Mandarin Chinese can be downloaded for offline use from Settings.
- Hindi, Arabic, Russian and Indonesian: Settings opens Keyboard settings so Dictation can be enabled for the language.
- For languages that would otherwise use Apple's servers, speech tracking switches to the on-device engine when that language's offline model is installed.
- README: screenshots, language and offline guide, FAQ.

## 1.0.0

First public release.

- Notch-anchored teleprompter with voice following in eleven languages.
- Words-per-minute and time-left readout.
- DualSense gamepad control, adjustable stick curve and speed, and light bar state.
- Script library saved to iCloud Drive or Documents, with import from text, Markdown, RTF, HTML, Word, OpenDocument and PDF.
- Hover control bar, horizontal positioning, Spaces support and screen-sharing privacy.
