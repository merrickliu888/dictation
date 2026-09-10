<div align="center">
  <img src="Assets/dictation-logo-transparent.png" alt="dictation-logo" width="75">
  <h1>Dictation</h1>
  <p>A minimal, macOS native, dictation tool. Speak into any text field.</p>
</div>

## Quick Start
1. Build and run: `make run` (needs Xcode 16 or later).
2. Grant the three permissions in the setup window: Microphone, Speech Recognition, and Accessibility.
3. Click into any text field, hold `fn`, say something, and let go. The words appear where the cursor is.

## Overview

Dictation is the voice half of [Minimal](https://github.com/merrickliu888/minimal) on its own. It lives in the menu bar; there is no window to open while you work. Hold the shortcut, a pill with a waveform appears at the bottom of the screen, and when you release, what you said is inserted into whatever had keyboard focus — a browser, a terminal, a chat box, a code editor.

Speech recognition is Apple's own, on device where the language supports it.

## Shortcuts

| Gesture | Default | What it does |
| --- | --- | --- |
| Hold | `fn` | Listen while held; release to insert. A quick tap discards. |
| Toggle | `fn fn` (double tap) | Listen hands-free until you press `fn` once more. |

Both can be changed in the setup window (menu bar → Settings… → Change), which records the next key you press — twice for a double tap. Any key combination with ⌘, ⌥ or ⌃ works, and so does a modifier key on its own (`fn`, `rightoption`, `rightcommand`…) or a function key.

> **fn and the emoji picker.** macOS gives the fn (🌐) key a job of its own, usually opening the emoji picker on a tap. Set **System Settings → Keyboard → Press 🌐 key to** to **Do Nothing** so it only dictates. The setup window has a button for it.

## Configuration

Shortcuts live in `~/.config/dictation/config.toml`, written on first launch with every action, its default, and the format, each line commented out so the defaults stay live. The setup window's **Change** button edits this file; you can also edit it by hand, or point a coding agent at it:

> Open `~/.config/dictation/config.toml` and make hold-to-dictate the right option key.

The same file holds the theme. The setup window's **Theme** picker writes it, or set it by hand:

```toml
[appearance]
theme = "dark"   # system, light, dark
```

Pick a hand edit up with **Reload Config** in the menu bar; no restart needed.

Dictation uses the first file that exists: `$DICTATION_CONFIG`, then `~/.config/dictation/config.toml` (`$XDG_CONFIG_HOME` is honoured), then `~/Library/Application Support/Dictation/config.toml`.

## How it works

- **Shortcuts** come from a Quartz event tap rather than a registered hotkey, which is what makes a bare modifier key like `fn` bindable and reports the release that hold-to-talk needs. Key combinations are swallowed so the front app doesn't also act on them; modifier keys pass through.
- **Insertion** pastes: the text goes on the pasteboard, ⌘V is synthesized, and your previous clipboard contents are restored right after. Pasting is what works in every kind of app.
- **The pill** never takes focus, so the cursor stays where you were typing.

Accessibility permission covers both the tap and the paste. The app is signed ad hoc by `make`, so a rebuild changes its identity: if `fn` stops responding after a rebuild, remove Dictation from the Accessibility list and add it again.

## Privacy

Everything runs locally. Voice transcription uses Apple's Speech framework on device; nothing leaves your Mac.
