# Jev and dialogue

The canonical integration lives in [`backend/`](../backend/README.md), a Cloudflare Worker running locally through Wrangler. That document contains the detailed contract, configuration, limits, and test commands.

- **TypeSafe Jev** selects actions through `Choice`; each call receives only the active resident's context. Its API returns structured decisions, not natural conversation. The configured version is `jev-1.13.0`, with explicitly labeled local rest when confidence is low.
- **Home visits:** `/visit-decision` asks the owner whether to admit a visitor based on personality, relationship memories, and routine. Low confidence denies admission with an explicit source. The engine retains authority over ownership, presence, and opening doors.
- **OpenAI** writes short dialogue using the configured `gpt-6-luna` model with reasoning disabled. `/dialogue/stream` delivers real-time fragments, a complete result, and per-request timing. Development sessions have measured real provider calls; those samples are not a benchmark or an access guarantee for other accounts.
- **The Godot engine** stores memories and procedures, distinguishes episodes from verified facts, and determines who may know each piece of information. A model does not permanently learn simply by receiving dialogue: learning must be represented and persisted in the game.

Provider keys live exclusively in Worker bindings. Godot uses a separate development token. Missing configuration or provider failure returns an error; the backend never labels a local simulation as a Jev or OpenAI response.

Ordinary contract tests use example responses and do not activate providers, create remote resources, or deploy to Cloudflare. Live checks are optional and may incur charges. See [chat reliability](chat-reliability.md) for the current transport validation.
