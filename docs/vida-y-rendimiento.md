# Daily life and responsive conversations

Product priority: responsive conversations and a game that remains interactive while models work. Real provider calls have been checked, but functional samples are not a comparative benchmark.

This document records the initial conversation and daily-life design. Some values and planned features below describe that historical revision. For current behavior, use the [gameplay guide](gameplay.md), [chat reliability](chat-reliability.md), and [backend contract](../backend/README.md): chat sessions, generated suggestions, output budgets, art, sleep, relationships, and settlement jobs have since evolved.

## Pair-specific conversation

Each pair has a stable identity, and each participant keeps their own account of the experience. Neighbors do not share one brain. Talking to César does not grant access to Lupita's private memories.

In the initial design, full history remained in the local save and the chat view showed the pair's latest **20 exchanges**. A reply included up to four recent pair exchanges, four relevant memories, the speaker's identity, perception, and learned procedures. Each recent exchange reserved up to 975 serialized characters for both voices, preserving the neighbor's reply ending when trimming. The first encounter remained a reference, while relevant terms were searched among the latest 300 experiences; this was not full semantic retrieval across an entire lifetime. Serialized context was capped at 12,000 characters. Later session-cleanup behavior is documented in [clean chat](chat-limpio.md).

This supports continuity without depending on an indefinitely growing remote chat. The save is the memory source; Responses uses `store: false`. A model can misinterpret memories, so actions and learning remain engine-validated.

A character's relevant conversations with third parties can also be retrieved. If Lupita told César about a planned meal, he can remember it while talking to the player, retaining source and time. Mateo does not receive that memory if he did not witness the exchange. Tests cover isolation; evaluating faithful narrative use with real models is a separate concern.

Characters should recall naturally, with phrases such as “Yes, I remember you mentioning something” or “Yes, I remember that,” without reciting encounter dates, times, or exact elapsed intervals. Temporal provenance stays in internal memory. Chat voices have no date headers; old automatic timestamp phrases are presented naturally without changing stored memory or the player's free text. AI receives the same rule: vary phrasing, recall only real encounters, and avoid repeating a memory introduction in every reply.

## A conversation that stays open

**Hablar** (Talk) supports a greeting, a suggested response, or free text up to 1,000 characters. **Enter** sends; **Shift+Enter** inserts a line. Initially suggestions were local rules based on the last reply, adding no call to the response path. Current connected suggestions arrive with the dialogue in the same request. The field remains editable during streaming so the player can draft the next message; sending waits for the pending turn.

The prompt asks for direct, general replies in one or two sentences, targeting at most 30 words and 180 characters in one paragraph, without line breaks, repeated spaces, lists, Markdown, or long dashes. A final question is optional and must help the topic. The historical provider-output cap was 96 tokens; consult the backend for its current budget. The client compacts accumulated speech and applies the 180-character/30-word limit before display and storage, preferring complete sentences when trimming. It retains original SSE bytes for final validation and respects the player's text.

Only one manual conversation is open. Player and neighbor remain reserved between turns: routines do not pull them away and another conversation cannot claim them. The rest of the world continues. Looking at another tab or person does not end the session; **Volver a la charla** (Return to conversation) restores the active pair. **Terminar** (End) or manual walking releases the reservation and cancels pending output. **Escape** releases the text field rather than ending the conversation by itself.

Drafts remain per neighbor while the game is open. A failure preserves the session and lets **Reintentar** (Retry) resend the previous message without deleting a newer draft. Partial replies do not become memories. Complete exchanges persist in the save; drafts, errors, and pending retries are session state and do not survive closing.

Manual chat uses OpenAI when **Play.command** supplies the Worker token, even if autonomous Jev decisions are off. Without a token, it offers explicitly local, non-AI conversation with predetermined text. If a token exists but the service or provider fails, it shows an error instead of silently substituting local text. The Jev toggle controls autonomous decisions and background encounters, not manual chat availability.

## The response path

1. Godot builds bounded context and checks that the characters are nearby.
2. The Worker calls OpenAI directly; a player-started conversation does not wait for a Jev decision.
3. Real SSE streams the text. Godot presents fragments as they arrive while keeping movement and UI responsive.
4. On completion, the engine revalidates the interaction and saves the exchange as testimony, not verified fact.

The UI measures time to first fragment and total duration. Transport is nonblocking, with deadlines, size limits, and cancellation. Player conversation takes priority over background chats. At most one conversation and one decision can be pending; residents take turns.

An isolated three-turn Godot → local Worker → OpenAI check passed **19/19** at the recorded revision. First-fragment times were **1.78 / 1.61 / 0.98 s**, with totals of **1.97 / 1.95 / 1.31 s**. It covered greeting, a later reply, and follow-up using “eso” without touching the personal save. These were functional samples before the last concision adjustment, not a benchmark. Measurements were recorded in local `artifacts/chat-validation/live-chat.json`, which is not included in the public repository.

`gpt-6-luna`, reasoning `none`, and one- or two-sentence replies formed the initial configuration. It is a latency-oriented choice, not a latency guarantee. The [model documentation](https://developers.openai.com/api/docs/models/gpt-6-luna) describes its capabilities. Before making a comparative claim, measure first and complete replies, median and 95th percentile, with representative conversations on the same network. Also compare memory fidelity and character voice.

## Everyday life

Each neighbor has a schedule: rest, breakfast, work, personal activities, and encounters. Schedules create opportunities; Jev can propose activity changes when somebody is nearby or an event occurs. Biography influences interests and preferences without rigidly determining behavior.

The local foundation includes individual schedules and reproducible daily variations. A character does not need an API to complete a route or sustain a routine. It includes five neighbor homes and the player's home, returning home, and morning departure. AStar uses a four-pixel grid with cached obstacles; routes are recomputed on destination changes, not every frame. Dedicated trade animations were pending at this revision.

An occupied home requires a visit request, answered by its owner or a present resident. Jev can accept or refuse based on context; offline, an explicit rule uses prior encounters, personality, and schedule. Permission expires, is consumed on entry, and becomes invalid if occupancy changes. Empty homes are open in the prototype. Visiting or inspecting an object does not magically transmit memories to an absent owner.

## Player control and observation

The player starts in manual control. **WASD/arrows** move with collisions; clicking follows a path. **E** finds a nearby door, shop, indoor object, or person. Near another inhabitant it opens their panel. **Space** toggles pause. Movement shortcuts do not run while typing or using an interaction modal.

**Vivir solo** (autonomous living) is an explicit choice to join routines and social encounters while the game is open and unpaused. Local mode uses game rules. With **IA** active, Jev can contribute decisions and OpenAI conversations; observation neither creates a permanent remote simulation nor queries models every frame.

**Tomar control** (Take control), keyboard walking, or a manual movement/interaction order restores manual control and **1×** speed. Previous intentions and applicable pending player AI work are cancelled. Interrupted dialogue never saves partial text as a complete episode.

**1×/2×/4×** changes local movement, clock, and routines. It neither reduces Internet latency nor multiplies Jev request frequency: attempts remain at least **four real seconds apart**, distributed among residents. Pending requests or conversations may delay the next attempt. Streaming, network deadlines, and latency measurements continue to use real time.

Loading a save restores manual control and **1×** speed while retaining appearance, memories, relationships, and progress. Closed-application time is not simulated and does not complete requests.

At the initial revision, art was provisional and several systems were only proposals. The [modular PNG pipeline](arte-modular.md), sleep, relationships, and community jobs have since been implemented; use their current guides rather than treating this historical roadmap as missing functionality.

Original proposed extensions were:

- Everyday needs: sleep, food, companionship, and quiet, as temporary motivations rather than experience levels.
- Commitments: accepted invitations, promises, and pending visits.
- Autonomous personal projects, such as maintaining a garden or organizing an exhibition, beyond the player's verified learning chains.
- Neighborhood events such as rain, outages, lost objects, and visitors, affecting those who observe them.
- Relationship changes through trust, disagreements, reconciliation, and shared memories with provenance.

## Potential Cloudflare continuity

The current Worker connects providers; it is not a deployed persistent simulation. Saves and the clock run in Godot and stop when the application closes.

For a future implementation, one Durable Object per settlement could hold an event queue and schedule its next wakeup with an alarm. [Cloudflare alarms](https://developers.cloudflare.com/durable-objects/api/alarms/) can wake an object without a player request; retries require idempotent events to avoid duplicate conversations or results. AI activity would need per-settlement daily limits.

A world needs one authority for time and outcomes before synchronizing several clients. Durable Object SQLite could hold simulation state, with [D1](https://developers.cloudflare.com/d1/) for queries and durable history when justified. No remote databases have been created. Development-token authentication must be replaced with sessions and per-save authorization before distributing access to a shared hosted service.
