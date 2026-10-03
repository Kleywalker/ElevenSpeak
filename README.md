# ElevenSpeak

Native macOS menu-bar text-to-speech client for ElevenLabs.

- ElevenLabs API only
- Voice list and previews
- Multilingual TTS with eleven_multilingual_v2
- Speed 0.7x–1.2x
- Global Option-Escape to read selected text; again to stop
- Accessibility API with Cmd-C fallback
- API key in macOS Keychain
- No Dock icon
- Intel x86_64 GitHub Actions build

The first version uses ElevenLabs' streaming endpoint but buffers the returned MP3 before playback. Progressive audio playback is the next iteration.
