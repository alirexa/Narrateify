# Shared Chatterbox server

In Settings → Models, select Chatterbox and enable **Use existing Chatterbox server**. Enter the local server address (default `http://127.0.0.1:8766`), click **Test Connection & Refresh Languages**, select a language and preview the voice.

The server must expose `/health`, `/v1/audio/voices`, and an OpenAI-compatible `/v1/audio/speech` endpoint accepting the Chatterbox language, exaggeration and CFG settings. This lets Narrateify share one model/runtime with another local application without installing duplicate weights.

Narrateify connects to the external server but never starts, kills or uninstalls it. Model startup, idle unloading and login startup belong to the external service. A cold model can take longer on the first request. Existing app-managed installation controls remain available with the toggle off.
