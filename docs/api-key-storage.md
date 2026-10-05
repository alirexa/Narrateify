# API-key storage

Cloud API keys stay in the existing Keychain service and accounts. Startup reads never display authorization dialogs; when a saved key is locked, Settings offers **Unlock saved key**. Editing a field is separate from **Save**, and removing a key requires confirmation.

Failed reads, writes, and removals preserve stored credentials. Legacy preference migration removes the plaintext value only after successfully saving it to Keychain. Local engines need no API key.

`APIKeyStoreTests` covers locked items, failed updates/removals, and migration without touching real credentials.
