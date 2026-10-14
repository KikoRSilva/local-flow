# LocalFlow — architecture

Push-to-talk dictation where every step runs on the Mac.

```
hotkey (CGEventTap) → mic (AVAudioEngine, 16 kHz mono) → whisper.cpp (Metal)
    → optional cleanup (Ollama on localhost) → replacements/snippets → paste (pasteboard + Cmd+V)
```

| Stage | Implementation | Source |
|---|---|---|
| Hotkey | Session CGEventTap on `flagsChanged`; fn (63/179), Right Option, or Right Command. The hotkey's own events are swallowed. | `Hotkey/` |
| Gestures | Pure reducer: hold ≥500 ms = push-to-talk; tap then press again within 500 ms = hands-free lock; fn+space locks too; Esc cancels; another key while holding cancels (the hotkey was used as a modifier); 20 min cap. | `Hotkey/DictationMachine.swift` |
| Audio | AVAudioEngine input tap → AVAudioConverter → 16 kHz mono Float32 in memory. No AEC/NS/AGC. RMS drives the level meter. | `Audio/` |
| Silence gate | Clips shorter than 0.3 s or with RMS below a threshold are dropped before inference (avoids "Thank you." hallucinations). | `App/DictationController.swift` |
| ASR | whisper.cpp static libs, Metal + flash attention, greedy decoding, no timestamps. Dictionary words go in as `initial_prompt`. Input is padded to ≥1.1 s. | `ASR/` |
| Context | At dictation start: frontmost app, window title, and up to 500 characters before and after the caret plus the selection, via Accessibility. Sets `AXManualAccessibility` so Electron/Chromium apps expose text. Password fields are detected and never pasted into. | `Context/` |
| Cleanup | Ollama `/api/chat`, temperature 0, `think:false` for reasoning models, 6 s timeout. The prompt combines the editing level (light/medium/heavy), a style for the app category (email, work chat, personal chat, developer, other), the text around the caret, and dictionary spellings. Output is rejected (raw text pasted instead) when empty or much longer than the input. | `Cleanup/` |
| Post-process | Strips whisper artifacts (`[BLANK_AUDIO]`, `(music)`…), applies replacements and snippets on Unicode word boundaries (longest first), and adds a leading space when continuing a word. | `Cleanup/TextPostProcessor.swift`, `Store/Stores.swift` |
| Insert | Pasteboard item marked `org.nspasteboard.ConcealedType`/`TransientType` so clipboard managers ignore it, then Cmd+V with the layout-correct V key code, then the previous clipboard is restored after 500 ms unless it changed. | `Insert/Paster.swift` |
| UI | Menu-bar app (no Dock icon). Non-activating, click-through `NSPanel` at screen-saver level on all Spaces showing level bars / transcribing state. | `App/AppDelegate.swift`, `UI/` |
| Storage | `~/Library/Application Support/LocalFlow/`: `Models/`, `dictionary.json`, `history.jsonl`. Settings in UserDefaults. | `Store/` |

## Notes

- **Globe key:** macOS may still open the emoji picker on fn. Set *System Settings → Keyboard → Press 🌐 key to → Do Nothing*, or use Right Option.
- **Latency:** on an M4 Max, the cleanup step measured 0.3–0.7 s warm with `qwen3.5`; whisper turbo Q5 is typically well under a second for short dictation.
- **Ideas:** command mode (selected text + spoken instruction → LLM → replace), streaming partial transcripts, Core ML encoder, per-app style overrides, edit-learning for the dictionary.
