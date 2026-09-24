# Prototype validation · September 23, 2026

Environment: macOS, Godot 4.7.2, TypeScript Worker, Bun, and local Wrangler. Automated suites use separate saves and simulated providers. The brief, separate live check described below was also performed; there was no remote deployment.

Final run after sprite integration: **14 client suites, 632/632 checks; backend 53 passing tests and no TypeScript errors**. Logs retained in `artifacts/validation/`. The final importer passed **27/27** local checks with temporary fixtures. The live HTTP checks described below are separate from those 14 suites.

| Check | Result |
| --- | --- |
| Memory, per-pair context, learning, schedules, homes, and permissions | 104/104 checks |
| Navigation, obstacles, six doors, interiors, and recovery of old positions | 82/82 checks |
| Complete world: NPC return/exit, interaction, player entry, inspection, and exit | 51/51 checks; 25,200 sampled traversable positions |
| Direct keyboard movement: diagonals, sliding, and collisions without A* routes | 26/26 checks |
| Player autonomy: schedules, local conversations, knowledge, and saving without automatic activation | 35/35 checks |
| Controls and world: keyboard, focus, modals, pause, speeds, doors, and stopping without jitter | 44/44 checks |
| Autonomy and AI: cancellation, stale responses, route recovery, and queries at 4× | 39/39 checks; no network |
| SSE transport: UTF-8 fragmentation, cancellation, errors, and consecutive requests | 21/21 checks |
| UI: selection, customization, bounds, streaming, and memories | 12/12 checks |
| Layout: long text, panels, schedule, conversation, and control bounds | 45/45 checks |
| Sprites: manifest, layers, variants, animation, directions, cache, and composition | 50/50 checks |
| Quests: purchases, deliveries, steps, three completed learning procedures, partial saves, and migration | 72/72 checks |
| Playable bicycle chain: buttons, shop, home, repair, and mounted speed | 30/30 checks; 25,200 traversable positions |
| Interactions with the clock running: following a mentor, scrolling, drafts, and entry into the player's home | 21/21 checks |
| Live HTTP Godot → local Worker → test provider | 9/9 checks |
| Worker: auth, Jev, visits, OpenAI, streaming, progression context, redirects, and errors | 53 passing tests |
| TypeScript | `bun run check` passed |
| Worker bundle | `wrangler deploy --dry-run` passed; no publication |
| `.env` loading and client credential isolation | 10 passing tests; derived files `0600`, ignored by Git |
| Real Worker in local Wrangler → real providers | `/health` 200, valid Jev decision, and complete OpenAI streaming with 11 fragments |

Autonomy controls, the map, customization, interiors, journal, repair procedure, and cyclist were rendered with Godot/OpenGL and visually reviewed. Local captures are in `artifacts/`, ignored by Git.

The new chains are one-time projects. Planting credits one sowing and tea produces one cup; harvesting, serving other characters, and repeating projects are not yet implemented. Quest purchases are limited to outstanding materials. The bicycle changes actual movement from 48 to 120 pixels per second along the same obstacle-aware routes; [current movement validation](bicicleta-y-movimiento.md) checks sweeps of up to one pixel.

Live credential check on September 23, 2026, invoking the Worker handler with fictional data: Jev `jev-1.13.0` returned HTTP 200 with a valid decision in 2,059 ms; OpenAI `gpt-6-luna` returned HTTP 200 with 11 fragments, first text at 2,486 ms and completion at 2,700 ms. Secrets were neither printed nor versioned. This check confirms access to both providers; it is not an in-Godot performance measurement or a Cloudflare deployment.

The complete HTTP path through local Wrangler/Workerd was then checked. Two runtime incompatibilities were fixed: the entry point now exports only the Worker handler, and requests use `redirect: manual` to reject redirects without forwarding credentials. `/decide` finished with a low-confidence Jev response and the expected local fallback; `/dialogue/stream` finished successfully with 11 fragments. The health endpoint confirmed both keys without showing them. These checks used fictional data and did not modify player memories.

Pending: benchmarks and quality evaluation with real Jev/OpenAI, per-user authentication, remote persistence and simulation while the game is closed, and art based on the reference images. NPCs have routes around static obstacles; dynamic body avoidance is not yet present. Initial trust depends on shared experiences, schedule, and personality; it is not yet a complete social model.

The new autonomy is optional and resets to manual mode on load. New AI tests replace transport with a local probe; they verify coordination and frequency, not real-model quality or latency. After conversation, participants' current destinations are restored. Manual recovery cancels old actions, and a partial conversation creates no memories.

Visual control verification in Godot: the current version was opened, Space was confirmed to switch to “Seguir” (Resume) and stop the clock, and the game was left open paused. The isolated autonomy-mode capture is in `artifacts/autonomy-preview.png`.

## PNG sprite batch · executed checks

This section records the final batch of 88 PNGs and its September 23 import. All 14 client suites were rerun with the integrated sprite renderer; their results appear above and in `artifacts/validation/`, including `sprite_smoke.log` and `layout_smoke.log`.

Declared provenance in `game/assets/sprites/manifest.json`: `gpt-image-2.5-sunburst-2026-09-08`, official Imagegen CLI with `generate-batch`, `edit`, and `generate`, PNG format. Sources are in `output/imagegen/`, exact prompts in `output/imagegen/prompts/`. `output/imagegen/provenance.json` records all nine sources, parameters, references, and full image and prompt SHA-256 hashes. The model is recorded by the pipeline and manifest, not inferred from images. [Reproducible process and limits](arte-modular.md).

| Executed check | Result and scope |
| --- | --- |
| Sharp read of all nine source PNGs | Eight 1024×1024 files and buildings 1536×1024; all decodable |
| Alpha in cutout sources | Eight PNGs with real transparency; all also contain partial alpha values, maximum 254 |
| Terrain textures | `terrain.png` opaque; no background belonging to the material was removed |
| `node scripts/prepare-sprites.mjs --self-test` | 27 passing checks in the final run; temporary synthetic fixtures, no network or generation calls |
| Imported manifest files | 88 PNGs decoded; all dimensions match the manifest; includes separate `garden_left`/`garden_right` beds |
| Alpha in all 88 imported PNGs | 70 with transparent pixels, 18 fully opaque, none with partial alpha; normalized 0/255 output |
| Static interaction/scene correspondence | The shop and each interior's five slots have equivalents in `sprite_art.scenery_objects()` in the usual state; code review, not a click test |

The executed self-test includes preservation of existing alpha, edge-connected chroma removal without erasing an interior color, rejection of ambiguous chroma, material/region selection, alpha threshold, offset, cell ordering, dimensions, and metadata. It does not demonstrate that every art crop is correctly chosen or that accessories visually fit the body.

Provenance fingerprints for inspected originals, as SHA-256 prefixes; these distinguish this batch from future regenerations:

| Source | SHA-256, first 16 characters |
| --- | --- |
| `body.png` | `ae94fa7a629c3975` |
| `hair.png` | `be2ee6a0c6b8745b` |
| `hats.png` | `c8197f153cee7161` |
| `beards.png` | `b583bb401fe96471` |
| `buildings.png` | `e306daeba2e1eec8` |
| `outdoors.png` | `97a8049428bacd32` |
| `interiors.png` | `e4223dcf7569fa86` |
| `terrain.png` | `69426fc838de03f5` |
| `ui.png` | `e63c1524add3b622` |

Static review findings: photographs and several furniture items are shared between homes; lore remains specific and palette/project distinguish the homes. `bicycle_away=true` removes the entire bicycle without showing a separate stand, although it preserves the hotspot and collision. The host currently supplies `false`, so this disappearance does not occur in the current scene; its visual state would need completing if enabled.

Final visual review confirmed no errors in home and customization: `artifacts/sprites-home.png` and `artifacts/sprites-appearance.png`. Final captures `artifacts/sprites-street.png` and `artifacts/sprites-journal.png` were regenerated and reviewed after correcting focus and selection contrast. `artifacts/sprites-learning/learning-procedure.png`, `bicycle-repaired-home.png`, and `cycling.png` were also reviewed. A new game session was opened through Play.command, loaded existing progress, and remained paused at Your character → Appearance. This does not claim an exhaustive visual review of all six homes or all accessory combinations. No API cost was measured or inferred for the batch.

## Sustained conversation with a neighbor · subsequent check

This batch concerns manual chat and follows the sprite integration recorded above. It does not replace the historical results of those suites.

| Check | Result and scope |
| --- | --- |
| Memory and simulation core | 138/138 checks; includes pair continuity and preservation of both voices during compaction |
| Backend | 56 passing tests; simulated providers, no real calls |
| TypeScript | `bun run check` passed |
| Real conversation Godot → local Worker → OpenAI | 24/24 checks after the brevity adjustment; three isolated turns without reading or modifying the user's save |
| Dedicated chat session/UI suite | 60/60 checks |
| Layout after chat integration | 47/47 checks |

The backend retains one request per turn, streaming, `reasoning: none`, and `store: false`. The latest adjustment reduces the maximum to 96 tokens and requests one or two direct, general sentences, targeting up to 30 words and 180 characters in one paragraph without line breaks, lists, repeated spaces, or long dashes. It does not require every turn to end with a question. New tests check four exchanges in order through both routes, separation between pairs, and absence of inherited state when switching neighbors. They verify contracts and errors; mocks do not evaluate model naturalness or real latency.

The live test used Lupita: a greeting, a question about her interests, and the follow-up “¿Cómo podría participar en eso?” (How could I take part in that?). After the concision adjustment, responses stayed on topic, arrived with 72, 155, and 114 provider characters, and needed no length trimming. Local evidence: `artifacts/chat-validation/live-chat-brief.json`, containing texts, OpenAI origin, timing, and no failed checks. The earlier 19/19 sample remains in `live-chat.json`.

| Turn | First fragment | Complete response |
| --- | --- | --- |
| Greeting | 1.06 s | 1.32 s |
| Neighbor's interests | 1.04 s | 1.36 s |
| Follow-up on the previous topic | 0.70 s | 0.93 s |

These are three samples from one conversation, not a benchmark, model comparison, or timing guarantee. The model's invitation to organize a meal is dialogue: it does not create a quest, objects, or an implemented world capability. There was no remote deployment.

Static review of closing during streaming confirms cancellation and release of the pair without saving partial text. Error recovery preserves retry and respects a newly written draft. Drafts remain only during the session; complete exchanges persist when the game is saved.

The chat suite also verifies normalization of split SSE fragments, identical final response and memory, a maximum of 180 characters and 30 words, autonomous and local voices, intact player free text, and compact presentation of old saves without rewriting their memories. Reopening a conversation offers a greeting even when history exists; after a reply, options appear according to the new turn. Final log: `artifacts/chat-validation/player_chat-final.log`. Synthetic capture without network: `artifacts/chat-compact-fixture.png`.

## Subsequent world-scale calibration

The character's visible 22-pixel reference is retained. All 88 PNGs were reimported from the same GPT Image 2.5 sources; this correction made no new generation calls. Five facades share a row and baseline, doors are 24–27 pixels high, and all four garden beds use equal modules. Furniture was reduced within a compact interior. Drawing, collisions, doors, routines, and stations share `world_layout.json`.

| Check | Result |
| --- | --- |
| Proportions, native pixels, states, and access | 69/69 |
| Sprites and layers | 50/50 |
| Interface layout | 47/47 |
| Conversation and interaction | 60/60 and 21/21 |
| Navigation and keyboard | 99/99 and 26/26 |
| Memory and progression | 138/138 and 72/72 |
| World and learning chain | 51/51 and 31/31; 25,200 positions sampled in each suite |
| Controls and autonomy | 44/44 and 35/35 |
| Backend | 56 passing tests; no real providers |

Evidence: `artifacts/scale-validation/`, `artifacts/world-scale/scale-smoke.log`, and four reviewed captures in `artifacts/world-scale/`. Captures place reference avatars in front of doors and furniture without opening the save. The real game was closed with a save and backed up before loading the new geometry. Measurement details and limits are in [escala-del-mundo.md](escala-del-mundo.md).
