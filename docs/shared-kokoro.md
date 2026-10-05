# Shared Kokoro and synchronized reading

Keep a Kokoro-FastAPI server running (for example, OpenReader’s Docker container). In Settings → Models, select Kokoro, enable **Use existing Kokoro server**, enter its localhost URL (default `http://127.0.0.1:8880`), then **Test Connection & Refresh Voices**. Narrateify does not install, stop, or uninstall that external server.

**Open reader with highlighting** uses `/dev/captioned_speech` WAV audio and word timestamps. Audio is prepared before playback; seeking, speed changes, sentence/word highlighting and automatic scrolling follow the player clock. Saved history preserves optional timings, while old recordings remain readable.

The reader’s Appearance controls persist font size, highlight color/intensity, background and opacity. Its title bar stays opaque independently of reading-area transparency. Closing the reader leaves audio playing; **Open Reader** restores it.

WAV size placeholders are repaired and chunks are PCM-merged with finalized headers. Timestamp offsets account for chunk duration and UTF-16 text length. Words that cannot be matched to server-normalized text are skipped. Cancelled synthesis cannot replace newer playback.

Connections are restricted to localhost. Highlighting needs the caption endpoint and is not provided by OpenAI, Chatterbox, or the app-managed Kokoro server. Tests cover URL validation, timing alignment, malformed WAVs, merged duration, seeking and history compatibility.
