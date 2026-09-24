# Agent working guide

First read [`AGENTS.md`](../AGENTS.md), the [README](../README.md), and the [architecture](architecture.md). Then open only the module, catalog, topic documentation, and test involved in the task. This guide explains repository changes; it does not authorize paid calls, deployments, publication, or changes to secrets.

## Before editing

1. Check Git status and preserve other contributors' changes. Search with `rg` / `rg --files`; confirm paths and calls in the code, not only in historical documentation.
2. Identify who owns the state you will change, which action modifies it, and how loading validates it. If only presentation changes, avoid adding more persistent state.
3. Choose a fixture that reproduces the problem without personal saves or providers. A UI test must be isolated from the start, before adding `Main` to the tree.
4. Make the smallest complete change: data, consumer, validation/migration, and documentation as appropriate. Follow existing modules; do not add a web framework or remote service without a concrete need.

[`settlement-contract.md`](settlement-contract.md) preserves a coordination contract from an earlier implementation, including that task's agent assignments. Do not treat those assignments as instructions for a new task or assume its signatures supersede the current code.

## Reading by task

Full paths in this table are relative to the repository root. Scripts without a directory are in `game/scripts/`; suites are in `game/tests/`. Confirm each test's required arguments before running it.

| Task | Read and edit first | Relevant verification |
| --- | --- | --- |
| Saves, new game, menu | `game/scripts/colony.gd`, `session_store.gd`, `shell.gd`, `game_settings.gd`; [menu and display](menu-y-pantalla.md) | `smoke.gd`, `menu_lifecycle_smoke.gd`, `settings_smoke.gd` |
| Coins, inventory, learning, coffee | `progression.gd`, `game/data/apprenticeships.json`; [apprenticeships](aprendizaje-y-encargos.md) | `progression_smoke.gd`, `learning_world_smoke.gd`, `coffee_smoke.gd` |
| Construction, jobs, residents, crops | `settlement.gd`, `settlement_jobs.gd`, `settlement_catalog.gd`, `game/data/settlement.json`, `resident_catalog.gd`; [design](settlement-design.md) | `settlement_smoke.gd`, `settlement_integrity_smoke.gd`, `settlement_jobs_smoke.gd`, `settlement_progression_smoke.gd` |
| Dialogue, streaming, suggestions | `player_chat.gd`, `chat_view.gd`, `chat_suggestions.gd`, `dialogue_stream.gd`, context in `colony.gd`, `backend/src/index.ts`; [reliability](chat-reliability.md) | `player_chat_smoke.gd`, `stream_smoke.gd`, `chat_suggestions_smoke.gd`, Worker tests and `test:godot` |
| Relationships, secrets, rumors | `social_relationships.gd`, `social_knowledge.gd`, `social_dialogue.gd`, `social_dynamics.gd`, `social_encounters.gd`, `game/data/social_content.json`; [social design](social-knowledge-design.md) | `social_knowledge_smoke.gd`, `social_story_smoke.gd`, `social_world_smoke.gd`, Godot → Worker social fixture |
| Paths, doors, movement | `world_layout.gd`, `navigation.gd`, `crowd_motion.gd`, `world_interactions.gd`, `game/data/neighborhood.json`, `world_layout.json`; [neighborhood](barrio-conectado.md) | `navigation_smoke.gd`, `multi_area_smoke.gd`, `world_interactions_smoke.gd`, `crowd_spacing_smoke.gd` |
| Sleep, energy, routines | `colony.gd`, `daily_life.gd`, `rest_state.gd`, `sleep_ui.gd`; [daily life](sueno-y-vida-cotidiana.md) | `daily_life_smoke.gd`, `sleep_timing_smoke.gd`, `energy_smoke.gd`, `exhaustion_smoke.gd` |
| Interactive environment | `environment_state.gd`, `environmental_catalog.gd`, `environment_interactions.gd`; [environment](environment-mvp.md) | `environment_state_smoke.gd`, `environment_world_smoke.gd` |
| UI, sprites, scale | `main.gd`, affected UI module, `sprite_art.gd`, manifest, and geometry; [visual system](pixel-art-design-system.md), [modular art](arte-modular.md) | Relevant UI suite with `--ui-test`, `sprite_smoke.gd`, `scale_smoke.gd`, and visual review |
| Configuration and HTTP | `backend/src/worker.ts`, `backend/src/index.ts`, `backend/scripts/local-config.mjs`, `scripts/play.mjs`; [backend](../backend/README.md) | Worker, configuration, and launcher tests; TypeScript, fixture, and local bundle |

## Boundaries to preserve

**Economy and execution.** `Progression` owns coins and inventory; `Settlement` validates community transactions; `SettlementJobs` requires willingness, energy, and physical presence. Preserve receipts and idempotency. Check cancellation, repeated delivery, saving during a job, and resumption. Do not credit rewards, learning, or construction because dialogue says they happened.

**Perception and privacy.** Use `is_present()`, area, and distance; a catalog name or schedule does not prove current location. Each person receives only their own knowledge and the profile authorized for their conversation partner. Test that private content is absent from the entire outgoing JSON, including memories, recent conversation, and `known_people`, not only `social_context`. Preserve source, date, certainty, and version; testimony is not verified fact. An allowed narrative disclosure does not authorize every secret or access to the private transmission chain.

**Conversation.** Preserve real streaming and bounded context per pair. Save only complete exchanges: `delta` is provisional; `done` confirms; failure, cancellation, or changing partners discards partial text. Also test that participants are released and stale responses are not applied. Suggestions must not invent commitments or admissions by the player. The engine determines social consequences without a second analysis call.

**AI and performance.** Jev chooses structured actions; OpenAI writes dialogue. Do not query AI every frame, accelerate networking with 2×/4× speed, or add automatic paid retries. Keep local rules, fixtures, and real connections visibly distinct. A simulated test verifies contracts, not narrative quality or provider latency.

**Saves.** Do not read, edit, delete, or replace a personal save to build a fixture. Use `setup(false)` and a dedicated temporary path before saving. A developed fixture uses `setup(false, true)`; do not change the game's starting state to satisfy older tests. Preserve validation before loading, backups, temporary writes, and protection against overwriting damaged files. Do not rename persisted IDs without migration or introduce offline progress.

**Secrets.** Do not edit, print, copy to the client, or version `.env`, `backend/.dev.vars`, real keys, or tokens. Do not execute `.env` with `source`. Use fake values and temporary files in tests; consult examples without secrets to explain configuration. `configure` generates `.dev.vars`, and `dev` runs it before startup: neither is required for verification without providers. Any change to real configuration requires explicit user instruction; never make it a side effect of a test.

## Verification without providers

From the root, with Godot installed at the macOS path used by the project:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path game --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/smoke.gd
```

If Godot is elsewhere, replace the executable path. The first command imports local resources; it does not generate art. For a suite that instantiates the UI, keep `--ui-test`, for example:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/player_chat_smoke.gd -- --ui-test
```

`Main` uses that argument to avoid loading the save, start paused, and keep the view isolated. If the case needs the smaller starting settlement, check the fixture's use of `--settlement-start`. `--headless` can test logic and control structure; it does not show that the image looks correct. Visual changes also require opening an isolated view with a renderer and reviewing the screenshot.

From `backend/`, with dependencies installed as described in the README:

```sh
bun run check
bun test
bun run test:godot
bun tests/social-context-from-godot.ts
bun run build
```

- `bun test` uses simulated HTTP/SSE and fake credentials. Configuration and launcher tests use temporary files.
- `test:godot` opens a temporary server on `127.0.0.1:18787` and runs the real Godot transport against the Worker with a replacement provider. Do not start `backend_smoke.gd` directly: the fixture manages the server and token.
- The social fixture produces contexts from a synthetic colony and tests their acceptance by JSON, SSE, and Jev routes with simulated transport. It needs neither a save nor real keys.
- `build` runs `wrangler deploy --dry-run --outdir dist`: it checks the local bundle without publishing.

Before finishing simulation changes, run `smoke.gd` and the service tests as required by `AGENTS.md`; add suites for the affected behavior. Do not run every script by pattern: some capture images, require arguments, or target real providers. In particular, `chat_live_check.gd` requires `--live-chat --ui-test` and queries OpenAI; it is outside ordinary validation. Starting `Start-AI.command` or using connected conversation can also consume API usage. Do not turn local verification into a paid call without authorization.

## Art and resources

Preserve the user's rule: every AI-generated asset must use **GPT Images 2.5** and be delivered as **PNG**. The recorded production used `gpt-image-2.5-sunburst-2026-09-08`; verify the effective model before generation and do not silently substitute another if the tool does not allow model selection. Do not infer the model from pixels or present the requested model as additional provider attestation.

Prefer PNG RGBA with real alpha for characters, accessories, and cutouts. If that is unavailable, follow the uniform fluorescent green or Mexican pink chroma workflow in `AGENTS.md`, without shadows or gradients; remove the background without halos or holes. Keep scene backgrounds that should remain visible.

Before editing sprites, read [modular art](arte-modular.md), the [catalog](sprite-catalog.md), and [production](pixel-art-production.md). Preserve accepted sources, prompts, provenance, and hashes; review palette, perspective, scale, anchors, frames, and transparency. Reimporting local sources is not AI regeneration. Do not automatically replace originals or manifests with a new generation. Some production records and sources are ignored local artifacts: check availability before promising full reproducibility.

## Delivery

Describe the observable change, its purpose, and the evidence supporting it. State which tests ran and any relevant limitation: no rendering, simulated provider, migration not covered, or missing art source. Update the affected topic document; do not present historical results from other runs as tests performed in this task. Do not include secrets, personal saves, or private transcripts in versioned logs, fixtures, or screenshots.
