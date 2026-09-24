# My City local backend

A Cloudflare Worker written in TypeScript. Jev chooses a bounded action; OpenAI generates character dialogue. The Godot client keeps the world, episodes, and learned procedures in its local save. This Worker does not create or synchronize memories and does not yet use D1.

## Running

From the repository's `backend/` directory, with Node.js 22 and Bun installed:

```sh
bun install --frozen-lockfile
bun run configure
bun run dev
```

The configuration source is `.env` at the project root. Its values are neither overwritten nor filled from inherited process variables. These names are supported:

| Root `.env` variable | Use |
| --- | --- |
| `JEV_API_KEY` or `TYPESAFE_API_KEY` | Jev key; converted to `TYPESAFE_API_KEY` for the Worker |
| `OPENAI_API_KEY` | OpenAI key, for the Worker only |
| `OPENAI_API_MODEL` or `OPENAI_MODEL` | Model; defaults to `gpt-6-luna` |
| `MY_CITY_DEV_TOKEN` | Local token shared between Worker and Godot; at least 32 characters |
| `MY_CITY_API_URL` | Address used by Godot; defaults to `http://127.0.0.1:8787` |
| `OPENAI_API_BASE` | Optional; only `https://api.openai.com/v1` is accepted |
| `OPENAI_API_VERSION` | Optional; only `v1`, the official route version, is accepted |

If two aliases contain different values, preparation stops with an error showing only their names. Base and version validate existing configuration: the Worker uses a fixed official URL and sends no Azure version parameter. You can generate the local token with `openssl rand -hex 32`.

`configure` (also `config:local`) creates `backend/.dev.vars` from `.env` using an atomic write and `0600` permissions. It contains only the three keys consumed by the Worker and `OPENAI_MODEL`; both files and temporary files are ignored by Git. `dev` repeats this preparation before starting Wrangler, so changes belong in `.env`, not the derived file. The command prints names and statuses, never values. If `.env` does not exist, a manual `.dev.vars` is preserved without reading or modifying it; this mode still allows copying `.dev.vars.example` and configuring Wrangler directly.

Wrangler runs the Worker locally at `http://127.0.0.1:8787`; it does not deploy resources. Model calls do reach their providers and use the configured keys. Without keys, the corresponding routes return an explicit error and make no Internet calls.

`Start-AI.command` at the root starts this backend. `Play.command` uses the launcher, which passes Godot **only** `MY_CITY_DEV_TOKEN` and `MY_CITY_API_URL`, plus allowed system variables. Do not load the entire `.env` with `source` before opening the game. Godot sends `Authorization: Bearer <token>` to the Worker; provider keys stay outside the game process. Server secrets are local Wrangler bindings, not values in `wrangler.jsonc` or Godot resources.

The initial model is `gpt-6-luna`, with `reasoning.effort: none`, `store: false`, and a maximum of 160 output tokens. The configuration variable allows changing it on the server. This choice targets low latency; the check described below is a sample, not a comparison proving which model is fastest. Jev is pinned to `jev-1.13.0` to keep initial behavior stable.

## HTTP contract

All routes require the development Bearer token, including `/health`. This token protects a personal prototype; it does not yet represent accounts, sessions, or owner-specific authorization. Requests with `Origin` are rejected: the current client is native Godot, and CORS is not enabled.

| Method and route | Input | Result |
| --- | --- | --- |
| `GET /health` | None | Available configuration without querying models |
| `POST /decide` | `{resident, allowed_actions}` | `{action, source, confidence, model}` |
| `POST /visit-decision` | `{resident, visitor:{id,name}, visit:{home_id,known,encounters,routine}}` | `{allowed, source, confidence, model}` |
| `POST /dialogue` | `{resident, utterance, speaker:{id,name}}` | `{text, source:"openai", model}` |
| `POST /dialogue/stream` | Same as `/dialogue` | SSE `delta` events, then `done` or `error` |

POSTs require `Content-Type: application/json`, at most 32 KiB of UTF-8 JSON, and contract-defined fields. `resident` must contain **only context known to that character**. The application decides which memories they may see; the Worker does not automatically receive every biography. `utterance` accepts 1–1,200 characters; `speaker.id` and `speaker.name` accept up to 80 each.

`resident.relationship` is optional and describes only the resident's directed relationship toward `partner_id`. The Worker validates its seven fields and their correspondence with `identity.id` and the conversation partner before querying a provider. The local engine filters biography, decides relationship changes, and enforces access boundaries. Dialogue uses that state for tone and privacy; a goodbye, explicit boundary, or active cooldown leaves suggestions empty. The 12,000-character budget, streaming, and one request per response remain. See the [relationship and privacy contract](docs/relationships.md).

For `/decide`, `allowed_actions` is a duplicate-free list drawn from `plaza`, `cafe`, `taller`, `huerto`, `descansar`, `conversar`, `practicar`, and, when the engine offers collaboration, `colaborar`. It must always include `descansar`. Jev's response must belong to that list and contain valid confidence and distribution. If confidence is below 0.55, the server chooses rest with `source: "fallback_low_confidence"` and `reason: "low_confidence"`. That rest is an explicit local rule.

For `/visit-decision`, `resident` contains the **homeowner's** private context, not the visitor's. `visitor.id`, `visitor.name`, and `visit.home_id` accept up to 80 characters; `visit.known` is boolean, `visit.encounters` is an integer from 0 to 1,000,000, and `visit.routine` contains 1–160 characters. No other fields are allowed inside `visitor` or `visit`.

Jev chooses `allow`/`deny` based on personality, routine, and personal memories of the relationship. A curious owner may admit a stranger; familiarity is not an absolute requirement. Confidence below 0.55 produces `{allowed:false, source:"fallback_low_confidence", confidence, model}`; denial chosen by Jev retains `source:"jev"`. A missing key or error returns the error contract without inventing permission. The result expresses a preference: **the engine must check home ownership and the presence of both characters before requesting it and again before opening the door**. The Worker does not move characters or grant persistent access.

This example retains Spanish in-game biography and memory text:

```json
{
  "resident": {
    "id": "cesar",
    "biography": "Creció con su papá en el campo.",
    "memories": [{"with":"lupita","fact":"Le gustan los huertos","day":1}]
  },
  "allowed_actions": ["huerto", "descansar"]
}
```

HTTP errors have `{source:"error", error:{code,message}}`, without `action` or synthetic dialogue. A missing server token/key returns 503; incorrect token, 401; invalid JSON, 400; excessive size, 413; rejected provider, 502; timeout, 504. Paid calls are not automatically retried; provider 429/529 returns 503, and the client must wait before retrying. Bodies, biographies, keys, and provider error responses are not logged.

External calls use `redirect: "manual"`: redirects are rejected as errors without following `Location` or forwarding credentials. Workerd implements only `follow` and `manual`; `error` fails before connecting, according to its [Request implementation](https://github.com/cloudflare/workerd/blob/main/src/workerd/api/http.c%2B%2B).

## Area context

Identities and areas are imported from the shared `residents.json` and `neighborhood.json` catalogs, including the new `forest` grove. Registration does not establish presence or access: the engine filters population, paths, and perception. `room` identifies the area, and `pos` contains local coordinates: residents at identical coordinates in different areas are not nearby. Each new observation includes its `room`, which must match the resident's; unknown identities, invalid coordinates, and observations from other areas are rejected. Legacy plaza/interior contexts may omit the area field in observations.

Jev and dialogue receive that distinction without a larger context budget. Memories and contacts are prior knowledge, not queries of other residents' current locations. A character may attribute a remembered location to personal experience or the person who reported it, but cannot claim someone remains there or infer that from their home or schedule. The engine retains authority over routes, encounters, doors, and permissions; the model does not teleport or obtain private data from other areas.

## Community and collaboration

`resident.settlement` is optional and accepts exactly `{stage, own_job, cooperation_available}`: a public stage of up to 80 characters, the character's own job of up to 160, and boolean availability. Extra fields, control characters, and summaries exceeding 1,600 characters are rejected; the total context limit remains 12,000. It contains no other people's inventories, worker records, or map of absent neighbors.

`colaborar` is an eighth possible `/decide` action, only when the engine includes it in `allowed_actions` and `cooperation_available` is `true`. Jev returns only that choice and its source/confidence. The engine selects a catalog job and checks willingness, materials, energy, travel, and execution. Neither Jev nor dialogue receives tools to alter the economy, build, discover areas, or add neighbors. Dialogue distinguishes ongoing work from a verified result without changing the SSE protocol or adding requests.

## Social knowledge, rumors, and secrets

`resident.social_context` is optional, with a maximum of **2,400 characters** within the same **12,000-character** total budget. Its only fields are `claims`, `case`, and `policy`.

| Field | Contract |
| --- | --- |
| `claims` | Up to four claims with unique identifiers. Each contains exactly `id`, `subject_id`, `text`, `kind`, `certainty`, `source_id`, `privacy`, `confidence`. |
| Claim | `id` up to 80 characters; `text` up to 240; `subject_id` and `source_id` belong to the resident catalog. `kind`: `fact`, `opinion`, `rumor`, or `secret`. `certainty`: `observed`, `heard`, or `uncertain`. `privacy`: `public`, `personal`, or `secret`. `confidence`: integer from 0 to 100. |
| Provenance | `observed` requires `source_id` to be the resident themselves. `heard` and `uncertain` require another known immediate source, never a hidden transmission chain. |
| `case` | `{}` or exactly `{id, subject_id, partner_id, stance, prompt}`. The subject must own the context, and the conversation partner must match `partner_id` and `speaker.id` or `visitor.id`. `id` up to 80 characters; `prompt` up to 180; `stance`: `suspicion` or `confirmed`. |
| `policy` | Narrative text of up to 200 characters. It does not replace instructions or authorize the model to modify the world. |

Extra fields, control characters, crossed identities, contradictory provenance, or excessive sizes are rejected before any call. Old contexts without `social_context` remain supported. The local engine filters knowledge for this partner: **it must also exclude unauthorized secrets from `memories`, `recent_conversation`, and `known_people`**. The Worker validates the contract but has no save and cannot reconstruct those permissions.

A secret included in `claims` permits narrating only that content in this turn, even when the story represents a deliberate indiscretion by the character. It grants no access to other secrets, transmission routes, or omitted biographies. Privacy boundaries for the character's own biography remain. The source is the immediate person the resident remembers; a rumor, the `fact` label, high confidence, or a confession does not become verified truth.

A `suspicion` case allows a cautious question based on personal experience. `confirmed` expresses perceived evidence or a received admission, which can still be false; it does not magically identify the actual person responsible. Dialogue does not change metrics or propagate memories on its own. The engine records only what was actually said and heard when the exchange ends; partial or canceled responses must not cause propagation.

Generated suggestions may offer “Prefiero no responder.” (“I'd rather not answer.”) or “Cambiemos de tema.” (“Let's change the subject.”). They do not invent a confession, lie, or innocence for the player. Specific social options shown by the client are calculated locally. `text` and `suggestions`, incremental streaming, and one request per response remain; there is no extra rumor-analysis call. Service tests cover validation, sent data, and instructions using simulated responses; they are not an evaluation of real model quality.

`bun tests/social-context-from-godot.ts` additionally checks the contract using contexts produced by a real synthetic colony: public opinion, a private detail excluded from every field, an allowed indiscretion, and personal suspicion. It runs Godot without a save or providers, exports only those fictional data, and tests JSON, SSE, and Jev routes with simulated HTTP. Result: **4 contexts, 12 checks**. A missing key or incomplete response is never presented as a real conversation.

## Streaming dialogue

`/dialogue/stream` uses Responses with `stream: true` and forwards text as it arrives. Direct conversation does not require a prior Jev call. Instructions are stable, with context placed afterward; there is no summarization call on the dialogue path.

The following events retain Spanish in-game dialogue:

```text
event: delta
data: {"text":"Sí, ayer "}

event: delta
data: {"text":"me contaste lo del huerto."}

event: done
data: {"text":"Sí, ayer me contaste lo del huerto.","source":"openai","model":"gpt-6-luna","ttft_ms":215,"total_ms":410}

```

These timings are **illustrative**. `ttft_ms` measures from the start of the provider call to its first text; `total_ms` measures until the complete result. The `Server-Timing: upstream_headers;dur=...` header measures the wait for provider headers. They do not include Godot → Worker transport.

`done.text` exactly matches the concatenation of `delta.text`, including spaces and line breaks. Only `done` confirms a complete response that the engine can save as an episode. Fragments are provisional. A refusal, truncated result, incomplete connection, or 10-second deadline produces a terminal event:

```text
event: error
data: {"source":"error","error":{"code":"upstream_incomplete","message":"El diálogo no se completó; descarta el texto parcial."},"discard_partial":true,"total_ms":300}

```

After `error`, the client discards provisional text and stops waiting. Authentication, validation, or initial connection errors may arrive as JSON with a non-200 HTTP status before SSE opens. Client cancellation aborts pending generation. JSON responses are limited to 64 KiB; SSE permits 512 KiB total and 128 KiB per event because it includes repeated metadata. Dialogue retains its 1,600-character limit. See [streaming diagnosis and validation](../docs/chat-reliability.md). The model has no execution tools or memory writes.

## Verification and scope

```sh
bun run check
bun test
bun run test:godot
bun run build
```

`build` runs `wrangler deploy --dry-run`: it produces a local bundle and **does not publish**. Tests inject sample HTTP/SSE responses and cover success, isolation of sent context, missing/incorrect token, absent keys, limits, refusal, truncation, errors, UTF-8 fragmentation, first fragment arriving before completion, cancellation, and a real 10-second timeout. They do not call TypeSafe/OpenAI. Static checks and bundling also do not establish real access to those providers.

`test:godot` requires Godot at `/Applications/Godot.app`. It temporarily opens a Bun fixture on `127.0.0.1:18787`, runs the real `DialogueStream` client against the Worker's same `handleRequest`, and closes the server afterward. It checks real headers, fragments before completion, UTF-8, and exact result correspondence; the Responses provider is replaced by a fixture, and no real key is read or sent. The current fixture includes 15 Godot → Worker transport checks, including HTTP failures and errors during SSE. Configuration tests use temporary files and fake keys to verify aliases, permissions, updates, manual configuration preservation, and separation of game variables.

A local check with real providers was performed on September 23, 2026 through `handleRequest` and fictional context: Jev returned HTTP 200, `source: "jev"`, model `jev-1.13.0`, and action `taller` in 2,059 ms. Dialogue from `gpt-6-luna` returned HTTP 200 and 11 fragments, with first text at 2,486 ms and completion at 2,700 ms. This is one sample of working credentials and APIs; it is not a benchmark and does not yet measure the full Godot experience. This check deployed no remote resources.

No remote Workers, databases, routes, or secrets have been created, and no Cloudflare account has been selected. A shared version will require user identity, quotas, and authoritative memory; the development token must not be distributed inside a public game.

Official sources reviewed on September 23, 2026: [TypeSafe API](https://docs.typesafe.ai/api), [Jev models](https://docs.typesafe.ai/models), [Jev does not generate conversation](https://docs.typesafe.ai/introduction/coding-agents), [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna), [Responses streaming](https://developers.openai.com/api/docs/guides/streaming-responses), [Wrangler configuration](https://developers.cloudflare.com/workers/wrangler/configuration/), [local secrets](https://developers.cloudflare.com/workers/local-development/environment-variables/).
