# Interrupted chat responses · September 24, 2026

## Reproduced cause

The HTTP connection opened successfully, so Wrangler showed `200 OK`. The Worker began streaming the character's words but could later stop with an SSE error event. The UI correctly discarded the incomplete exchange and displayed a generic notice.

The 64 KiB limit for complete JSON responses was also applied to the **provider's entire stream**. Responses includes request metadata in several lifecycle events, in addition to each fragment's wrapper. Those bytes are not the character's words.

In four calls to the real service using fictional context, one failed after streaming 82 characters: `invalid_upstream_response`, “El stream excedió el límite” (“The stream exceeded the limit”). A later measurement received **69,705 bytes**, with 47 fragments and three lifecycle events of approximately 18 KiB each. Its text was valid, but the transport exceeded the old 65,536-byte limit.

## Fix

- Streaming has its own budget of **512 KiB total** and **128 KiB per UTF-8 event**, including an event whose delimiter never closes. Multiple small events grouped in one chunk are processed individually.
- Content limits remain separate: 1,600 characters for received dialogue, 4,096 for the structured document, and 180 for the brief structured response. Token budgets, model, and timeout remain unchanged.
- The client still receives incremental text. Only a valid, matching completion confirms the exchange and records it in memory.
- Terminal stream errors leave a safe service diagnostic: code, duration, bytes, and character count. Keys, instructions, conversations, and provider bodies are not logged. This distinguishes actual completion from a mere HTTP 200.
- Godot preserves error code, message, and HTTP status. It reads HTTP error JSON asynchronously with an 8 KiB maximum and stops requesting fragments once the body ends.
- Chat distinguishes connection failure, delay, a busy service, and interruption with brief text. It preserves the draft and retry. It introduces neither fake responses nor automatic retries of paid calls.

Retrying a failed send does not apply social consequences twice: metrics update when a complete exchange is recorded.

## Verification

- Service: **97/97** tests, **2,743** assertions, and a passing TypeScript check. New regressions reproduce repeated metadata exceeding 64 KiB, byte-by-byte fragmentation, grouped chunks, and cancellation at event and stream limits.
- Godot transport: **32/32**; chat: **164/164**; local Godot → Worker integration: **15/15**, including HTTP 503 and HTTP 200 followed by an SSE error.
- Simulation: **141/141**; chat UI: **28/28**; suggestions: **986/986**; social willingness: **55/55**. The UI fixture moved to clear ground because its old position intersected a planter in the current map; it now explicitly checks visibility and that the initial conversation is recorded.
- Eight consecutive calls to the real service using fictional context completed streaming after the fix, with exact correspondence between fragments and completion.
- A real session from Godot completed three turns, **24/24 checks**, without errors or save writes. First text: 1.09 / 0.87 / 0.83 s; total: 1.41 / 1.22 / 1.24 s. These are individual samples, not a latency guarantee.

Reproduction, measurement, and verification reports are in `artifacts/chat-reliability/`. Fictional test residents were used, and the player's save was neither loaded nor modified. The local service picks up the fix through its usual reload; an open game must restart to incorporate the client's new error messages.
