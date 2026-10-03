# ElevenSpeak

Native macOS menu-bar text-to-speech client tightly coupled to ElevenLabs.

## Features

- ElevenLabs API only; no fallback TTS provider
- ElevenLabs voice list and available voice previews
- `eleven_multilingual_v2` for multilingual text
- Adjustable speech speed from 0.7x to 1.2x
- Global hotkey with configurable presets, including the default ⌥ Esc
- Press the hotkey again to stop playback
- Reads the current selection automatically through macOS Accessibility
- Cmd-C fallback for applications that do not expose selected text through Accessibility
- Native MP3 streaming playback while ElevenLabs is still generating
- Optional buffered playback mode
- API key stored in the macOS Keychain
- Menu-bar-only application with no Dock icon
- Launch at login via macOS ServiceManagement
- Intel x86_64 build for Intel Macs
- Minimum macOS 13

## First launch

1. Create an ElevenLabs account and obtain an API key.
2. Start ElevenSpeak from the menu bar.
3. Open **Settings…** and enter the API key.
4. Allow ElevenSpeak under **System Settings → Privacy & Security → Accessibility**.
5. Select text in any supported application and press **⌥ Esc**.
6. Press **⌥ Esc** again to stop.

The API key never needs to be stored in the project or Git repository; ElevenSpeak keeps it in the macOS Keychain.

## Build

The repository contains a GitHub Actions workflow that builds an Intel x86_64 application bundle on every push to `main`.

The generated GitHub Actions artifact contains the complete `ElevenSpeak.app` bundle.
