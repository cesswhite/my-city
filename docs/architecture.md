# My City architecture

The Godot client owns the save and decides what happens in the world. The TypeScript Worker validates requests and queries providers: Jev proposes an action from an allowed list; OpenAI produces dialogue. No provider directly writes coins, inventory, memories, relationships, permissions, or unlocks.

This map describes the current code. Design documents and dated validation reports preserve decisions and historical evidence; when they differ, check the implementation and its tests before changing the contract.

## Entry points and coordination

```text
game/project.godot
  → scenes/shell.tscn / scripts/shell.gd
      → SessionStore: continue, validate, and back up a save
      → GameSettings: display preferences
      → scenes/main.tscn / scripts/main.gd
          → Colony: world, residents, and persistence
          → UI, drawing, movement, and encounter modules
          → HTTPRequest: decisions and visits
          → DialogueStream: SSE conversation
              → local Worker → Jev / OpenAI
```

[`shell.gd`](../game/scripts/shell.gd) manages the menu and session lifecycle. [`main.gd`](../game/scripts/main.gd) connects input, clock, presentation, requests, and interaction modules. Many UI modules receive `host` and use this coordinator; there is no service container or global autoload that owns the save.

[`colony.gd`](../game/scripts/colony.gd) is a `RefCounted` that can be tested without opening the scene. `setup(load_existing, developed)` builds residents and subsystems before attempting to load. `setup(false)` creates the smaller starting settlement; `setup(false, true)` creates a developed colony for fixtures. A catalog entry does not imply presence: simulation must use `active_residents()` / `is_present()` and check open areas.

World time advances locally in five-minute steps. `Main` coordinates continuous movement, pause, speeds, and sleep; `Colony.tick()` advances environment, energy, jobs, and routines. Networking neither determines the clock nor runs every frame. Closing the application does not calculate offline progress.

## State ownership

| Module | Responsibility and state |
| --- | --- |
| [`colony.gd`](../game/scripts/colony.gd) | Residents, minute, episodes, known contacts, skills, supplies for the initial recipe, and subsystem coordination. Builds the individual context sent to the Worker. |
| [`progression.gd`](../game/scripts/progression.gd) | The player's only wallet and inventory, learning assignments, procedures, and personal unlocks. Validates purchases, coffee, and execution of steps. |
| [`settlement.gd`](../game/scripts/settlement.gd) | Town transactions: areas, buildings, resident presence, projects, resource reservations, plots, discoveries, orders, sales, and receipts. Persistent jobs also live in `settlement.state.jobs`. Uses the `Progression` wallet and inventory. |
| [`settlement_jobs.gd`](../game/scripts/settlement_jobs.gd) | Acceptance, willingness, energy, travel, and job phases. Orchestrates `Settlement`; does not maintain another economy. Restores `work_profile` from the catalog when loading. |
| [`daily_life.gd`](../game/scripts/daily_life.gd), [`rest_state.gd`](../game/scripts/rest_state.gd) | Routines, everyday tasks, pauses, and sleep. Persistent sleep data belongs to each resident; coordination indexes and timers are rebuilt. |
| [`social_relationships.gd`](../game/scripts/social_relationships.gd) | Directed relationships and willingness to converse, saved on each resident. Relationship A → B does not replace B → A. Filters the profile each conversation partner may see. |
| [`social_knowledge.gd`](../game/scripts/social_knowledge.gd) | Bounded registry of topics, individual knowledge, versions, sources, disclosures, cases, and social receipts. Saved separately from episodes. |
| [`social_dialogue.gd`](../game/scripts/social_dialogue.gd), [`social_dynamics.gd`](../game/scripts/social_dynamics.gd) | Local social options and dialogue; bounded interpretation of complete exchanges and social consequences based on the character's own evidence. |
| [`environment_state.gd`](../game/scripts/environment_state.gd) | Persistent environmental changes: crop damage and regrowth, trees, fruit, and household objects. Preserves a seed; reading a view does not reroll outcomes or advance time. |
| [`session_store.gd`](../game/scripts/session_store.gd), [`game_settings.gd`](../game/scripts/game_settings.gd) | Safe save replacement and display preferences, respectively. Settings are separate in `user://settings.cfg`. |

`snapshot()` objects return copies for persistence. Catalogs and geometry caches are not save state: do not modify them to simulate construction, farming, or opening an area.

## Catalogs and shared geometry

| Source | Use |
| --- | --- |
| [`residents.json`](../game/data/residents.json) | Stable identities, initial history, appearance, schedules, and work preferences. `ResidentCatalog` centralizes IDs and profiles; the Worker imports the same JSON. |
| [`neighborhood.json`](../game/data/neighborhood.json) | Outdoor areas, connections, places, homes, and starting points. Also feeds the Worker's area validation. |
| [`world_layout.json`](../game/data/world_layout.json) | Shared geometry, interiors and house variants, furniture, anchors, and interactions. |
| [`settlement.json`](../game/data/settlement.json) | Town starting state, resources, recipes, projects, explorations, plots, market, orders, and geometry extensions. |
| [`apprenticeships.json`](../game/data/apprenticeships.json) | Assignments, materials, and verifiable learning steps. `Progression` adds community resources to its item catalog. |
| [`social_content.json`](../game/data/social_content.json) | Initial social topics and who knows them; not a public biography available to everyone. |

[`world_layout.gd`](../game/scripts/world_layout.gd) combines these data for drawing, routing, and interaction. [`navigation.gd`](../game/scripts/navigation.gd) uses that geometry and route caches per area; [`crowd_motion.gd`](../game/scripts/crowd_motion.gd) coordinates body spacing and blockage recovery. A position always needs its `room`: identical coordinates in two areas do not establish proximity.

Art starts from [`game/assets/sprites/manifest.json`](../game/assets/sprites/manifest.json). `sprite_art.gd`, `pixel_art.gd`, `environment_art.gd`, `crop_sprites.gd`, and `bicycle_rider.gd` present it; `settlement_world.gd` adapts town state into visible, interactive objects. `Main.home_project_state()` gathers the views these adapters need. `world_interactions.gd`, `environment_interactions.gd`, and `interaction_hover.gd` keep drawing, targets, and actions connected. See [map integration](integracion-del-mapa.md) and [modular art](arte-modular.md).

## Transactions and physical execution

A job follows this path: UI → `SettlementJobs.request()` → availability and willingness checks → `Settlement.prepare_task()` → travel and work → `Settlement.complete_task()`.

- `offer()` and `preview()` check feasibility; preparing a job consumes or reserves inputs. Do not turn a view or tooltip into a transaction.
- The character must reach the walkable target and work. Conversation or sleep suspends progress. NPCs who gather or explore return to the board before delivering results.
- Costs, duration, discoveries, and rewards come from the catalog. Job IDs and receipts prevent settling a result twice.
- Cancellation returns the applicable reserved inputs; a construction project retains its initial investment and progress. Do not apply a generic refund that duplicates resources.
- Openings and arrivals must be justified by completed projects. Save validation checks these relationships as well as types and ranges.

Text such as “I already repaired the bicycle” does not perform the repair. Learning requires remembered instructions and steps performed in the world; it does not represent XP or weight training. Details: [learning and assignments](aprendizaje-y-encargos.md), [town design](settlement-design.md), and the `settlement_*` suites.

## Conversation, perception, and service

[`player_chat.gd`](../game/scripts/player_chat.gd) manages manual conversation and its session; [`social_encounters.gd`](../game/scripts/social_encounters.gd) handles physical encounters; [`dialogue_stream.gd`](../game/scripts/dialogue_stream.gd) provides non-blocking incremental transport. `Main` coordinates participant reservations, cancellation, and response application. Old waits or responses must not survive a change of partner or control mode.

`Colony.context_for(id, partner_id, query)` selects personal memory, the pair's recent conversation, the allowed profile, skills, nearby observations, and bounded summaries of work and social knowledge. It also filters `memories`, `recent_conversation`, and `known_people.last_topic`: removing a secret only from `social_context` is insufficient. The total limit is 12,000 characters; the social block has an additional 2,400-character limit in the Worker contract.

Characters distinguish observation, testimony, opinion, and secrets. Source, date, and certainty belong to individual knowledge; repetition, high trust, or confession do not turn a rumor into verified fact. Sent context includes neither the global registry nor the private transmission chain. Social transmission occurs after a completed physical exchange and covers only what was actually said and heard. See [social knowledge](social-knowledge-design.md).

[`backend/src/worker.ts`](../backend/src/worker.ts) exports only the handler loaded by Workerd. [`backend/src/index.ts`](../backend/src/index.ts) contains validation, authorization, prompts, provider adapters, SSE, and `handleRequest`, whose HTTP transport can be replaced in tests.

| Route | Authority boundary |
| --- | --- |
| `GET /health` | Reports available configuration without querying providers. |
| `POST /decide` | Jev chooses from allowed actions. `colaborar` leaves selection and validation of the specific job to the engine. |
| `POST /visit-decision` | Owner preference; the engine rechecks presence, home, and permission before entry. |
| `POST /dialogue`, `POST /dialogue/stream` | Bounded dialogue and suggestions. No tools to alter the world. |

SSE `delta` events are provisional. Only `done` confirms the complete text; error, cancellation, or truncation discard partial text and do not create an episode. Each response retains one OpenAI call, without another summarization call on the critical path. Local mode and simulated providers must be identified as such.

The current Worker does not use D1, accounts, memory synchronization, or remote simulation. It requires the local token even for health, rejects `Origin`, limits POSTs to 32 KiB, and does not automatically retry paid calls. `scripts/play.mjs` passes Godot only the service URL and token, plus allowed system variables; Jev/OpenAI keys stay in the backend. Full contract and scope: [backend/README.md](../backend/README.md).

## Saves and compatibility

The save lives at `user://colony.json`, within the `MyCityPrototype` user directory configured in `project.godot`. The current outer format is `version: 1` with `world_revision: 2`; each subsystem validates its schema. It contains residents, clock, episodes, supplies, and the `progression`, `settlement`, `social_knowledge`, and `environment` blocks.

1. `Colony.load_game()` limits reads to 16 MiB and validates the whole document before assigning state. It checks unique identities, finite values, locations, relationships, memory, and subsystem consistency.
2. Missing historical fields are reconstructed through explicit paths. A save without `settlement` receives the developed town; it is not reset to the smaller starting state. Old geometry recovers only blocked positions and rebuilds routes when appropriate.
3. Saving validates current state and the previous file, writes `.tmp`, retains `.bak`, and replaces the file by renaming. An invalid existing save prevents autosave from overwriting it.
4. `SessionStore.new_game()` prepares another save and preserves the previous one in `.archive-<suffix>` before replacing it. This backup is independent of the rotating `.bak`.

`player_autonomy`, conversation reservations, temporary visit permissions, pending requests, drafts, and caches are not persistent progress. Autonomy returns to manual control on load; a saved manual route can be restored. Do not add real time elapsed since closing to migrations.

## Extending without breaking boundaries

- **Content:** start with the relevant catalog and its consumers. Renaming a persisted ID or adding a resident affects validators, saves, homes, and social knowledge; it requires an explicit migration.
- **Economy and jobs:** extend `Settlement` / `Progression` and their validators; use `SettlementJobs` for physical execution. The UI describes requirements and requests operations.
- **Map and art:** change shared geometry, anchors, navigation, and interaction together. Keep views pure and caches separate from save state.
- **AI:** first adjust filtered context and the contract; check Godot and the Worker together with simulated transport. A prompt does not replace an engine rule.
- **Persistence:** update validation and restoration in the same change; cover old saves, invalid data, save round trips, and absence of duplicate effects.

The [agent guide](agent-guide.md) connects these entry points to concrete tasks and checks.
