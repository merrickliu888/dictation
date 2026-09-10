<div align="center">
  <img src="Assets/dictation-logo-transparent.png" alt="dictation-logo" width="75">
  <h1>Dictation</h1>
  <p>A minimal, macOS native, dictation tool.</p>
</div>

## Quick Start
1. Download Dictation for [Apple Silicon](https://github.com/merrickliu888/dictation/releases/download/v0.1.0/Dictation-0.1.0-Apple-Silicon.dmg) or [Intel](https://github.com/merrickliu888/dictation/releases/download/v0.1.0/Dictation-0.1.0-Intel.dmg), or build it yourself with `make run` (needs Xcode 16 or later).
2. Open the DMG and drag Dictation into Applications. The app is not signed with an Apple Developer ID, so after macOS blocks the first launch, open **System Settings → Privacy & Security**, scroll to **Security**, click **Open Anyway**, then confirm **Open**.
3. Grant the three permissions in the setup window: Microphone, Speech Recognition, and Accessibility.
4. Click into any text field, hold `fn`, say something, and let go. The words appear where the cursor is.

Requires macOS 15 or later.

## Overview

Dictation is a native macOS dictation tool that turns speech into text using Apple's Speech framework. Hold the shortcut, speak, and let go: what you said is typed into whatever has keyboard focus.


## Shortcuts

| Gesture | Default | What it does |
| --- | --- | --- |
| Hold | `fn` | Listen while held; release to insert. A quick tap discards. |
| Toggle | `fn fn` (double tap) | Listen hands-free until you press `fn` once more. |

> **fn and the emoji picker.** macOS gives the fn (🌐) key a job of its own, usually opening the emoji picker on a tap. Set **System Settings → Keyboard → Press 🌐 key to** to **Do Nothing** so it only dictates. The setup window has a button for it.

## Privacy

Everything runs locally. Voice transcription uses Apple's Speech framework on device; nothing leaves your Mac.