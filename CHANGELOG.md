# Changelog

## Unreleased

- iPhone camera view: the whole recorded picture is shown, never cropped, as large as the screen allows in portrait and landscape. The rest of the screen is not left empty: the same live picture is drawn behind it, dimmed and blurred. The prompter text and the controls sit on top; the controls have a dark plate so they stay visible on bright scenes. The layout previously counted the safe area twice and left empty strips at the top and bottom; that is fixed. Placements saved by earlier versions are reset once.
- iPhone, landscape: the 9:16 guide is exactly 9:16 of the recorded picture (full height, width 9/16 of it) for every video shape, and because the preview is never cropped it also looks 9:16 on screen. Covered by tests for 16:9, 4:3 and common pixel sizes.
- iPhone camera view: face detection outlines faces on the preview, and focus and exposure follow the face (face-driven autofocus and auto exposure in continuous mode, which comes back after a tap to focus).
- iPhone camera view: a spirit level (horizon line that tilts against the phone, plus a lean bubble) turns green when the phone is level and upright. Works in portrait and landscape.
- iPhone: prompter text over the video is drawn with a difference blend (an invert, like Photoshop's Difference mode), so it reads on bright and dark scenes alike; over the black part of the screen it stays white.
- Library sync: the folder is observed through file presenters, checked every 2 s and fully re-read every 8 s, and re-read when the app comes to the foreground, so a change from the other device shows up in seconds.

- iPhone: an edit to the active script made on the Mac (or on the phone) shows up in the prompter within seconds, in the camera view too, with the reading position kept. While a take is being recorded the text is left alone and the change is applied when the recording stops.

- Library sync: the library always lives in iCloud Drive > Sightline Prompter, on the Mac and on the iPhone, and each side picks up the other's added, edited and deleted scripts within a couple of seconds (the folder is checked every 2 s, besides file events). The Mac moves scripts from its old folders (Documents, a custom folder, the unregistered container folder) into it. A build without the iCloud entitlement cannot reach iCloud Drive by itself on the iPhone, so it asks once for the folder (iCloud Drive or Sightline Prompter), moves the scripts on the phone into it and remembers it.

- iPhone, camera mode: the prompter text is always the top layer and has no background, so it can be placed over the video (a soft shadow keeps it readable). The preview keeps its aspect ratio and is no longer shrunk by the text. Arrange mode has a small reset-layout icon button.

- iPhone, landscape recording: a guide on the camera preview marks the centered 9:16 strip that stays when the clip is cropped to a vertical video in the edit. Shown on screen only, never in the recorded file. Portrait is unchanged.

- iPhone: press and hold the camera preview or the prompter text, in portrait or landscape, to move and resize it. The preview keeps the chosen aspect ratio, the text resizes freely. The placement is saved per orientation; Reset returns to the automatic layout.

- Delivery cues: text between double square brackets (`[[pause]]`) is shown in the prompter as a direction, in its own style, and is never spoken: speech following, word counts and the pace estimate skip it. Mac and iPhone.
- Script library shared between Mac and iPhone through the iCloud container `iCloud.com.berkbayri.SightlinePrompter` (iCloud Drive > Sightline Prompter). Scripts saved by earlier versions are moved in on first launch. Needs a build signed by a paid developer team; on a personal team the iPhone app can instead use a folder chosen in Settings > Library.
- Developer build of the Mac app (`macOS/build.sh`) opens every Pro feature.
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
