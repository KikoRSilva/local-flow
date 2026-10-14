# LocalFlow

Fully-local push-to-talk dictation for macOS 26: whisper.cpp on Metal for transcription, an Ollama model for cleanup, pasted into whatever app you're typing in. Nothing leaves the Mac. An open-source, offline alternative to cloud dictation apps. See `DESIGN.md` for the architecture.

## Build

```sh
./scripts/bundle.sh          # builds whisper.cpp (first run) + LocalFlow.app into build/
open build/LocalFlow.app
```

Grant **Microphone**, **Accessibility** and **Input Monitoring** when asked (System Settings → Privacy & Security). Ad-hoc signed builds must be re-granted after each rebuild; set `SIGN_IDENTITY="Apple Development: …"` to avoid that.

Recommended: System Settings → Keyboard → *Press 🌐 key to* → **Do Nothing**, so fn doesn't open the emoji picker.

## Use

| Gesture | Action |
|---|---|
| Hold fn, speak, release | Dictate and paste |
| Double-tap fn, or fn+space | Hands-free; press fn again to finish |
| Esc while recording | Cancel |

Menu bar (waveform icon): hotkey (fn / Right Option / Right Command), whisper model, language, AI cleanup level (off/light/medium/heavy), Ollama model, sounds, paste last transcript, dictionary, history.

## Files

`~/Library/Application Support/LocalFlow/`

- `Models/`: ggml whisper models (downloaded on first use)
- `dictionary.json`: `words` (spelling hints for whisper + LLM), `replacements` (phrase → text), `snippets` (trigger → expansion)
- `history.jsonl`: one line per dictation, with raw and final text and timings

## Requirements

- Apple Silicon, macOS 26, Command Line Tools (Swift 6.2+), CMake
- [Ollama](https://ollama.com) with a model pulled (default `qwen3.5`); cleanup falls back to raw whisper text if Ollama is offline

## License

MIT. whisper.cpp (MIT) is fetched and built from source by `scripts/build-whisper.sh`; models are downloaded from Hugging Face under their own licenses.
